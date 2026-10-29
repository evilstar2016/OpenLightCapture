# 开发指南 / Development

## 环境 / Prerequisites

需要 macOS、完整 Xcode（不仅是 Command Line Tools）、Swift 6、XcodeGen。最近的完整验证使用 macOS 27.0.1、Xcode 27.1、Apple Silicon；最低应用运行目标为 macOS 14，不代表所有旧工具链已经验证。

Full Xcode, Swift 6, and XcodeGen are required. SwiftFormat and Python 3 are additionally required by the verification script. Runtime deployment targets macOS 14+, while the recorded toolchain is newer.

可通过各工具的官方安装方式安装 [XcodeGen](https://github.com/yonaskolb/XcodeGen)、[SwiftFormat](https://github.com/nicklockwood/SwiftFormat)。使用 Homebrew 时：

```sh
brew install xcodegen swiftformat
xcodebuild -version
xcrun swift --version
xcodegen --version
swiftformat --version
python3 --version
```

在 Xcode 的 Settings → Locations 中选择正确的 Command Line Tools；如果 `xcodebuild` 指向单独的 CLT 目录，先修正工具链选择。

## 构建 / Build

先按 [README](../README.md#获取与构建) 克隆并构建。配置来源是 [project.yml](../project.yml)，`.xcodeproj` 同时保留在仓库中，便于直接打开；修改配置或新增文件后重新生成，并一起评审差异。

```sh
xcodegen generate
open OpenLightCapture.xcodeproj
```

选择 `OpenLightCapture` scheme 后运行。现有配置采用 ad hoc 签名、默认 Bundle ID `io.github.evilstar2016.openlightcapture`，不需要把开发账号或证书写入仓库。本地签名不等于 Developer ID、公证或 App Store 分发；公开发行见 [发布指南](RELEASING.md)。

构建产物、工程、scheme、应用 target 和可执行文件使用 `OpenLightCapture`，中英文显示名均为 OpenLightCapture。源码目录、Swift 模块和测试 target 分别为 `LightCapture` / `LightCaptureTests`。仓库地址为 `evilstar2016/OpenLightCapture`。

## 测试 / Tests

```sh
xcodebuild -project OpenLightCapture.xcodeproj \
  -scheme OpenLightCapture \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath build/TestDerivedData \
  test
```

按需加 `-only-testing:LightCaptureTests/LocalizationTests` 等 XCTest 过滤参数。测试使用隔离数据目录和私有剪贴板；不要为测试申请真实截图权限或注册用户热键。真实权限、输入法和跨应用粘贴另行手工验收。

```sh
swiftformat LightCapture LightCaptureTests --lint --swiftversion 6
python3 scripts/verify-localizations.py
bash scripts/verify.sh
```

完整脚本会生成工程、检查格式、运行全部 XCTest 与覆盖率、构建 arm64/x86_64 Release，并校验架构、签名、Info.plist 和本地化资源。结果保存在 `build/verification/<时间>-<PID>/`，Release 位于 `build/DerivedData/Build/Products/Release/`。它不负责公证或发布，也不自动覆盖标准交付 app/ZIP。

The full script regenerates the project, lints Swift, runs tests/coverage, builds both architectures, and validates signing/metadata/localizations. GUI and real permission tests remain separate. Check the generated logs and state any untested conditions in a PR.

自动滚动通过 `CGEventPostToPid` 向绑定窗口所属进程投递原生像素滚轮，避免全局事件流改写真实光标位置。窗口路由还需要未公开的 CoreGraphics 窗口标签与 `CGEventSetWindowLocation`；后者通过运行时查找使用，缺失时暂停采集，不退回全局投递。此兼容路径不新增权限，但系统升级后仍需实测原生 App、浏览器、光标位置以及暂停/继续；仅通过单元测试不能证明跨应用滚动有效。

## 手工验证 / Manual checks

使用不含私人内容的合成页面、图像或临时文档，避免公开私人截图。请自行准备不含私人内容的测试样本。建议按改动覆盖：

- 普通区域/窗口、Retina/多显示器坐标、边缘与小选区。
- 标注样式、撤销/重做、输入法组合、文字移动与继续编辑。
- 手动/自动长图、暂停与部分结果、目标切换及容量上限。
- 保存成功/取消、图片接收应用和 Finder 文件粘贴。
- 中英文、浅深外观、会话期间语言切换。

不要把“测试页存在”“能编译”或“只核对 OCR 行号”写成完整实机验收；记录实际使用的样本、操作、输出和未覆盖的环境。

## 可选性能与图像验证 / Optional probes

```sh
bash scripts/performance.sh
bash scripts/performance.sh build/capacity-local capacity
```

性能探针编译生产核心，在独立进程中使用合成图像、临时工作区和私有剪贴板；不采集真实屏幕，也不代替整机性能与 GUI 时延测量。大容量模式的内存和耗时较高，按需运行。

`verify-long-image.py` 使用 Tesseract；其可选裁剪检查及 `verify-image-coverage.py` 另需 Pillow/LittleCMS。它们不是应用或常规 XCTest 的运行依赖。通过各脚本的 `--help` 查看参数，并使用自己的样本和输出图片。

## 产物与目录 / Generated data

`build/` 为生成目录，不纳入 Git。运行构建、测试或性能脚本会重新生成缓存、日志和临时文件。清理时先确认需要保留的 app/ZIP；不要对应用实际的数据目录进行构建清理。

当前为 OpenLightCapture 1.0.0（构建 27），发行入口为 [v1.0.0](https://github.com/evilstar2016/OpenLightCapture/releases/tag/v1.0.0)。在 macOS 27.0.1、Apple Silicon、Xcode 27.1 上，199 项 XCTest、双架构 Release、签名与本地化检查通过。DMG 在上传前完成校验与只读挂载检查；当前采用 ad hoc 签名，尚未进行 Apple 公证。真实系统权限和跨应用 GUI 流程仍需实机验收。可运行上述命令重新验证；当前仓库未配置 GitHub Actions 工作流。
