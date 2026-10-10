# iPhone 远端开发：已发布任务索引

2026-10-10。来源：[规格 v0.4](../../specs/iphone-remote-development.md)。用户已批准 18 项拆分、GitHub Issues 和默认标签；发布时均为 open、ready-for-agent，正文和标签已回读核对。#1 代码与 8 项自动验证已完成，参见 [PR #19](https://github.com/goingta/herdrm/pull/19)，真机表单验收仍待完成。

## 最新实施优先级

用户已确认[Mac 与 iPhone 的视觉一致性补充](../../specs/mac-iphone-visual-consistency.md)：先完成 #1 真机表单验收，再交付独立的 Logo、共享主题、语言/外观设置与基础组件工作，随后继续 #2 → #18。各页面在相应功能任务中接入统一视觉，完成未读行为单独衔接 #6 与 #8/#11，最终截图对比纳入 #18。

新增工作尚未拆成 GitHub Issue，不为它预分配 Issue 编号，也未修改现有 GitHub 依赖关系。上述是实施优先级调整，原有功能之间的依赖继续适用。

2026-10-10 书面规格复核通过，已形成[新增六项功能任务的拆分草案](../mac-iphone-visual-consistency-tickets/README.md)。草案列明独立交付、阻塞关系及与原有 #1–#18 的完整实施顺序，任务颗粒度待确认后发布。

## GitHub 任务与阻塞关系

