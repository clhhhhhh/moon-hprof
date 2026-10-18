# moon-hprof

MoonBit HPROF 解析可行性验证项目，目标是读取真实 HotSpot 堆转储中的类名、实例和数组，并与独立解析器核对数量。当前不是完整堆分析器，不提供泄漏判断或保留堆大小计算。

项目采用 Apache-2.0。开发阶段使用 AI 辅助编程。

验证数据由本仓库的 `validation/GenerateHeap.java` 生成，不使用用户业务进程的内存数据。第三方解析器仅作外部验证工具，不随包分发。

## 本地使用

安装 MoonBit 工具链后：

```sh
moon update
moon check --target wasm --deny-warn
moon test --target wasm --deny-warn
moon run cmd/main --target wasm -- path/to/heap.hprof
```

可选第二个参数为 JVM 内部类名（例如 `java/lang/String`），输出该类的实例数。统计同名类时合并所有类加载器的实例，不计算对象字段、引用图或保留堆大小。

当前原型支持 HotSpot `JAVA PROFILE 1.0.2`、基础类记录、实例和两种数组的扫描。只统计记录，不把转储文件中的字节数作为实际内存占用。输入完整加载到内存，因此不宣称适合超大转储。未识别的堆子记录会明确报错；未知的顶层记录按长度跳过。类名使用 UTF-8 宽松解码，尚未实现完整的 Java Modified UTF-8。

## 真实 JVM 对照验证

需要 JDK（含 `java` 和 `javac`）及 PowerShell；CI 使用 Ubuntu、JDK 21，本地首次使用 Windows、JDK 24。执行：

```powershell
./validation/verify.ps1 -Jdk '你的JDK安装目录'
```

脚本固定使用外部 [eaftan/hprof-parser](https://github.com/eaftan/hprof-parser) 的提交 `849678cca7c69eb8a25a927ad7836ad94bb02aef`（Apache-2.0），并校验其 Guava 16.0.1 依赖的 SHA-256。两者仅用于外部验证，保存在忽略目录 `_tools/`。本仓库的 `ReferenceCounts.java` 只接收参考解析器回调，不实现二进制解码。

脚本在默认配置和关闭压缩指针两种模式下分别生成真实转储，核对类、实例、对象数组、基本类型数组的总数，并断言自建 `Marker` 类恰有 37 个实例。任何编译、解析或对照不一致都会导致验证失败。

2026-10-18 首次 Windows/JDK 24 本地结果：

| 模式 | 类记录 | 实例 | 对象数组 | 基本类型数组 | Marker 实例 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 默认 | 935 | 16154 | 2063 | 10216 | 37 |
| 关闭压缩指针 | 958 | 9466 | 1656 | 3525 | 37 |

两份结果均与独立 Java 解析器一致。JVM 版本和环境会改变系统类与对象数量；脚本对同一次生成的文件做比较，不把本表总数作为跨环境固定答案。真实样本的 ID 宽度由 JVM 决定；4/8 字节头部另有合成测试，这不等于已验证所有 32 位 JVM 转储。

## 当前验证边界

5 个单元测试覆盖 4/8 字节头部、最小文件的全部截断前缀、无效标识符宽度、数组长度越界和未知堆子记录。真实文件验证目前只对照计数与指定类识别，不代表全部字段语义、Android 扩展、任意损坏文件或大型文件性能已验证。
