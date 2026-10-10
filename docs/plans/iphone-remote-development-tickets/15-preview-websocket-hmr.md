# 15 — API、WebSocket 与同源 HMR 预览

状态：已批准并发布，标签 ready-for-agent；实施尚未开始。GitHub：[[iPhone] 15 — API、WebSocket 与同源 HMR 预览](https://github.com/goingta/herdrm/issues/15)。

## What to build

SSH 预览中的相对 API、同源 WebSocket 和 HMR 可正常交互，页面实时更新时 Agent 仍可操作。

## Acceptance criteria

- [ ] 真实 HTTP 方法、响应和 WebSocket 双向数据经同一入口正确传递，长连接与并发资源不阻塞终端/RPC。
- [ ] 同源 HMR 可观察到代码或夹具内容更新；不以单次 HTML 200 代替交互验收。
- [ ] 独立端口或绝对 localhost 等配置问题有检查服务地址、Host/Origin 和 HMR 配置的说明，不自动重写网页。
- [ ] 长流量、取消和半关闭不丢失字节或无界积压；关闭预览回收相关资源。

## Verification

在现有真实 SSH 夹具上提供 HTTP/API/WebSocket 和同源 HMR 服务，使用浏览器交互结果及服务端记录验证。

## Blocked by

- 13 — SSH 远端端口的 App 内预览

## Spec coverage

用户故事：37、38、42。基于 iPhone 远端开发规格 v0.4；与当前实现相比，本任务应补齐、整理或验证上述完整行为，已有能力不必重写。

