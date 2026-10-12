# 荧绿 / 橙光：双固定深色色系验收

2026-10-12。配色源码 `b0361e3`；合并已确认的 Logo D 后，产品 checkpoint 为 `8d27c7124bea257fcdead5dec7f4c8a9ffb641ce`。用户确认“荧绿 / 橙光”，两套固定深色、默认荧绿。此模块没有更改 SSH 配置/凭据、Agent 操作、Mac 布局或字号。

## 实际行为

- 外观仅两个选项，中文“荧绿 / 橙光”，英文“Phosphor / Amber”。公开偏好接口持久化选择；旧 `system/light/dark` 或未知值迁移到默认荧绿，不改无关偏好。
- 荧绿沿用纯黑、中性灰、白字及亮绿。橙光恢复 `275daf7^` 的 iPhone 参考 token：背景 `#12100E`、面板 `#181613`、输入 `#1C1916`、强调 `#F0A830`；按钮均为黑字。App UI、原生终端和 WK 聊天跟随当前色系；ANSI、Agent 品牌、蓝色未读和语义状态色保持原含义。
- 原生 App 使用共同的呈现 modifier，传递显式的色系与 sRGB tint。Ghostty 对原 controller 调用 `setTheme` 热更新，WK 发布同文档的新 theme，均不重建模型/PTY/页面，也不丢选择、终端文字、展开状态、滚动或草稿。
- 语言菜单 Picker 的初始原生标题 tint 缓存已通过实际像素确认。只替换该无内部状态的语言控件，其选择仍由保留的语言偏好持有。没有给 App、设置根页面、终端、WK 或模型加配色 identity。
- 相同内容的 WebKit 结构化参数可能采用不同对象键顺序。稳定内容签名避免纯改色重建 DOM；旧文档或 viewport 已改变时，晚到的 RAF 不再重设滚动。

## 验证与边界

| 边界 | 结果 | 证据 |
|---|---|---|
| 公开偏好、实际 mounted Ghostty、WK 渲染 | 最终同批次 17 项通过（Appearance 8 + renderer 9） | `/private/tmp/herdr-color-checkpoint-hosted.log`；`Test-HerdrMobile-2026.10.12_10-23-00-+0800.xcresult` |
| 真实设置控件、两模式及 Space/Tab/草稿 | 1 项通过，固定 checkpoint 两色完整切换 | `/private/tmp/herdr-color-checkpoint-ui.log`；`Test-HerdrNavigationAcceptance-2026.10.12_10-25-18-+0800.xcresult` |
| Mac 正式 target | BUILD SUCCEEDED | `/private/tmp/herdr-color-final-mac-build.log` |
| Mac 设置 UI runner | 两次 bootstrap 前被系统 kill，0 项实际执行 | `/private/tmp/herdr-color-mac-settings-ui.log`、`/private/tmp/herdr-color-mac-settings-ui-signed.log` |
| 正式 iPhone | 由 root 进行最终安装与用户验收 | 此 worker 未操作手机 |

真实 Ghostty 截图验证橙光背景像素为 RGB 18/16/14，保留原 surface、中文/ANSI 内容及相同 attach 次数。真实 WK 页验证暖黑 CSS、原 WK/turn 节点、展开 work block 与滚动位置；最新结果可见性原断言保持。UI 场景通过“荧绿→橙光→荧绿”的真实点击验证两个选项、中文名称、原生语言控件橙色像素且无残留绿色、Space/Tab 选择及聊天/终端未发送草稿保留。

测试使用隔离偏好和受控 SSH/HTTP 边界，无真实服务令牌或私人聊天。UI fixture 的 PTY attach 明确失败，不作为真实 SSH 验收；renderer 测试使用真正 Ghostty/WK 挂载。模拟器为 iPhone 13 / iOS 26.5，不能替代 iPhone 13 / iOS 18.7.3 真机验收。Mac UI runner 未进入测试页面，不能计作成功；未再次运行无关的完整截图矩阵。

## 失败与修复记录

- 第一个偏好红测因原三选项没有新 case 而编译失败，加入两色接口后通过。终端红测实际仍为黑色，热更新后暖黑像素通过。
- WK 初始探针试图跨桥返回 DOM 对象而报错，改为标量后才取得有效红测。有效红测显示暖黑样式缺失及同内容 DOM 重建，稳定签名与 CSS 接入后通过。
- 保留原已读证明测试发现旧 cached 文档的晚到 RAF 把当前 viewport 推到回复底部；最终 guard 尊重当前文档和已改变的 viewport，原断言完整通过。所有临时 probe 已移除。
- 原生语言控件红测得到零橙色及 2756 绿色像素。sRGB、Scene 注入或父层显式 tint 单独修改均未解决，因此不将它们宣称为故障原因；在控件局部更新 identity 后，原始像素断言和上下文断言通过。shared modifier 仅作为两端共同呈现入口。
- 两次早期 UI 测试选择关闭按钮的 query 有歧义或命中底层 scrim；最终点真正 X 按钮，保留所有选择断言。旧失败结果不计入通过数量。

## 当前截图

截图均来自受控场景，来源见 [manifest](color-presets/manifest.json)。原生设置表单保留平台深色底面和结构，主题强调色跟随当前选择；项目预览网页保留网站自己的样式。

- [荧绿聊天](color-presets/color-presets-chat-phosphor.png)
- [橙光聊天](color-presets/color-presets-chat-amber.png)
- [荧绿设置](color-presets/color-presets-settings-phosphor.png)
- [橙光设置](color-presets/color-presets-settings-amber.png)
- [橙光侧栏](color-presets/color-presets-drawer-amber.png)
- [原生语言控件橙光](color-presets/color-presets-language-amber.png)

正式 `Sources/HerdrMobile/Info.plist` SHA256 仍为 `2642238694cdfe5c7777b1972b046f8b69572b4f822b8fed3e54096018380c2a`。`project.yml` 无修改；没有放宽 ATS、改签名配置或迁移私钥。

## 最终集成与真机安装

最终源 `5a59a568` 经 merger 集成为 `b29c738719d1edc48b24337d08476101380e465e`，树相同。独立 Standards / Spec 完整审查 `30bbb63...5a59a56`，各 0 项剩余问题。

集成后的完整 Mac target 和个人签名 iPhone target 均 BUILD SUCCEEDED：`/private/tmp/herdr-color-combined-mac-build.log`、`/private/tmp/herdr-color-presets-device-build.log`。正式包已更新安装到连接的 iPhone 13 / iOS 18.7.3，Bundle `dev.bybee.herdrm.ios`，保留原数据和 Keychain。自动启动被 FBS Locked 拒绝（手机未解锁）；这是本次的实际原因，不沿用上一轮签名/信任诊断。已请用户解锁手动打开，验收新 Logo、两套固定深色默认荧绿及切色保留上下文。安装与构建不替代这次真机验收；真实服务/发送/锁屏原门槛仍保留。
