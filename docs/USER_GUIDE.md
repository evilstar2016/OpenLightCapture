# 使用指南 / User guide

[中文首页](../README.md) · [English overview](../README.en.md)

需要逐步操作说明、工具速查和实际配图，请阅读 [OpenLightCapture 操作手册](OPERATION_MANUAL.md)。权限设置示例见手册第 2 节。

## 截图与标注

从菜单栏选择“截图 / Capture”，或按默认快捷键 `⇧⌘A`。快捷键可在设置中修改；如果冲突，先用菜单栏入口确认采集功能是否正常。

拖动框选区域，按 `Space` 切换窗口/区域选择。选好范围后直接在工具栏选择矩形、椭圆、箭头、画笔、文字或马赛克。形状和画笔支持粗细与颜色，文字支持字号与颜色，马赛克支持颗粒档位。撤销/重做作用于当前标注会话。

所有标注均可直接单击选中并拖动，包括形状、箭头、画笔、文字和马赛克，无需切换绘制工具；也可使用“选择标注”工具。重叠时优先选中最上层标注，选中后按 `Delete` 删除。一次拖动可用 `⌘Z` 撤销、`⇧⌘Z` 重做。在已有标注上开始绘制新标注时，按住 `Option` 再拖动。普通截图和长图编辑器操作相同；“调整选区”工具仍用于调整或裁剪截图范围。

文字输入时，回车先确认文字，确认后可拖动，双击继续编辑；应先结束文字输入，再完成截图。未在文字输入时，可用 `Enter`、`⌘C`、完成按钮或双击选区完成。保存按钮或 `⌘S` 打开 PNG 保存界面。

完成后，在图片接收应用按 `⌘V` 粘贴图片，或在 Finder 的可写目录中粘贴 PNG 文件。接收应用决定使用剪贴板中的哪种表示，因此并非所有纯文本编辑器都能直接接收图片。

## 文字水印模板

在“设置 → 水印模板 → 管理模板…”中新建模板，填写署名、账号或保密提示，选择单点或平铺，并调整位置、字号、颜色、透明度、角度和间距。内置模板需要先复制才能编辑；自定义模板修改后点击“保存模板”。

普通截图和长图编辑器工具栏中的水滴按钮打开水印面板。选择模板或“无水印”，按需调整本次文字与样式，然后点击“应用”（或 `⌘Return`）。面板中的示例实时预览草稿，应用后显示在当前截图；取消或点击面板外部会丢弃草稿。本次调整支持撤销/重做，不会覆盖模板。

默认不添加水印，可在设置中指定默认模板。默认与模板修改只影响新开始的截图，当前截图保留原选择。水印会随最终裁剪区域重新定位，长图在拼接结束后加水印；保存和复制使用同一合成结果。

水印仅用于静态截图和长图。GIF/视频录制选区不应用默认水印，也不提供水印编辑；从普通截图选区转入录制时，若当前选区含标注或水印，可选择“清除并录制”。

模板仅存储在本机 `Watermarks/templates.json`，不随截图暂存清理。模板库异常时保留原文件，并在管理器提供“备份并重置模板库”。首期只支持文字；最多 50 个自定义模板，名称 40 字符、正文 120 字符且不超过 3 行。

## 长截图

当前源码支持固定头部：从普通“截图”框选包含固定顶部和滚动正文的区域，在尚未添加标注时开启“保留固定头部（仅一次）”，拖动分隔线贴齐正文顶部，再点击“长截图”选择手动或自动模式。头部只在输出顶部保留一次，匹配与自动滚动使用正文区域。该设置仅作用于本次会话；不适用于固定底栏、多段固定区域或动态变化的正文。直接使用菜单栏“长截图…”仍进入快速模式。

1. 从菜单栏选择“长截图…”，按“长截图 · 框选滚动区域”提示选择同一个窗口的滚动正文，避开固定标题、底栏和滚动条。
2. 框选后松开鼠标，直接选择手动或自动滚动；也可从普通截图的选区工具栏切入长图。
3. 手动模式小幅向下滚动；自动模式锁定目标窗口，鼠标可以移出选区，随时使用面板暂停或结束。
4. 面板显示当前选区缩略图、已确认像素高度和时间；它不是完整拼接结果的实时总览。
5. 结束采集后进入编辑器。只有再次完成编辑，才会发布到剪贴板。

