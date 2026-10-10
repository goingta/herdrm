# 05 — 分阶段连接测试与修复提示

状态：已批准并发布，标签 ready-for-agent；实施尚未开始。GitHub：[[iPhone] 05 — 分阶段连接测试与修复提示](https://github.com/goingta/herdrm/issues/5)。

## What to build

点击测试连接后，用户看到网络/网关、主机校验、认证和 herdr 探测的结果，并能按失败原因修复。

## Acceptance criteria

- [ ] 只有 ping、能力/兼容检查及快照读取成功才显示 Agent 控制可用；SSH 成功不提前宣告整条链路成功。
- [ ] 网关失败、指纹待确认、未登记公钥、缺少凭据、herdr/socket 不可用及协议不兼容有不同提示。
- [ ] 支持可选 socket 地址及远端默认位置；不自动安装、升级或启动 herdr。
- [ ] 测试可取消、可重新执行；旧测试完成不会覆盖最新结果；测试失败不删除配置。

## Verification

真实 SSH/RPC 入口逐项制造阶段失败，并确认 UI 所显示的阶段、可执行下一步和最终成功状态。

## Blocked by

- 02 — HTTP CONNECT 网关连接
- 03 — 手机公钥配对与撤销指导
- 04 — 服务器指纹确认与变化处理

## Spec coverage

用户故事：10、13。基于 iPhone 远端开发规格 v0.4；与当前实现相比，本任务应补齐、整理或验证上述完整行为，已有能力不必重写。

