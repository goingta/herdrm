# 09 — Prompt 提交确认与待核对状态

状态：已批准并发布，标签 ready-for-agent；实施尚未开始。GitHub：[[iPhone] 09 — Prompt 提交确认与待核对状态](https://github.com/goingta/herdrm/issues/9)。

## What to build

用户发送中文、多行 prompt 后看到明确提交状态；重复点击和断网不会触发客户端自动重复提交。

## Acceptance criteria

- [ ] prompt 到达正确 pane；提交期间防止重复点击；只有确认接收后清空对应已提交草稿，保留期间新编辑的内容。
- [ ] 提交前持久保存待确认记录；可确定尚未发送的失败与可能送达但缺失确认的结果区分。
- [ ] 未知结果保留内容并提示先核对终端；恢复连接或重启都不会自动重发。
- [ ] 确认接收与 Agent 任务完成分开呈现；不宣称服务端严格 exactly-once。

## Verification

在真实 RPC 链路拦截响应，覆盖发送前失败和服务端已接收但确认丢失；核对服务端收到的 prompt 次数及草稿。

## Blocked by

- 08 — 按设备和 Agent 保存草稿与选择

## Spec coverage

用户故事：20、24、25、26。基于 iPhone 远端开发规格 v0.4；与当前实现相比，本任务应补齐、整理或验证上述完整行为，已有能力不必重写。

