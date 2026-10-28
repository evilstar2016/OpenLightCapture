import Foundation

/// Stable semantic keys. Translations are maintained in Localizable.xcstrings.
enum L10n {
    static var toolSelect: String {
        LocalizationContext.current.string("tool.select", defaultValue: "Select")
    }

    static var toolRectangle: String {
        LocalizationContext.current.string("tool.rectangle", defaultValue: "Rectangle")
    }

    static var toolEllipse: String {
        LocalizationContext.current.string("tool.ellipse", defaultValue: "Ellipse")
    }

    static var toolArrow: String {
        LocalizationContext.current.string("tool.arrow", defaultValue: "Arrow")
    }

    static var toolBrush: String {
        LocalizationContext.current.string("tool.brush", defaultValue: "Brush")
    }

    static var toolText: String {
        LocalizationContext.current.string("tool.text", defaultValue: "Text")
    }

    static var toolMosaic: String {
        LocalizationContext.current.string("tool.mosaic", defaultValue: "Mosaic")
    }

    static var toolCrop: String {
        LocalizationContext.current.string("tool.crop", defaultValue: "Crop")
    }

    static var editorTitle: String {
        LocalizationContext.current.string("editor.title", defaultValue: "Screenshot Editor")
    }

    static var editorFitWindow: String {
        LocalizationContext.current.string("editor.fitWindow", defaultValue: "Fit Window")
    }

    static var editorFitWidth: String {
        LocalizationContext.current.string("editor.fitWidth", defaultValue: "Fit Width")
    }

    static var editorChangeSource: String {
        LocalizationContext.current.string("editor.changeSource", defaultValue: "Change Image…")
    }

    static var actionUndo: String {
        LocalizationContext.current.string("action.undo", defaultValue: "Undo")
    }

    static var actionRedo: String {
        LocalizationContext.current.string("action.redo", defaultValue: "Redo")
    }

    static var actionSave: String {
        LocalizationContext.current.string("action.save", defaultValue: "Save to File")
    }

    static var actionCancel: String {
        LocalizationContext.current.string("action.cancel", defaultValue: "Cancel")
    }

    static var actionComplete: String {
        LocalizationContext.current.string("action.complete", defaultValue: "Finish and Copy")
    }

    static var editorSourceTitle: String {
        LocalizationContext.current.string("editor.sourceTitle", defaultValue: "Choose a New Screenshot Source")
    }

    static var editorDiscardChanges: String {
        LocalizationContext.current.string("editor.discardChanges", defaultValue: "Continuing discards the current annotations and crop. Choose “Keep Editing” to retain them.")
    }

    static var editorSourceHelp: String {
        LocalizationContext.current.string("editor.sourceHelp", defaultValue: "Select a new area or start a scrolling screenshot.")
    }

    static var editorReselect: String {
        LocalizationContext.current.string("editor.reselect", defaultValue: "Select New Area")
    }

    static var actionStartLong: String {
        LocalizationContext.current.string("action.startLong", defaultValue: "Start Scrolling Screenshot")
    }

    static var editorKeepEditing: String {
        LocalizationContext.current.string("editor.keepEditing", defaultValue: "Keep Editing")
    }

    static var errorRenderTitle: String {
        LocalizationContext.current.string("error.renderTitle", defaultValue: "Unable to Create Screenshot")
    }

    static var actionOk: String {
        LocalizationContext.current.string("action.ok", defaultValue: "OK")
    }

    static var errorInvalidCrop: String {
        LocalizationContext.current.string("error.invalidCrop", defaultValue: "The crop area is invalid.")
    }

    static var errorRenderMemory: String {
        LocalizationContext.current.string("error.renderMemory", defaultValue: "Not enough memory to create the image.")
    }

    static var errorMosaic: String {
        LocalizationContext.current.string("error.mosaic", defaultValue: "Unable to process the mosaic area.")
    }

    static var styleWidth: String {
        LocalizationContext.current.string("style.width", defaultValue: "Width")
    }

    static var styleThin: String {
        LocalizationContext.current.string("style.thin", defaultValue: "Thin")
    }

    static var styleMedium: String {
        LocalizationContext.current.string("style.medium", defaultValue: "Medium")
    }

    static var styleThick: String {
        LocalizationContext.current.string("style.thick", defaultValue: "Thick")
    }

    static var styleSmall: String {
        LocalizationContext.current.string("style.small", defaultValue: "Small")
    }

    static var styleLarge: String {
        LocalizationContext.current.string("style.large", defaultValue: "Large")
    }

    static var colorRed: String {
        LocalizationContext.current.string("color.red", defaultValue: "Red")
    }

