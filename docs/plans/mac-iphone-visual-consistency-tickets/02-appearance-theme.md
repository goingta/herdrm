# V02 — 统一 App 与终端主题及外观设置

状态：已批准并发布，标签 ready-for-agent；实施尚未开始。GitHub：[[双端 UI] V02 — 统一 App 与终端主题及外观设置](https://github.com/goingta/herdrm/issues/21)。

## What to build

用户在任一客户端选择跟随系统、浅色或深色，App 和终端同时呈现 Mac 视觉体系；切换外观后可以继续当前开发任务。

## Acceptance criteria

- [ ] 提取两端共用的明暗配色和视觉层级，平台专属外观处理保留在各自适配处；现有调用逐步迁移，两个 App 在各阶段仍可构建。
- [ ] 两端提供跟随系统/浅色/深色，默认跟随系统，选择在当前客户端保存并在重启后恢复。
- [ ] App 和终端采用所选模式；浅色终端的中文、ANSI 文本、光标和选区可读，不能仅改变背景。
- [ ] 列表选中、强调色、分隔线和现有工作中/等待输入状态使用同一视觉定义；完成未读的行为改变由 [#24 — [双端 UI] V05 — 统一两端完成未读规则与本地保存](https://github.com/goingta/herdrm/issues/24) 负责。
- [ ] 切换模式不触发 SSH 重连，不清除 Agent 草稿或预览目标；后续网页内容主题由项目网站自行决定。

## Verification

构建两端，对比跟随系统/浅色/深色截图，在连接中的终端切换外观并核对连接连续性和文字可读性。

## Blocked by

None — can start immediately.

## Spec coverage

第一轮选择 1；共享主题、基本状态样式、App 与终端外观边界。 基于 Mac 与 iPhone 视觉一致性规格 v1.0，产品选择、任务颗粒度和依赖均已确认。

<!-- herdrm-visual-v1-ticket:V02 -->
