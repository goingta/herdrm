# Mac / iPhone 原生 UI 验收（V06，规格 v1.1）

状态：本文保留规格 v1.1 的验收基线，V06 尚未完成。2026-10-11 用户进一步要求保留底部 App 栏，并将其上方界面与 herdr-web-ui 的会话标题、侧栏、更多和模式切换交互对齐，插件模式须实际可用；新的移动布局与功能范围正在梳理。因此旧移动布局的截图只保存在临时验收目录，不作为新要求的最终证据。已启动的行为和 Mac 可访问性回归继续记录，最终移动截图需按新范围重新采集。

## 数据与验收边界

两端读取同一个 `Tests/VisualAcceptance/scene.json`，使用相同开发机名称、两个 Space、真实 Tab/pane 标识、工作中/等待输入/完成未读/完成已读/空闲 Agent，以及相同 UTF-8、ANSI 和 truecolor 终端字节。未读由公开 `AgentReadState.applySnapshot` 的 working → done 转换产生，不直接写入蓝点字段。

手机夹具实际挂载正式 `MobileWorkspaceView`、侧栏、Tab、分屏菜单、设备表单、设置、输入框和 WKWebView。Mac 夹具挂载正式 Sidebar、DevicePopover、EditDeviceSheet、外观设置和 Ghostty 终端组件，保留 Mac 的侧栏布局；没有用截图或自绘页面代替这些控件。Mac 的单组件窗口与手机的全页面分别标注，不把它们称为完整 Mac RootView 的对照。

夹具使用独立 Bundle ID、隔离存储和固定的公钥文字提供器。没有读取或修改正式 App 配置、私钥、Keychain，也没有向远端 Agent 发送 prompt。普通 workspace 场景的 SSH attach 被明确设为失败，所以输入框和错误提示截图证明布局、草稿保留及失败呈现；独立终端场景通过真实 Ghostty 视图渲染受控字节，证明文字和颜色，不证明真实 SSH 流。网页由 UI runner 在测试手机内部通过临时 TCP 端口提供，实际点击链接并使用 App 的返回控件；网页自身 CSS 保持原样。

## 环境与来源

| 平台 | 环境 | 截图/测试范围 |
| --- | --- | --- |
| iPhone 真机 | iPhone 13，iOS 18.7.3，1170 × 2532 像素，390 × 844 pt，3× | 正式页面组件、系统键盘、实际 WKWebView、中文长名、accessibility3 |
| iPhone 模拟器 | iPhone 13，iOS 26.5 | 同一夹具的先行回归；不当作 iOS 18.7.3 证据 |
| Mac | macOS 26.5.2 (25F84) | 实际原生组件窗口；每张尺寸见后续截图清单 |
| 构建 | Xcode 26.6 (17F113)，SDK 26.5 | 真机签名只用临时命令覆盖，正式项目签名配置不变 |

手机独立测试 App 显示名为 **Herdr UI Fixture**，Bundle ID `dev.bybee.herdrm.navigation-fixture`。Mac 独立 host 为 `dev.bybee.herdrm.mac-visual-fixture`。中文和英文切换只翻译 App 文案，远端名字保持原文。

## 已执行的门槛

| 门槛 | 结果 | 本机日志/结果 |
| --- | --- | --- |
| 原生中文页面 tracer | RED → GREEN | `/private/tmp/herdr-visual-acceptance-red.log`、`/private/tmp/herdr-visual-acceptance-green1.log` |
| 模拟器：3 个 VisualAcceptanceTests | 通过，0 失败，123.631s | `/private/tmp/herdr-visual-matrix-final.log`、同名 `.xcresult` |
| 真机：四组中英/浅深色，预览链接 → 原生返回 → Agent 草稿和选择保留 | 通过，112.803s | `/private/tmp/herdr-visual-device-matrix.log`、同名 `.xcresult` |
| 真机：中文页面 tracer | 通过，3.973s | 上述真机结果 |
| 真机：放大文字、长 Space、44pt 入口与空设备页面 | 通过，20.025s | `/private/tmp/herdr-visual-device-ax-green.log`、同名 `.xcresult` |
| Mac：32 个原生窗口场景（4 组合 × 8 场景） | 控件断言通过；捕获质量需重采 | `/private/tmp/herdr-mac-window-matrix-final.log`、同名 `.xcresult` |

