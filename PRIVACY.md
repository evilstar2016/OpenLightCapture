# 隐私与本地数据 / Privacy and local data

更新 / Updated: 2026-10-28。描述 OpenLightCapture 0.5.2 开发版（构建 25）；该版本尚未发布。

## 中文

### 采集与处理

应用在用户发起截图后，通过 macOS 的 ScreenCaptureKit 读取屏幕画面。普通截图会先读取可用显示器的画面并暂存在内存中，供框选和窗口选择使用，最终输出选区。不要将这一过程理解为系统只向应用提供了最终选区的像素。

长截图会在活动会话中持续接收配置区域的画面，并在本机拼接。窗口 ID、进程 ID、窗口几何和前台应用状态用于选区、目标绑定与恢复焦点。应用空闲时不运行屏幕采集流。

自动滚动仅在用户选择自动模式后使用控制权限，向所选目标发送滚动。采集流不启用音频；应用不请求麦克风、摄像头或全盘访问。

### 网络与第三方

当前应用没有账号、云上传、分析 SDK、遥测或更新检查的网络实现。系统授权页面和 Finder 操作由 macOS 处理。设置页的 X 账号链接仅在用户点击后调用默认浏览器打开 `https://x.com/EverSeenU`；浏览器会连接该网站并适用其隐私政策，应用不预加载账号内容。

复制后，系统通用剪贴板、剪贴板管理器和目标应用可能按各自设置保存、同步或上传图片；这不由本项目控制。本说明也不涵盖 GitHub 上的 Issue、附件或下载服务。

### 本地文件与保留

默认 Bundle ID 为 `io.github.evilstar2016.openlightcapture`，数据位于：

```text
~/Library/Application Support/io.github.evilstar2016.openlightcapture/
  Assets/<asset-id>/       PNG 与 asset.json
  Working/<session-id>/    长图工作图块
  instance.lock           单实例运行锁
```

- 发布截图时生成本地 PNG，为 Finder 的文件粘贴提供持续可读的 URL。
- `asset.json` 记录资产 ID、相对文件名、创建/退役时间、发布阶段及剪贴板变更计数；不作为截图历史库。
- 当前剪贴板引用的文件会保留，正常退出应用后仍可粘贴。系统重启或系统回收后的可用性不作保证。
- 被替换的已退役资产至少保留 15 分钟，之后由应用运行期间的清理流程回收；这不是精确到时删除的承诺。
- 长图工作文件在会话取消或结果生成后清理，遗留工作目录会在后续启动时检查清理；异常退出可能留下文件。
- 用户另存或粘贴到其他目录的图片不会被应用的暂存清理删除。

这些文件可能含原始画面。应用私有目录不等于额外加密，也不提供安全擦除保证。修改 Bundle ID 后，数据目录会随之变化。

### 设置与系统权限

应用使用 `io.github.evilstar2016.openlightcapture` 偏好域保存设置。首次使用时，按提示授予屏幕录制权限；自动滚动另外需要控制权限。“登录时启动”由用户在设置中开启。

系统剪贴板由所有应用共享，复制行为会替换当前剪贴板内容。

### 剪贴板、设置与日志

一个发布项目同时提供 PNG 数据、文件 URL 和本工具的资产标识。为维护自己的暂存文件，应用会检查剪贴板变更计数、类型与私有资产标识；不会为此保存其他应用复制的文本或图片内容。

语言、快捷键和登录项意图保存在 macOS 用户偏好中，实际登录项状态由系统管理。系统日志可能包含会话 ID、快捷键、状态码和系统错误描述；错误描述可能包含本机路径，分享日志前请自行检查和脱敏。

### 删除与反馈

先关闭“登录时启动”并退出应用，再删除应用。如不再需要当前剪贴板的文件粘贴，可自行删除上述数据目录；已经保存到其他目录的图片需要单独处理。权限可在系统设置中撤销。

隐私问题按 [安全政策](SECURITY.md) 联系。不要在公开报告中粘贴真实截图、文件路径或其他人的内容。

## English

### Capture and processing

Capture starts after a user action. Regular screenshots temporarily read available display images into memory for area/window selection, then export the selected region. The app can therefore see more pixels during selection than the final output contains.

An active scrolling session receives the configured capture area and stitches it locally. Window/process identifiers, geometry, and foreground-app state support selection, target binding, and focus restoration. There is no idle screen-capture stream. Automatic scrolling uses control permission only after the user selects that mode. Audio capture is disabled; microphone, camera, and Full Disk Access are not requested.

### Network and local storage

The current app implements no accounts, uploads, analytics, telemetry, or network update checks. macOS handles system settings and Finder actions. Clicking the author’s X link in Settings opens `https://x.com/EverSeenU` in the default browser, which connects to the site under its own privacy policy. The app does not preload the profile. The operating system's clipboard services, clipboard managers, and receiving apps can retain or sync copied images independently.

For the default bundle identifier, files live under `~/Library/Application Support/io.github.evilstar2016.openlightcapture/`: `Assets/` contains PNGs and asset metadata, `Working/` contains scrolling tiles, and `instance.lock` enforces one running instance. Changing the bundle identifier changes the storage location.

The clipboard's current asset is retained for Finder paste after normal app exit. Replaced, retired assets are eligible for cleanup after at least 15 minutes while the app runs. Working files are cleaned during session disposal and startup cleanup; crashes can leave files behind. User-saved files elsewhere are not deleted by this cleanup. Availability across system restart is not guaranteed.

Asset metadata contains identifiers, a relative filename, timestamps, publication state, and a clipboard change count. Files can include original screen content. App-private storage is not additional encryption or a secure-erasure guarantee.

### Settings and system permissions

Preferences use the `io.github.evilstar2016.openlightcapture` domain. Follow the app's prompts to grant Screen Recording permission; automatic scrolling additionally needs control permission. Launch at Login is enabled by the user in Settings.

The system clipboard is shared by all apps; copying replaces its current contents.

### Clipboard, preferences, logs, and removal

Published clipboard items carry PNG data, a file URL, and a private asset ID. Maintenance checks clipboard change counts/types and that ID to manage the app's own files; it does not archive other apps' copied text or images. Language, shortcut, and login preferences are stored locally. System logs can contain session IDs, shortcuts, status codes, and errors that may include local paths.

Disable Launch at Login and quit before removing the app. Delete the support directory only when you no longer need its clipboard-backed file paste. Remove saved copies elsewhere separately, and revoke permissions in System Settings if desired.

Review and redact diagnostics before sharing. Report privacy concerns through [SECURITY.md](SECURITY.md), without posting sensitive captures publicly.
