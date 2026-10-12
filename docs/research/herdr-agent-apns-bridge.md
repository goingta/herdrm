# herdr Agent 状态到自有 APNs 发送端接入调查

调查日期：2026-10-12（Asia/Shanghai）。研究票：[调查 herdr 状态到自有 APNs 发送端的接入路径](https://github.com/goingta/herdrm/issues/32)。

## 结论与范围

最小建议是在 **herdr 所在开发机以同一用户运行一个独立 push bridge 常驻进程**：读取 Unix socket 的 snapshot 和 events，生成精简状态快照，持久保存手机订阅及待发送结果，用 HTTP/2 TLS 调用 APNs。手机现有 SSH 仅承担前台配对、注册、更新固定对象及解除订阅；锁屏后更新由 bridge → APNs → ActivityKit 完成。桌面 widget 使用独立缓存与 timeline，不能把 ActivityKit 的更新视为 widget 缓存已经更新。

这是技术调查与架构建议，**未实施、未部署、未连接用户服务、未读取机密、未发送真实通知**。可行性不代表已有可用 Apple Developer 签名、APNs key 或在线常驻主机。字段含义、展示优先级和生命周期仍由后续设计票确定。

## 证据与版本边界

发布目标为 goingta/herdrm：项目 issue-tracker 约定将规格与任务发布到该仓库；用户显式调用的 wayfinder 要求 research 报告发布到独立研究分支，且不创建 PR、不合并。通过 GitHub connector 核实该仓库为公开仓库，默认分支 main，并重新直接读取下列公开源码。此报告不包含本地机器绝对路径、私有 Git remote、当前工作目录 revision、凭据或终端内容。

| 文件 | main 内容 blob SHA |
| --- | --- |
| [project.yml](https://github.com/goingta/herdrm/blob/main/project.yml) | bedf0458a9744d412e42e1a09227f8e91481e293 |
| [MobileAppModel.swift](https://github.com/goingta/herdrm/blob/main/Sources/HerdrMobile/MobileAppModel.swift) | 9624fe4161becfdd62767ba2105b2471158ce21e |
| [Models.swift](https://github.com/goingta/herdrm/blob/main/Packages/HerdrKit/Sources/HerdrKit/Models.swift) | bb7fd7bc0629edc7066d17cc7707e48891e2069d |
| [MobileTransport.swift](https://github.com/goingta/herdrm/blob/main/Sources/HerdrMobile/MobileTransport.swift) | fb0f9c50e3f56a241f1b83cc7b052cec430ad1ec |
| [SocketRPC.swift](https://github.com/goingta/herdrm/blob/main/Packages/HerdrKit/Sources/HerdrKit/SocketRPC.swift) | ba4a22ccdd845ed0e4fe036f11b384d8b2469f18 |
| [MobileDevice.swift](https://github.com/goingta/herdrm/blob/main/Sources/HerdrMobile/MobileDevice.swift) | 0163cb366598c31c949f4546ac50fff50d36e904 |
| [HerdrSessionDiscovery.swift](https://github.com/goingta/herdrm/blob/main/Packages/HerdrKit/Sources/HerdrKit/HerdrSessionDiscovery.swift) | 27e5540957c5fd984efc961e66d6d61705a105df |

当前本地 checkout 与远端 main 并非相同基线；以下发布版本的实现事实只引用已读过的公开 main 文件。实施时须重新核对实际 checkout。main project.yml 有 iOS 18 部署目标；阅读时没有本功能的 widget / notification-service targets、App Group、APNs 或 Live Activities 配置。源码中的签名团队配置不证明用户有权使用该团队或具备推送能力。

## 现有接入点和四字段候选

公开 main [MobileTransport.swift](https://github.com/goingta/herdrm/blob/main/Sources/HerdrMobile/MobileTransport.swift) 的 SSHDirectTransport 验证 SSH host key，以 DeviceKey 或密码认证；每次 RPC 使用新的 direct-streamlocal channel，events.subscribe 则保持长连接并读取 NDJSON。默认 socket 为远端 home 下 `/.config/herdr/herdr.sock`，允许 override。因此可以沿已认证 SSH 会话另开 channel 访问 **新增 bridge 自己的 Unix socket**；该 socket 并不存在于当前实现，不能把其新方法发送给 herdr socket。

公开 main [SocketRPC.swift](https://github.com/goingta/herdrm/blob/main/Packages/HerdrKit/Sources/HerdrKit/SocketRPC.swift) 提供请求编解码、NDJSON 事件、逐 pane 的状态订阅参数。遇到订阅中的 pane 已关闭会退回无状态 scoped subscription，再由调用方刷新拓扑。MobileDeviceSession 使用 session.snapshot、pane.agent_status_changed 与生命周期事件，合并频繁 refresh，并用 statusGeneration 避免在途旧 snapshot 覆盖较新的直接状态更新。[main MobileAppModel 参考](https://github.com/goingta/herdrm/blob/main/Sources/HerdrMobile/MobileAppModel.swift)

| 用户要的信息 | 当前候选来源 | 尚未定下的语义 |
| --- | --- | --- |
| 项目名 | WorkspaceInfo.label；必要时 agent.cwd basename | workspace 的展示名称未必等于仓库名 |
| 会话名 | TabInfo.customLabel；terminal_title_stripped / terminal_title | 用户说的“会话”是 tab、agent 对话还是 herdr named session，需设计决定 |
| agent 名字 | AgentInfo.name；agentKindRaw 是类型，例如 codex | name 缺失时的降级；不要用混合 title 同时假装覆盖会话名和名字 |
| agent 状态 | agent_status → idle / working / blocked / done / unknown | unknown 不应变成 idle；断线是新鲜度状态，不应伪造 agent lifecycle |

AgentInfo.title(tabLabel:) 会合并 customTitle、tab label、name、terminal title、kind；它方便现有 sidebar 显示，却不能独立表达以上四个概念。[Models.swift](https://github.com/goingta/herdrm/blob/main/Packages/HerdrKit/Sources/HerdrKit/Models.swift)

公开 main HerdrSessionDiscovery（macOS 编译条件）读取 `~/.config/herdr/sessions/<name>/herdr.sock`，而手机 MobileDevice 目前只有 socket override，没有独立 sessionName。跨设备推送建议加入稳定 source ID，明确 host + socket namespace；名称仅作展示，不能作主键。后续需验证 named-session 和默认-session 的注册范围。

## 最小架构与 placement

```text
herdr daemon (default / named sessions)
  ├─ events.subscribe: topology + pane-scoped status
  └─ session.snapshot / authoritative reads
              ↓
push bridge (same user, independent daemon)
  source reconciliation → sanitized snapshot → subscription selection
  persistent registration + state/outbox → APNs provider
              ↑ authenticated SSH stream-local registration
iPhone foreground App
  Activity push tokens / alert device token → register/update/unregister
  SSH snapshot → atomic App Group cache → WidgetCenter timeline reload

bridge → APNs liveactivity → Lock Screen / Dynamic Island
bridge → APNs alert → blocked / newly completed notification
iOS18 WidgetKit → shared cache + system-scheduled timeline
```

| Placement | 判断 |
| --- | --- |
| 每个 herdr 主机上运行 bridge | 建议第一版。直接访问用户 socket，无需公开公网入口；APNs 凭据在主机；手机背景连接不影响状态采集。主机关机/休眠时无新推送，需 stale 显示。 |
| 自有常在线服务器汇总多个主机 | 可行备选。服务器通过独立 SSH identity 订阅各主机，或各主机用认证出站链路上报；集中管理 APNs 凭据。增加主机身份、网络恢复和账户隔离成本，并不能使已休眠主机产生活状态。 |
| herdr plugin hook | 可作后续补强。若需要 bridge 离线期间每次短暂 blocked/done 的完整历史，应调查持久事件日志；第一版的状态流与 snapshot 只保证恢复当前状态。 |
| 手机长驻 SSH / widget 自建长连接 | 不适合持续更新契约。iOS App 会挂起，widget extension 不是常驻进程。 |

建议 bridge 用 launchd（macOS）或 systemd user service（Linux）管理，与 GUI App 生命周期分离。可用 Go/Rust/Python 等可运行于目标主机的实现；公开 main HerdrKit SocketRPC 用 Darwin API，不能未经改造声称直接支持 Linux。语言选择不影响协议，留给实现票。

## 订阅注册、身份和机密

以下是**新增协议建议**，不是现有 herdr API：

- bridge Unix socket 置于用户私有目录，按用户权限限制；手机通过已经验证 host key、已经认证的 SSH channel 访问它，避免新增公网注册端口。
- register/upsert 请求带 install ID、source ID、选择范围或固定 agent identity、Activity ID、token kind、token generation、bundle topic、APNs environment 和通知偏好；响应给 subscription ID 与完整当前快照。
- 单个 SSH Unix 用户的第一版可将该 UID 作为授权边界。多用户/汇总服务器必须显式 owner scope，注册、读取、删除都查 owner，不把可猜的 UUID 当鉴权。
- 普通通知 device token 与每个 Live Activity push token 分开存；push-to-start token 也是另一种 token，不互换。第一版可在前台开始 Activity，再绑定其 update token，远程启动是否进入首版由生命周期票决定。
- 按 ActivityKit pushTokenUpdates 监听首次 token 和后续轮换，新的注册原子替换旧 generation；失效 response 只失效发送时使用的那个 generation，避免旧响应删掉新 token。Apple 会在 Activity token 更新时给予后台时间处理，但**已有 SSH 不保证仍在线**；持久记录待注册 token，有限尝试重建 SSH，失败下次前台补注册。若产品要求更强保证，再增加可通过 URLSession 访问的认证 HTTPS 注册服务。[ActivityKit push token 指南](https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications)
- 解除订阅、删除设备、结束 Activity 和本地配置撤销要幂等；无法联网时本地先停展示、排队撤销，服务器注册加 lease/expiry，防止永久旧订阅。固定对象切换时新旧 Activity 是否复用需在设计票定。
- APNs provider 私钥只在发送端保存；手机 Keychain 保存手机注册身份或 SSH 私钥，widget App Group 只存显示字段和 opaque identity，不存 APNs provider key、SSH 密码、原始终端 transcript。APNs token 不写普通日志。

## 状态恢复、排序和去重

**官方 herdr 事实：** snapshot 是单次读取；事件与 snapshot 没有共享 sequence boundary；只有同一 subscription entry 内保证顺序。events_lost 后要新建订阅，等 subscription_started，一边读流一边从另一连接读取 snapshot；将事件作为 invalidation 信号，串行权威读取，并在读取期间有事件时再刷新。恢复只能获得当前状态，不能恢复缺失事件历史。[herdr Socket API](https://herdr.dev/docs/socket-api/#event-subscriptions)

**bridge 设计建议：**

1. 每个 source 单独串行 reconciler；拓扑和状态事件标记 dirty，读取 snapshot 后仍 dirty 就再读。启动、重连、events_lost、未知 pane、pane 移动都执行 reconcile。不能把断线前缓冲的 status payload 无条件覆盖新 snapshot。
2. 建立 source namespace + server epoch + terminalID（可用时）/pane identity；pane ID 跨主机可碰撞、重启可复用、move 可改变，因此不要只按 paneID 去重。当前协议是否给可靠 server epoch 要实际版本核实；无法可靠识别重启时保守重新基线，禁止据此发“刚完成”。
3. 归一化精简快照内容，持久保存 monotonic bridge revision 和内容 hash；相同内容不发。revision 是 bridge 自己的，不冒充 herdr 的历史 cursor。数据库中的 last observed、notification dedupe、outbox 尽量同事务提交。
4. 普通通知只发新 blocked 或确认的新完成；首次注册/重启看到 done 不自动发完成。官方 done 表示 idle 且尚未 seen，并不等于一个新的业务完成事件。新版本的 completion_seq 可标识完成过渡，旧服务器可能缺失，当前 Swift AgentInfo 未解码它；需特性检测并用已观察到 working → done 的保守策略。[herdr Agent automation](https://herdr.dev/docs/agent-automation/#agent-identity-and-launch)
5. outbox 可重试但不宣称 exactly-once。发送前重新确认订阅仍有效且 revision 未被更新状态替代；状态更新可合并成最新值，关键提醒按 episode 去重。bridge 恢复失败标记 unavailable / stale，不把 agent 写成 idle。
6. APNs 是 best effort，可乱序、延迟、丢弃。Activity payload 携带完整 ContentState、timestamp、stale-date，桌面缓存携带 source epoch/revision/observedAt。不要假设 APNs 200 是手机收到或屏幕刷新。[APNs delivery](https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns)
7. ActivityKit 用 timestamp 判定最新状态；发送端同秒快速事件合并，不制造未来时间戳，不用每个字符输出驱动 push。Activity 更新使用 liveactivity push type 与 app bundle ID 的 push-type.liveactivity topic 后缀；普通提醒使用单独 alert token/topic。[Apple WWDC23](https://developer.apple.com/videos/play/wwdc2023/10185/)
8. 处理 410 Unregistered / ExpiredToken，BadDeviceToken 检查 environment/topic；不要盲重试。429 退避，5xx 按 Apple 建议等待后重试且用当前状态取代过时 outbox；记录 apns-id、结果和脱敏订阅 ID。[APNs response handling](https://developer.apple.com/documentation/usernotifications/handling-notification-responses-from-apns)

## iOS 18 的 widget 缓存更新路径

Apple 的 App Group 可让主 App 和 extension 共享容器；建议用原子 JSON 文件或事务数据库保存版本化显示 DTO，读失败保留最后有效值，缓存注明 freshness。[Configuring app groups](https://developer.apple.com/documentation/xcode/configuring-app-groups)

- **前台可靠路径：** 手机 SSH 获取状态 → 写 App Group → 请求 WidgetCenter.reloadTimelines。timeline 本身仍由系统调度，UI 不能承诺精确刷新时刻。
- **后台补充路径：** 可低频发 background APNs，App 在获准运行时写完整状态并请求 reload；Apple 不保证送达且会节流，不建议超过每小时两三次。不能每个状态变化都 silent push 来维持实时桌面卡片。[Background push](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app)
- **关键提醒补充路径：** blocked/done 的 alert 加 mutable-content，可在 notification service extension 有限执行时间中把 payload 的精简状态写共享缓存、请求 reload。必须是展示 alert 的 remote notification；提醒被禁用时 extension 不运行。它不适用于 silent-only 或 ActivityKit push，不应用它伪造 working 通知。[Notification service extension](https://developer.apple.com/documentation/usernotifications/modifying-content-in-newly-delivered-notifications)
- **可选网络拉取：** Widget 的 timeline provider 可以有限联网，但若只开放 SSH bridge，需要额外短连接认证或 HTTPS snapshot endpoint。第一版建议明确 widget 是“最近同步概览”，保留更新年龄及打开 App 刷新入口，避免 widget 带 SSH 密钥或建立长期连接。
- **新系统增强不能误用：** 普通 widget 的 WidgetPushHandler / WidgetPushInfo 是新系统能力，应按 availability gating；iOS 18 ControlWidget 的 push handler 不能当作普通桌面状态 widget 的 API。第一版以 iOS 18 timeline + cache 为基线。[WidgetPushHandler 官方 API](https://developer.apple.com/documentation/widgetkit/widgetpushhandler)


Apple 说明 widget extension 即使显示在屏幕上也不持续运行，刷新有动态预算；常看 widget 的典型每日预算约 40–70 次不是 SLA，不能由它承诺秒级 working/idle。[Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)

**关键推论：** ActivityKit push 可以让锁屏 UI 更新，但不代表主 App 获得运行时间，更不代表 App Group widget cache 已写入。Live Activity 自己不能联网；其动态内容直接来自 ActivityKit App 更新或 APNs，并有约 4 KB 数据限制。[Displaying Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)

## 后续实现前仍需验证的事实

1. 用户可用 Apple Developer 团队、App ID 的 push/App Group 权限、签名 profiles、APNs environment；当前没有查证可用凭据。
2. 发送端运行在哪个常在线 host、该 host 网络能否出站访问 APNs、睡眠与重启策略。
3. 目标 herdr 版本/protocol、events_lost 与 completion_seq、server restart identity 支持；主机上的实际 socket 和 named-session 数量。
4. “会话名”的产品定义、四字段缺失降级、固定 agent 的稳定 identity、状态隐私显示策略。
5. 是否接受 iOS 18 桌面 widget 最近快照而锁屏 Activity 接近实时；若要求后台桌面 fresh，需要另选认证 snapshot 拉取路径并真机测调度。
6. token 轮换时 SSH 重连是否满足可用性要求；否则 HTTPS 注册端点的可达性与身份方案。

建议后续验收覆盖 source 重启、事件丢失、新 pane/移动、多个同名主机与会话、重复 token 注册、延迟 410 回应、服务重启后的 dedupe、手机离线与回前台、通知关闭、锁屏网络切换。验收必须区分“APNs 接受”“Activity 展示”“widget cache 写入”“widget 渲染”，不能合成一个成功指标。
