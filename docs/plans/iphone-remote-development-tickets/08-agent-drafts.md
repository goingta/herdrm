# 08 — 按设备和 Agent 保存草稿与选择

状态：已批准并发布，标签 ready-for-agent；实施尚未开始。GitHub：[[iPhone] 08 — 按设备和 Agent 保存草稿与选择](https://github.com/goingta/herdrm/issues/8)。

## What to build

用户切换开发机或 Agent、锁屏或重启后能找回各自的未发送草稿和原选择，不发生跨项目混用。

## Acceptance criteria

- [ ] 草稿以设备标识和 pane ID 隔离，编辑时持续保存；不只在后台回调时保存。
- [ ] 保存设备、工作区和 Agent 选择；名称变化不丢失草稿；不存在的目标保留可取回文本并提示重新选择。
- [ ] 删除设备只清除其草稿和选择；其他设备相同 pane 文本标识不受影响。
- [ ] 保留已有正式存储；原型记录仅在来源可确定时迁移，不能猜测设备归属而误配草稿。

## Verification

用两台设备上的相同 pane 标识输入不同草稿，执行切换、删除、锁屏和重启，核对归属及保留结果。

## Blocked by

None — can start immediately.

## Spec coverage

用户故事：23、27、28。基于 iPhone 远端开发规格 v0.4；与当前实现相比，本任务应补齐、整理或验证上述完整行为，已有能力不必重写。