选区确认后，截图区保持清亮，选区外持续变暗；滚动及暂停时保持，结束、取消或采集失败后恢复。遮罩允许鼠标与滚轮穿透，不会遮挡自动滚动的目标，也不会出现在最终长图中。申请控制权限时暂时恢复亮度，方便操作系统设置。框选后按 `Esc` 可随时取消并恢复亮度，焦点在目标页面也有效；长图会话结束后即停止占用该按键。

目标应用切换、窗口关闭/隐藏/移动或显示器变化时可能停止。无法可靠拼接时会等待、暂停或提示部分结果；“没有更多内容”并不保证已经到达页面底部。可使用已确认的部分，也可取消后重新选择区域。

<a id="ocr"></a>

## 本地文字识别

当前源码提供 OCR，最低要求 macOS 13，支持简体中文、英文和混排横排印刷文字。普通截图框选后点击“识别文字”；长截图先结束采集，再从长图编辑器点击同一按钮。识别使用当前裁剪范围和已渲染的标注、水印。GIF 和视频不提供 OCR 入口。

结果可直接编辑。选择文字后按 `⌘C` 只复制选中部分，窗口保持打开；点击“复制文字并结束”复制完整文本并结束本次截图。复制文字会替换之前的剪贴板内容。识别、预览和编辑本身不修改剪贴板，也不生成用于 Finder 粘贴的图片资产。

“返回截图”或 `Esc` 恢复原选区或长图编辑器，保留标注、裁剪和滚动位置。没有识别到文字或识别失败时，可以重试或返回调整范围；识别中可以取消。长图按完整宽度分段识别并去重。

识别在本机运行，无需账号、网络服务或额外权限。macOS 27+ 每次会话使用独立识别进程，完成或取消后退出并清理私有临时图片。小字号、模糊、旋转、手写或复杂排版的准确率需要自行检查；复制前请核对结果。

<a id="gif"></a>
## GIF 动态截图

1. 从菜单栏选择“录制 GIF”，或在截图选区工具栏点击录制按钮。窗口选择只是快速框定区域，录制中不跟随窗口。
2. 确认输出尺寸及鼠标开关，点击“开始录制”。3 秒倒计时可取消，结束后开始采集实时画面，不录声音。
3. 操作目标应用；控制面板显示已录时长。点击“停止并预览”保留片段，“放弃”丢弃未发布素材。最长 30 秒后自动停止。
4. 预览可循环播放/暂停，显示实际时长、尺寸和文件大小；可确认重录，或“复制动图”“保存并复制”。关闭未输出结果会要求确认。
5. 在 Finder 粘贴得到 GIF 文件；接收应用决定动图、静态图或附件的粘贴方式。不接受动图时，保存 GIF 后作为文件发送。飞书、微信的动态粘贴尚待逐版本实测。

当前固定为最高 10 fps、长边最多 1280 px、小图不放大；鼠标默认显示且可关闭。静止时间保留，采集不稳定时结果页提示。尚不支持暂停录制、裁剪时长或动态标注。单个 GIF 超过 50 MiB 会停止生成，保留原始预览并提示重录；不静默降画质。

录制区域固定，其他窗口和通知遮挡可能录入；录制工具和边框不计入输出。大选区最长录制的临时原始素材可接近 2 GiB，空间不足时请缩小选区。素材仅在本机处理；放弃或结束会话后清理，异常退出遗留素材在下次启动时清理。已保存文件和当前剪贴板资产按各自规则保留。

录制中撤销权限、锁屏、休眠或显示器配置变化会结束录制，不自动恢复；已停止采集的结果仍可访问。自动化与合成样本验证不代表真实屏幕、Finder 或聊天应用已完成实机验收。

<a id="video"></a>
## 无声视频录屏

1. 菜单栏选择“录制视频”，或在截图选区工具栏点击视频按钮。框选区域，也可通过窗口选择快速框定范围。
2. 确认 MP4 输出尺寸和鼠标开关，点击“开始录制”；3 秒倒计时结束后开始，不录系统声音或麦克风。
3. 录制区域固定，不随窗口移动。点击“停止并预览”结束；“放弃”删除本次素材。10 分钟达到上限后自动停止。
4. 预览中使用系统播放器播放、暂停或拖动进度；可以重录或点击“保存视频”选择 MP4 文件位置。取消保存或保存失败会保留预览供重试，保存成功后结束会话，不修改剪贴板。

