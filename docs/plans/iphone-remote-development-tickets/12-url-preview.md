# 12 — 完整 URL 的 App 内预览与导航

状态：已批准并发布，标签 ready-for-agent；实施尚未开始。 GitHub：[[iPhone] 12 — 完整 URL 的 App 内预览与导航](https://github.com/goingta/herdrm/issues/12)。

## What to build

用户在正式 App 中输入 HTTP/HTTPS URL，浏览页面、返回/前进/刷新，并切回 Agent 继续操作。

## Acceptance criteria

- [ ] 正式 App 提供预览入口；校验 URL 并明确显示直接访问模式和当前目标，不隐式改为 SSH。
- [ ] 返回、前进、刷新、关闭键盘及回到 Agent 可用；WebKit 只对开发网页所需 HTTP 使用相应配置。
- [ ] HTTPS 使用正常证书验证；无效地址、加载失败和 TLS 错误有提示及重试入口。
- [ ] 网页加载或失败不清除 Agent 选择、草稿或停止远端任务。

- [ ] 正式 App 的 Agent、项目预览和设置入口可达，预览导航使用统一主题与文案；网页内容保持网站自身样式，切回 Agent 不丢失选择和草稿。

## Verification

真机访问可控 HTTP/HTTPS 网站，完成导航及错误重试；切回 Agent 验证草稿和终端状态。

## Blocked by

None — can start immediately.

## Spec coverage

用户故事：32、33、35、36、41。基于 iPhone 远端开发规格 v0.4；与当前实现相比，本任务应补齐、整理或验证上述完整行为，已有能力不必重写。

<!-- herdrm-iphone-v1-ticket:12 -->

## Visual consistency

采用 [#21 — 统一主题](https://github.com/goingta/herdrm/issues/21)、[#22 — 统一语言](https://github.com/goingta/herdrm/issues/22) 的界面约定；这些是既定实施顺序中的视觉基础，URL 预览本身没有新增逻辑阻塞。正式导航与 [#25 — 双端视觉验收](https://github.com/goingta/herdrm/issues/25) 衔接。

