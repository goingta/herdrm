# V01 — 统一两端 Logo 与正式应用名称

状态：已批准并发布，标签 ready-for-agent；实施尚未开始。GitHub：[[双端 UI] V01 — 统一两端 Logo 与正式应用名称](https://github.com/goingta/herdrm/issues/20)。

## What to build

用户安装 Mac 和 iPhone 正式 App 后看到同一 herdrm 名称和同一 Logo 构图，能辨认为同一产品。

## Acceptance criteria

- [ ] 沿用现有 Logo 源素材，分别接入两端应用图标；系统裁剪、尺寸和呈现按平台处理，不另设计手机 Logo。
- [ ] 正式应用的安装名称与应用内品牌名称统一；现有配置、凭据和应用身份不因显示名称调整而丢失。
- [ ] 两端安装图标不为空；保持 Mac 现有图标构图，iPhone 18.7.3 真机显示正确。

## Verification

检查源素材归属及打包资源，构建两端并查看实际安装图标和显示名称；不为图标像素常量编写镜像测试。

## Blocked by

None — can start immediately.

## Spec coverage

统一 Logo 与正式应用名称；两端资源适配。 基于 Mac 与 iPhone 视觉一致性规格 v1.0，产品选择、任务颗粒度和依赖均已确认。

<!-- herdrm-visual-v1-ticket:V01 -->
