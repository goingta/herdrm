# 10 — 锁屏与断网后的终端恢复

状态：已批准并发布，标签 ready-for-agent；实施尚未开始。GitHub：[[iPhone] 10 — 锁屏与断网后的终端恢复](https://github.com/goingta/herdrm/issues/10)。

## What to build

用户锁屏或切换网络再返回时保留终端原画面，显示恢复状态并自动重建连接，恢复后继续操作。

## Acceptance criteria

- [ ] 进程仍在时保留终端视图与缓冲，已有选择不会闪成 No Agent Selected；草稿可继续编辑。
- [ ] 区分短暂 inactive 与 background；有界收尾、暂停连接，前台重新验证控制连接、订阅及终端附着。
- [ ] 前台断网采用有界退避，耗尽可手动重试；认证、指纹和兼容性失败转为待处理，不能靠重试绕过。
- [ ] 切换设备或 Agent 可取消旧恢复；旧通道回调不覆盖当前状态；控制键和 prompt 不自动重放。

## Verification

真机锁屏 30 秒/3 分钟、Wi-Fi/蜂窝切换、断网和快速切换目标；记录画面、可交互恢复耗时及重复提交情况。

## Blocked by

- 07 — 原生终端与控制键

## Spec coverage

用户故事：27、30。基于 iPhone 远端开发规格 v0.4；与当前实现相比，本任务应补齐、整理或验证上述完整行为，已有能力不必重写。

