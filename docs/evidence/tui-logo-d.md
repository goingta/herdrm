# D 版 Logo 资源验收

用户选择 D「极简状态行」，并明确以原 herdrm 的 TUI Logo 为参照。
正式资源保留原有的侧栏 / 终端构图，将三个 Agent 卡片简化为递减的灰色
状态行和亮绿方点，右侧为亮绿 `>` 与白色块光标。正式图标使用绿色，UI
主题切换不增加动态图标功能。

生成的 D 概念图作为视觉参考，最终在已有
`Resources/AppIcon/herdrm-icon.svg` 中重建可编辑矢量图。
没有裁切、编辑或直接打包概念展示板；没有使用用户的 Moshi 截图作为资源。

## 资源与尺寸

- canonical / Mac source：1024 × 1024 sRGB，全幅正方形，所有像素不透明。
- iOS AppIcon：同构图、1024 × 1024 RGB PNG，无 alpha 通道，无预烘焙圆角。
- 圆角文档预览：256 × 256，带透明角，仅用于预览，不进入平台图标生成链。
- canonical 与 Mac source 的文件 SHA-256 相同：
  `c154ad05ec341ad25732bd7add2dc4e7d0dcf3d5e0ebe03e8e3e25443426938c`。
- mobile source SHA-256：
  `40c8431f670810d6c33e7d7cc5a4f3bf0e524e7e3fa2b82ee4574d5a6a0e3bbe`。
- CoreGraphics 统一解码为 sRGB RGBA 后，canonical / Mac / iOS 源逐像素相同，
  所有 alpha 均为 255；三个图标消费者全部同步。

![正式 full-bleed 原图](tui-logo-d/canonical-1024.png)

## 验证结果

已执行现有平台适配脚本，并实际查看 full-size 源图、小尺寸 iOS 编译结果、
以及 Mac Icon Composer 的编译结果。120 px 的 iOS 图标中状态行 / 方点 / 提示符
可辨认；Mac 图标仍由 Icon Composer 施加系统 mask 与现有表现。

```sh
swift Resources/AppIcon/generate-mobile-icon.swift

xcrun actool Resources/AppIcon/MobileAssets.xcassets \
  --compile /private/tmp/herdr-tui-logo-d-ios \
  --platform iphoneos --minimum-deployment-target 18.0 \
  --app-icon AppIcon \
  --output-partial-info-plist /private/tmp/herdr-tui-logo-d-ios/icon-info.plist \
  --target-device iphone --target-device ipad

xcrun actool Sources/HerdrM/AppIcon.icon \
  --compile /private/tmp/herdr-tui-logo-d-mac \
  --platform macosx --minimum-deployment-target 26.0 \
  --app-icon AppIcon \
  --output-partial-info-plist /private/tmp/herdr-tui-logo-d-mac/icon-info.plist \
  --target-device mac
```

两次 actool 资源编译均成功，分别产生 `Assets.car` 与 iOS AppIcon PNG / Mac
`AppIcon.icns`。本步骤未运行模拟器、未操作手机，也不把资源编译等同于完整
App 构建或真机图标验收；合入后随正式 App 构建、安装，由用户核对主屏幕图标。

![iOS 编译图标](tui-logo-d/compiled-ios-120.png)
![Mac 编译图标](tui-logo-d/compiled-mac-256.png)

本资源改动未修改 `project.yml`、`Sources/HerdrMobile/Info.plist`、
`Sources/HerdrM/AppIcon.icon/icon.json`，未修改 bundle 标识、签名或 ATS 设置。

最终与双主题一起集成至 `b29c7387`，完整 Mac/iPhone App 构建成功。正式 iPhone 包更新安装成功；自动启动因手机锁屏被拒绝，主屏幕 D 图标的用户真机验收仍待完成，不能以 actool 结果代替。
