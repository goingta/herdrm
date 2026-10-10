# #1 开发机配置与切换：审查及验证

2026-10-10。基准为实施前提交 `8c018cc8d8501027d8cacd8e73493f6cb072046f`，用户确认按该基准审查；任务为 [GitHub #1](https://github.com/goingta/herdrm/issues/1)。正式工作树从 main 建立，原型仅作参考。配置管理公开接口为已确认测试边界。

## Standards

初审未发现 CLAUDE.md、领域文档或 Issue 工作流的硬性规范违规。提出一项 P3 可选改进：端口解析在即时校验、新增和编辑保存中重复，属于 Duplicated Code 判断项。

处理：三处统一使用 `parsedSSHPort()`；表单更名 `DeviceEditorSheet`，对应新增及编辑职责。

复查原结论：

> 复查通过。重复端口解析已统一为 `parsedSSHPort()`，`DeviceEditorSheet` 名称也符合新增和编辑的职责。新增的 `closingTasks` 将同一设备的桥接关闭与重新连接顺序集中在模型内，范围清晰，未发现新的硬性规范违规或值得阻塞提交的代码异味。

## Spec

初审发现一项 P2：Tailcat 快速 A → B → A 切换时，旧 transport 异步关闭按设备 ID 拆除桥接，可能终止新 transport 复用的桥接，违反旧通道关闭回调不能污染当前页面的要求。

处理：测试先复现该故障；同设备 Tailcat 重连等待此前的关闭任务及取消中的建立连接任务完成。SSH transport 资源独立，允许新 SSH 连接立即建立。追加任务链只等待更早的任务，不构成循环。

复查原结论：

> The Tailcat P2 finding is resolved by the uncommitted fix. Each reconnect waits for that device’s earlier teardown and canceled opening task to complete. Rapid repeated switches form an acyclic chain: opening tasks reference older closing tasks; new closing tasks await those openings and earlier closes. I found no new actionable cancellation, editing, or deletion regression. SSH replacement connections remain independent and can connect immediately.

物理 iPhone 表单验收仍待完成。其余问题未发现；名称留空回退主机与规格“主机及用户名不能为空”的要求一致。

## 验证证据

- 命令：`make mobile-test`，等价于 HerdrMobile scheme 的全部原生 App 测试，arm64 iPhone 17 Simulator / iOS 26.5。
- 结果：2026-10-10 12:22:05 +0800，8 项测试，0 失败，`TEST SUCCEEDED`。
- 四个新增行为循环均记录先失败再通过：旧连接晚到、配置编辑、共享服务器信任保留、只改名称保持上下文。审查发现的共享桥接竞态也先失败再通过。
- 其余回归验证：旧 v1 密码配置解码、无效编辑不修改保存配置、旧快照延迟返回的隔离。
- 仓库相关源码全部通过 iOS App 编译。未修改 HerdrKit/HerdrSSH 协议实现或 macOS App；该命令不代表运行了 macOS、HerdrKit 真服务器或 HerdrSSH 实机集成测试。
- 用户现有 POC 的真机终端和预览验收是原型证据；本次正式分支的新增/编辑/删除 UI 尚未在物理 iPhone 验收。

初审：Standards 1 项（最重 P3）、Spec 1 项（最重 P2），均已解决；复查未解决问题：Standards 0，Spec 0。
