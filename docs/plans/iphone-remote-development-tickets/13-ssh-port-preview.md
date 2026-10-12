# 13 — SSH 远端端口的 App 内预览

状态：已批准并发布，标签 ready-for-agent；实施尚未开始。GitHub：[[iPhone] 13 — SSH 远端端口的 App 内预览](https://github.com/goingta/herdrm/issues/13)。

## What to build

用户选择开发机并输入服务端口，App 经 SSH 私有转发加载网页和并发资源，终端与 prompt 仍可使用。

## Acceptance criteria

- [ ] 端口校验后转发到远端 127.0.0.1 的目标服务，本地监听仅限 App 所需回环地址，不新增公网或系统级代理。
- [ ] 复用开发机直连/CONNECT、主机信任和认证设置；多个页面资源并发加载时 RPC/PTY 不被独占转发阻塞。
- [ ] 转发打开、取消、关闭及目标切换有界；不遗留 listener、socket 或持续增长的 SSH 连接。
- [ ] 服务未启动、端口拒绝及 SSH 失败有区分；原型每个 TCP 新建 SSH、上限 8 条的策略须重新评估并记录最终选择。

## Verification

真实 SSH 转发访问含并发资源的 HTTP 服务，同时查看终端、发送人工测试 prompt，并覆盖服务停机及快速开关预览。

## Blocked by

- 02 — HTTP CONNECT 网关连接
- 12 — 完整 URL 的 App 内预览与导航

## Spec coverage

用户故事：31、33、41、42。基于 iPhone 远端开发规格 v0.4；与当前实现相比，本任务应补齐、整理或验证上述完整行为，已有能力不必重写。