    static var colorOrange: String {
        LocalizationContext.current.string("color.orange", defaultValue: "Orange")
    }

    static var colorYellow: String {
        LocalizationContext.current.string("color.yellow", defaultValue: "Yellow")
    }

    static var colorGreen: String {
        LocalizationContext.current.string("color.green", defaultValue: "Green")
    }

    static var colorBlue: String {
        LocalizationContext.current.string("color.blue", defaultValue: "Blue")
    }

    static var colorBlack: String {
        LocalizationContext.current.string("color.black", defaultValue: "Black")
    }

    static var colorWhite: String {
        LocalizationContext.current.string("color.white", defaultValue: "White")
    }

    static var styleFontSize: String {
        LocalizationContext.current.string("style.fontSize", defaultValue: "Size")
    }

    static var styleMosaicSize: String {
        LocalizationContext.current.string("style.mosaicSize", defaultValue: "Block Size")
    }

    static var toolAdjustSelection: String {
        LocalizationContext.current.string("tool.adjustSelection", defaultValue: "Adjust Selection")
    }

    static var toolSelectAnnotation: String {
        LocalizationContext.current.string("tool.selectAnnotation", defaultValue: "Select Annotation")
    }

    static var toolTextHelp: String {
        LocalizationContext.current.string("tool.textHelp", defaultValue: "Text: click to type and press Return to confirm. Drag to move; double-click to edit.")
    }

    static func captureRestartHint(_ p0: String, in context: LocalizationContext = .current) -> String {
        context.format("capture.restartHint", defaultValue: "%1$@ Press the shortcut again to start a new screenshot.", arguments: [p0])
    }

    static func menuCaptureShortcut(_ p0: String, in context: LocalizationContext = .current) -> String {
        context.format("menu.captureShortcut", defaultValue: "Capture  %1$@", arguments: [p0])
    }

    static var errorHotKeyTitle: String {
        LocalizationContext.current.string("error.hotKeyTitle", defaultValue: "Shortcut Unavailable")
    }

    static var appName: String {
        LocalizationContext.current.string("app.name", defaultValue: "OpenLightCapture")
    }

    static var menuCapture: String {
        LocalizationContext.current.string("menu.capture", defaultValue: "Capture")
    }

    static var menuLongCapture: String {
        LocalizationContext.current.string("menu.longCapture", defaultValue: "Scrolling Screenshot…")
    }

    static var menuSettings: String {
        LocalizationContext.current.string("menu.settings", defaultValue: "Settings…")
    }

    static var menuPermissionHelp: String {
        LocalizationContext.current.string("menu.permissionHelp", defaultValue: "Permissions and Help…")
    }

    static var menuQuit: String {
        LocalizationContext.current.string("menu.quit", defaultValue: "Quit OpenLightCapture")
    }

    static var menuEdit: String {
        LocalizationContext.current.string("menu.edit", defaultValue: "Edit")
    }

    static var actionCut: String {
        LocalizationContext.current.string("action.cut", defaultValue: "Cut")
    }

    static var actionCopy: String {
        LocalizationContext.current.string("action.copy", defaultValue: "Copy")
    }

    static var actionPaste: String {
        LocalizationContext.current.string("action.paste", defaultValue: "Paste")
    }

    static var actionSelectAll: String {
        LocalizationContext.current.string("action.selectAll", defaultValue: "Select All")
    }

    static var captureCopied: String {
        LocalizationContext.current.string("capture.copied", defaultValue: "Screenshot copied")
    }

    static var interruptionSleep: String {
        LocalizationContext.current.string("interruption.sleep", defaultValue: "The computer is going to sleep. The screenshot was cancelled.")
    }

    static var interruptionDisplaySleep: String {
        LocalizationContext.current.string("interruption.displaySleep", defaultValue: "The display is asleep. The screenshot was cancelled.")
    }

    static var interruptionSession: String {
        LocalizationContext.current.string("interruption.session", defaultValue: "The user session was locked or switched. The screenshot was cancelled.")
    }

    static var interruptionDisplayChange: String {
        LocalizationContext.current.string("interruption.displayChange", defaultValue: "The display configuration changed. The screenshot was cancelled.")
    }

    static func errorHotKeyRejected(_ p0: String, _ p1: Int, in context: LocalizationContext = .current) -> String {
        context.format("error.hotKeyRejected", defaultValue: "The system rejected %1$@ (error %2$lld). Try another shortcut; the menu bar remains available.", arguments: [p0, p1])
    }

    static var errorHotKeyModifier: String {
        LocalizationContext.current.string("error.hotKeyModifier", defaultValue: "Hold at least one modifier key, such as ⌘, ⇧, or ⌥.")
    }

