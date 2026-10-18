// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "clhhhhhh/moon-hprof"

version = "0.1.0"

readme = "README.md"

repository = "https://github.com/clhhhhhh/moon-hprof"

license = "Apache-2.0"

keywords = [ "hprof", "jvm", "heap-dump" ]

preferred_target = "wasm"

description = "Experimental HPROF heap dump parser for MoonBit."

import {
  "moonbitlang/async@0.22.1",
}
