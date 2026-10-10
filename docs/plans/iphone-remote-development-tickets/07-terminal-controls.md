# 07 — 原生终端与控制键

状态：已批准并发布，标签 ready-for-agent；实施尚未开始。GitHub：[[iPhone] 07 — 原生终端与控制键](https://github.com/goingta/herdrm/issues/7)。

## What to build

用户附着已有 Agent 或普通终端，查看实时画面并发送必要控制键；电脑同时连接时得到明确接管行为。

## Acceptance criteria

- [ ] Agent 按 pane 目标附着，普通终端按 terminal 目标附着；正常输出、中文、尺寸变化和键盘操作可用。
- [ ] Esc、Tab、方向键、Enter、Ctrl+C 到达当前目标；通道未就绪时阻止控制键发送，重连不重放。
- [ ] 普通终端输入与 Agent prompt 路径分开，发送到正确目标。
- [ ] 真机和电脑同时附着验证尺寸与控制权；沿用既有 takeover 契约时展示接管说明，服务端冲突不冒充网络故障。

## Verification

使用真实 herdr 的可丢弃 Agent/terminal，逐项观察按键结果、尺寸变化及电脑同时附着行为。

## Blocked by

None — can start immediately.

## Spec coverage

用户故事：19、21、22、29。基于 iPhone 远端开发规格 v0.4；与当前实现相比，本任务应补齐、整理或验证上述完整行为，已有能力不必重写。

