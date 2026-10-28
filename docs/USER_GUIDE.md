# 使用指南 / User guide

[中文首页](../README.md) · [English overview](../README.en.md)

需要逐步操作说明、工具速查和实际配图，请阅读 [OpenLightCapture 操作手册](OPERATION_MANUAL.md)。权限设置示例见手册第 2 节。

## 截图与标注

从菜单栏选择“截图 / Capture”，或按默认快捷键 `⇧⌘A`。快捷键可在设置中修改；如果冲突，先用菜单栏入口确认采集功能是否正常。

拖动框选区域，按 `Space` 切换窗口/区域选择。选好范围后直接在工具栏选择矩形、椭圆、箭头、画笔、文字或马赛克。形状和画笔支持粗细与颜色，文字支持字号与颜色，马赛克支持颗粒档位。撤销/重做作用于当前标注会话。

所有标注均可直接单击选中并拖动，包括形状、箭头、画笔、文字和马赛克，无需切换绘制工具；也可使用“选择标注”工具。重叠时优先选中最上层标注，选中后按 `Delete` 删除。一次拖动可用 `⌘Z` 撤销、`⇧⌘Z` 重做。在已有标注上开始绘制新标注时，按住 `Option` 再拖动。普通截图和长图编辑器操作相同；“调整选区”工具仍用于调整或裁剪截图范围。

文字输入时，回车先确认文字，确认后可拖动，双击继续编辑；应先结束文字输入，再完成截图。未在文字输入时，可用 `Enter`、`⌘C`、完成按钮或双击选区完成。保存按钮或 `⌘S` 打开 PNG 保存界面。

完成后，在图片接收应用按 `⌘V` 粘贴图片，或在 Finder 的可写目录中粘贴 PNG 文件。接收应用决定使用剪贴板中的哪种表示，因此并非所有纯文本编辑器都能直接接收图片。

## 长截图

1. 框选同一个窗口的滚动正文，避开固定标题、底栏和滚动条。
2. 选择长截图，再选择手动或自动滚动。
3. 手动模式小幅向下滚动；自动模式锁定目标窗口，鼠标可以移出选区，随时使用面板暂停或结束。
4. 面板显示当前选区缩略图、已确认像素高度和时间；它不是完整拼接结果的实时总览。
5. 结束采集后进入编辑器。只有再次完成编辑，才会发布到剪贴板。

目标应用切换、窗口关闭/隐藏/移动或显示器变化时可能停止。无法可靠拼接时会等待、暂停或提示部分结果；“没有更多内容”并不保证已经到达页面底部。可使用已确认的部分，也可取消后重新选择区域。

<a id="limits"></a>
## 限制 / Limits

| 项目 | 当前边界 |
|---|---|
| 最大高度 | 50,000 原生像素 |
| 最大像素总量 | 60 百万像素 |
| 活动采集时间 | 180 秒；暂停不计入 |
| 滚动方向 | 向下；不支持横向/双向长图 |
| 适合内容 | 足够分散、可唯一匹配的正文，保留足够视口重叠 |
| 困难内容 | 固定栏、大范围动画、虚拟列表、重复纹理、横向漂移、反向或过快滚动 |

应用不会把不确定结果标为完整。当前没有录屏、OCR、云同步、截图历史库或完整长图实时总览。Intel 和较早 macOS 的实际覆盖不完整，编译成功不等于这些环境已验收通过。

<a id="permissions"></a>
## 权限与故障排查

普通截图与所有长图需要“屏幕录制”。自动模式额外需要控制权限，系统可能称为“辅助功能”“控制电脑”或“设备控制和数据访问”；名称因版本不同而变化。

点击截图或自动模式时，应用按需检查并引导到相应设置。开启后请退出并重新打开应用，再发起新的截图。拒绝控制权限仍可使用普通截图和手动长图；运行中撤销控制权限会使自动滚动暂停。

从截图或自动模式提示前往授权后，检测到权限生效或从系统设置返回时，会弹出“立即重启 / 稍后”。选择“立即重启”会结束当前截图并重新打开同一路径的 OpenLightCapture，之后需重新开始截图；选择“稍后”不会自动退出。若只新增自动控制权限，普通截图和手动长图仍可使用。系统状态尚未刷新时，返回后的提醒不会把权限当作已生效。