视频使用系统 H.264 编码，最高 30 fps，长边最多 1920 px，不放大小图，输出宽高向下取偶数像素。单文件上限 1 GiB，超限或编码失败会终止本次录制并提示。静止片段和停止前的静止尾段按实际时长保留；暂不支持暂停录制、剪辑或动态标注。

遮挡选区的其他窗口和通知可能录入；录制面板和边框不计入输出。素材直接编码到本机 `WorkingVideo` 工作目录，不保存整段原始帧；放弃、重录或会话结束后清理，异常退出遗留文件在下次启动时清理，尚不支持崩溃恢复。另存文件不参与清理。

仅需现有“屏幕录制”权限。录制中撤销权限、锁屏、休眠或显示器配置变化会结束本次录制；停止后的预览仍可访问。合成帧编码与会话自动化已覆盖，真实屏幕采集、播放器交互、Intel 和较早 macOS 仍需实机验收。

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

应用不会把不确定结果标为完整。当前没有 WebM、音频、OCR、云同步、截图历史库或完整长图实时总览。Intel 和较早 macOS 的实际覆盖不完整，编译成功不等于这些环境已验收通过。

<a id="permissions"></a>
## 权限与故障排查

普通截图、所有长图与 GIF、视频录制需要“屏幕录制”。自动模式额外需要控制权限，系统可能称为“辅助功能”“控制电脑”或“设备控制和数据访问”；名称因版本不同而变化。

首次点击截图且没有录屏权限时，先显示 macOS 锁头授权对话框：选择“打开系统设置”后进入“录屏与系统录音”，手动开启 OpenLightCapture 的开关，再按系统提示“退出并重新打开”；选择“拒绝”不会自动打开设置。应用不会额外叠加重启提醒。重新打开后请发起新的截图；若没有出现系统授权对话框，可从“权限与帮助”手动打开录屏权限设置。

选择自动模式时，应用单独检查控制权限；未授权时先显示系统授权对话框，由用户选择打开系统设置或拒绝。手动开启控制权限后，应用会自动检测并弹出“立即重启 / 稍后”，无需先返回 OpenLightCapture；旧进程的自动滚动状态尚未生效时，也会显示提醒。未开启开关或拒绝授权时不提示。选择“立即重启”会结束当前截图并重新打开同一路径的 OpenLightCapture，之后需重新开始截图；选择“稍后”不会自动退出，同一次授权不重复提示。普通截图和手动长图仍可使用；运行中撤销控制权限会使自动滚动暂停。

如果已开启仍显示未生效，确认授权的是当前路径下的应用；从菜单栏打开“权限与帮助”刷新状态。保持应用安装路径稳定，避免同时运行不同位置的多个构建。无需麦克风、摄像头或全盘访问。

若 macOS 拦截下载包，先核对该 Release 的来源、签名与公证说明；当前本地开发包并不代表已经公证。也可以按 [开发指南](DEVELOPMENT.md) 从源码构建。不要为此关闭系统安全机制。

## 语言与文件名

“设置 / Settings”提供跟随系统、简体中文和 English；无匹配语言时回退英文。空闲时立即生效，活动会话中在完成或取消后统一切换。快捷键录入期间先完成或取消录入。

新文件默认使用“截图”或“Screenshot”前缀，时间格式与副本序号保留。用户输入的标注、手动文件名、历史文件不被翻译或改名。macOS 自己的按钮和错误详情可能继续使用系统语言。

## 应用标识与本地设置

OpenLightCapture 的 Bundle ID 为 `io.github.evilstar2016.openlightcapture`，应用为 `OpenLightCapture.app`。语言、快捷键和登录项意图保存在本机偏好中。首次使用请按提示授予系统权限。

截图、长图和录屏工作文件存储在 `~/Library/Application Support/io.github.evilstar2016.openlightcapture/`。系统剪贴板由所有应用共享，复制截图会替换当前剪贴板内容。

## 卸载与本地数据

先在设置中关闭登录时启动并退出应用，再删除 app。如不再需要当前剪贴板的文件粘贴，可自行删除 `~/Library/Application Support/io.github.evilstar2016.openlightcapture/`。此目录可能仍含剪贴板引用的 PNG 与长图工作文件；删除后对应的 Finder 文件粘贴会失效。用户另存的图片需要自行处理。更多信息见 [隐私说明](../PRIVACY.md)。

