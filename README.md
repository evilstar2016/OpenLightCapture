# OpenLightCapture

<img src="LightCapture/Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" width="80" height="80" alt="OpenLightCapture 图标">

一个开源、本地运行的 macOS 菜单栏截图工具。框选、标注、长截图，完成后直接复制图片，也能在 Finder 中粘贴成 PNG 文件。

**简体中文** · [English](README.en.md)

欢迎在 X 关注作者 [@EverSeenU](https://x.com/EverSeenU)，了解项目动态与开发记录，也欢迎交流使用体验。

[操作手册](docs/OPERATION_MANUAL.md) · [使用指南](docs/USER_GUIDE.md) · [从源码构建](docs/DEVELOPMENT.md) · [参与贡献](CONTRIBUTING.md) · [隐私说明](PRIVACY.md) · [更新记录](CHANGELOG.md)

## 能做什么

| 功能 | 说明 |
|---|---|
| 区域与窗口截图 | 默认快捷键 `⇧⌘A`，`Space` 切换区域/窗口选择 |
| 直接标注 | 矩形、椭圆、箭头、画笔、文字、马赛克，均可选中拖动，支持样式调整和撤销/重做 |
| 自动与手动长图 | 逐段检查拼接可靠性，支持暂停、继续和使用已确认部分 |
| 图片与文件粘贴 | 同一剪贴板项目提供 PNG 和文件 URL；在图片接收应用或 Finder 中按 `⌘V` |
| 另存 PNG | 自选目录，同时保留复制流程 |
| 中英文界面 | 跟随系统、简体中文或 English；选择自动保存 |
| 原生运行 | 菜单栏入口、可配置快捷键、可选登录时启动，无账号和云端处理 |

图片处理在本机完成，当前应用没有网络请求、遥测或第三方运行时依赖。为选区预览会临时读取显示器画面，为 Finder 粘贴会保存本地 PNG；具体数据与保留规则见 [PRIVACY.md](PRIVACY.md)。

## 项目状态与支持范围

当前开发版本为 **0.5.2（构建 25，未发布）**。

- 目标系统：macOS 14 及以上。
- 构建架构：Apple Silicon `arm64` 与 Intel `x86_64`。Intel 和更早 macOS 的实机覆盖尚不完整。
- 在 macOS 27.0.1、Apple Silicon、Xcode 27.1 上完成更名验证：196 项 XCTest、arm64/x86_64 构建、签名和中英文本地化资源检查通过。新应用身份的真实权限与 GUI 流程仍需实机验收。
- 当前本地构建使用 ad hoc 签名，尚未进行 Developer ID 签名或 Apple 公证。

支持边界和历史验收情况见 [已知限制](docs/USER_GUIDE.md#limits) 与 [开发验证说明](docs/DEVELOPMENT.md)。

## 获取与构建

OpenLightCapture 尚未发布安装包，目前请从源码构建。应用支持 Apple Silicon 和 Intel。

本地构建采用 ad hoc 签名，尚未完成 Developer ID 签名与 Apple 公证。仓库不提交本机 `build/` 目录。

需要完整 Xcode、Swift 6 工具链和 [XcodeGen](https://github.com/yonaskolb/XcodeGen)。在终端运行：

```sh
git clone https://github.com/evilstar2016/OpenLightCapture.git
cd OpenLightCapture
xcodegen generate
xcodebuild -project OpenLightCapture.xcodeproj \
  -scheme OpenLightCapture \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath build/DerivedData \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  build
ditto build/DerivedData/Build/Products/Release/OpenLightCapture.app build/OpenLightCapture.app
```

打开 `build/OpenLightCapture.app` 即可使用。也可以在 Xcode 中打开工程后运行。开发环境、验证命令与签名说明见 [开发指南](docs/DEVELOPMENT.md)。

## 第一次使用

1. 打开应用后，从菜单栏选择“截图”，或按 `⇧⌘A`。应用默认不显示 Dock 图标。
2. 按提示开启屏幕录制权限；授权后退出并重新打开应用。
3. 拖动框选，按 `Space` 切换窗口选择。选区工具栏可直接标注和调整样式。
4. 点击“完成并复制”，或使用 `Enter` / `⌘C` 完成；在目标应用或 Finder 中按 `⌘V`。
5. 使用保存按钮或 `⌘S` 另存 PNG。长截图需要先结束采集，再在编辑器中完成并复制。

默认快捷键可能与飞书冲突，可在任一应用中修改。截图只在你主动发起时开始；自动长图额外需要控制权限，普通截图和手动长图不需要该项权限。

## 语言与权限

“设置 / Settings”支持跟随系统、简体中文和 English。没有匹配语言时使用英文。空闲时立即切换；正在截图或编辑时，在本次会话完成或取消后生效。系统弹窗可能继续使用系统语言。

| 权限 | 使用场景 |
|---|---|
| 屏幕录制 | 普通截图、手动长图、自动长图 |
| 辅助功能 / 控制电脑 | 仅用于用户发起的自动滚动；系统名称随 macOS 版本变化 |

不请求麦克风、摄像头或全盘访问。权限排查、长图用法和卸载步骤见 [使用指南](docs/USER_GUIDE.md)。

## 长截图的边界

长图最多 50,000 像素高、60 百万总像素和 180 秒活动采集时间。重复内容、固定栏、动态区域、横向漂移或滚动过快可能影响拼接。无法确认完整性时，应用会暂停或提示部分结果，不把不确定的内容标为完整。

当前不提供录屏、OCR、云同步、截图历史库或横向长图。更多细节见 [使用指南](docs/USER_GUIDE.md#limits)。

## 参与项目

- 问题与建议：[GitHub Issues](https://github.com/evilstar2016/OpenLightCapture/issues)，可用中文或英文。
- 提交修改：[贡献指南](CONTRIBUTING.md)，包含测试、翻译和 PR 要求。
- 使用问题：[支持说明](SUPPORT.md)。
- 安全漏洞：按 [安全政策](SECURITY.md) 联系，勿在公开 Issue 中附利用细节或敏感截图。
- 社区交流：[行为准则](CODE_OF_CONDUCT.md)。

本项目采用 [MIT License](LICENSE)。Apple 系统框架及开发工具适用各自条款，见 [第三方说明](THIRD_PARTY_NOTICES.md)。
