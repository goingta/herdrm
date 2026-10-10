# Domain docs

采用单上下文布局。探索项目前读取根目录 CONTEXT.md（存在时）及 docs/adr 中相关 ADR；若未来已有 CONTEXT-MAP.md，则按其指向读取相关上下文。文档缺失时继续工作，不为补齐目录而创建空文档。

输出使用已有领域词汇：Space 是 UI 名称，对应 workspace；Agent 目标使用 pane ID，普通终端附着使用 terminal ID；开发机是连接配置，与远端工作区区分。

术语定义以现有上下文文档为准；架构决定与 ADR 冲突时明确指出冲突。CONTEXT.md 与 ADR 按实际需要创建，不把原型细节自动升级为长期决定。
