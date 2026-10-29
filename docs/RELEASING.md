# 公开与发布 / Releasing

供维护者准备 OpenLightCapture 发行包。

## 发布准备

- 核对 [MIT License](../LICENSE) 和 [第三方说明](../THIRD_PARTY_NOTICES.md)。
- 检查待发布提交，排除凭据、证书、真实用户截图、剪贴板数据和本机构建缓存。
- README 的下载、支持范围、签名与公证说明必须与实际发行包一致。
- 按 [安全政策](../SECURITY.md) 配置漏洞报告入口。

## 版本与验证

应用版本和构建号维护于 [Info.plist](../LightCapture/Resources/Info.plist)。一次可分发构建使用新的构建号，更新 [CHANGELOG](../CHANGELOG.md)，确认准备发布的 commit，再运行：

```sh
bash scripts/verify.sh
```

记录真实结果：测试数、失败/跳过项、Xcode/macOS、两种架构、实际 GUI 验收，以及仍未覆盖的系统或硬件。生成的本地报告不应未经脱敏就作为公开附件。

当前发行版本为 OpenLightCapture 1.0.0（构建 27），发布标签为 `v1.0.0`。先提交版本源码并从该 commit 构建，核验最终产物后创建对应 tag 和 Release；发布页附通用 DMG 和 SHA-256 校验文件。

## 签名与公证

工程默认使用 ad hoc 签名。当前 v1.0.0 包内应用仍采用 ad hoc 签名，未进行 Developer ID 签名或 Apple 公证，下载页必须明确说明，不能宣称已经通过 Gatekeeper。后续使用维护者自己的 Developer ID 配置和 Apple 公证流程时，完成签名、公证和必要的 stapling 后，再打包验证最终产物，并更新发布说明。

账号、证书、私钥和公证凭据不能入库。是否已签名/公证应在具体 Release 中如实说明；不要把 `codesign --verify` 通过写成已经通过 Gatekeeper 或完成公证。实际操作参照 [Apple 公证文档](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。

## 打包许可与说明

不修改已经签名的 `.app` 内容来临时加入文档。DMG 将 LICENSE、第三方说明、隐私说明和源码提交号放在 app 外，并提供指向 `/Applications` 的安装快捷方式。打包脚本从应用读取版本号，检查应用身份、双架构、签名和本地化资源，拒绝覆盖已有 DMG：

```sh
bash scripts/package-dmg.sh
hdiutil verify build/OpenLightCapture-1.0.0-macOS-universal.dmg
(cd build && shasum -a 256 -c OpenLightCapture-1.0.0-macOS-universal.dmg.sha256)
```

校验文件中的文件名相对其所在目录，执行 `shasum -c` 时应位于 `build/`。只读挂载最终 DMG，核对包内应用版本、构建号、架构、签名、资源、许可文件、源码提交号与安装快捷方式，再卸载镜像。真实权限与 GUI 验收单独记录；只有实际完成的步骤才能写为通过。上传后重新下载公开资产，核对 SHA-256。发布页附真实版本、支持范围、变更、已知限制与校验和，是否标为预发布应与开发状态一致。

`build/` 和临时 staging 都是生成产物，打包脚本退出时清理自己的 staging；不要把临时目录或旧版本误作发行源。

## Homebrew Cask

[维护者 Tap](https://github.com/evilstar2016/homebrew-tap) 中的 `Casks/openlightcapture.rb` 固定使用已发布 DMG 的版本和 SHA-256。发布新版本后，用公开下载的最终文件核对摘要，再更新 Tap 的 `version` 与 `sha256`；不要修改旧版本的安装包来替代版本更新。`livecheck` 可发现新的上游版本，但用户的 `brew upgrade` 需要 Tap 中的版本元数据先更新。

在 Tap 仓库运行 `brew style Casks/openlightcapture.rb`，并对 `evilstar2016/tap/openlightcapture` 执行 `brew audit --cask --strict --online`、`brew livecheck --cask` 和 `brew fetch --cask`。使用临时 `--appdir` 验证安装、包内版本、签名与卸载，避免覆盖已有安装。不移除隔离属性、不禁用 Gatekeeper；签名和公证状态应在 Cask 提示、README 与 Release 中保持一致。

## English summary

Before a release, review the license, third-party notices, selected commit, support scope, and repository settings. Enable private vulnerability reporting separately from adding SECURITY.md. Ensure the README matches the actual artifacts.

Update the version/build and changelog, verify the exact commit, and record test and platform coverage. The default ad hoc signature is for local development; use your own Developer ID and Apple's notarization process for the intended distribution model. Never commit credentials or certificates.

Package license/notices/privacy files alongside the signed app without altering its bundle. Verify the final extracted archive, checksum, architectures, resources, and behavior before publishing release assets. Keep the release status and signing/notarization claims accurate.