    static var permissionDeviceControl: String {
        LocalizationContext.current.string("permission.deviceControl", defaultValue: "Device Control and Data Access")
    }

    static var permissionAccessibility: String {
        LocalizationContext.current.string("permission.accessibility", defaultValue: "Accessibility")
    }

    static func permissionAutomaticGuidance(_ p0: String, in context: LocalizationContext = .current) -> String {
        context.format("permission.automaticGuidance", defaultValue: "Automatic scrolling screenshots require “%1$@” permission.\nAfter allowing access, quit and reopen OpenLightCapture before starting another screenshot.", arguments: [p0])
    }

    static var permissionControlLost: String {
        LocalizationContext.current.string("permission.controlLost", defaultValue: "Control permission is not active or was revoked. Automatic scrolling is paused.\nAfter allowing access, end this screenshot, then quit and reopen OpenLightCapture.")
    }

    static var permissionTitle: String {
        LocalizationContext.current.string("permission.title", defaultValue: "Permissions and Help")
    }

    static var permissionHeading: String {
        LocalizationContext.current.string("permission.heading", defaultValue: "Enable Permissions for Your Capture Mode")
    }

    static var permissionScreenRecording: String {
        LocalizationContext.current.string("permission.screenRecording", defaultValue: "Screen Recording")
    }

    static var permissionScreenHelp: String {
        LocalizationContext.current.string("permission.screenHelp", defaultValue: "Required for regular, manual scrolling, and automatic scrolling screenshots to read the screen area you select.")
    }

    static var permissionOpenScreen: String {
        LocalizationContext.current.string("permission.openScreen", defaultValue: "Open Screen Recording Settings")
    }

    static var permissionControlHelp: String {
        LocalizationContext.current.string("permission.controlHelp", defaultValue: "Automatic scrolling also needs control permission to scroll the page. Regular and manual scrolling screenshots only need Screen Recording.")
    }

    static var permissionOpenControl: String {
        LocalizationContext.current.string("permission.openControl", defaultValue: "Open Control Settings")
    }

    static var permissionRestartHeading: String {
        LocalizationContext.current.string("permission.restartHeading", defaultValue: "After allowing access, quit and reopen OpenLightCapture")
    }

    static var permissionRestartHelp: String {
        LocalizationContext.current.string("permission.restartHelp", defaultValue: "After allowing access in System Settings, choose “Quit OpenLightCapture” from the menu bar, then reopen the app and start a new screenshot.")
    }

    static var permissionRestartPrompt: String {
        LocalizationContext.current.string("permission.restartPrompt", defaultValue: "If you enabled access in System Settings, restart OpenLightCapture to apply it. Restarting ends the current screenshot. Start a new screenshot after the app reopens.")
    }

    static var permissionRestartNow: String {
        LocalizationContext.current.string("permission.restartNow", defaultValue: "Restart Now")
    }

    static var permissionRestartLater: String {
        LocalizationContext.current.string("permission.restartLater", defaultValue: "Later")
    }

    static func permissionRestartFailed(_ detail: String, in context: LocalizationContext = .current) -> String {
        context.format("permission.restartFailed", defaultValue: "Unable to restart OpenLightCapture: %1$@\nQuit the app from the menu bar, then reopen it manually.", arguments: [detail])
    }

    static var permissionQuitWarning: String {
        LocalizationContext.current.string("permission.quitWarning", defaultValue: "Quitting ends the current screenshot.")
    }

    static var permissionRefresh: String {
        LocalizationContext.current.string("permission.refresh", defaultValue: "Refresh Permission Status")
    }

    static var permissionRevealApp: String {
        LocalizationContext.current.string("permission.revealApp", defaultValue: "Show App in Finder")
    }

    static var permissionStatusHelp: String {
        LocalizationContext.current.string("permission.statusHelp", defaultValue: "Status shows whether this app can use the permission now. If access is enabled but still shows “Not Active,” restart the app as described above.")
    }

    static var permissionPrivacy: String {
        LocalizationContext.current.string("permission.privacy", defaultValue: "Screenshots are processed locally and are not uploaded by this app. After pasting, the system clipboard and receiving app may handle the image according to their settings.")
    }

    static var permissionAvailable: String {
        LocalizationContext.current.string("permission.available", defaultValue: "Available")
    }

    static var permissionUnavailable: String {
        LocalizationContext.current.string("permission.unavailable", defaultValue: "Not Active")
    }

    static var settingsTitle: String {
        LocalizationContext.current.string("settings.title", defaultValue: "OpenLightCapture Settings")
    }

