# V06 — 双端视觉、导航与可访问性验收

状态：已批准并发布，标签 ready-for-agent；实施中；v1.1 行为基线已通过；新参考布局及聊天扩展的模拟器验收通过，真机与真实服务待验收。GitHub：[[双端 UI] V06 — 双端视觉、导航与可访问性验收](https://github.com/goingta/herdrm/issues/25)。

## What to build

证明两端在同一开发场景下呈现一致品牌和状态，同时手机导航、键盘、语言和文字放大可用于日常开发，并提供可重复的截图与真机验收结果。

## Acceptance criteria

- [ ] 使用相同数据对比两端安装图标、空状态、设备表单、工作区/Agent 列表、终端和失败提示，覆盖浅色/深色及中文/英文。
- [ ] 正式 iPhone 的 Agent、项目预览与设置入口可达；列表到终端、预览到 Agent 的导航保留选择和草稿，预览导航采用统一视觉，网页自身样式不被改写。
- [ ] 真机验证长中文名称、文字放大、可点击区域、键盘和状态文字可读；可访问性不依赖仅用颜色表达状态。
- [ ] 验证蓝点真实产生、看到终端后清除、重启保留及两端互不清除；相关行为测试证据复用任务 05。
- [ ] 报告已实施页面的截图与结果；后续连接、预览恢复及完整流程页面继续按统一规则在 #18 验收，不把本任务当作功能稳定性验收替代。

## Verification

在 Mac 和 iPhone 13 / iOS 18.7.3 保存同场景对比截图和可重复操作步骤；实际浏览 URL 预览并回到 Agent，记录发现的问题及修复后的证据。

## Blocked by

- [#20 — [双端 UI] V01 — 统一两端 Logo 与正式应用名称](https://github.com/goingta/herdrm/issues/20)
- [#22 — [双端 UI] V03 — 统一中英文文案与语言设置](https://github.com/goingta/herdrm/issues/22)
- [#23 — [双端 UI] V04 — 适配手机版开发机、工作区与 Agent 界面](https://github.com/goingta/herdrm/issues/23)
- [#24 — [双端 UI] V05 — 统一两端完成未读规则与本地保存](https://github.com/goingta/herdrm/issues/24)
- [#12 — 完整 URL 的 App 内预览与导航](https://github.com/goingta/herdrm/issues/12)。

#21 与 #1 已经通过 #23 构成传递依赖，不重复列出。

## Spec coverage

统一视觉规格的验收条件；为 #18 提供视觉证据。 基于 Mac 与 iPhone 视觉一致性规格 v1.0，产品选择、任务颗粒度和依赖均已确认。

<!-- herdrm-visual-v1-ticket:V06 -->

## v1.1 导航补充

验收手机默认收起的侧栏、选择 Space 自动收起、同 Space 的真实 Tab 顺序与名称、多分屏菜单切换、跨 Space 草稿和选择隔离，以及恢复期间保留当前 Space/Tab/pane。对比截图使用相同 Space/Agent 数据，保留 Mac 并排侧栏布局。上述真实页面边界及截图验收已由用户确认。

## Implementation baseline, 2026-10-11

[Baseline report](../../evidence/mac-iphone-visual-acceptance.md) records five passed physical iPhone 13 / iOS 18.7.3 tests, native Mac accessibility labels, current-Tab visibility and controlled recovery. The user subsequently requested herdr-web-ui interaction above the retained bottom App bar and functional plugin mode. Superseded mobile screenshots remain outside the repository; V06 remains incomplete until acceptance of the updated scope. No GitHub Issue was closed.

## Reference/chat extension acceptance, 2026-10-11

[Updated report](../../evidence/iphone-web-ui-chat-acceptance.md) contains 24 inspected original PNGs and exact per-image provenance for canonical native/reference language/theme comparison. Final production integration is `4a21178` / fix `04f919a`; the four-scene Simulator matrix passed at test-only `0a342a1`, and actual drawer/modal occlusion plus ordinary-shell draft controls passed at `1579733` with identical production source. Earlier failed and superseded captures are excluded; overlapping production test batches remain separate. Mac build passed; prior Mac window/AX evidence is explicitly historical.

The user requested Simulator testing first. The new iOS 18.7.3 phone runner failed before any gate, so physical accessibility/keyboard/recovery and real authenticated service binding/update/send/upload remain pending. No issue is closed and the full acceptance checkboxes above remain open. Existing physical CRUD/Tab evidence does not replace the new chat extension gates.
