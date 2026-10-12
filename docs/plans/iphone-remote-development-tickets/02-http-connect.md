# 02 — HTTP CONNECT 网关连接

状态：已批准并发布，标签 ready-for-agent；实施尚未开始。GitHub：[[iPhone] 02 — HTTP CONNECT 网关连接](https://github.com/goingta/herdrm/issues/2)。

## What to build

用户填写网关主机和端口后，经 HTTP CONNECT 完成 SSH 认证及 herdr 读取，也能切回直连。

## Acceptance criteria

- [ ] 新增和编辑界面可选择直连或 HTTP CONNECT；网关字段有完整校验和持久化。
- [ ] 网关隧道建立后执行正常 SSH 主机校验与认证；直连及既有认证方式保持可用。
- [ ] 拒绝、超时、格式异常和握手取消均有可识别结果，关闭残留 socket；不消费隧道后紧随的 SSH banner。
- [ ] 支持用户当前无认证 CONNECT 路径，不增加任意 ProxyCommand 执行或代理账号密码。

## Verification

复用真实 sshd，加入可控 CONNECT 网关；验证成功、拒绝、慢响应、取消以及隧道后立即到达的 SSH 字节。

## Blocked by

None — can start immediately.

## Spec coverage

用户故事：2。基于 iPhone 远端开发规格 v0.4；与当前实现相比，本任务应补齐、整理或验证上述完整行为，已有能力不必重写。

