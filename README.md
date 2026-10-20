# moon-hprof

MoonBit 编写的 HotSpot HPROF 堆转储解析库与命令行工具。支持类和对象索引、字段与数组查询、按类统计、JSON/CSV 导出、栈信息解析，以及两份转储的类统计比较。

这是一个可通过源码或 MoonCake 使用的堆分析基础库，不是 Eclipse MAT 的完整替代品；提供基于 HPROF 显式引用的支配分析和 payload retained 统计，不提供自动泄漏判定或 JVM 实际 retained heap。MoonCake 已发布版本为 `clhhhhhh/moon-hprof@0.1.0`，最新 GC 分析功能可从仓库源码运行。

项目采用 Apache-2.0。开发阶段使用 AI 辅助编程。

验证数据由本仓库的 `validation/GenerateHeap.java` 生成，不使用用户业务进程的内存数据。第三方解析器仅作外部验证工具，不随包分发。

## 本地使用

安装 MoonBit 工具链后：

```sh
moon update
moon check --target wasm --deny-warn
moon build --target wasm --deny-warn
moon test --target wasm --deny-warn
moon run cmd/main --target wasm -- --help
moon run cmd/main --target wasm -- summary path/to/heap.hprof
moon run cmd/main --target wasm -- histogram path/to/heap.hprof --format csv --limit 20
moon run cmd/main --target wasm -- objects path/to/heap.hprof 0 --limit 10
moon run cmd/main --target wasm -- check path/to/heap.hprof
```

首次使用前请在仓库根目录执行 `moon update`。运行 CLI 使用 `moonrun` 提供的文件能力，不是浏览器文件读取接口。CLI 输出到标准输出，可使用终端重定向保存 JSON 或 CSV。

## 功能与接口

| 能力 | API / 命令 |
| --- | --- |
| 索引与汇总 | `parse`、`parse_with_limits`、`summary` |
| 类、继承和静态字段 | `class_info`、`hierarchy`、`static_fields`、`class` |
| 对象查找与字段解码 | `object_ids`、`instance_fields`、`field`、`objects`、`object` |
| 数组分页 | `array_values`，支持八种基本类型及对象引用数组 |
| Java String | `java_string`，支持 char[]、Latin-1、compact UTF-16，字节顺序由调用者明确指定 |
| 根引用与栈 | `roots`、`roots_for`、`stack_trace`、`roots` / `stack` 命令 |
| 根可达性与支配分析 | `gc_analysis` API；CLI `gc` 输出可达对象、立即支配者和 retained payload |
| 直接引用 | `references` / `refs`，返回字段或数组引用，不进行可达性或泄漏推断 |
| 反向引用与路径 | `ReferenceIndex`、`incoming`、`referrer_ids`、`most_referenced`、有预算的 `path`；CLI `inbound` / `referenced` |
| 内容预览与批量导出 | `preview`、`objects_jsonl`、`previews_jsonl`；CLI `preview` / `export` |
| 统计与比较 | `histogram`、`select_histogram`、`totals`、`largest_objects`、`loader_statistics`、`compare_heaps` |
| 导出 | JSON、RFC 4180 CSV；`diff` 比较两份转储 |
| 校验 | `validate` / `check`，检查继承链、字段布局和元数据引用 |

用 histogram 获得 class ID 后，可通过 `objects <file> <class-id>` 列出对象 ID，再以 `object <file> <object-id>` 查询。ID 支持无符号十进制和 `0x` 十六进制。`objects` 的 class ID 为 0 时列出全部普通对象和数组，不包含类对象；类对象使用 `class` 查询。

例如：

```sh
moon run cmd/main --target wasm -- summary heap.hprof --class java/lang/String
moon run cmd/main --target wasm -- histogram heap.hprof --prefix java/ --sort payload --format json
moon run cmd/main --target wasm -- object heap.hprof 0x1234 --offset 0 --limit 20
moon run cmd/main --target wasm -- diff before.hprof after.hprof
moon run cmd/main --target wasm -- inbound heap.hprof 0x1234 --limit 20
moon run cmd/main --target wasm -- preview heap.hprof 0x1234 --limit 8
moon run cmd/main --target wasm -- export heap.hprof 0 --limit 100 > objects.jsonl
moon run cmd/main --target wasm -- gc heap.hprof --limit 20
```

其中 `0x1234` 是占位 ID，请替换成文件中的实际 ID。`--offset`、`--limit` 支持数组页面、根列表和对象列表，具体参数见 `--help`。

## 数据含义与支持边界

