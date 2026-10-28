# 安全政策 / Security policy

## 支持范围

安全修复优先面向 `main` 的当前代码和后续发布。当前项目处于开发阶段，不承诺对旧开发构建逐一回补，也不承诺固定响应时限。

与本项目相关的问题包括：越界读取或输出屏幕内容、自动滚动控制越过目标边界、剪贴板或暂存文件泄漏、路径穿越/符号链接绕过、权限检查绕过，以及发布包或依赖被篡改。

## 如何报告

1. 优先使用仓库 **Security → Report a vulnerability**，或 [私密报告入口](https://github.com/evilstar2016/OpenLightCapture/security/advisories/new)。此功能需要维护者在公开仓库中启用。
2. 如果没有这个入口，可先新建一个仅请求安全联系方式的 [Issue](https://github.com/evilstar2016/OpenLightCapture/issues/new)，不要公开技术细节、利用代码或敏感数据；获得私密渠道后再发送完整报告。
3. 私密报告应包含受影响版本/commit、macOS 与架构、最小复现、影响范围和可用的修复建议。用合成数据，移除身份信息和真实截图。

请给维护者留出核实和修复的沟通空间，再协调公开技术细节。普通功能错误和使用问题请见 [SUPPORT.md](SUPPORT.md)。

## English

Security fixes target the current `main` branch and future releases. This development-stage project does not promise backports for every old build or a fixed response deadline.

Relevant issues include capture/output outside intended boundaries, misdirected automatic input, clipboard or temporary-file disclosure, path/symlink validation bypasses, permission bypasses, and compromised distributions or dependencies.

Use **Security → Report a vulnerability**, or the [private report form](https://github.com/evilstar2016/OpenLightCapture/security/advisories/new), when the maintainer has enabled it. If unavailable, open an [issue](https://github.com/evilstar2016/OpenLightCapture/issues/new) asking only for a preferred security contact. Do not include exploit details, secrets, or sensitive captures there.

In a private channel, provide the affected build/commit, macOS version, architecture, minimal reproduction, impact, and any suggested fix. Use synthetic data. Coordinate disclosure after maintainers have had an opportunity to investigate. Ordinary bugs and questions belong in [Support](SUPPORT.md).

GitHub explains the availability of private reports in its [official documentation](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/report-privately).
