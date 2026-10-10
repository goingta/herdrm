# 16 — 锁屏、断网与网页终止后的预览恢复

状态：已批准并发布，标签 ready-for-agent；实施尚未开始。GitHub：[[iPhone] 16 — 锁屏、断网与网页终止后的预览恢复](https://github.com/goingta/herdrm/issues/16)。

## What to build

用户返回前台或重启 App 时恢复原预览目标、地址和有效登录状态，WebSocket/HMR 再次可用，Agent 上下文不受影响。

## Acceptance criteria

- [ ] 进程仍在时保留网页或明确恢复画面，先恢复可达通道再加载，不加载旧目标的新端口路径。
- [ ] 保存最后可恢复 URL/path/query/fragment；恢复站点存储及有效登录数据，过期登录遵循项目网页自身流程。
- [ ] WebContent 终止或 App 冷启动允许重新加载；不承诺恢复任意 JavaScript 内存、未提交表单和全部滚动状态。
- [ ] 锁屏及网络变化后 API/WebSocket/HMR 再次可用；失败有重试入口，恢复不清除 Agent 草稿、选择或写操作确认状态。

## Verification

真机锁屏、网络切换、强制结束 App，另触发可控网页进程终止；恢复后访问 API、推送 WebSocket 数据并再次触发 HMR。

## Blocked by

- 14 — 保存预览、工作区关联与站点隔离
- 15 — API、WebSocket 与同源 HMR 预览

## Spec coverage

用户故事：38、39、43。基于 iPhone 远端开发规格 v0.4；与当前实现相比，本任务应补齐、整理或验证上述完整行为，已有能力不必重写。

