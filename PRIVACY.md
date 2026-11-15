# 隐私与本地数据 / Privacy and local data

本文描述 OpenLightCapture 的数据处理方式，适用于包含本地文字识别的 1.2.0 发行版。

## 中文

### 采集与处理

应用在用户发起截图后，通过 macOS 的 ScreenCaptureKit 读取屏幕画面。普通截图会先读取可用显示器的画面并暂存在内存中，供框选和窗口选择使用，最终输出选区。不要将这一过程理解为系统只向应用提供了最终选区的像素。

长截图会在活动会话中持续接收配置区域的画面，并在本机拼接。GIF 录制在用户确认并完成倒计时后持续接收固定区域画面，原始帧和时间信息暂存在本机，停止后生成 GIF；不录声音。窗口 ID、进程 ID、窗口几何和前台应用状态用于选区、目标绑定与恢复焦点。应用空闲时不运行屏幕采集流。

视频录屏同样在确认和倒计时后开始接收固定区域画面，持续编码为本机 MP4/H.264 工作文件，不录系统声音或麦克风。停止后预览，用户可另存视频；保存视频不修改剪贴板。

自动滚动仅在用户选择自动模式后使用控制权限，向所选目标发送滚动。采集流不启用音频；应用不请求麦克风、摄像头或全盘访问。

### 本地文字识别

OCR 只在用户点击“识别文字”后运行，使用当前裁剪、标注和水印合成后的图片。识别由 Apple Vision 在本机完成，不上传图片或文字、不新增文字历史。预览、编辑、重试与返回截图不修改剪贴板；选择复制或全文复制时写入纯文本，替换之前的剪贴板内容，不建立图片资产。

macOS 27+ 每次 OCR 会话使用同一应用可执行文件的独立工作进程。输入图片写入系统临时目录中的 `OpenLightCaptureOCR-<pid>-<random-id>/input.png`，目录权限为 0700，文件权限为 0600；结果通过本机管道返回。正常成功、失败或取消后回收工作进程并删除临时目录。强制结束或崩溃可能留下临时文件，应用私有权限不等同于额外加密或安全擦除。无需新增系统权限。

### 网络与第三方

当前应用没有账号、云上传、分析 SDK、遥测或更新检查的网络实现。系统授权页面和 Finder 操作由 macOS 处理。设置页的 X 账号链接仅在用户点击后调用默认浏览器打开 `https://x.com/qishu_lab`；浏览器会连接该网站并适用其隐私政策，应用不预加载账号内容。

复制后，系统通用剪贴板、剪贴板管理器和目标应用可能按各自设置保存、同步或上传图片或文字；这不由本项目控制。本说明也不涵盖 GitHub 上的 Issue、附件或下载服务。

### 本地文件与保留

默认 Bundle ID 为 `io.github.evilstar2016.openlightcapture`，数据位于：

```text
~/Library/Application Support/io.github.evilstar2016.openlightcapture/
  Assets/<asset-id>/       PNG/GIF 与 asset.json
  Working/<session-id>/    长图工作图块
  Watermarks/templates.json  自定义文字水印模板与默认选择
  WorkingGIF/<attempt-id>/ GIF 原始帧与未发布结果
  WorkingVideo/<attempt-id>/ MP4 工作文件与未保存结果
  instance.lock           单实例运行锁
```

- 发布截图或动图时生成本地 PNG/GIF，为 Finder 的文件粘贴提供持续可读的 URL。
- `asset.json` 记录资产 ID、相对文件名、创建/退役时间、发布阶段及剪贴板变更计数；不作为截图历史库。
- 当前剪贴板引用的文件会保留，正常退出应用后仍可粘贴。系统重启或系统回收后的可用性不作保证。
- 被替换的已退役资产至少保留 15 分钟，之后由应用运行期间的清理流程回收；这不是精确到时删除的承诺。
- GIF 原始帧在成功生成后清理；生成失败/超限时可保留在当前会话供原始预览和重录。GIF 未发布结果在放弃/结束后清理，异常退出遗留内容在下次启动时清理。最大规格原始素材可接近 2 GiB。
- 视频直接编码到工作文件，不保存整片原始帧。放弃、重录或会话结束后清理，异常退出遗留视频在下次启动时清理；不提供历史库或崩溃恢复。
- 长图工作文件在会话取消或结果生成后清理，遗留工作目录会在后续启动时检查清理；异常退出可能留下文件。
- 用户另存或粘贴到其他目录的图片和视频不会被应用的暂存清理删除。
- 水印模板可能包含署名、账号与保密提示，保存在本机，不上传；不会随截图资产回收。重置异常模板库前会保留备份，备份也需用户自行删除。本次临时水印调整保留在编辑会话内，不会自动写回模板库。

这些文件可能含原始画面。应用私有目录不等于额外加密，也不提供安全擦除保证。修改 Bundle ID 后，数据目录会随之变化。

### 设置与系统权限

应用使用 `io.github.evilstar2016.openlightcapture` 偏好域保存设置。首次使用时，按提示授予屏幕录制权限；自动滚动另外需要控制权限。“登录时启动”由用户在设置中开启。

系统剪贴板由所有应用共享，复制行为会替换当前剪贴板内容。

### 剪贴板、设置与日志

