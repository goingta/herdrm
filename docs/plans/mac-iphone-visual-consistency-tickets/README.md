# Mac 与 iPhone 视觉一致性：已发布任务索引

2026-10-10。来源：[已确认规格 v1.1](../../specs/mac-iphone-visual-consistency.md)与 [ADR 0001](../../adr/0001-client-owned-agent-read-state.md)。用户已批准规格、六项拆分和依赖，任务已发布到 goingta/herdrm 的 GitHub Issues，均为 open、ready-for-agent；六项新任务及三项既有任务更新的正文与标签已回读核对。实施在 `codex/mac-iphone-ui-integration` 集成分支进行，见 [PR #26](https://github.com/goingta/herdrm/pull/26)。#1 真机表单通过，#20/#21/#22/#24 及前置 #2/#12 已集成；#23 正按 v1.1 Space/真实 Tab/分屏菜单导航实施，#25 待最终双端验收。

## 任务与阻塞关系

| 编号 | GitHub Issue | Blocked by | 独立交付 |
| --- | --- | --- | --- |
| V01 | [#20 — 统一 Logo 与应用名称](https://github.com/goingta/herdrm/issues/20) | 无 | 两端实际安装显示同一品牌 |
| V02 | [#21 — App 与终端主题及外观设置](https://github.com/goingta/herdrm/issues/21) | 无 | 两端三种外观设置生效并保存 |
| V03 | [#22 — 中英文文案与语言设置](https://github.com/goingta/herdrm/issues/22) | 无 | 两端语言一致，可切换并保存 |
| V04 | [#23 — 手机开发机、工作区与 Agent 界面](https://github.com/goingta/herdrm/issues/23) | [#21](https://github.com/goingta/herdrm/issues/21)、[#1](https://github.com/goingta/herdrm/issues/1) | 在既有功能上展示一致且可触控的界面 |
| V05 | [#24 — 完成未读规则与本地保存](https://github.com/goingta/herdrm/issues/24) | 无 | 两端状态行为一致，重启保留，互不清除 |
| V06 | [#25 — 双端视觉与可访问性验收](https://github.com/goingta/herdrm/issues/25) | [#20](https://github.com/goingta/herdrm/issues/20)、[#22](https://github.com/goingta/herdrm/issues/22)、[#23](https://github.com/goingta/herdrm/issues/23)、[#24](https://github.com/goingta/herdrm/issues/24)、[#12](https://github.com/goingta/herdrm/issues/12) | 对比截图、导航和真机操作证据 |

这些任务均包含可观察行为、需要的设置/状态及验证。#21 先增加共享定义，再逐步迁移调用，保持两端可构建；不单独增加只有结构整理而没有可验收效果的基础层任务。#24 可直接基于现有 Agent 和终端能力实施，不因编辑共享文件而强加 #6、#7、#8 的依赖。

## 已确认实施顺序

先完成 #1 真机表单验收 → #20 → #21 → #22 → #2 → #3 → #4 → #5 → #6 → #23 → #7 → #24 → #8 → #9 → #10 → #11 → #12 → #13 → #14 → #15 → #16 → #17 → #25 → #18。

此顺序满足全部 24 项任务的依赖，包括 #18 新增的 #25 阻塞项。#20、#21、#22、#24 没有逻辑阻塞；以上是逐项实施的优先顺序，不表示安排多个 Agent 并行。#25 的视觉证据并入 #18 完整流程验收，不重复执行同一验证。

## 与既有功能票的责任边界

- #2–#5 等后续页面采用 #21/#22 提供的视觉和语言定义；新增字段不另建一套主题。
- #6 负责真实工作区筛选与在线 Agent 状态，#23 负责当前列表、设备表单及终端控件的视觉与触控；#24 负责完成未读行为。
- #8/#11 负责草稿与选中上下文的保存和恢复；#24 负责未读状态，两类状态以同一目标身份隔离，互不覆盖。
- #12 负责正式 Agent/项目预览/设置导航中的实际网页入口与操作，使用统一组件；#23 不增加没有功能的预览页。
- #18 阻塞于 #25，复用视觉证据，继续覆盖后续预览恢复、连接诊断与完整日常开发流程。

## 本地任务正文

- [V01 — Logo 与名称](01-shared-app-icon.md)
- [V02 — 主题与外观](02-appearance-theme.md)
- [V03 — 语言设置](03-shared-language.md)
- [V04 — 手机页面适配](04-mobile-device-agent-ui.md)
- [V05 — 完成未读](05-persistent-agent-unread.md)
- [V06 — 视觉验收](06-cross-platform-visual-acceptance.md)

## 发布结果

六项按依赖顺序创建，未自动分配、关闭任务或开始编码。相关 #1、#12、#18 的正文已同步更新，没有父 Issue，也未修改或关闭任何父任务。

当前 GitHub 连接工具未提供原生 blocked_by 写入能力，既有 UI 尝试也未成功，因此使用 Issue 正文的真实阻塞链接。不要依赖 GitHub 原生阻塞计数领取任务；ready-for-agent 表示规格完整，仍须核对正文阻塞项完成。完整编号与依赖见 [github-publication.json](github-publication.json)。
