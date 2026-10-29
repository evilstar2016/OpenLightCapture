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

当前为 OpenLightCapture 0.5.2 开发版（构建 26），尚未创建 v0.5.2 tag 或发布安装包。先提交版本源码并从该 commit 构建，核验最终产物后创建对应 tag 和 Release。

## 签名与公证

工程默认使用 ad hoc 签名，适合本地构建验证。面向下载分发时，使用维护者自己的 Developer ID 配置和 Apple 公证流程；完成相应签名、公证和必要的 stapling 后，再打包验证最终产物。当前开发构建使用 ad hoc 签名，尚未公证，下载页必须明确说明，不能宣称已经通过 Gatekeeper。

账号、证书、私钥和公证凭据不能入库。是否已签名/公证应在具体 Release 中如实说明；不要把 `codesign --verify` 通过写成已经通过 Gatekeeper 或完成公证。实际操作参照 [Apple 公证文档](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。

## 打包许可与说明

不修改已经签名的 `.app` 内容来临时加入文档。将 LICENSE、第三方说明和隐私说明放在 app 外，与 app 一起打包。下面以待发布的 0.5.2 为例；后续发行替换成已确认的版本，并确认 app 来源正确：

```sh
release_stage="$(mktemp -d)"
mkdir "$release_stage/OpenLightCapture"
ditto build/DerivedData/Build/Products/Release/OpenLightCapture.app \
  "$release_stage/OpenLightCapture/OpenLightCapture.app"
cp LICENSE THIRD_PARTY_NOTICES.md PRIVACY.md "$release_stage/OpenLightCapture/"
codesign --verify --deep --strict "$release_stage/OpenLightCapture/OpenLightCapture.app"
lipo -archs "$release_stage/OpenLightCapture/OpenLightCapture.app/Contents/MacOS/OpenLightCapture"
python3 scripts/verify-localizations.py --app "$release_stage/OpenLightCapture/OpenLightCapture.app"
ditto -c -k --sequesterRsrc --keepParent \
  "$release_stage/OpenLightCapture" build/OpenLightCapture-0.5.2-macOS-universal.zip
shasum -a 256 build/OpenLightCapture-0.5.2-macOS-universal.zip
```

解压最终 ZIP，核对构建号、架构、签名、资源、许可文件与 SHA-256，再运行 app 检查中英文、权限引导和基本截图/粘贴。只有生成与核验都完成后才上传 Release；附真实版本、支持范围、变更、已知限制与校验和。是否标为预发布应与开发状态一致。

`build/` 和临时 staging 都是生成产物，完成后按需清理；不要把临时目录或旧版本误作发行源。

## English summary

Before a release, review the license, third-party notices, selected commit, support scope, and repository settings. Enable private vulnerability reporting separately from adding SECURITY.md. Ensure the README matches the actual artifacts.

Update the version/build and changelog, verify the exact commit, and record test and platform coverage. The default ad hoc signature is for local development; use your own Developer ID and Apple's notarization process for the intended distribution model. Never commit credentials or certificates.

Package license/notices/privacy files alongside the signed app without altering its bundle. Verify the final extracted archive, checksum, architectures, resources, and behavior before publishing release assets. Keep the release status and signing/notarization claims accurate.