语言、快捷键与登录项意图保存在 macOS 用户偏好中。修改过 Bundle ID 的构建使用自己的偏好域与数据目录。

## English quick reference

- Source builds provide local Chinese/English OCR from the screenshot toolbar and scrolling-result editor. Edit before copying, use `⌘C` for selected text or Copy Text and Finish for all text; retry or return without replacing the clipboard. macOS 27+ uses a separate local process per recognition session.
- For a fixed scrolling header, start with a normal area screenshot, enable Keep Header Once before adding annotations, adjust the boundary, then enter scrolling capture. The header is retained once and the body supplies alignment evidence.

- Start with the menu bar or `⇧⌘A`; use `Space` for area/window selection.
- Annotate directly. Return confirms active text editing first; finish text entry before completing the screenshot. Outside text entry, use the finish action, `Enter`, or `⌘C`. Use `⌘S` to save PNG.
- Click and drag any annotation to move it without switching drawing tools. Overlaps select the topmost item; `Delete` removes the selection, and undo/redo includes moves. Hold `Option` to draw over an existing annotation. This works in both capture editors; the crop tool adjusts the capture area.
- Paste an image into a compatible app, or a file into a writable Finder directory. Plain-text receivers may not accept images.
- Settings → Watermark Templates manages local text presets. Use the drop icon in either capture editor, choose a preset or No Watermark, and Apply (`⌘Return`). The sample previews the draft; applying updates the screenshot. Cancel or dismiss to discard the draft. Changes affect only this screenshot and support undo/redo. Default watermarks are off; explicitly choosing a default affects new sessions only. Built-ins must be duplicated before editing. Templates support single or tiled placement and live in `Watermarks/templates.json` independently of clipboard cleanup.
- Choose Scrolling Screenshot from the menu to enter its dedicated selection flow. Drag over the scrolling body without fixed bars; releasing the mouse opens the manual/automatic mode panel directly. The selected area stays clear while the surrounding desktop is shaded throughout scrolling and pauses; mouse and wheel input pass through. Press Esc to cancel even when the target page has focus; the temporary shortcut is released when the scrolling session ends. Finishing, cancellation, or a capture failure removes the shade. End acquisition and finish in the editor to publish the image.
- Limits are 50,000 pixels high, 60 million total pixels, and 180 active seconds. Dynamic content, repeated textures, drift, and fast/reversed scrolling can prevent reliable alignment. Partial results are labelled; reaching the bottom is not always provable.
- All capture modes need Screen Recording; only automatic scrolling needs control permission. Quit and reopen after granting access. Use the permissions help window to inspect status.
- For silent MP4/H.264 recording, select a region, start after a 3-second countdown, stop, preview with system playback controls, and save the video. Defaults are up to 30 fps, 1920 px on the long edge, 10 minutes, and 1 GiB. Saving does not change the clipboard. Live capture and platform coverage still need hands-on validation.
- Without Screen Recording access, the first capture shows the native macOS permission dialog. Choose Open System Settings, enable OpenLightCapture, then use the system's Quit & Reopen action. Deny leaves Settings closed. The app adds no restart dialog for Screen Recording; start a new capture after reopening. If no native dialog appears, open Screen Recording settings from permissions help.
- Automatic scrolling uses the native control permission dialog too. Choose Open System Settings and enable access. OpenLightCapture detects the grant and shows “Restart Now / Later” even while Settings remains active, including when event posting in the old process still needs a restart. Opening Settings or denying access does not trigger the reminder. Restart Now ends the current capture and reopens the same app; start a new capture afterward. Later keeps the app open, with regular and manual scrolling screenshots available. Each grant prompts once.
- Keep a stable app location. If macOS blocks a downloaded package, check its release/signing information or build from source rather than disabling security controls.
- Language changes wait until an active session ends. System dialogs can retain the system language.
- OpenLightCapture uses the `io.github.evilstar2016.openlightcapture` preference domain and support directory. Grant the required permissions on first use and configure Launch at Login in Settings.
- Disable Launch at Login and quit before removal. Delete the support directory only when clipboard-backed file paste is no longer needed. See [Privacy](../PRIVACY.md) and [Support](../SUPPORT.md).
