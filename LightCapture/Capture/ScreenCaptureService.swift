import AppKit
import CoreGraphics
import ScreenCaptureKit

@MainActor
final class ScreenCaptureService {
    func captureVisibleDisplays() async throws -> [FrozenScreen] {
        let shareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let processIdentifier = ProcessInfo.processInfo.processIdentifier
        let excludedApplications = shareableContent.applications.filter { $0.processID == processIdentifier }
        let primaryScreenHeight = NSScreen.screens.first?.frame.maxY ?? 0
        // SCShareableContent does not promise a stacking order. Hit testing must use
        // the Window Server's front-to-back list, including for area capture targets.
        let windowInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        let frontToBackWindowIDs = windowInfo?.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value } ?? []
        var results: [FrozenScreen] = []

        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let display = shareableContent.displays.first(where: { $0.displayID == number.uint32Value })
            else {
                continue
            }

            let filter = SCContentFilter(display: display, excludingApplications: excludedApplications, exceptingWindows: [])
            let transform = try DisplayTransform(
                screenFrame: screen.frame,
                capturePointSize: filter.contentRect.size,
                pointPixelScale: CGFloat(filter.pointPixelScale)
            )
            let configuration = SCStreamConfiguration()
            configuration.width = transform.pixelWidth
            configuration.height = transform.pixelHeight
            configuration.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            guard image.width == transform.pixelWidth, image.height == transform.pixelHeight else {
                throw ScreenCaptureError.invalidImageGeometry(displayID: display.displayID)
            }

            let windowFrames = shareableContent.windows.compactMap { window -> CapturedWindow? in
                let frame = DisplayTransform.appKitRect(fromQuartzRect: window.frame, primaryScreenHeight: primaryScreenHeight)
                guard let owningApplication = window.owningApplication,
                      owningApplication.processID != processIdentifier,
                      window.windowLayer == 0, window.isOnScreen,
                      frame.width > 0, frame.height > 0, frame.intersects(screen.frame)
                else {
                    return nil
                }
                return CapturedWindow(id: window.windowID, processIdentifier: owningApplication.processID, frame: frame)
            }
            let orderedWindows = CapturedWindow.frontToBack(windowFrames, onScreenWindowIDs: frontToBackWindowIDs)
            results.append(FrozenScreen(displayID: display.displayID, screenFrame: screen.frame, image: image, transform: transform, windows: orderedWindows))
        }

        guard !results.isEmpty else { throw ScreenCaptureError.noVisibleDisplays }
        return results
    }
}

struct FrozenScreen {
    let displayID: CGDirectDisplayID
    let screenFrame: CGRect
    let image: CGImage
    let transform: DisplayTransform
    let windows: [CapturedWindow]
}

struct CapturedDisplay {
    let displayID: CGDirectDisplayID
    let screenFrame: CGRect
    let pixelWidth: Int
    let pixelHeight: Int
    let transform: DisplayTransform

    init(_ screen: FrozenScreen) {
        displayID = screen.displayID
        screenFrame = screen.screenFrame
        pixelWidth = screen.image.width
        pixelHeight = screen.image.height
        transform = screen.transform
    }
}

struct CapturedWindow: Equatable {
    let id: CGWindowID
    let processIdentifier: Int32
    let frame: CGRect

    static func target(for selection: CGRect, in frontToBackWindows: [CapturedWindow]) -> CapturedWindow? {
        guard selection.width > 0, selection.height > 0 else { return nil }
        let center = CGPoint(x: selection.midX, y: selection.midY)
        return frontToBackWindows.first { $0.frame.contains(center) }
    }

    static func frontToBack(_ candidates: [CapturedWindow], onScreenWindowIDs: [CGWindowID]) -> [CapturedWindow] {
        var remaining = Dictionary(candidates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Omit windows absent from the current on-screen list instead of allowing
        // a stale, unordered candidate to intercept a visible window's selection.
        return onScreenWindowIDs.compactMap { remaining.removeValue(forKey: $0) }
    }
}

enum ScreenCaptureError: LocalizedError {
    case noVisibleDisplays
    case invalidImageGeometry(displayID: CGDirectDisplayID)

    var errorDescription: String? {
        switch self {
        case .noVisibleDisplays:
            L10n.errorNoDisplay
        case .invalidImageGeometry:
            L10n.errorScreenSizeChanged
        }
    }
}