    static var settingsShortcuts: String {
        LocalizationContext.current.string("settings.shortcuts", defaultValue: "Shortcut")
    }

    static var settingsRestore: String {
        LocalizationContext.current.string("settings.restore", defaultValue: "Restore Default")
    }

    static func settingsShortcutRestored(_ p0: String, in context: LocalizationContext = .current) -> String {
        context.format("settings.shortcutRestored", defaultValue: "Restored: %1$@", arguments: [p0])
    }

    static var settingsShortcutConflict: String {
        LocalizationContext.current.string("settings.shortcutConflict", defaultValue: "The default shortcut ⇧⌘A may conflict with Feishu. Change it in either app.")
    }

    static var settingsShortcutFallback: String {
        LocalizationContext.current.string("settings.shortcutFallback", defaultValue: "You can always start a capture from the menu bar.")
    }

    static var settingsStartup: String {
        LocalizationContext.current.string("settings.startup", defaultValue: "Startup")
    }

    static var settingsLaunchAtLogin: String {
        LocalizationContext.current.string("settings.launchAtLogin", defaultValue: "Launch at Login")
    }

    static func settingsLoginError(_ p0: String, in context: LocalizationContext = .current) -> String {
        context.format("settings.loginError", defaultValue: "The system did not accept the login item setting: %1$@", arguments: [p0])
    }

    static var settingsLoginEnabled: String {
        LocalizationContext.current.string("settings.loginEnabled", defaultValue: "OpenLightCapture launches automatically after you log in.")
    }

    static var settingsLoginApproval: String {
        LocalizationContext.current.string("settings.loginApproval", defaultValue: "Allow this app in System Settings to enable Launch at Login.")
    }

    static var settingsLoginDisabled: String {
        LocalizationContext.current.string("settings.loginDisabled", defaultValue: "The app won’t launch automatically at login.")
    }

    static var settingsLoginNotFound: String {
        LocalizationContext.current.string("settings.loginNotFound", defaultValue: "Launch at Login is not enabled.")
    }

    static var settingsLoginUnknown: String {
        LocalizationContext.current.string("settings.loginUnknown", defaultValue: "Unable to read the startup setting. Try again later.")
    }

    static var settingsShortcutRecording: String {
        LocalizationContext.current.string("settings.shortcutRecording", defaultValue: "Press a new shortcut; Esc to cancel")
    }

    static func settingsShortcutSet(_ p0: String, in context: LocalizationContext = .current) -> String {
        context.format("settings.shortcutSet", defaultValue: "Set: %1$@", arguments: [p0])
    }

    static var settingsShortcutPrompt: String {
        LocalizationContext.current.string("settings.shortcutPrompt", defaultValue: "Press a shortcut; Esc to cancel")
    }

    static func settingsKeyCode(_ p0: Int, in context: LocalizationContext = .current) -> String {
        context.format("settings.keyCode", defaultValue: "Key code %1$lld", arguments: [p0])
    }

    static var permissionScreenTitle: String {
        LocalizationContext.current.string("permission.screenTitle", defaultValue: "OpenLightCapture Needs Screen Recording Permission")
    }

    static func permissionControlTitle(_ p0: String, in context: LocalizationContext = .current) -> String {
        context.format("permission.controlTitle", defaultValue: "Automatic Scrolling Needs “%1$@” Permission", arguments: [p0])
    }

    static var permissionScreenPurpose: String {
        LocalizationContext.current.string("permission.screenPurpose", defaultValue: "Regular and scrolling screenshots need access to the screen area you select.")
    }

    static var permissionControlPurpose: String {
        LocalizationContext.current.string("permission.controlPurpose", defaultValue: "Automatic scrolling also needs control permission to scroll the page.")
    }

    static var permissionAuthorize: String {
        LocalizationContext.current.string("permission.authorize", defaultValue: "Open Settings")
    }

    static var permissionLater: String {
        LocalizationContext.current.string("permission.later", defaultValue: "Not Now")
    }

    static var longModeManual: String {
        LocalizationContext.current.string("long.modeManual", defaultValue: "Manual")
    }

    static var longModeAutomatic: String {
        LocalizationContext.current.string("long.modeAutomatic", defaultValue: "Automatic")
    }

    static var longPreparing: String {
        LocalizationContext.current.string("long.preparing", defaultValue: "Preparing Scrolling Screenshot")
    }

    static var longPermissionHelp: String {
        LocalizationContext.current.string("long.permissionHelp", defaultValue: "Regular and manual scrolling screenshots need Screen Recording. Automatic scrolling also needs control permission. Restart the app after allowing access.")
    }