第一轮真机的 44pt 比较返回 `43.99999999999999`，仅修正浮点比较的 `1e-6 pt` 容差，再运行受影响的单个测试；没有放宽实际点击区域要求。Mac 的一张原生窗口图被其他前台窗口遮挡，已剔除，不作通过证据。最终捕获要求激活测试 App、确认前台，并逐张检查选入报告的图片；不发布全桌面图和自动录屏。

## 发现及待复测

1. 选中第 4 个 Tab 时，终端属于正确 pane，但横向 TabStrip 起初显示第 1 个 Tab。修复需要保证当前 Tab 在初始进入、切换及恢复后可见；验收通过实际控件 `isHittable` 和选中状态确认。
2. Mac 的完成已读 AX 标签起初只有名称，完成未读标签只有“未查看”，没有“已完成”。修复后应复用共享状态文字，逐一验证 working、blocked、done-read、done-unread、idle 标签。
3. 用户确认正式真机 Tab 切换正常，但锁屏返回会出现连接过程。恢复修复应先验证现有连接；健康连接保留终端，失效时显示轻量、真实的恢复状态，并保留 Space/Tab/pane 和草稿。独立夹具与正式 App 使用同一恢复入口后重测。
4. 同 UUID 的连接目标/账号编辑须隔离未读缓存，名称编辑保留状态；复用对应公开模型回归。

## 其他验收证据与限制

- V01 的品牌资源验证已经确认 Mac 原图与移动源图 sRGB 像素一致，并检查编译后的 AppIcon 完整构图；真机已安装正式 `herdrm`。这不同于以夹具窗口标题推断安装图标验收。
- V05 的真实完成转移、终端 readiness 后清除、持久化和独立客户端状态测试复用其已通过证据；本夹具截图的蓝点不代替这些行为门槛。
- 先前正式真机配置 CRUD 测试已通过 78.265s：保存、改名、重启持久化、删除及恢复原选择。当前夹具表单截图只读取测试数据，不重复改动原配置。
- 用户已明确确认当前正式 iPhone 的 Tab 切换正常。真实代理身份验证、远端网页、长期断线/锁屏/网络切换的稳定性继续由 #18 负责；受控终端与临时网页不宣称覆盖这些情况。

重现命令与隔离说明见 `Tests/HerdrNavigationHarness/README.md`。最终选中图片、来源提交和校验值将在修复合入后补齐，不能从尚未完成的记录推断规格已经全部验收。

## Fixed-source baseline retained after scope change

Captured source: `12b59e49599c4b99a263248643a0ccba9763209e`, including latest integration `cf0091c2843cef4bdbe37f5025cca73e1693a38d` and fixes `b79c14e5617c035973a3a6cd8b671d2142b0a8fe`. These are baseline records, not final approval of the newly requested mobile layout/plugin mode.

- Physical iPhone: 5 tests passed, 0 failures, 164.789s. Includes current fourth-Tab visibility and Space return, retained selection through controlled recovery/failure, Dynamic Type, populated Edit form, actual preview navigation, and draft preservation. Log `/private/tmp/herdr-visual-device-fixed-matrix.log`; result `/private/tmp/herdr-visual-device-fixed-matrix.xcresult`; attachments `/private/tmp/herdr-native-fixed-phone`.
- Mac: 32 native-window scenes and actual working/blocked/done-unread/done-read/idle accessibility-label assertions passed. Log `/private/tmp/herdr-mac-fixed-matrix.log`; result `/private/tmp/herdr-mac-fixed-matrix.xcresult`; attachments `/private/tmp/herdr-native-fixed-mac`. Label-only text attachments record the actual rendered strings.
- Source/platform/locale/theme/Dynamic Type/dimensions/checksum metadata is preserved outside the repository: `/private/tmp/herdr-native-fixed-baseline-manifest.json`. No superseded mobile screenshots were published in the repository.
- Visually inspected the recaptured Chinese Mac form/sidebar and physical current Tab/keyboard/restoring images. The current Tab is visible. Restoring keeps the selected context and uses a compact hint; the controlled attach fixture supplies no real terminal bytes, so its blank terminal region does not prove preservation of a healthy SSH frame.

The user's 2026-10-11 formal-device feedback confirmed normal Tab switching and objected to connecting after lock return. Implementation validates and reuses a healthy held connection within a bound, reconnects only after failure, retains the matching Ghostty/context, delays the restoring hint by 250ms, and gates input/read acknowledgement immediately. This implements the previously confirmed context-retention requirement; it is not a claim that the user approved each internal mechanism. Actual model/rendered regressions passed; long-running real SSH/network/lock stability remains in #18. New mobile styling and functional plugin mode still require updated implementation and final acceptance.
