# 03 — 手机公钥配对与撤销指导

状态：已批准并发布，标签 ready-for-agent；实施尚未开始。GitHub：[[iPhone] 03 — 手机公钥配对与撤销指导](https://github.com/goingta/herdrm/issues/3)。

## What to build

用户查看手机公钥及指纹，复制登记命令在远端执行，然后使用同一手机身份登录；密钥访问失败时获得明确修复提示。

## Acceptance criteria

- [ ] 首次生成并成功保存 Ed25519 身份后才用于登录；正常重启复用原密钥。
- [ ] 密钥不存在与读取/保存失败可区分；失败不会静默生成替代身份，错误同时反映在配对页和连接结果中。
- [ ] 登记命令可重复执行，保留已有 authorized_keys、首次修改前备份并设置权限；App 不自行修改远端。
- [ ] 配对页可复制公钥和指纹，说明如何单独撤销该手机公钥；删除单台开发机不销毁共用手机身份。

## Verification

在可丢弃账号运行登记命令两次，确认公钥只有一行且旧登录仍可用；验证 Keychain 失败与正常重启。

## Blocked by

None — can start immediately.

## Spec coverage

用户故事：7、8、9、14、15。基于 iPhone 远端开发规格 v0.4；与当前实现相比，本任务应补齐、整理或验证上述完整行为，已有能力不必重写。