    static var longStartManual: String {
        LocalizationContext.current.string("long.startManual", defaultValue: "Manual Scrolling")
    }

    static var longStartAutomatic: String {
        LocalizationContext.current.string("long.startAutomatic", defaultValue: "Automatic Scrolling…")
    }

    static var actionPause: String {
        LocalizationContext.current.string("action.pause", defaultValue: "Pause")
    }

    static var actionResume: String {
        LocalizationContext.current.string("action.resume", defaultValue: "Resume")
    }

    static var longSwitchManual: String {
        LocalizationContext.current.string("long.switchManual", defaultValue: "Switch to Manual")
    }

    static var longPreview: String {
        LocalizationContext.current.string("long.preview", defaultValue: "End and Preview")
    }

    static var longUsePartial: String {
        LocalizationContext.current.string("long.usePartial", defaultValue: "Use Captured Portion")
    }

    static var longTitle: String {
        LocalizationContext.current.string("long.title", defaultValue: "Scrolling Screenshot")
    }

    static var longChooseMode: String {
        LocalizationContext.current.string("long.chooseMode", defaultValue: "Scrolling Screenshot Mode")
    }

    static var longSelectionHelp: String {
        LocalizationContext.current.string("long.selectionHelp", defaultValue: "Manual mode needs Screen Recording; automatic mode also needs control permission. Restart after allowing access. Exclude fixed headers, footers, and scrollbars.")
    }

    static func longRunning(_ p0: String, _ p1: Int, _ p2: Int, in context: LocalizationContext = .current) -> String {
        context.format("long.running", defaultValue: "%1$@ scroll · Confirmed %2$lld px · %3$lld seconds", arguments: [p0, p1, p2])
    }

    static var longAutomaticHelp: String {
        LocalizationContext.current.string("long.automaticHelp", defaultValue: "Automatic scrolling is locked to the target window. You can move the pointer freely, pause, or end and preview at any time.")
    }

    static var longManualHelp: String {
        LocalizationContext.current.string("long.manualHelp", defaultValue: "Scroll down in small steps. Brief changes wait for alignment. The image is only copied after you finish editing.")
    }

    static var longWaiting: String {
        LocalizationContext.current.string("long.waiting", defaultValue: "Waiting for the image to stabilize and align. Stop scrolling briefly; confirmed content is retained.")
    }

    static func longPaused(_ p0: Int, in context: LocalizationContext = .current) -> String {
        context.format("long.paused", defaultValue: "Paused · Confirmed %1$lld px", arguments: [p0])
    }

    static func longPartial(_ p0: Int, in context: LocalizationContext = .current) -> String {
        context.format("long.partial", defaultValue: "Partial Result · Confirmed %1$lld px", arguments: [p0])
    }

    static var longFailure: String {
        LocalizationContext.current.string("long.failure", defaultValue: "Unable to Continue Scrolling Screenshot")
    }

    static var longPreviewCaption: String {
        LocalizationContext.current.string("long.previewCaption", defaultValue: "Current Selection")
    }

    static var errorNoDisplay: String {
        LocalizationContext.current.string("error.noDisplay", defaultValue: "No display image is available. Regular and scrolling screenshots require Screen Recording permission. After allowing access, quit and reopen OpenLightCapture.")
    }

    static var errorScreenSizeChanged: String {
        LocalizationContext.current.string("error.screenSizeChanged", defaultValue: "The screen dimensions changed. Start a new screenshot.")
    }

    static var errorDisplayUnavailable: String {
        LocalizationContext.current.string("error.displayUnavailable", defaultValue: "The selected display is unavailable. Select a new screenshot area.")
    }

    static func errorStreamStart(_ p0: String, in context: LocalizationContext = .current) -> String {
        context.format("error.streamStart", defaultValue: "Unable to start screen capture: %1$@", arguments: [p0])
    }

    static var errorInvalidPNG: String {
        LocalizationContext.current.string("error.invalidPNG", defaultValue: "The PNG data is invalid. The clipboard was not changed.")
    }

    static var errorInvalidDimensions: String {
        LocalizationContext.current.string("error.invalidDimensions", defaultValue: "The screenshot exceeds the image limits. The clipboard was not changed.")
    }

    static var errorAssetStorage: String {
        LocalizationContext.current.string("error.assetStorage", defaultValue: "Not enough local storage. Free disk space and try again.")
    }

    static var errorAssetUnsafe: String {
        LocalizationContext.current.string("error.assetUnsafe", defaultValue: "The screenshot storage directory is in an unexpected state. Existing files were retained.")
    }