| 本地编号 | GitHub Issue | Blocked by |
| --- | --- | --- |
| 01 | [#1 — 开发机配置与切换](https://github.com/goingta/herdrm/issues/1) | 无 |
| 02 | [#2 — HTTP CONNECT 网关连接](https://github.com/goingta/herdrm/issues/2) | 无 |
| 03 | [#3 — 手机公钥配对与撤销指导](https://github.com/goingta/herdrm/issues/3) | 无 |
| 04 | [#4 — 服务器指纹确认与变化处理](https://github.com/goingta/herdrm/issues/4) | 无 |
| 05 | [#5 — 分阶段连接测试与修复提示](https://github.com/goingta/herdrm/issues/5) | [#2](https://github.com/goingta/herdrm/issues/2)、[#3](https://github.com/goingta/herdrm/issues/3)、[#4](https://github.com/goingta/herdrm/issues/4) |
| 06 | [#6 — 工作区筛选与已有 Agent 状态](https://github.com/goingta/herdrm/issues/6) | 无 |
| 07 | [#7 — 原生终端与控制键](https://github.com/goingta/herdrm/issues/7) | 无 |
| 08 | [#8 — 按设备和 Agent 保存草稿与选择](https://github.com/goingta/herdrm/issues/8) | 无 |
| 09 | [#9 — Prompt 提交确认与待核对状态](https://github.com/goingta/herdrm/issues/9) | [#8](https://github.com/goingta/herdrm/issues/8) |
| 10 | [#10 — 锁屏与断网后的终端恢复](https://github.com/goingta/herdrm/issues/10) | [#7](https://github.com/goingta/herdrm/issues/7) |
| 11 | [#11 — 冷启动恢复 Agent 开发上下文](https://github.com/goingta/herdrm/issues/11) | [#9](https://github.com/goingta/herdrm/issues/9) |
| 12 | [#12 — 完整 URL 的 App 内预览与导航](https://github.com/goingta/herdrm/issues/12) | 无 |
| 13 | [#13 — SSH 远端端口的 App 内预览](https://github.com/goingta/herdrm/issues/13) | [#2](https://github.com/goingta/herdrm/issues/2)、[#12](https://github.com/goingta/herdrm/issues/12) |
| 14 | [#14 — 保存预览、工作区关联与站点隔离](https://github.com/goingta/herdrm/issues/14) | [#13](https://github.com/goingta/herdrm/issues/13) |
| 15 | [#15 — API、WebSocket 与同源 HMR 预览](https://github.com/goingta/herdrm/issues/15) | [#13](https://github.com/goingta/herdrm/issues/13) |
| 16 | [#16 — 锁屏、断网与网页终止后的预览恢复](https://github.com/goingta/herdrm/issues/16) | [#14](https://github.com/goingta/herdrm/issues/14)、[#15](https://github.com/goingta/herdrm/issues/15) |
| 17 | [#17 — 可复制的连接与恢复诊断](https://github.com/goingta/herdrm/issues/17) | [#5](https://github.com/goingta/herdrm/issues/5)、[#10](https://github.com/goingta/herdrm/issues/10)、[#13](https://github.com/goingta/herdrm/issues/13) |
| 18 | [#18 — 完整开发流程与稳定性验收](https://github.com/goingta/herdrm/issues/18) | [#1](https://github.com/goingta/herdrm/issues/1)、[#6](https://github.com/goingta/herdrm/issues/6)、[#11](https://github.com/goingta/herdrm/issues/11)、[#16](https://github.com/goingta/herdrm/issues/16)、[#17](https://github.com/goingta/herdrm/issues/17) |

GitHub 原生关系编辑器报 Cannot edit issues right now，重试后仍未保存关系。本轮使用每个 Issue 正文中的 Blocked by 真实链接表示依赖；不能依赖原生阻塞计数领取任务。ready-for-agent 表示规格完整，仍须核对正文中的阻塞项全部完成。

## 拆分原则

- 共 18 项，每项包含用户行为、存储/传输/UI 所需改动与对应验证，可独立演示或验收。每项以一个新的工作上下文可完成为目标。
- 原生 HerdrMobile 已有设备模型、RPC 和终端接口，可作为共同基线；不把已经存在的能力再包装成所有任务的前置依赖。原型仅供行为参考，正式入口移除个人配置和原型耦合。
- 每项先完成自身所需的小范围整理，再补功能；当前没有证据需要全局重构，不设所有任务都依赖的“基础层重构”票。SSH 转发的资源所有权整理归入端口预览，密钥错误语义整理归入配对。
- 阻塞关系只表示缺少前置交付就不能完成本任务，不表示不能提前设计或阅读。共享界面或模型的编辑需要协调，但代码位置相同不自动构成阻塞。
- 每项都进行相应验证；18 是产品整体集成与验收证据汇总，不能替代各任务验证。是否增加完整 App UI 自动化，仍沿用规格中的待确认测试建议，不额外扩展首版范围。

## 编号任务

1. **[开发机配置与切换](01-device-profiles.md)**
   - 阻塞：无，可立即开始。
   - 交付：在 App 中新增、编辑、删除和切换开发机，并保存连接字段；配置改变后使用新入口连接，旧结果不会覆盖当前设备。

2. **[HTTP CONNECT 网关连接](02-http-connect.md)**
   - 阻塞：无，可立即开始。
   - 交付：用户填写网关主机和端口后，经 HTTP CONNECT 完成 SSH 认证及 herdr 读取，也能切回直连。

3. **[手机公钥配对与撤销指导](03-phone-key-pairing.md)**
   - 阻塞：无，可立即开始。
   - 交付：用户查看手机公钥及指纹，复制登记命令在远端执行，然后使用同一手机身份登录；密钥访问失败时获得明确修复提示。

4. **[服务器指纹确认与变化处理](04-host-trust.md)**
   - 阻塞：无，可立即开始。
   - 交付：首次连接由用户核对服务器指纹后信任；指纹变化时阻止认证，用户核对后才能明确更新信任。

5. **[分阶段连接测试与修复提示](05-connection-check.md)**
   - 阻塞：02、03、04。
   - 交付：点击测试连接后，用户看到网络/网关、主机校验、认证和 herdr 探测的结果，并能按失败原因修复。

6. **[工作区筛选与已有 Agent 状态](06-agent-discovery.md)**
   - 阻塞：无，可立即开始。
   - 交付：用户按 Space/workspace 查看已有 Agent，读取实时状态；连接恢复中、列表为空和目标被删除有不同呈现。

7. **[原生终端与控制键](07-terminal-controls.md)**
   - 阻塞：无，可立即开始。
   - 交付：用户附着已有 Agent 或普通终端，查看实时画面并发送必要控制键；电脑同时连接时得到明确接管行为。

8. **[按设备和 Agent 保存草稿与选择](08-agent-drafts.md)**
   - 阻塞：无，可立即开始。
   - 交付：用户切换开发机或 Agent、锁屏或重启后能找回各自的未发送草稿和原选择，不发生跨项目混用。

9. **[Prompt 提交确认与待核对状态](09-prompt-receipts.md)**
   - 阻塞：08。
   - 交付：用户发送中文、多行 prompt 后看到明确提交状态；重复点击和断网不会触发客户端自动重复提交。

10. **[锁屏与断网后的终端恢复](10-terminal-resume.md)**
   - 阻塞：07。
   - 交付：用户锁屏或切换网络再返回时保留终端原画面，显示恢复状态并自动重建连接，恢复后继续操作。

11. **[冷启动恢复 Agent 开发上下文](11-agent-cold-start.md)**
   - 阻塞：09。
   - 交付：用户强制结束 App 后重新打开，回到保存的开发机和 Agent，找回草稿及待核对状态并重新附着当前终端。

12. **[完整 URL 的 App 内预览与导航](12-url-preview.md)**
   - 阻塞：无，可立即开始。
   - 交付：用户在正式 App 中输入 HTTP/HTTPS URL，浏览页面、返回/前进/刷新，并切回 Agent 继续操作。

13. **[SSH 远端端口的 App 内预览](13-ssh-port-preview.md)**
   - 阻塞：02、12。
   - 交付：用户选择开发机并输入服务端口，App 经 SSH 私有转发加载网页和并发资源，终端与 prompt 仍可使用。

14. **[保存预览、工作区关联与站点隔离](14-saved-preview-targets.md)**
   - 阻塞：13。
   - 交付：用户给端口或 URL 预览命名、关联工作区并重复打开；每次一个活动目标，不串用不同项目的浏览数据或路径。

15. **[API、WebSocket 与同源 HMR 预览](15-preview-websocket-hmr.md)**
   - 阻塞：13。
   - 交付：SSH 预览中的相对 API、同源 WebSocket 和 HMR 可正常交互，页面实时更新时 Agent 仍可操作。

16. **[锁屏、断网与网页终止后的预览恢复](16-preview-resume.md)**
   - 阻塞：14、15。
   - 交付：用户返回前台或重启 App 时恢复原预览目标、地址和有效登录状态，WebSocket/HMR 再次可用，Agent 上下文不受影响。

17. **[可复制的连接与恢复诊断](17-copyable-diagnostics.md)**
   - 阻塞：05、10、13。
   - 交付：用户在连接或预览失败后查看时间、阶段、错误和重连耗时，复制脱敏诊断以描述问题。

18. **[完整开发流程与稳定性验收](18-real-device-acceptance.md)**
   - 阻塞：01、06、11、16、17。
   - 交付：证明正式 App 能完成配对、已有 Agent 开发、项目预览及故障后恢复，给出可重复的验收结果。

## 依赖说明

- 05 等待网关、密钥错误语义和主机信任交互，才能完整验证各连接阶段。
- 09 等待 08 的设备/pane 草稿及持久状态归属；11 等待 09 后便具备冷启动所需的草稿和待确认记录，08 是传递依赖。
- 10 需要 07 验证后的终端附着及控制键行为；不等待 URL 或端口预览。
- 13 需要 02 的正式 CONNECT 能力和 12 的正式网页入口。使用既有设备认证/RPC 接口，不等待完整诊断或 Agent 列表改进。
- 14 与 15 在 13 后分别完成目标管理和网页交互，可以并行；14 同时覆盖两种入口，12 已是传递依赖。
- 16 需要目标身份、隔离存储及真实 WebSocket/HMR 行为，才能验证正确目标的恢复，不等待 Agent 终端恢复。
- 17 汇总 05、10、13 的阶段及恢复结果；Agent 的提交状态或预览收藏不阻塞诊断交付。
- 18 只列叶节点 01、06、11、16、17，其他任务通过传递依赖覆盖，不重复列出全部任务。

## 可立即开始的任务

01、02、03、04、06、07、08、12 无阻塞。这里表示逻辑上可分别开发，不表示已安排并行 Agent，也不承诺共享文件不存在合并冲突。

## 发布结果

18 项按依赖顺序创建，全部具有交付行为、验收条件、验证方法及真实阻塞链接；覆盖 44 条用户故事。未自动分配、关闭任务或开始编码，当前可领取前沿仍为 01、02、03、04、06、07、08、12。

项目 skills 配置已应用到 CLAUDE.md 和 docs/agents；[配置确认记录](../iphone-agent-skills-setup.md)保存批准时的内容。未修改或关闭任何父 Issue；本次源规格是本地文档，没有既有父 Issue。发布编号映射保存于 github-publication.json。

