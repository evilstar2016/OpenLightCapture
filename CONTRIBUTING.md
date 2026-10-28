# 贡献指南 / Contributing

欢迎问题反馈、文档修正、翻译、测试和代码贡献。中文、英文均可。交流请遵守 [行为准则](CODE_OF_CONDUCT.md)。

## 开始之前

- 先搜索 [已有 Issue](https://github.com/evilstar2016/OpenLightCapture/issues)，大改动先讨论问题、预期行为和范围。
- 本项目当前专注原生 macOS 截图、标注、长图与图片/文件粘贴。不要在一个 PR 中混入无关重构或新平台。
- 安全漏洞请走 [SECURITY.md](SECURITY.md)，不要提交公开利用细节。

## 开发与验证

先读 [开发指南](docs/DEVELOPMENT.md) 和 [架构概览](docs/ARCHITECTURE.md)。`project.yml` 是工程配置来源；新增文件或调整 target 后运行 `xcodegen generate`，同时检查生成工程的差异。

从当前 `main` 建立功能分支，完成一项清晰的改动。Swift 使用项目的 SwiftFormat 设置（`--swiftversion 6`）。

```sh
swiftformat LightCapture LightCaptureTests --lint --swiftversion 6
python3 scripts/verify-localizations.py
```

行为改动运行相关 XCTest；影响会话、采集、标注或输出时，再运行 `bash scripts/verify.sh` 完整回归。纯文档修改检查链接、代码示例和 YAML，不必为了文档重建应用。验证脚本会重新生成 `build/` 下的缓存与日志。

UI 修改请检查简体中文、英文、浅色/深色，以及较小窗口/选区。涉及文字输入时检查输入法组合；涉及导出时核对 PNG 像素、保存取消和原有剪贴板行为。自动化通过不等于已经完成真实系统权限与跨应用验收。

## 代码边界

- UI 状态由 MainActor 管理；保持会话 ID/generation 保护，不让旧异步结果覆盖新会话。
- 长图保持有界缓冲和部分结果语义；无法确认完整时不要报告成功到底。
- 只在用户发起截图或自动滚动时申请相应权限；不在测试中主动改变用户权限、全局快捷键或系统剪贴板。
- 不新增网络请求、遥测、依赖或额外权限而不解释用途与影响。
- 暂存只在应用管理的目录内操作；保持文件路径、符号链接和当前剪贴板资产的保护。
- 可见文案通过本地化入口，参数整句翻译；见 [翻译指南](docs/LOCALIZATION.md)。

## 提交 PR

说明问题、最终行为、测试结果和仍未验证的边界。界面变更附脱敏的前后对照，使用不含私人内容的合成样本。手工验收请使用不含私人内容的合成样本。缺少某项测试时写明原因，不把计划测试标成通过。

不要提交本地应用/ZIP、DerivedData、截图中的个人内容、凭据、签名证书、开发账号信息、个人工作记录。检查 Git 暂存区，不用一次性添加整个工作目录来代替检查。

新增依赖或复用代码时说明来源、版本与许可证，更新 [第三方记录](THIRD_PARTY_NOTICES.md)。提交的贡献按仓库 [MIT License](LICENSE) 提供；请确认你有权提交相应内容。

## English

Contributions to code, documentation, translations, and tests are welcome. Search existing issues first and discuss large changes before opening a broad PR. Follow the [code of conduct](CODE_OF_CONDUCT.md); use the [security policy](SECURITY.md) for vulnerabilities.

1. Read [Development](docs/DEVELOPMENT.md) and [Architecture](docs/ARCHITECTURE.md), then branch from `main`.
2. Treat `project.yml` as the source of project configuration. Regenerate and review the Xcode project when needed.
3. Keep changes focused. Run relevant tests, localization checks, and SwiftFormat; use the full verification script for capture, session, rendering, or output changes.
4. For UI work, check both languages, light/dark appearances, and constrained layouts. Check input-method composition and save cancellation when relevant.
5. Explain what changed, why, how you verified it, and what remains untested. Use synthetic or redacted screenshots.
6. Do not include generated packages, private work records, credentials, certificates, or user capture data. Review the staged diff before submitting.

Preserve session/generation checks, bounded capture work, managed-file validation, and permission timing. Explain new dependencies, network behavior, telemetry, or permissions, and update the notices. User-facing text belongs in the localization resources.

Your contributions are provided under the [MIT License](LICENSE). Submit only material you are entitled to contribute. Documentation-only changes do not require a full application rebuild.