    static func errorAssetFile(_ p0: String, in context: LocalizationContext = .current) -> String {
        context.format("error.assetFile", defaultValue: "Unable to prepare the local screenshot file: %1$@", arguments: [p0])
    }

    static var errorClipboardRejected: String {
        LocalizationContext.current.string("error.clipboardRejected", defaultValue: "The system clipboard rejected the screenshot. Its previous content may have been replaced. The screenshot preview is retained so you can try again.")
    }

    static var errorCopyTitle: String {
        LocalizationContext.current.string("error.copyTitle", defaultValue: "Copy Failed")
    }

    static var errorPngTitle: String {
        LocalizationContext.current.string("error.pngTitle", defaultValue: "Unable to Create PNG")
    }

    static var errorSaveTitle: String {
        LocalizationContext.current.string("error.saveTitle", defaultValue: "Save Failed")
    }

    static var errorSavedCopyTitle: String {
        LocalizationContext.current.string("error.savedCopyTitle", defaultValue: "File Saved, Copy Failed")
    }

    static func errorSavedCopyDetail(_ p0: String, _ p1: String, in context: LocalizationContext = .current) -> String {
        context.format("error.savedCopyDetail", defaultValue: "The file was saved as “%1$@”.\n%2$@", arguments: [p0, p1])
    }

    static var errorPngDestination: String {
        LocalizationContext.current.string("error.pngDestination", defaultValue: "Unable to create the PNG encoder.")
    }

    static var errorPngEncoding: String {
        LocalizationContext.current.string("error.pngEncoding", defaultValue: "PNG encoding did not finish.")
    }

    static var selectionHint: String {
        LocalizationContext.current.string("selection.hint", defaultValue: "Drag to select · Space to switch windows · Esc to cancel")
    }

    static var selectionArea: String {
        LocalizationContext.current.string("selection.area", defaultValue: "Area")
    }

    static var selectionWindow: String {
        LocalizationContext.current.string("selection.window", defaultValue: "Window")
    }

    static var selectionLongAfterMarks: String {
        LocalizationContext.current.string("selection.longAfterMarks", defaultValue: "Start scrolling capture before annotating, or undo the annotations first")
    }

    static var errorCaptureTitle: String {
        LocalizationContext.current.string("error.captureTitle", defaultValue: "Unable to Start Screenshot")
    }

    static var errorLongUnavailable: String {
        LocalizationContext.current.string("error.longUnavailable", defaultValue: "Scrolling Screenshot Unavailable")
    }

    static var errorLongService: String {
        LocalizationContext.current.string("error.longService", defaultValue: "The scrolling capture service is unavailable. Start a new screenshot or press Esc to cancel.")
    }

    static var errorSelectionTitle: String {
        LocalizationContext.current.string("error.selectionTitle", defaultValue: "Unable to Use Selection")
    }

    static var errorSelectionPixels: String {
        LocalizationContext.current.string("error.selectionPixels", defaultValue: "The selection has no usable pixels. Select a new area.")
    }

    static var errorCopyRetained: String {
        LocalizationContext.current.string("error.copyRetained", defaultValue: "Copy failed. You can still edit this screenshot and try again.")
    }

    static var errorOutputTitle: String {
        LocalizationContext.current.string("error.outputTitle", defaultValue: "Output Unavailable")
    }

    static var errorSaveService: String {
        LocalizationContext.current.string("error.saveService", defaultValue: "The save service is unavailable.")
    }

    static var errorClipboardService: String {
        LocalizationContext.current.string("error.clipboardService", defaultValue: "The clipboard publishing service is unavailable.")
    }

    static var longUserPaused: String {
        LocalizationContext.current.string("long.userPaused", defaultValue: "Paused by the user.")
    }

    static var longPartialContent: String {
        LocalizationContext.current.string("long.partialContent", defaultValue: "Only part of the content was captured.")
    }

    static var longTargetNotLocked: String {
        LocalizationContext.current.string("long.targetNotLocked", defaultValue: "Unable to lock the scrolling window. Select the scrollable content in one window again, or use manual scrolling.")
    }

    static var longReturnToTarget: String {
        LocalizationContext.current.string("long.returnToTarget", defaultValue: "The target app changed. Return to the selected page and start again.")
    }

    static var longInvalidSelection: String {
        LocalizationContext.current.string("long.invalidSelection", defaultValue: "The selection is no longer valid. Select a new screenshot area.")
    }

    static func longStreamStopped(_ p0: String, in context: LocalizationContext = .current) -> String {
        context.format("long.streamStopped", defaultValue: "Screen capture stopped: %1$@", arguments: [p0])
    }

