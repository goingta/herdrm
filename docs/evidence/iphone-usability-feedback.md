# iPhone 真机反馈：分支、键盘与字号

2026-10-11，基线 `6db30e094315ff920acdd449e0fd1361e07fdd35`。本记录覆盖用户真实手机反馈的三项修正。模拟器采用独立 fixture Bundle，真实 SSH 登录和手机操作由主代理后续验证；没有向远端 Agent 发送业务 prompt。

## 实现与来源

- Space 副标题显示只读 Git 查询所得的真实分支。新版 snapshot 的 `worktree.checkout_path` 优先，旧服务从该 Space 已报告的 pane cwd 选取；非仓库、detached HEAD、不可用不显示伪值。使用已有 SSH 连接、单次两秒上限及安全 shell 引用；不依赖聊天服务。抽屉可见且 App 前台时每三十秒更新，旧连接和 cwd 变化后的返回不能覆盖当前数据。
- 窗口被动 tap observer 保留控件的原始事件；UITextField/UITextView 的编辑触摸除外。原生聊天、Agent 终端、普通 shell 的 FocusState 与 Ghostty 键盘状态同步，外点收回且草稿保持。Preview 根页面不启用 Agent observer。键盘按钮捕获点按前已有 responder，打开键盘的同一次 tap 不会立即关闭它。
- [herdr-web-ui](https://github.com/devswha/herdr-web-ui) 源码 `21d1b9208ac489f8690fe8ba758dc5cd73842cf6` 的 styles.css 是字号基准：标题 16、正文/侧栏 15、次要 13、元数据 12、快捷键 13、输入 16pt。原生角色通过 @ScaledMetric 保留 Dynamic Type；44pt 控件和现有底部栏保持。已符合参考的 WK 正文 15px 与 Ghostty 输出 12pt 保持，没有对系统设置表单或预览网页缩放。
- 真实页面回归暴露透明 retained chat hosting 层令终端键盘按钮的 AX hit point 不可达。只去掉 fixture 聊天绑定时标准 tap 恢复；WK 原生 isHidden 单变量无效，已撤回。双层 ZStack 将当前 mode 提升到顶层后标准 tap 与实际打开键盘均通过，保留 renderer 身份及页面上下文。

## 红绿与验证边界

- 首次聊天外点回归：`/private/tmp/herdr-usability-keyboard-red.log`，键盘仍存在；修正后真实 tap/type/外点/草稿与工作记录展开通过。
- 首次字号回归：`/private/tmp/herdr-usability-type-red.log`，标题 glyph bounds 高度 20.333pt（不是字体 point size）超出移动 16pt 标题的默认 glyph 高度 gate；修正后默认/放大文字、长中文名称、44pt 控件通过。
- Git 公共 model seam 最终 8 项通过：`/private/tmp/herdr-usability-branch-final.log`，结果包 `Test-HerdrMobile-2026.10.11_20-36-04-+0800.xcresult`。包括非仓库、checkout path、换开发机和同连接 cwd 变化的延迟返回隔离。
- 共享模型兼容 `swift test --filter TabReorderTests` 7 项通过，`/private/tmp/herdr-usability-kit.log`。
- Mac build 通过：`/private/tmp/herdr-usability-mac-build.log`；Mac UI 源码无更改。正式 Info.plist、project.yml、ATS、密钥账户和签名配置无更改，模拟器命令仅覆盖临时签名参数。
- Ghostty 标准按钮 tap、打开不自关闭、标题外点关闭、composer 编辑、Ctrl 原动作通过：`/private/tmp/herdr-usability-mode-layer.log`，结果包 `Test-HerdrNavigationAcceptance-2026.10.11_20-49-02-+0800.xcresult`。
- 最终三项反馈 batch 实际 7 项通过（6 个新回归及 1 个聊天折叠回归），`/private/tmp/herdr-usability-ui-checkpoint-green.log`，结果包 `Test-HerdrNavigationAcceptance-2026.10.11_20-49-42-+0800.xcresult`。不是 9 项：另两个过滤器误用测试类名，未运行，后续使用正确类单独补测。
- 正确类补测与 affected retained chat 回归 4 项全部通过，`/private/tmp/herdr-usability-retained-chat-green.log`，结果包 `Test-HerdrNavigationAcceptance-2026.10.11_20-52-00-+0800.xcresult`。覆盖长中文名称/放大文字、真实快捷键、模式和底部根切换保留草稿、抽屉与配置模态遮挡后恢复相同消息位置。

最终 batch 原始截图已逐张检查：[真实分支](iphone-usability-feedback/sidebar-real-branch.png)、[默认字号](iphone-usability-feedback/mobile-reading-scale.png)、[放大字号](iphone-usability-feedback/dynamic-type-reading-scale.png)。390×844pt、3×，iPhone 13 Simulator / iOS 26.5。

UI fixture 的 SSH attach 为受控不可用，渲染/键盘是实际生产控件及系统键盘；以上不能证明真实 PTY 或远端业务写入。一次草稿测试误把重新点击后的 caret 位置当作末尾，已改为验证实际编辑字符串在外点后原样保持，未归为产品故障。失败批次不作为最终 green 结果，重叠批次不相加。

## 终端恢复提示与键盘焦点的补充诊断

新的实际 UI 测试打开 Ghostty 软件键盘后直接点击 composer，曾报没有 keyboard focus。最初失败 snapshot 的 composer y663.7 被误推断为未避让键盘；打开键盘时的原始截图与 AX frame 证明实际 composer y329.7、max349.7，在键盘 y553 之上。真正遮挡是 SSH attach 失败的 Reconnect 提示居中覆盖整个终端及 controls；点击它作为外点收键盘后 frame 才回到 y663.7。`ignoresSafeArea(.container)` 单变量无效，已撤回，不添加裸 keyboard height 或焦点抢占补丁。

修正将恢复提示限制在 terminal display，并裁剪/限定命中区域，始终保留输入 controls 可操作。`/private/tmp/herdr-usability-ghostty-inset-red.log` 与 geometry 诊断为 red；`/private/tmp/herdr-usability-ghostty-recovery-overlay-green.log` 为真实标准按钮 tap→Ghostty 键盘→composer tap/type→外点收回→草稿及原位置恢复的 green，结果包 `Test-HerdrNavigationAcceptance-2026.10.11_20-56-42-+0800.xcresult`。

横屏实际 composer 输入、返回竖屏后的 Ctrl 原动作/外点收回、前台恢复及原位置无残留通过：`/private/tmp/herdr-usability-landscape-roundtrip-green.log`，结果包 `Test-HerdrNavigationAcceptance-2026.10.11_21-00-50-+0800.xcresult`。边界：旋转可能关闭 Ghostty 键盘，测试采用先横屏再打开；横屏软件键盘下，既有 chrome 最小高度会使顶栏及部分快捷键暂时不可达。本轮没有改动竖向 chrome，也不声称该状态所有控件可达。无需新键盘 inset；因此原生输入框已有避让不被重复 padding。

**最终同源码实际 UI batch：10 项、0 failures、112.168s**。`/private/tmp/herdr-usability-ui-complete-final.log`，结果包 `/private/tmp/herdr-usability-dd/Logs/Test/Test-HerdrNavigationAcceptance-2026.10.11_21-01-43-+0800.xcresult`。其中 VisualAcceptanceTests 8 个新反馈/诊断回归，SpaceNavigationTests 2 个长名称和快捷键回归。该批替代早先不完整或失败的同类 UI batch；不与其相加。共享模型 8 项和 Mac build 的最终源码保持不变，采用上文独立结果；真机仍待主代理安装和用户验收。

## 集成审查与真机更新

最终源 `825c848` 经 merger 无冲突集成为 `3d9012b33a81b220ecb03adeadd372fadadae479`，树内容相同。独立 Standards / Spec 审查各 0 项，正式 Info.plist 与 project.yml 无差异。

2026-10-11 已在连接的 iPhone 13 / iOS 18.7.3 构建、更新安装正式 `dev.bybee.herdrm.ios`，保留原数据和 Keychain；构建日志 `/private/tmp/herdr-usability-final-device-build.log`，BUILD SUCCEEDED。安装成功，自动启动失败：CoreDevice 10002 / FBS Security（签名、权限或用户未信任）。本机完整签名校验通过，个人 Team `NHN8A752UN`，provisioning profile 包含该手机且有效至 2026-10-17。已请用户手动打开 App 并核对手机上的开发者信任/验证状态，再验收三项修正；安装不能替代实际 UI 验收。
