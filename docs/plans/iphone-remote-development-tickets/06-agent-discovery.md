# 06 — 工作区筛选与已有 Agent 状态

状态：已批准并发布，标签 ready-for-agent；实施尚未开始。GitHub：[[iPhone] 06 — 工作区筛选与已有 Agent 状态](https://github.com/goingta/herdrm/issues/6)。

## What to build

用户按 Space/workspace 查看已有 Agent，读取实时状态；连接恢复中、列表为空和目标被删除有不同呈现。

## Acceptance criteria

- [ ] 显示服务端名称、类型、所属工作区及状态；筛选不改变远端任务。
- [ ] 状态事件和拓扑变化更新列表，不以静态快照冒充实时在线状态。
- [ ] 未连接、恢复中与真正空列表可区分；删除已选 pane 后提示目标不存在并允许重新选择。
- [ ] 按设备及 pane ID 识别目标；中文显示名或重名不导致错误附着；不加入创建或生命周期管理入口。

## Verification

对真实 herdr 的可丢弃 pane 改变状态、工作区和拓扑，验证列表、筛选与已选目标失效。

## Blocked by

None — can start immediately.

## Spec coverage

用户故事：16、17、18、29。基于 iPhone 远端开发规格 v0.4；与当前实现相比，本任务应补齐、整理或验证上述完整行为，已有能力不必重写。

