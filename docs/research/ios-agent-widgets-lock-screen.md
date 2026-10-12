# iPhone Agent 小组件与锁屏状态：能力边界研究

调查日期：2026-10-12（Asia/Shanghai）。对应决策票：[[Wayfinder] 核实 iOS 小组件、实时活动与锁屏通知的能力边界](https://github.com/goingta/herdrm/issues/31)。

基线：项目最低 iOS 18.0；既有用户验证设备为 iPhone 13 / iOS 18.7.3。设备版本来自决策票，本调查未连接真机，未发送推送，未检查签名或密钥。已确认的产品方向是桌面概览、锁屏 Live Activity、仅 blocked / done 普通通知，支持手动固定并优先待处理；本报告核实平台约束，不替代后续布局和状态语义决策。

## 结论

组合可行。手机 App 前台负责同步快照，开发机或自有服务器上的 bridge 独立观察远端 Agent，并发送 APNs。Live Activity 可在主 App 不执行代码时由系统更新；桌面小组件是受预算控制的状态概览，不能承诺秒级实时。iOS 18 没有新版 WidgetKit 原生推送 API。Live Activity 不能永久常驻，须显示数据新鲜度并处理结束、关闭和失联。

## 三种展示机制

| 位置 / 机制 | 可以展示的内容 | 更新与限制 |
| --- | --- | --- |
| 桌面 WidgetKit，small / medium | 项目、会话、Agent、状态；small 选一个，medium 可展示多个 | Timeline 或 App 请求 reload，系统决定执行时机 |
| 锁屏 Live Activity，ActivityKit + SwiftUI | 一个关注目标的四项字段、最近更新时间；点击进入目标会话 | App 有执行时间时更新，或服务器 ActivityKit APNs 更新；有限生命周期 |
| 普通锁屏通知，UserNotifications | blocked / done 的事件摘要及会话入口 | 系统负责显示；需用户允许通知和锁屏展示，可被专注模式等设置影响 |
| 可选锁屏 accessory widget | 小矩形可压缩显示名称和状态；圆形、单行只能放更少信息 | 与桌面 widget 同样受刷新预算限制，不替代实时活动 |

截图底部卡片是普通通知的位置；持续状态推荐 Live Activity，占用系统安排的锁屏区域，不能任意绘制整个锁屏或固定通知排序。锁屏 accessory widgets 是用户另行添加的较小槽位。iPhone 13 没有 Dynamic Island，主要验收锁屏 Live Activity；仍须为支持 Dynamic Island 的其他设备提供对应布局。[WidgetKit strategy](https://developer.apple.com/documentation/widgetkit/developing-a-widgetkit-strategy/)、[accessoryRectangular](https://developer.apple.com/documentation/widgetkit/widgetfamily/accessoryrectangular)、[iPhone 型号](https://support.apple.com/en-us/108044)、[Live Activity 展示](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)

## WidgetKit：概览及缓存边界

Widget extension 不会持续运行。Apple 对经常被查看的小组件给出的典型预算是每天 40–70 次刷新，可能约 15–60 分钟一次；这是动态预算，不是 SLA。每个实例有自己的预算，24 小时窗口不一定午夜重置。Timeline entry 应大致相隔至少 5 分钟；这不等于每 5 分钟一定联网刷新。App 前台更新快照并调用 reload、系统按 timeline 调度、系统动态渲染日期，是不同机制。测试预算必须脱离 Xcode debugger。[Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date/)、[TimelineProvider](https://developer.apple.com/documentation/widgetkit/timelineprovider)

实施建议（本报告推导）：App 与 extension 通过 App Group 保存最小快照。Widget 显示快照时间；离线或超时显示“未更新”，不能把旧 working 推导成当前 working。需要独立拉取时，提供受认证的最小 HTTPS 快照接口；只有 App 写共享文件的方案在 App 长期挂起后会一直旧。不要在 widget 里重建常驻 SSH / WebSocket。

新版 WidgetKit push 会触发 timeline reload，仍受预算控制、机会式递送，并不替代 timeline。SDK 将 WidgetPushInfo、WidgetPushHandler、pushHandler 标为 iOS 26.0，因此 iOS 18.7.3 无法使用。后续若采用，必须运行时 availability 分支，并保留 iOS 18 路径。[WidgetKit push](https://developer.apple.com/documentation/widgetkit/updating-widgets-with-widgetkit-push-notifications)

## ActivityKit：生命周期

Live Activity 最长 active 8 小时；结束后锁屏可保留最终状态最多另 4 小时，总计最多 12 小时。结束状态不能继续更新。用户可以随时移除，且移除不代表取消远端 Agent。标准活动的 UI 在独立 sandbox 中运行，不能自行访问网络。静态 attributes 与动态 content-state 合计不得超过 4 KB。配置 NSSupportsLiveActivities，并检查 areActivitiesEnabled；处理请求失败及 active / stale / ended / dismissed 状态。[生命周期](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)、[ActivityAuthorizationInfo](https://developer.apple.com/documentation/activitykit/activityauthorizationinfo/areactivitiesenabled)、[update](https://developer.apple.com/documentation/activitykit/activity/update(_:))

实施建议：关注具体有界 Agent 工作周期；结束时提交最终状态，按选定 dismissal policy 留短暂结果。不能声称锁屏全天永久显示。用户主动关闭后不要自动反复重建。staleDate / stale-date 标记数据过时，不代表 Agent idle、blocked 或 done；显示“状态未更新”并保留上次事实。明确名称截断与标识：路由依赖稳定设备/项目/会话/Agent ID，不依赖显示名称。切换关注目标时，固定 attributes 与可变 content-state 的划分需在下一决策票确定。

## ActivityKit APNs：后台路径

iOS 17.2 起支持 push-to-start，iOS 18 基线可用；此前只能 App 启动后由 push 更新/结束。普通通知 device token、每个 Activity 的 update token、push-to-start token 是不同用途，不可互换；监听 token 更新并同步到 bridge，失效旧 token。APNs 请求使用 liveactivity push type、主题 bundleID.push-type.liveactivity，event 为 start / update / end，content-state 必须与 Swift 类型一致。timestamp 控制新旧，stale-date 与 dismissal-date 分别描述过时和结束后移除时间。正常变化优先 priority 5；priority 10 受小时预算限制，Apple 未公布可兑现固定配额。Frequent Updates 配置与用户设置不能视为实时保证。[ActivityKit push](https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications)

实施建议：第一版可在 App 中开启关注并注册 update token，降低远端自动启动的复杂度；若要求 App 没打开也启动新活动，须实现并真机验证 push-to-start 完整路径。bridge 独立保存关注关系、token 类型、APNs 环境及状态版本；以状态变化合并发送，不推终端每一行日志。不要同时对同一 blocked / done 事件发送 Live Activity alert 和普通 alert 通知，以免重复打扰。

## 普通通知：权限与去重

通知 alert / sound / badge 必须请求授权，读取当前 notification settings，用户可以随时修改。Provisional 仅静默通知中心历史，不出锁屏，不能满足截图里的提醒。Live Activity 使用独立 ActivityAuthorizationInfo，不能用通知授权布尔值替代活动可用性。[通知授权](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications)、[活动授权](https://developer.apple.com/documentation/activitykit/activityauthorizationinfo/areactivitiesenabled)

APNs collapse-id 可将同一标识通知合并，长度不超过 64 bytes，但不是事件处理幂等保证。相同本地通知 request identifier 若已经送达，替换仍会再次提醒；因此必须在发送端以稳定 eventID 做去重，而非仅靠 identifier。thread-id 的分组也不能替代去重。[APNs 请求](https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns)、[UNNotificationRequest identifier](https://developer.apple.com/documentation/usernotifications/unnotificationrequest/identifier)、[本地请求初始化](https://developer.apple.com/documentation/usernotifications/unnotificationrequest/init(identifier:content:trigger:))

实施建议：事件 ID 包含目标 ID、工作轮次和状态版本；同一事件只选一个普通通知发送者，避免 bridge remote + App local 双重发送。前台可只更新界面。done 的业务事实不能仅凭 idle 推断，状态定义由后续票确定。通知点击携带稳定路由 ID，App 启动后重新核实状态和恢复连接。

## 主 App 挂起、终止、强退

| 情况 | 可承诺的设计行为 | 必须实测或不能承诺 |
| --- | --- | --- |
| 前台 | 同步状态、保存快照、更新活动、请求 widget reload | widget 请求不等于系统立即渲染 |
| 普通后台 / 挂起 | bridge 继续独立观察 Agent，已有活动可由 ActivityKit push 更新 | 主 App SSH / WebSocket 不持续处理；不保证 push 秒级到达 |
| 系统终止 | 远端 Agent 和 bridge 独立运行；重新打开后恢复关注及最新快照 | 不能依赖旧进程或旧内存；推送启动及 token 交接需验收 |
| 用户从多任务界面强退 | 不假装主 App 后台运行；保留平台允许的系统展示路径 | 特别验收活动 update / end / push-to-start；官方文档不足以证明所有强退场景同样可靠 |
| 无网 / bridge 停止 | 显示最后快照及过时信息，返回 App 后刷新 | APNs 不是有序可靠消息队列，也不保证全部事件到达 |

普通 background silent push 低优先、可能节流，Apple 建议不要尝试每小时超过 2–3 条；被挂起通知在 App 被强制结束时可能被丢弃。因此 iOS 18 的“silent push 唤醒 App → 写缓存 → reload widget”只能辅助，不能作为实时核心。[Background notifications](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app)

ActivityKit push 是系统渲染路径，不等于上述 silent push。不能把 silent push 强退限制简单推广为“所有 Live Activity push 都失效”，也不能反向保证每个强退组合成功。Apple DTS 指出子系统处理强退不同，最终需按目标 OS 测量。[Apple DTS 对强退边界的说明](https://developer.apple.com/forums/thread/826318)

## 签名与部署前提

原生 APNs 必须启用 App ID 的 Push Notifications，并使已签名 App 有正确 aps-environment entitlement；注册失败需处理。开发与生产 token / endpoint 分离，TestFlight 使用生产环境。App Group 共享缓存也需 app / extension 一致配置。可先编译与验证本地 UI，真实锁屏远端更新验收必须有支持这些能力的开发者团队与 provisioning。[APNs 注册](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns)、[APS entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/aps-environment)、[开发者账号](https://developer.apple.com/help/account/basics/about-your-developer-account)

bridge 放用户开发机或自有服务器即可：需能出站访问 APNs，App 需能安全上传 token / 关注设置，widget 独立 fetch 还需可达快照 API。APNs 私钥只留发送端。此为部署推导，本次没有确认具体 Apple 团队、创建能力或部署服务。

## 本地 SDK 与项目观察

读取但未修改工作区。xcode-select 指向 /Applications/Xcode.app/Contents/Developer；xcrun --sdk iphoneos --show-sdk-version 返回 26.5。SDK Swift interface 证据：

- ActivityKit.framework/Modules/ActivityKit.swiftmodule/arm64e-apple-ios.swiftinterface：ActivityAttributes / Activity 为 iOS 16.1；ActivityContent request 为 iOS 16.2；pushToStartToken 与 pushToStartTokenUpdates 为 iOS 17.2。
- WidgetKit.framework/Modules/WidgetKit.swiftmodule/arm64e-apple-ios.swiftinterface：WidgetPushInfo / WidgetPushHandler / WidgetConfiguration.pushHandler 为 iOS 26.0。

本地 project.yml 的 HerdrMobile 最低 iOS 18.0，本地 Sources/HerdrMobile/Info.plist 尚无 NSSupportsLiveActivities；本地未发现移动 WidgetKit / ActivityKit 或 APNs 注册实现。macOS NotificationManager 的本地通知不是移动 APNs 路径。以上仅描述调查时当前工作区，不声称远端 main 与工作区全部相同；研究分支从远端 main 创建，只新增本报告，不合并。

## 真机验收清单

脱离 debugger，在 iPhone 13 / iOS 18.7.3 首先测试：

1. small / medium widget 四项字段、固定目标与自动选择、长名称、中文、深色/着色模式；快照时间与失联不误报 Agent 状态。
2. App 开启关注，拿到 update token；锁屏 15–30 分钟后 bridge 更新 working / blocked / done，记录源事件、APNs 接受、设备呈现三个时间，不能把接受时间视为到达。
3. 通知授权允许 / 拒绝、关闭锁屏通知、Live Activity 关闭、频繁更新关闭、专注模式分别验证降级。
4. 同事件重复输入及推送重试不重复提醒；同 Agent 新轮次 done 可以再次提醒；前台通知和 Live Activity alert 不双响。
5. 挂起、系统终止、手动强退分开测试；分别验证活动更新、结束、可选 push-to-start、重新启动 token 交接。
6. 用户移除活动后远端 Agent 继续运行，bridge 不反复重建；8 小时到期、final dismissal 与新工作周期重新关注需覆盖。
7. 断网、bridge 停机、旧 timestamp、token 轮换及失效、开发/生产环境错配：呈现过时，停止失效目标推送，恢复后获取最新事实。
8. 点击 widget / 活动 / 通知，冷启动和已运行 App 都进入正确设备及会话；会话不存在给出明确反馈。另用支持 Dynamic Island 的设备或 simulator 验证完整布局。

本次只完成官方文档与 SDK 调查，以上是真机验收要求，均不标记为已通过。
