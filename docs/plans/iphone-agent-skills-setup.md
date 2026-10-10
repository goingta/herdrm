# 工程 skills 配置确认记录

2026-10-10。用户已批准配置，内容已写入现有 CLAUDE.md 和 docs/agents 下的三份说明；以下保留批准时的内容作为记录。长期约定以实际配置文件为准。

## CLAUDE.md 拟追加内容

```markdown
## Agent skills

### Issue tracker

规格和任务发布到 goingta/herdrm 的 GitHub Issues。参见 docs/agents/issue-tracker.md。

### Triage labels

使用五个默认 triage 标签；可实施任务标记 ready-for-agent。参见 docs/agents/triage-labels.md。

### Domain docs

采用单上下文布局；术语与架构决定按需读取。参见 docs/agents/domain.md。
```

## docs/agents/issue-tracker.md 拟写入内容

```markdown
# Issue tracker: GitHub

规格与任务发布到 goingta/herdrm 的 GitHub Issues。每次操作显式使用该仓库，避免沿用上游仓库的发布说明。

- 优先使用 gh CLI；本机没有 gh 时可用已连接的 GitHub 工具。不要读取、复制或输出认证令牌。
- 读取任务时获取完整正文、标签和评论；发布任务前检查同一功能是否已存在，避免重复。
- 多行正文使用结构化工具参数，或保存原文后通过 gh 的 --body-file 提交。
- 一项任务一个 Issue，按依赖顺序创建；优先使用原生 blocked_by 依赖，接口不可用时在正文列真实阻塞 Issue 链接，并明确记录该限制。
- 任务只有全部阻塞项完成后才进入可领取前沿；ready-for-agent 表示规格完备，不表示没有阻塞。
- 发布与执行是不同阶段；未明确要求实施时，不自动认领或开始编码。
- PRs as a request surface: no.
```

## docs/agents/triage-labels.md 拟写入内容

```markdown
# Triage labels

| 角色 | 标签 | 含义 |
| --- | --- | --- |
| needs-triage | needs-triage | 待维护者评估 |
| needs-info | needs-info | 等待补充信息 |
| ready-for-agent | ready-for-agent | 规格完整，可由 Agent 实施；仍需检查阻塞关系 |
| ready-for-human | ready-for-human | 需要人工实施 |
| wontfix | wontfix | 不计划处理 |
```

## docs/agents/domain.md 拟写入内容

```markdown
# Domain docs

采用单上下文布局。探索项目前读取根目录 CONTEXT.md（存在时）及 docs/adr 中相关 ADR；若未来已有 CONTEXT-MAP.md，则按其指向读取相关上下文。文档缺失时继续工作，不为补齐目录而创建空文档。

输出使用已有领域词汇：Space 是 UI 名称，对应 workspace；Agent 目标使用 pane ID，普通终端附着使用 terminal ID；开发机是连接配置，与远端工作区区分。

术语定义以现有上下文文档为准；架构决定与 ADR 冲突时明确指出冲突。CONTEXT.md 与 ADR 按实际需要创建，不把原型细节自动升级为长期决定。
```

本轮通过 GitHub 连接器发布任务，并在 Chrome 中开启仓库 Issues。本机 gh 不在 PATH。原生依赖编辑器报 Cannot edit issues right now，正文阻塞链接作为当前依赖表示。

