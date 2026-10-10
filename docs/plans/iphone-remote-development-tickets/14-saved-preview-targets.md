# 14 — 保存预览、工作区关联与站点隔离

状态：已批准并发布，标签 ready-for-agent；实施尚未开始。GitHub：[[iPhone] 14 — 保存预览、工作区关联与站点隔离](https://github.com/goingta/herdrm/issues/14)。

## What to build

用户给端口或 URL 预览命名、关联工作区并重复打开；每次一个活动目标，不串用不同项目的浏览数据或路径。

## Acceptance criteria

- [ ] 保存、编辑、删除多个端口/URL 目标并关联开发机与工作区；重启后记录保留。
- [ ] 切换目标关闭上一活动转发；从工作区方便进入对应预览并返回 Agent。
- [ ] 目标身份绑定稳定 origin 与浏览数据存储；不同目标的 cookie、localStorage 和恢复地址隔离。
- [ ] 删除设备清除其所属预览；服务端口或设备改变后不能误用旧目标路径与登录数据。

## Verification

两个服务设置同名 cookie/localStorage 和不同路径，切换及重启后核对各自数据；验证编辑目标和删除设备。

## Blocked by

- 13 — SSH 远端端口的 App 内预览

## Spec coverage

用户故事：34、36、39、40。基于 iPhone 远端开发规格 v0.4；与当前实现相比，本任务应补齐、整理或验证上述完整行为，已有能力不必重写。