- 支持 `JAVA PROFILE 1.0.2`、4/8 字节标识符、分段和非分段堆记录，以及标准 HotSpot GC 根类型。不支持 Android 专有扩展；未知堆子记录报错，未知顶层记录按长度跳过。
- 文本支持 Java Modified UTF-8 和标准四字节 UTF-8。无法表示为有效 Unicode 标量的孤立代理项明确报错，不默默替换。
- `payload_bytes` 是文件中实例字段或数组元素的字节数，不是 shallow heap、retained heap 或 JVM 总内存占用。类定义的 `reported_instance_size` 保留文件字段原值。
- JSON 中对象 ID、时间戳及 64 位整数使用十进制字符串；NaN/Infinity 以带类型的字符串表达，避免 JSON 精度损失和非法数值。
- 直方图按 class ID 区分类加载器。`count_class` 及跨转储比较按类名聚合；比较结果不证明同一对象跨 GC 存活。
- `java_string` 对 compact UTF-16 必须明确原 JVM 的本机字节顺序。HPROF 没有直接携带这一信息。它解码字符串内容，不推断业务语义。
- 输入完整加载到内存，再保存对象偏移和元数据索引；没有 mmap 或流式文件读取。默认文件上限 512 MiB、普通对象/数组上限 200 万、类上限 20 万，可通过 `ParseLimits` 调整；CLI 使用默认值。文件上限在读取后检查，不能替代调用者读取前的大小检查。
- 查询页最多 100000 项；导出单个对象不会展开整个引用图。当前验证目标是 Windows/JDK 24 与 Ubuntu/JDK 21 的小型真实样本，不承诺大型转储性能或任意 JVM 兼容性。
- `ReferenceIndex` 只索引实例字段、静态字段和对象数组，不包括 VM 隐式引用、类加载器元数据边，也不区分弱/软引用。路径只表示这些已记录边的连接，不是 GC 根路径、保留大小或泄漏证据。路径预算耗尽时 `truncated=true`，不会冒充“确定不存在路径”。
- `gc_analysis` 在上述已记录边上从 GC Roots 做可达性遍历，并用迭代支配集合求解支配关系；`retained_payload` 是 HPROF 文件 payload 字节的支配子树累加，不等同于 JVM 实际 shallow heap 或完整 MAT retained heap。
- 反向索引默认最多 100 万非空边、1000 万引用槽（包括空槽），超限明确报错。引用目标排行区分边数与不同源对象数，并标识指向堆中未定义对象的引用。
- 对象预览只展示一层，省略项和字符裁剪会标记 `truncated`。JSON Lines 导出按对象分页，每行一个 JSON 文档；数组元素另有上限，不递归展开引用。

## 真实 JVM 对照验证

需要 JDK（含 `java` 和 `javac`）及 PowerShell；CI 使用 Ubuntu、JDK 21，本地首次使用 Windows、JDK 24。执行：

```powershell
./validation/verify.ps1 -Jdk '你的JDK安装目录'
```

脚本固定使用外部 [eaftan/hprof-parser](https://github.com/eaftan/hprof-parser) 的提交 `849678cca7c69eb8a25a927ad7836ad94bb02aef`（Apache-2.0），并校验其 Guava 16.0.1 依赖的 SHA-256。两者仅用于外部验证，保存在忽略目录 `_tools/`。本仓库的 `ReferenceCounts.java` 只接收参考解析器回调，不实现二进制解码。

脚本在默认配置和关闭压缩指针两种模式下分别生成真实转储，核对类、实例、对象数组、基本类型数组的总数，并断言自建 `Marker` 类恰有 37 个实例。随后运行 `cmd/verify`，检查继承 long 字段、静态对象引用、Marker 顺序、八种基本类型数组、NaN/Infinity，以及包含 NUL、中文和表情的 String。任何编译、解析或对照不一致都会导致验证失败。

本地 Windows/JDK 24 已通过上述双配置对照和字段语义验证。JVM 版本和环境会改变系统类与对象数量；脚本比较同一次生成的文件，不把系统对象数量作为跨环境固定答案。真实样本的 ID 宽度由 JVM 决定；4/8 字节完整索引、字段和数组解码另有合成测试，这不等于已验证所有 32 位 JVM 转储。

## 当前验证边界

87 个单元测试覆盖二进制边界、完整合成文件的所有截断前缀、重复/空 ID、数值位模式、类型解码、继承循环、字段遮蔽、数组、元数据、资源上限、类加载器统计、Unicode、JSON/CSV/JSON Lines、正反向引用、循环路径与预算截断、对象预览、GC 支配与 retained 累加、CLI 和描述符。真实文件对照另在 CI 执行，不计入这个单元测试数量。

2026-10-18 的 Git 跟踪 `.mbt` 文件合计 4735 行：实现和可执行程序 3025 行，测试 1710 行。该统计包含注释及空行，不包含生成的 `.mbti` 接口文件、Java 验证代码或第三方源码；行数不代表生产成熟度。

GitHub Actions 执行 WASM 目标的 check/build/test，然后在 Linux/JDK 21 上重新生成样本并运行独立对照与语义验证。工具链版本、输入来源、参考解析器版本和边界均可在仓库内追溯。

## 项目结构

- `parser.mbt` / `model.mbt`：边界读取、记录解析和数据模型。
- `query.mbt` / `validate.mbt`：索引查询、类型与结构校验。
- `export.mbt` / `report.mbt`：导出、过滤排序、统计与比较。
- `references.mbt` / `reference_report.mbt` / `preview.mbt`：反向索引、有预算的路径查询、引用排行、对象预览和 JSON Lines。
- `text.mbt` / `strings.mbt` / `descriptor.mbt`：Unicode、Java String 和 JVM 描述符。
- `limits.mbt` / `cli.mbt`：资源限制和命令渲染。
- `cmd/main`：CLI；`cmd/verify`：真实样本语义断言；`validation`：生成和独立对照。

## 来源与许可证

按 HPROF 记录结构编写 MoonBit 实现，参考 [eaftan/hprof-parser](https://github.com/eaftan/hprof-parser)（Apache-2.0）理解记录及验证行为。第三方仓库和 Guava 验证依赖不会提交或随包分发。测试转储由自己的 Java 样本程序生成，二进制堆文件被 Git 忽略。项目及样本程序采用根目录 [LICENSE](LICENSE) 的 Apache-2.0 许可证。
