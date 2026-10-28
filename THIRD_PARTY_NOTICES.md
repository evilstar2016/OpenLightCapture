# 第三方与素材说明 / Third-party and asset notices

核对日期 / Reviewed: 2026-10-26。

## 项目许可

本仓库自有源码、文档及随附项目图标采用 [MIT License](LICENSE)，署名为 `evilstar2016`。此文件记录其他来源与工具，不替代项目许可证，也不为第三方内容授予额外权利。

## 应用运行依赖

当前工程没有集成第三方源码包、Swift Package Manager 依赖或第三方运行时二进制。应用使用 macOS SDK 框架，包括 AppKit、ApplicationServices、Carbon、CoreGraphics、CoreImage、CoreText、CoreVideo、Foundation、ImageIO、ScreenCaptureKit、ServiceManagement、SwiftUI 与 UniformTypeIdentifiers。

Apple 的 SDK、系统框架与 SF Symbols 适用 Apple 的相关条款，不因本仓库的 MIT License 而重新许可。

## 开发与验证工具

[XcodeGen](https://github.com/yonaskolb/XcodeGen)、[SwiftFormat](https://github.com/nicklockwood/SwiftFormat) 和 Python 用于开发或验证，不随 app 打包。部分可选图像验证需要 Tesseract、Pillow/LittleCMS；它们也不是应用运行依赖。使用或分发这些工具时遵守各自许可证。

## 图标与文档素材

应用图标由本项目使用 AI 图像生成工具生成母版，再通过 macOS `sips` / `iconutil` 导出尺寸与图标包。应用使用的图标尺寸文件位于 `LightCapture/Resources/Assets.xcassets/AppIcon.appiconset/`。未集成外部图标库。

复用第三方代码、图片、字体或新依赖的贡献应补充来源、版本和适用许可证。

## English

The project's own source, documentation, and included project icons use the [MIT License](LICENSE). The app currently bundles no third-party source packages, Swift packages, or third-party runtime binaries. Apple SDKs, system frameworks, and SF Symbols retain Apple's terms.

XcodeGen, SwiftFormat, Python, and optional image-verification tools are development tools, not bundled runtime dependencies. Their own licenses apply. The app icon was AI-assisted and exported with macOS tools; its source and export tools are described above. New third-party material must be documented with its source and license.
