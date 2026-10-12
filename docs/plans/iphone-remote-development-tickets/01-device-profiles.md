# 01 — 开发机配置与切换

状态：已批准并发布，标签 ready-for-agent；代码与自动验证完成，真机表单验收待完成。 GitHub：[[iPhone] 01 — 开发机配置与切换](https://github.com/goingta/herdrm/issues/1)。

## What to build

在 App 中新增、编辑、删除和切换开发机，并保存连接字段；配置改变后使用新入口连接，旧结果不会覆盖当前设备。

## Acceptance criteria

- [ ] 名称、主机、用户名、SSH 端口及可选 socket 地址可编辑；空字段与无效端口在保存前提示。
- [ ] 多个开发机重启后仍存在；既有配置和密码认证可继续使用；正式入口不预置个人开发机。
- [ ] 编辑或切换设备取消旧连接；旧快照及延迟完成不会显示为新设备的数据。
- [ ] 删除设备关闭其连接、清除所属配置及已有本地状态；保留其他设备凭据及共用手机密钥，并说明远端权限需另行撤销。

## Verification

使用两台可区分的测试设备，编辑、切换、重启和删除；延迟其中一台响应，核对当前页面不串数据。

## Blocked by

None — can start immediately.

## Spec coverage

用户故事：1、3、4、5、6、15。基于 iPhone 远端开发规格 v0.4；与当前实现相比，本任务应补齐、整理或验证上述完整行为，已有能力不必重写。

<!-- herdrm-iphone-v1-ticket:01 -->

## Implementation status

2026-10-10：代码实现和自动验证完成，Draft PR [#19](https://github.com/goingta/herdrm/pull/19)。`make mobile-test` 在 arm64 iPhone 17 / iOS 26.5 Simulator 上 8 项全部通过，Standards / Spec 审查问题均已修复并复查；详见 PR 中 `docs/reviews/iphone-device-profiles.md`。

物理 iPhone 的新增、编辑、切换和删除表单验收待完成，因此 Issue 保持 open。自动测试在配置管理公开接口模拟旧连接/快照延迟和共用桥接，不代表物理设备验收。用户已确认新的顺序：完成本任务真机验收后，先实施 [#20 — 统一 Logo 与应用名称](https://github.com/goingta/herdrm/issues/20)、[#21 — 主题与外观设置](https://github.com/goingta/herdrm/issues/21)、[#22 — 语言设置](https://github.com/goingta/herdrm/issues/22)，随后继续 #2 HTTP CONNECT 网关连接。

