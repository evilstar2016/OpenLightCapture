import AppKit

struct AutomaticScrollTarget: Equatable {
    let window: CapturedWindow
    let globalPoint: CGPoint

    init?(window: CapturedWindow, selection: CGRect) {
        guard window.id > 0, window.processIdentifier > 0,
              selection.width > 0, selection.height > 0,
              selection.minX.isFinite, selection.minY.isFinite,
              selection.maxX.isFinite, selection.maxY.isFinite,
              window.frame.width > 0, window.frame.height > 0
        else { return nil }
        let point = CGPoint(x: selection.midX, y: selection.midY)
        guard window.frame.contains(point) else { return nil }
        self.window = window
        globalPoint = point
    }

    func matches(_ currentWindow: CapturedWindow?) -> Bool {
        currentWindow == window
    }

    func allowsForeground(processID: Int32?, controllerProcessID: Int32, controlPanelVisible: Bool) -> Bool {
        processID == window.processIdentifier || (controlPanelVisible && processID == controllerProcessID)
    }

    @MainActor
    static func topmostWindow(at point: CGPoint) -> CapturedWindow? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        let primaryScreenHeight = NSScreen.screens.first?.frame.maxY ?? 0
        // WindowServer returns front-to-back order. Include floating panels and
        // our own control panel: an occluded point must never scroll another UI.
        for info in windows {
            guard let windowID = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let processID = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let quartzFrame = CGRect(dictionaryRepresentation: bounds as CFDictionary)
            else { continue }
            let frame = DisplayTransform.appKitRect(fromQuartzRect: quartzFrame, primaryScreenHeight: primaryScreenHeight)
            if frame.contains(point) {
                return CapturedWindow(id: windowID, processIdentifier: processID, frame: frame)
            }
        }
        return nil
    }

    @MainActor
    static func currentWindow(_ windowID: CGWindowID) -> CapturedWindow? {
        guard let windows = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID) as? [[String: Any]],
              let info = windows.first(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == windowID }),
              (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue == true,
              (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
              let processID = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
              let bounds = info[kCGWindowBounds as String] as? [String: Any],
              let quartzFrame = CGRect(dictionaryRepresentation: bounds as CFDictionary)
        else { return nil }
        return CapturedWindow(id: windowID, processIdentifier: processID, frame: DisplayTransform.appKitRect(
            fromQuartzRect: quartzFrame,
            primaryScreenHeight: NSScreen.screens.first?.frame.maxY ?? 0
        ))
    }
}