    static var longTargetSwitched: String {
        LocalizationContext.current.string("long.targetSwitched", defaultValue: "The target app changed. Scrolling capture stopped safely.")
    }

    static var longAreaChanged: String {
        LocalizationContext.current.string("long.areaChanged", defaultValue: "The scrolling capture area changed size. Capture stopped.")
    }

    static var longCapacityPartial: String {
        LocalizationContext.current.string("long.capacityPartial", defaultValue: "The image height or pixel limit was reached. Only reliably captured content is retained.")
    }

    static var longCapacityReached: String {
        LocalizationContext.current.string("long.capacityReached", defaultValue: "The resource limit was reached.")
    }

    static var longBottomUnconfirmed: String {
        LocalizationContext.current.string("long.bottomUnconfirmed", defaultValue: "Three small scroll steps found no additional content. The bottom of the page could not be confirmed.")
    }

    static var longNoMoreContent: String {
        LocalizationContext.current.string("long.noMoreContent", defaultValue: "No additional content was detected.")
    }

    static var longAutoTargetChanged: String {
        LocalizationContext.current.string("long.autoTargetChanged", defaultValue: "The target app changed. Automatic scrolling stopped.")
    }

    static var longEventFailed: String {
        LocalizationContext.current.string("long.eventFailed", defaultValue: "Unable to create a scroll event.")
    }

    static var longTargetDeliveryFailed: String {
        LocalizationContext.current.string("long.targetDeliveryFailed", defaultValue: "The target window closed, moved, or could not receive scrolling reliably. Confirmed content is retained. Select a new area.")
    }

    static var longEnded: String {
        LocalizationContext.current.string("long.ended", defaultValue: "Capture ended.")
    }

    static var longStartPending: String {
        LocalizationContext.current.string("long.startPending", defaultValue: "Preparing scrolling capture. Please wait.")
    }

    static var longTimeLimit: String {
        LocalizationContext.current.string("long.timeLimit", defaultValue: "The 180-second active capture limit was reached. Only reliably captured content is retained.")
    }

    static var longStartupTimeout: String {
        LocalizationContext.current.string("long.startupTimeout", defaultValue: "No reliable first frame was established within 5 seconds. Pause dynamic content or exclude it from the selection and try again.")
    }

    static var longFrameTimeout: String {
        LocalizationContext.current.string("long.frameTimeout", defaultValue: "No screen image was received for 5 seconds. Capture is paused.")
    }

    static var longTargetClosed: String {
        LocalizationContext.current.string("long.targetClosed", defaultValue: "The target app closed or changed. Scrolling capture stopped safely.")
    }

    static var longWindowChanged: String {
        LocalizationContext.current.string("long.windowChanged", defaultValue: "The target window closed, hid, or moved. Scrolling capture stopped safely.")
    }

    static var longDisplayChanged: String {
        LocalizationContext.current.string("long.displayChanged", defaultValue: "The display configuration changed. Scrolling capture stopped.")
    }

    static var stitchIntakeStopped: String {
        LocalizationContext.current.string("stitch.intakeStopped", defaultValue: "No longer receiving frames")
    }

    static var stitchInvalidImage: String {
        LocalizationContext.current.string("stitch.invalidImage", defaultValue: "The captured image dimensions are invalid or exceed the limit")
    }

    static var stitchWorkspaceFailed: String {
        LocalizationContext.current.string("stitch.workspaceFailed", defaultValue: "Unable to create the scrolling capture workspace")
    }

    static var stitchInitialAlignment: String {
        LocalizationContext.current.string("stitch.initialAlignment", defaultValue: "Unable to align the image reliably. Select a new scrolling area.")
    }

    static var stitchInitialTile: String {
        LocalizationContext.current.string("stitch.initialTile", defaultValue: "The first image tile was not written")
    }

    static var stitchSizeChanged: String {
        LocalizationContext.current.string("stitch.sizeChanged", defaultValue: "The screen or selection size changed. Start a new scrolling screenshot")
    }

    static var stitchAlignmentLost: String {
        LocalizationContext.current.string("stitch.alignmentLost", defaultValue: "Unable to align the image reliably. Confirmed content is retained.")
    }

    static var stitchProcessingFailed: String {
        LocalizationContext.current.string("stitch.processingFailed", defaultValue: "Unable to process the captured image")
    }

    static var stitchDuplicateFrame: String {
        LocalizationContext.current.string("stitch.duplicateFrame", defaultValue: "A duplicate frame sequence was detected")
    }

    static var stitchFirstPixels: String {
        LocalizationContext.current.string("stitch.firstPixels", defaultValue: "Unable to read the first frame's pixels")
    }