一个发布项目同时提供 PNG 或 GIF 数据、文件 URL 和本工具的资产标识。为维护自己的暂存文件，应用会检查剪贴板变更计数、类型与私有资产标识；不会为此保存其他应用复制的文本或图片内容。

语言、快捷键和登录项意图保存在 macOS 用户偏好中，实际登录项状态由系统管理。系统日志可能包含会话 ID、快捷键、状态码和系统错误描述；错误描述可能包含本机路径，分享日志前请自行检查和脱敏。

### 删除与反馈

先关闭“登录时启动”并退出应用，再删除应用。如不再需要当前剪贴板的文件粘贴，可自行删除上述数据目录；已经保存到其他目录的图片和视频需要单独处理。权限可在系统设置中撤销。

隐私问题按 [安全政策](SECURITY.md) 联系。不要在公开报告中粘贴真实截图、文件路径或其他人的内容。

## English

### Capture and processing

Capture starts after a user action. Regular screenshots temporarily read available display images into memory for area/window selection, then export the selected region. The app can therefore see more pixels during selection than the final output contains.

An active scrolling session receives the configured capture area and stitches it locally. Window/process identifiers, geometry, and foreground-app state support selection, target binding, and focus restoration. There is no idle screen-capture stream. Automatic scrolling uses control permission only after the user selects that mode. Audio capture is disabled; microphone, camera, and Full Disk Access are not requested.

### Local text recognition

OCR runs only after Recognize Text is selected, using the rendered crop, annotations, and watermark. Apple Vision recognizes text locally. The app does not upload images/text or create text history. Recognition and editing leave the clipboard unchanged; copying writes plain text and replaces its previous contents without creating an image asset.

On macOS 27+, each session uses a separate instance of the app executable. A PNG input is placed in `OpenLightCaptureOCR-<pid>-<random-id>/input.png` under the system temporary directory, with mode 0700 for the directory and 0600 for the file. Results return through a local pipe. Normal completion, failure, and cancellation remove the input and reap the worker. A crash or forced termination can leave temporary files; private permissions do not provide extra encryption or secure erasure. No new system permission is required.

### Network and local storage

The current app implements no accounts, uploads, analytics, telemetry, or network update checks. macOS handles system settings and Finder actions. Clicking the author’s X link in Settings opens `https://x.com/qishu_lab` in the default browser, which connects to the site under its own privacy policy. The app does not preload the profile. The operating system's clipboard services, clipboard managers, and receiving apps can retain or sync copied images independently.

For the default bundle identifier, files live under `~/Library/Application Support/io.github.evilstar2016.openlightcapture/`: `Assets/` contains PNG/GIF files and asset metadata, `Working/` contains scrolling tiles, `WorkingGIF/` holds GIF raw frames and unpublished results, `WorkingVideo/` holds MP4 working files and unsaved results, and `instance.lock` enforces one running instance. Changing the bundle identifier changes the storage location.

The app also stores custom text watermark templates and the default choice in `Watermarks/templates.json`. Names, handles, and notices remain local. These files are retained independently of clipboard asset cleanup. Recovery makes a backup before resetting a damaged library; backups also remain until manually removed. Per-screenshot adjustments stay in the editing session and are not automatically saved to the template library.

The clipboard's current asset is retained for Finder paste after normal app exit. Replaced, retired assets are eligible for cleanup after at least 15 minutes while the app runs. Working files are cleaned during session disposal and startup cleanup; crashes can leave files behind. User-saved files elsewhere are not deleted by this cleanup. Availability across system restart is not guaranteed.

Asset metadata contains identifiers, a relative filename, timestamps, publication state, and a clipboard change count. Files can include original screen content. App-private storage is not additional encryption or a secure-erasure guarantee.

### Settings and system permissions

Preferences use the `io.github.evilstar2016.openlightcapture` domain. Follow the app's prompts to grant Screen Recording permission; automatic scrolling additionally needs control permission. Launch at Login is enabled by the user in Settings.

The system clipboard is shared by all apps; copying replaces its current contents.

### Clipboard, preferences, logs, and removal

GIF recording starts after explicit confirmation and a countdown, records a fixed region without audio, and processes temporary raw frames and timing locally. Successful generation removes raw frames; failures or size limits can retain them for the current preview. Discard/completion cleans unpublished results, and later launch cleans abandoned GIF workspaces. Maximum raw material can approach 2 GiB.

Silent video recording also starts after confirmation and a countdown. Screen frames are continuously encoded as local H.264/MP4, without system audio, microphone audio, or a full raw-frame spool. After stopping, users can preview and save the video; saving leaves the clipboard unchanged. Discard, re-recording, session completion, and later startup clean owned temporary files. User-saved videos are retained.

Published clipboard items carry PNG or GIF data, a file URL, and a private asset ID. Maintenance checks clipboard change counts/types and that ID to manage the app's own files; it does not archive other apps' copied text or images. Language, shortcut, and login preferences are stored locally. System logs can contain session IDs, shortcuts, status codes, and errors that may include local paths.

Disable Launch at Login and quit before removing the app. Delete the support directory only when you no longer need its clipboard-backed file paste. Remove saved copies elsewhere separately, and revoke permissions in System Settings if desired.

Review and redact diagnostics before sharing. Report privacy concerns through [SECURITY.md](SECURITY.md), without posting sensitive captures publicly.
