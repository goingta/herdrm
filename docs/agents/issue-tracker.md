# Issue tracker: GitHub

规格与任务发布到 goingta/herdrm 的 GitHub Issues。每次操作显式使用该仓库，避免沿用上游仓库的发布说明。

- 优先使用 gh CLI；本机没有 gh 时可用已连接的 GitHub 工具。不要读取、复制或输出认证令牌。
- 读取任务时获取完整正文、标签和评论；发布任务前检查同一功能是否已存在，避免重复。
- 多行正文使用结构化工具参数，或保存原文后通过 gh 的 --body-file 提交。
- 一项任务一个 Issue，按依赖顺序创建；优先使用原生 blocked_by 依赖，接口不可用时在正文列真实阻塞 Issue 链接，并明确记录该限制。
- 任务只有全部阻塞项完成后才进入可领取前沿；ready-for-agent 表示规格完备，不表示没有阻塞。
- 发布与执行是不同阶段；未明确要求实施时，不自动认领或开始编码。
- PRs as a request surface: no.