如果已开启仍显示未生效，确认授权的是当前路径下的应用；从菜单栏打开“权限与帮助”刷新状态。保持应用安装路径稳定，避免同时运行不同位置的多个构建。无需麦克风、摄像头或全盘访问。

若 macOS 拦截下载包，先核对该 Release 的来源、签名与公证说明；当前本地开发包并不代表已经公证。也可以按 [开发指南](DEVELOPMENT.md) 从源码构建。不要为此关闭系统安全机制。

## 语言与文件名

“设置 / Settings”提供跟随系统、简体中文和 English；无匹配语言时回退英文。空闲时立即生效，活动会话中在完成或取消后统一切换。快捷键录入期间先完成或取消录入。

新文件默认使用“截图”或“Screenshot”前缀，时间格式与副本序号保留。用户输入的标注、手动文件名、历史文件不被翻译或改名。macOS 自己的按钮和错误详情可能继续使用系统语言。

## 应用标识与本地设置

OpenLightCapture 的 Bundle ID 为 `io.github.evilstar2016.openlightcapture`，应用为 `OpenLightCapture.app`。语言、快捷键和登录项意图保存在本机偏好中。首次使用请按提示授予系统权限。

截图与长图工作文件存储在 `~/Library/Application Support/io.github.evilstar2016.openlightcapture/`。系统剪贴板由所有应用共享，复制截图会替换当前剪贴板内容。

## 卸载与本地数据

先在设置中关闭登录时启动并退出应用，再删除 app。如不再需要当前剪贴板的文件粘贴，可自行删除 `~/Library/Application Support/io.github.evilstar2016.openlightcapture/`。此目录可能仍含剪贴板引用的 PNG 与长图工作文件；删除后对应的 Finder 文件粘贴会失效。用户另存的图片需要自行处理。更多信息见 [隐私说明](../PRIVACY.md)。

语言、快捷键与登录项意图保存在 macOS 用户偏好中。修改过 Bundle ID 的构建使用自己的偏好域与数据目录。

## English quick reference

- Start with the menu bar or `⇧⌘A`; use `Space` for area/window selection.
- Annotate directly. Return confirms active text editing first; finish text entry before completing the screenshot. Outside text entry, use the finish action, `Enter`, or `⌘C`. Use `⌘S` to save PNG.
- Click and drag any annotation to move it without switching drawing tools. Overlaps select the topmost item; `Delete` removes the selection, and undo/redo includes moves. Hold `Option` to draw over an existing annotation. This works in both capture editors; the crop tool adjusts the capture area.
- Paste an image into a compatible app, or a file into a writable Finder directory. Plain-text receivers may not accept images.
- For scrolling captures, select the scrolling body without fixed bars. Choose manual or automatic mode, then end acquisition and finish in the editor. Only the final step publishes the image.
- Limits are 50,000 pixels high, 60 million total pixels, and 180 active seconds. Dynamic content, repeated textures, drift, and fast/reversed scrolling can prevent reliable alignment. Partial results are labelled; reaching the bottom is not always provable.
- All capture modes need Screen Recording; only automatic scrolling needs control permission. Quit and reopen after granting access. Use the permissions help window to inspect status.
- When a capture action sends you to permission settings, a detected grant or return from Settings shows “Restart Now / Later.” Restart Now ends the current capture and reopens the same app; start a new capture afterward. Later keeps the app open. Returning alone is not treated as proof that access was granted.
- Keep a stable app location. If macOS blocks a downloaded package, check its release/signing information or build from source rather than disabling security controls.
- Language changes wait until an active session ends. System dialogs can retain the system language.
- OpenLightCapture uses the `io.github.evilstar2016.openlightcapture` preference domain and support directory. Grant the required permissions on first use and configure Launch at Login in Settings.
- Disable Launch at Login and quit before removal. Delete the support directory only when clipboard-backed file paste is no longer needed. See [Privacy](../PRIVACY.md) and [Support](../SUPPORT.md).
