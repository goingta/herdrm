# V04 — 适配手机版开发机、工作区与 Agent 界面

状态：已批准并发布，标签 ready-for-agent；实施尚未开始。GitHub：[[双端 UI] V04 — 适配手机版开发机、工作区与 Agent 界面](https://github.com/goingta/herdrm/issues/23)。

## What to build

用户在手机上用接近 Mac 信息层级的紧凑列表管理开发机、选择工作区并进入已有 Agent 终端，保留清晰的触控操作和键盘空间。

## Acceptance criteria

- [ ] 开发机选择与新增/编辑/删除表单、工作区和 Agent 列表使用统一主题、图标、分组和选中样式，减少大标题与大块卡片。
- [ ] 按设备和 Agent 身份呈现当前选择，长中文名称和重名仍能辨认；保留只操作已有 Agent 的首版范围。
- [ ] 手机可点击区域至少 44 点；文本放大后允许换行和增加行高，不截断关键操作；终端控制键及输入框不被键盘遮挡。
- [ ] 连接中、失败与真正空列表有不同呈现，恢复过程中不以未选择空状态替代已保存目标。
- [ ] 本任务改造既有页面；预览入口和网页导航仍由 #12 完成，使用同一套基础组件，不加入无功能的预览占位页。

## Verification

使用 #1 已验证的配置管理行为，在 iPhone 13 / iOS 18.7.3 检查选择、表单、长名称、放大文本、键盘及浅深色界面；保留既有 Agent 和终端操作。

## Blocked by

- [#21 — [双端 UI] V02 — 统一 App 与终端主题及外观设置](https://github.com/goingta/herdrm/issues/21)
- [#1 — 开发机配置与切换](https://github.com/goingta/herdrm/issues/1)。

## Spec coverage

第一轮选择 3；移动端触控和页面适配；既有状态组件的展示。 基于 Mac 与 iPhone 视觉一致性规格 v1.0，产品选择、任务颗粒度和依赖均已确认。

<!-- herdrm-visual-v1-ticket:V04 -->
