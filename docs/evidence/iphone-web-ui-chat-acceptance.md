# iPhone herdr-web-ui 扩展：受控验收记录

2026-10-11：**本轮模拟器、参考页面及受影响回归通过；真机与真实服务验收仍待完成。** 早期用户要求先在模拟器跑；随后已重新连接真机并反馈分支、键盘与字号问题，当前进展见文末。#25 保持未完成，PR 保持 draft。本记录替代旧 V1.1 手机布局截图，不能从受控结果推断实际服务认证、远端消息或 SSH 已通过。

## 来源与共同数据

- 最终生产集成：`4a2117819cfdd0a4343ec27c16730ea4b9fa3a94`，修复源 `04f919ad8bf69a596d99bca62d1feedfda8e0880`。独立双轴最终审查为 0 findings。
- 最终四组原生截图/测试源：`0a342a1a3a1b43c48d3a0194b2c34637fc926f76`。遮挡和普通 shell 截图源：`1579733bef0521e1b796560b3cce177fe60036d1`。两者使用上述相同生产代码；后续差异只有测试对公开折叠状态的同步。
- 共同数据：[scene.json](../../Tests/VisualAcceptance/scene.json)。开发机、Space/Tab/pane、角色、消息和元数据均为合成数据。没有读取用户聊天、正式 App 偏好或 Keychain，没有向远端 Agent 发送 prompt。
- 原生：独立 **Herdr UI Fixture**，iPhone 13 Simulator / iOS 26.5，390×844pt、3×。实际 MobileWorkspaceView、生产聊天控制器、WK transcript、SwiftUI composer、表单和系统键盘。HTTPS URLProtocol 替代外部网络，生产服务仍核验身份归属；公开公钥/凭据接口注入夹具文字。
- 参考：[herdr-web-ui](https://github.com/devswha/herdr-web-ui)，源码 `21d1b9208ac489f8690fe8ba758dc5cd73842cf6`。实际 Vite/React dist，Chrome 154.0.8037.99 / macOS 26.5.2，390×750 CSS px、3×、全新浏览器上下文。API/WS 适配器提供相同 fixture 数据，没有改写参考组件或 CSS。[重现脚本](../../Tests/VisualAcceptance/reference-capture.mjs)。Node 26.5.1 / Vite 6.4.4；没有 Bun，不声称验证 Bun 服务器或 xterm IME 补丁。
- 用户已部署服务公开 health 的 revision 是 `5d18c535caf042bef69e569aa1f0299072760fde` / 0.4.5，与参考源码不同。本轮没有登录该服务。参考夹具补充协议字段，但 fixture 缺少 cwd，因此参考的 `unknown directory` 不是用户目录。

## 最终组件比较

所有发布的 24 张 PNG 均逐张视觉检查。逐图源码、尺寸、平台、fixture SHA256、文件 SHA256 和结果包见 [manifest.json](iphone-web-ui-chat/manifest.json)。截图保持原始字节，没有图像编辑。

| 场景 | 参考实际页面 | 原生实际页面 |
| --- | --- | --- |
| 英文浅色 | [聊天](iphone-web-ui-chat/reference-en-light-chat.png)、[侧栏](iphone-web-ui-chat/reference-en-light-sidebar.png) | [聊天](iphone-web-ui-chat/native-en-light-chat.png)、[侧栏](iphone-web-ui-chat/native-en-light-sidebar.png) |
| 英文深色 | [聊天](iphone-web-ui-chat/reference-en-dark-chat.png)、[侧栏](iphone-web-ui-chat/reference-en-dark-sidebar.png) | [聊天](iphone-web-ui-chat/native-en-dark-chat.png)、[侧栏](iphone-web-ui-chat/native-en-dark-sidebar.png) |
| 中文浅色 | [聊天](iphone-web-ui-chat/reference-zh-light-chat.png)、[侧栏](iphone-web-ui-chat/reference-zh-light-sidebar.png) | [聊天](iphone-web-ui-chat/native-zh-light-chat.png)、[侧栏](iphone-web-ui-chat/native-zh-light-sidebar.png) |
| 中文深色 | [聊天](iphone-web-ui-chat/reference-zh-dark-chat.png)、[侧栏](iphone-web-ui-chat/reference-zh-dark-sidebar.png) | [聊天](iphone-web-ui-chat/native-zh-dark-chat.png)、[侧栏](iphone-web-ui-chat/native-zh-dark-sidebar.png) |

顶部标题/Agent glyph、默认收起侧栏、真实横向 Tab/下拉、模式切换、More、暖黑/琥珀主题、消息正文和 composer 按参考组件比较。真实工作记录汇总为 `Worked for 6s · 1 file read` / `工作了 6 秒 · 读取 1 个文件`；闭合时 thinking/tool 子行实际消失，展开可见，再关闭消失。用户消息为单复制图标，Agent 回复为 MD/TXT。最终四张聊天图均为真实闭合状态。

批准的差异：保留原生底部三个入口和 sidebar.left 图标；只操作已有 Agent，不提供创建 Tab 的 +；附件 + 保留；Safari 工具栏和参考安装/更新横幅不属于原生 App。模型与推理信息只读。不同视口、系统字体和安全区按组件/功能比较，不声明逐像素一致。

[系统键盘](iphone-web-ui-chat/native-zh-dark-keyboard.png)、[实际预览](iphone-web-ui-chat/native-zh-dark-preview.png)、[已保存测试配置](iphone-web-ui-chat/native-zh-dark-saved-edit.png)、[普通 shell 控件](iphone-web-ui-chat/native-en-dark-ordinary-shell.png)、[抽屉遮挡](iphone-web-ui-chat/native-en-dark-drawer-occlusion.png)、[配置模态](iphone-web-ui-chat/native-en-dark-add-modal.png)、[返回聊天](iphone-web-ui-chat/native-en-dark-overlay-return.png)均为生产页面边界。普通 shell 的 attach 被明确设为不可用，截图中的错误是夹具边界；失败提交不重放并保留草稿的测试通过，但遮挡错误文字的那张输入图被排除。[独立 Ghostty](iphone-web-ui-chat/native-zh-dark-ghostty-renderer.png)显示共同 UTF-8/ANSI bytes，只证明 renderer，不证明 live SSH PTY。

## 有限测试与回归结果

各批存在重叠，不能相加成总测试数。未修改行为引用旧源时明确标注，不把旧截图算作最终布局。

| 源码 / 结果包 | 结果与边界 |
| --- | --- |
| `0a342a1`；`/private/tmp/herdr-chat-four-final.xcresult` | 最终 1 个矩阵测试 × 4 组语言/主题通过，194.552s；实际折叠隐藏→展开→隐藏、输入/系统键盘、模式/底部导航、测试表单、WK 预览链接→原生返回、真实 Ghostty 渲染 |
| `1579733`；`/private/tmp/herdr-chat-reference-polish-final.xcresult` | 实际抽屉/配置模态遮挡通过 17.768s，普通 shell composer/失败保留草稿通过 14.005s；同批早先矩阵失败，已由上述最终矩阵替代，不标为整批通过 |
| `6197450`；`/private/tmp/herdr-chat-fixed-final.xcresult` | 6 项未受后续样式修复影响的选择/恢复/大字体/tracer/缓存前台/中文文案通过；第 4 Tab 实际可点击，accessibility3 长 Space 及 44pt 控件可达；同批遮挡失败已修复，旧移动 PNG 未发布 |
| 修复源 `66773cb` | 82 个完整 hosted/mounted 测试、10 个实际导航 UI 测试分别通过；`/private/tmp/herdr-ui-final-full-tests.log`、`/private/tmp/herdr-ui-final-navigation-tests.log` |
| 最终修复源 `04f919a` | 28 个受影响 hosted/mounted、3 个实际 UI 分别通过；`/private/tmp/herdr-final-shell-fold-native-ax-green.log`、`/private/tmp/herdr-final-shell-affected-ui-green.log` |
| 最终生产源 `04f919a` | Mac resource build 通过；`/private/tmp/herdr-ui-final-mac-build.log` |

生产回归细节保存在本机 `/private/tmp/herdr-ui-final-review-fixes-evidence.md`：实际工作记录/复制/本地化、旧图片引用的缓存压力、模态下未读证明暂停、真实快捷键、More 刷新、成功 shell 字节、失败不重放及旧目标响应隔离。外部传输边界的成功不能视为实际远端命令成功。

iOS 26.5 多行输入框 AX isHittable 在已经聚焦、输入成功时偶尔为 false。键盘 gate 用实际 tap/type、保留文本、键盘存在和 public frame 位于键盘上方确认；没有把控件存在视为可输入。顶栏/底栏按钮仍检查 hittability 与 44pt（仅使用 1e-6 浮点容差）。

## 发现、修复及测试同步

实际截图发现的分散工作记录、用户 MD/TXT、闭合后子行仍显示、普通 shell 缺少 composer 以及被覆盖 WK 内容仍可访问，均由唯一生产修复分支解决。折叠 gate 检查 computed display、子行 clientRects；遮挡 gate 检查实际抽屉/模态与背景 AX，不能只依靠 SwiftUI host 的隐藏标记。fixture 不打开会读取 Keychain 的 Chat Service 表单，而使用注入公钥的实际开发机表单覆盖同一个根页面 modal gate。

一次四组矩阵在中文浅色第二次快速点击关闭时失败。第二 tap `(195,287)` 位于实际 header `(8,267,374,40)` 内，不能归因于点击出界。focused 相同生产源码展开→关闭通过，图片显示子行消失；AX 操作描述在更新中由旧 › 变成 ⌄。最后只调整测试同步：等待公开展开 caret、重新确认 hittable 后点击，再确认闭合 caret 和子行消失；最终四组通过。源码检查没有重现生产折叠 race，因此没有猜测性生产改动。原失败、focused 结果与最终结果均保留：`/private/tmp/herdr-chat-fold-reclose-inspection.xcresult`、`/private/tmp/herdr-chat-four-final.log`。

## Mac 与真机边界

Mac `Sources/HerdrM` 保留原布局，旧源 `12b59e49599c4b99a263248643a0ccba9763209e` 的 32 个实际原生窗口及状态 AX 为历史基线，见 [旧报告](mac-iphone-visual-acceptance.md)。共享资源/术语随后有变化，所以不把旧文本截图称为最终源重采；本轮最终 Mac build 已通过。新的移动主题分支限定 iOS，Mac unread 仍使用其原有 palette 映射。

用户 2026-10-11 真实手机反馈：Tab 切换正常，锁屏返回连接过程体验不好。已实施有界验证健康连接、仅失效重连、保留 Ghostty/上下文、250ms 可取消提示和立即输入/已读 gating；这是落实已批准恢复要求，不声称用户逐项批准内部机制。受控恢复通过，长期真实网络/锁屏稳定性留在 #18。

本轮 iPhone 13 / iOS 18.7.3 fixture 在第一项测试前失去 runner 连接，**0 UI gate 执行**：`/private/tmp/herdr-chat-physical-final.xcresult`。用户随后要求先跑模拟器。该设备的新版界面、大字体、键盘、锁屏恢复仍需重测；此前旧布局真机结果不可替代。真实服务认证、machine 绑定、最新历史、更新、用户授权发送和附件上传同样待用户在 App 完成。原生后台采用缓存/停止轮询/前台验证恢复，不保证永久运行。

## 隔离与重现

Simulator `4556EE75-CBAD-47CA-8765-C0A5EDA8709F`；独立 Bundle `dev.bybee.herdrm.navigation-fixture`。当前演示 artifact：`/private/tmp/herdr-chat-acceptance-dd/Build/Products/Debug-iphonesimulator/NavigationHarness.app`。从源码重建步骤见 [harness README](../../Tests/HerdrNavigationHarness/README.md)。演示仅包含合成数据：

```sh
SIMCTL_CHILD_VISUAL_ACCEPTANCE=1 SIMCTL_CHILD_VISUAL_LANGUAGE=zh-Hans \
SIMCTL_CHILD_VISUAL_THEME=dark SIMCTL_CHILD_VISUAL_SCENE=workspace \
xcrun simctl launch --terminate-running-process \
4556EE75-CBAD-47CA-8765-C0A5EDA8709F dev.bybee.herdrm.navigation-fixture
```

验收分支 `9595e28` 修改 fixture 网络配置时意外把正式 project.yml 的旧 WebContent 声明一同缩为 LocalNetworking。恢复旧声明被自动审批拒绝，已停止且未重试。集成代理仅选入合法 fixture/测试/报告更改，**排除意外正式 project.yml hunk 与未提交生成的正式 Info.plist**，保持集成原正式文件字节。该生成文件不是交付内容；没有绕过拒绝新增 ATS 例外。

## 后续真机反馈修正

用户在正式 App 提出三项问题：Space 副标题显示编号、外点不收键盘、整体字号过大。已修正并通过 10 项实际模拟器 UI 回归、8 项导航模型边界测试，独立 Standards / Spec 审查各 0 项；[最新证据及三张截图](iphone-usability-feedback.md)以新源码为准。先前本报告截图仍代表原受控阶段，不冒充新字号证据。

`3d9012b` 已构建并更新安装到 iPhone 13，自动启动被 iOS 信任检查拒绝；本机签名和有效描述文件检查通过，待用户手动打开验证。真实服务登录、machine 绑定、实时聊天/附件发送和健康 SSH 锁屏恢复等原验收门槛继续保留，#25 和草稿 PR 尚未完成。

随后用户完成手机验证，CoreDevice 重试已成功启动正式 App；信任问题解除，三项修正正在用户真机复验。
