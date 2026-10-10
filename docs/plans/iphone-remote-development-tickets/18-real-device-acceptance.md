# 18 — 完整开发流程与稳定性验收

状态：已批准并发布，标签 ready-for-agent；实施尚未开始。 GitHub：[[iPhone] 18 — 完整开发流程与稳定性验收](https://github.com/goingta/herdrm/issues/18)。

## What to build

证明正式 App 能完成配对、已有 Agent 开发、项目预览及故障后恢复，给出可重复的验收结果。

## Acceptance criteria

- [ ] 从正式入口完成新增开发机、手机公钥登记、连接验证、选择 Agent、中文 prompt 与端口/URL 预览；覆盖用户 CONNECT 路径。
- [ ] 补齐 HMR、网络切换、冷启动、已选 Agent 删除、电脑同时附着、预览隔离及提交确认丢失的证据，不沿用原型通过标记。
- [ ] 连续 20 轮切换/锁屏/恢复无崩溃、遗留监听占用或持续增长的活动连接；远端 Agent 和项目服务不中断。
- [ ] 至少 10 轮记录恢复成功率、终端/预览耗时及失败原因；500ms 提示和 10 秒恢复作为规格建议目标单独报告，不伪装成已确认硬门槛。
- [ ] 复用现有 SSH/RPC 回归和新增网页夹具；输出可重复真机步骤，保留既有 macOS/iOS 能力的相关构建回归。

- [ ] 复用 [#25 — 双端视觉、导航与可访问性验收](https://github.com/goingta/herdrm/issues/25) 的证据，继续核对后续连接、诊断和预览恢复页面符合统一 Logo、主题、语言及未读规则。

## Verification

使用 iPhone 13 / iOS 18.7.3 和可丢弃测试账号/Agent/服务进行完整验收；真实业务 Agent 的写操作由用户明确选定。

## Blocked by

- [#1 — 开发机配置与切换](https://github.com/goingta/herdrm/issues/1)
- [#6 — 工作区筛选与已有 Agent 状态](https://github.com/goingta/herdrm/issues/6)
- [#11 — 冷启动恢复 Agent 开发上下文](https://github.com/goingta/herdrm/issues/11)
- [#16 — 锁屏、断网与网页终止后的预览恢复](https://github.com/goingta/herdrm/issues/16)
- [#17 — 可复制的连接与恢复诊断](https://github.com/goingta/herdrm/issues/17)
- [#25 — [双端 UI] V06 — 双端视觉、导航与可访问性验收](https://github.com/goingta/herdrm/issues/25)

## Spec coverage

用户故事：10、20、27、28、30、31、37、38、39、40、42、43、44。基于 iPhone 远端开发规格 v0.4；与当前实现相比，本任务应补齐、整理或验证上述完整行为，已有能力不必重写。

<!-- herdrm-iphone-v1-ticket:18 -->

