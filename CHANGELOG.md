# 更新记录 / Changelog

应用版本来自 `CFBundleShortVersionString`，构建号来自 `CFBundleVersion`。

## 1.0.0 — 2026-10-29（Build 27）

- 区域与窗口截图，支持直接标注、样式调整、选中拖动以及撤销/重做。
- 手动与自动长截图，支持暂停、继续和保留已确认的部分结果。
- 修复自动长截图每次滚动将鼠标拉回选区的问题，使用绑定窗口的原生滚轮投递，保留权限、目标和遮挡校验。
- 复制图片、Finder 文件粘贴与另存 PNG，图片处理在本机完成。
- 跟随系统、简体中文与 English 界面，可配置快捷键和登录时启动。
- 提供源码、构建指南、使用手册、贡献指南和 MIT License。
- 首次发布适用于 Apple Silicon 和 Intel 的通用 DMG，包含拖入 Applications 的安装入口、许可文件和 SHA-256 校验和。
- 199 项 XCTest、arm64/x86_64 Release、签名及双语资源检查通过。当前采用 ad hoc 签名，尚未完成 Developer ID 签名或 Apple 公证；真实系统权限和跨应用 GUI 流程仍需实机验收。

### English

OpenLightCapture provides area/window capture, inline annotations with dragging and undo/redo, manual/automatic scrolling screenshots, image/file paste, and PNG saving. It supports English and Simplified Chinese, configurable shortcuts, and optional Launch at Login. All image processing is local.

Automatic scrolling now delivers native wheel input to the bound window without recentering the physical pointer, preserving permission, target, and occlusion checks.

The first binary release provides a universal DMG for Apple Silicon and Intel, with an Applications installation shortcut, license notices, and a SHA-256 checksum.

Validation passed 199 XCTest tests, arm64/x86_64 Release builds, signature checks, and bilingual resource checks. The DMG and its mounted app are verified before upload. Builds use ad hoc signing without Developer ID signing or Apple notarization; real permission and cross-application GUI checks remain pending.
