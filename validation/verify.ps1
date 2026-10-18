param([string]$Jdk = $env:JAVA_HOME)
$ErrorActionPreference = 'Stop'
if (-not $Jdk) { $Jdk = Split-Path (Split-Path (Get-Command java).Source) }
$javaExe = Join-Path $Jdk 'bin/java'
$javacExe = Join-Path $Jdk 'bin/javac'
$projectRoot = Split-Path $PSScriptRoot
Push-Location $projectRoot
try {
    New-Item -ItemType Directory -Force _tools | Out-Null
    if (-not (Test-Path _tools/hprof-parser/.git)) {
        git clone https://github.com/eaftan/hprof-parser.git _tools/hprof-parser
        if ($LASTEXITCODE) { throw 'Reference checkout failed' }
    }
    git -C _tools/hprof-parser checkout --detach 849678cca7c69eb8a25a927ad7836ad94bb02aef
    if ($LASTEXITCODE) { throw 'Reference version unavailable' }
    if (-not (Test-Path _tools/guava.jar)) {
        Invoke-WebRequest 'https://repo.maven.apache.org/maven2/com/google/guava/guava/16.0.1/guava-16.0.1.jar' -OutFile _tools/guava.jar
    }
    if ((Get-FileHash _tools/guava.jar -Algorithm SHA256).Hash -ne 'A896857D07845D38C7DC5BBC0457B6D9B0F62ECFFDA010E5E9EC12D561F676D3') {
        throw 'Guava checksum mismatch'
    }
    $sources = Get-ChildItem _tools/hprof-parser/src/main/java -Recurse -Filter '*.java' | Select-Object -ExpandProperty FullName
    & $javacExe -cp _tools/guava.jar -d _tools/reference-classes $sources validation/ReferenceCounts.java validation/GenerateHeap.java
    if ($LASTEXITCODE) { throw 'Java compilation failed' }
    $classPath = '_tools/reference-classes' + [IO.Path]::PathSeparator + '_tools/guava.jar'
    $runDir = '_tools/run-' + [guid]::NewGuid().ToString('N')
    New-Item -ItemType Directory $runDir | Out-Null
    foreach ($mode in @('default', 'uncompressed')) {
        $heapPath = Join-Path $runDir "$mode.hprof"
        $vmArgs = @('-Xmx64m')
        if ($mode -eq 'uncompressed') { $vmArgs += @('-XX:-UseCompressedOops', '-XX:-UseCompressedClassPointers') }
        & $javaExe @vmArgs -cp _tools/reference-classes GenerateHeap $heapPath
        if ($LASTEXITCODE) { throw 'Heap generation failed' }
        $actual = @(& moon run cmd/main --target wasm -- $heapPath 'GenerateHeap$Marker')
        if ($LASTEXITCODE) { throw 'MoonBit parsing failed' }
        $expected = @(& $javaExe -cp $classPath ReferenceCounts $heapPath)
        if ($LASTEXITCODE) { throw 'Reference parsing failed' }
        if (($actual -join "`n") -ne ($expected -join "`n")) {
            throw "Parser mismatch: MoonBit=$actual Reference=$expected"
        }
        if ($actual -notcontains 'class_instances=37') { throw 'Expected 37 known Marker instances' }
        Write-Output "PASS $mode"
        $actual | Write-Output
        Get-FileHash $heapPath -Algorithm SHA256 | Select-Object Hash | Format-Table
    }
} finally { Pop-Location }