    static var stitchPaused: String {
        LocalizationContext.current.string("stitch.paused", defaultValue: "Capture is paused.")
    }

    static var matchSizeChanged: String {
        LocalizationContext.current.string("match.sizeChanged", defaultValue: "Capture dimensions changed")
    }

    static var matchImageLimit: String {
        LocalizationContext.current.string("match.imageLimit", defaultValue: "The current image exceeds the image limit")
    }

    static var matchPixelsUnavailable: String {
        LocalizationContext.current.string("match.pixelsUnavailable", defaultValue: "Unable to read captured pixels")
    }

    static var matchSelectionTooSmall: String {
        LocalizationContext.current.string("match.selectionTooSmall", defaultValue: "The selection is too small for reliable alignment")
    }

    static var matchInsufficientContent: String {
        LocalizationContext.current.string("match.insufficientContent", defaultValue: "Not enough distinct content is available for alignment. Include more varied content and scroll in smaller steps.")
    }

    static var matchRepeatedContent: String {
        LocalizationContext.current.string("match.repeatedContent", defaultValue: "Repeated content makes the alignment ambiguous. Select an area with more distinct content.")
    }

    static var matchOverlapLost: String {
        LocalizationContext.current.string("match.overlapLost", defaultValue: "The image changed too much or has too little overlap to align reliably. Scroll more slowly, or select an area without fixed bars or dynamic content.")
    }

    static var tileInvalidDimensions: String {
        LocalizationContext.current.string("tile.invalidDimensions", defaultValue: "The stitching frame has invalid pixel dimensions.")
    }

    static var tileCapacity: String {
        LocalizationContext.current.string("tile.capacity", defaultValue: "The scrolling image reached the 50,000-pixel height or 60-million-pixel limit.")
    }

    static var tileStorage: String {
        LocalizationContext.current.string("tile.storage", defaultValue: "Not enough disk space for the scrolling capture workspace.")
    }

    static var tileNoFrames: String {
        LocalizationContext.current.string("tile.noFrames", defaultValue: "No reliable image is available to generate a preview.")
    }

    static var tileUnreadable: String {
        LocalizationContext.current.string("tile.unreadable", defaultValue: "A saved image tile could not be read.")
    }

    static var tileUnsafe: String {
        LocalizationContext.current.string("tile.unsafe", defaultValue: "The scrolling capture directory is in an unexpected state. Existing files were retained.")
    }

    static func tileFile(_ p0: String, in context: LocalizationContext = .current) -> String {
        context.format("tile.file", defaultValue: "Unable to save an image tile: %1$@", arguments: [p0])
    }

    static var settingsLanguage: String {
        LocalizationContext.current.string("settings.language", defaultValue: "Language / 语言")
    }

    static var settingsFollowSystem: String {
        LocalizationContext.current.string("settings.followSystem", defaultValue: "Follow System")
    }

    static var settingsLanguagePending: String {
        LocalizationContext.current.string("settings.languagePending", defaultValue: "The new language will apply after this screenshot ends.")
    }

    static var filenamePrefix: String {
        LocalizationContext.current.string("filename.prefix", defaultValue: "Screenshot")
    }

    static func permissionMessage(_ value: String, in context: LocalizationContext = .current) -> String {
        context.format("permission.message", defaultValue: "%1$@\n\n“Open Settings” takes you to the relevant setting. After allowing access for OpenLightCapture, quit and reopen the app before starting another screenshot.", arguments: [value])
    }

    static func longStartFailureManual(_ value: String, in context: LocalizationContext = .current) -> String {
        context.format("long.startFailureManual", defaultValue: "%1$@ Try again or cancel.", arguments: [value])
    }

    static func longStartFailureAutomatic(_ value: String, in context: LocalizationContext = .current) -> String {
        context.format("long.startFailureAutomatic", defaultValue: "%1$@ You can use manual scrolling instead.", arguments: [value])
    }

    static func longNoPreview(_ value: String, in context: LocalizationContext = .current) -> String {
        context.format("long.noPreview", defaultValue: "%1$@ No reliable image is available to preview yet.", arguments: [value])
    }

    static func settingsCurrentLanguageValue(_ value: String, in context: LocalizationContext = .current) -> String {
        context.format("settings.currentLanguageValue", defaultValue: "Current language: %1$@", arguments: [value])
    }

    static var settingsFollowAuthor: String {
        LocalizationContext.current.string("settings.followAuthor", defaultValue: "Follow the author")
    }

    static var settingsAuthorLinkHelp: String {
        LocalizationContext.current.string("settings.authorLinkHelp", defaultValue: "Open @EverSeenU on X in your browser")
    }
}
