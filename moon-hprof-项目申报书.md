# Moon HProf 项目申报书

## 基本信息

- 项目名称：Moon HProf：MoonBit 的 JVM HPROF 堆转储解析库
- 参赛者：clhhhhhh
- GitHub 仓库链接：https://github.com/clhhhhhh/moon-hprof
- MoonCake 包链接：https://mooncakes.io/docs/clhhhhhh/moon-hprof
- 项目方向：MoonBit 后端基础设施 / JVM 运维与诊断工具
- 是否为移植项目：否（参考 HPROF 公开格式规范重新实现）

## 项目简介

Moon HProf 是一个使用 MoonBit 编写的 JVM HPROF 堆转储解析库和命令行工具。它将二进制堆转储转换为可查询的类、对象、字段、数组、线程栈和根引用数据，为 MoonBit 后端工具、JVM 运维脚本、内存问题排查和离线数据分析提供可复用的基础能力。

现有 JVM 堆分析工具通常依赖大型桌面应用或 Java 运行时。Moon HProf 提供轻量的 MoonBit API、WASM 目标和命令行接口，支持在自动化流程中进行解析、统计、校验和 JSON/CSV/JSON Lines 导出，便于与日志平台、数据处理脚本和可视化工具衔接。

## 核心功能范围

- 解析 `JAVA PROFILE 1.0.2` HPROF 文件，支持 4/8 字节对象标识、顶层记录和标准堆记录；
- 建立类、继承关系、字段、静态字段、对象、数组、线程栈和 GC 根的索引；
- 提供对象字段解码、数组分页、Java String 解码、类统计和对象大小统计；
- 提供直接引用、反向引用、引用排名和有预算的引用路径查询；
- 提供从 GC Roots 出发的可达性分析、迭代支配关系计算和基于 HPROF payload 的 retained 结果；
- 提供输入资源限制、结构校验、重复 ID 检测和元数据引用检查；
- 提供 JSON、CSV、JSON Lines 导出，以及摘要、直方图、对象预览和快照差异命令；
- 提供 MoonBit 库 API 与 `moon run cmd/main` 命令行入口，并发布为 `clhhhhhh/moon-hprof@0.1.0`；
- 提供 `gc` 命令，以 JSON 输出 GC Roots 可达对象、立即支配者和 retained payload 排名；
- 通过合成 JVM 堆转储、独立 Java 参考解析器和 GitHub Actions 完成跨环境验证。

## 实现计划与预期产物

项目采用 MoonBit 原生模块结构，按读取层、模型层、查询层、导出层和 CLI 层组织。交付物包括可通过 `moon add clhhhhhh/moon-hprof` 使用的 MoonCake 包、GitHub 源码仓库、README 使用示例、单元测试、真实 JVM 对照验证脚本和 CI 配置。

项目当前聚焦 HPROF 解析、索引和可编程查询。GC 分析基于转储中明确记录的字段、静态字段和数组边；retained 结果按文件 payload 字节计算，不宣称等同于 JVM 实际分配量，也不替代 Eclipse MAT 的完整泄漏诊断。引用路径和索引结果会标注其边界与预算限制。

## 参考规范与许可

- 参考格式：Java HPROF `JAVA PROFILE 1.0.2` 公开记录格式；
- 参考验证项目：https://github.com/eaftan/hprof-parser （Apache-2.0，仅用于外部验证，不随本项目分发）；
- 本项目许可证：Apache-2.0，详见仓库根目录 `LICENSE`；
- 项目仓库与 MoonCake 包均使用 `clhhhhhh` 命名空间，便于复现、安装和后续维护。
