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
            let image: CGImage
            if #available(macOS 14.0, *) {
                let transform = try DisplayTransform(
                    screenFrame: screen.frame,
                    capturePointSize: filter.contentRect.size,
                    pointPixelScale: CGFloat(filter.pointPixelScale)
                )
                let configuration = SCStreamConfiguration()
                configuration.width = transform.pixelWidth
                configuration.height = transform.pixelHeight
                configuration.showsCursor = false
                image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            } else {
                // Ventura: SCScreenshotManager is unavailable; capture the display
                // rect through the window server at full backing resolution.
                let quartzRect = CGRect(x: screen.frame.minX, y: primaryScreenHeight - screen.frame.maxY,
                                        width: screen.frame.width, height: screen.frame.height)
                guard let legacyImage = CGWindowListCreateImage(quartzRect, [.optionOnScreenOnly, .excludeDesktopElements],
                                                                kCGNullWindowID, [.bestResolution])
                else {
                    throw ScreenCaptureError.invalidImageGeometry(displayID: display.displayID)
                }
                image = legacyImage
            }
            let transform: DisplayTransform = if #available(macOS 14.0, *) {
                try DisplayTransform(
                    screenFrame: screen.frame,
                    capturePointSize: filter.contentRect.size,
                    pointPixelScale: CGFloat(filter.pointPixelScale)
                )
            } else {
                try DisplayTransform(screenFrame: screen.frame, pixelWidth: image.width, pixelHeight: image.height)
            }
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
            let bars = ScreenBars.compute(frame: screen.frame, visibleFrame: screen.visibleFrame)
            results.append(FrozenScreen(displayID: display.displayID, screenFrame: screen.frame, image: image,
                                        transform: transform, windows: orderedWindows, bars: bars))
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
    var bars: ScreenBars = .zero
}

struct ScreenBars: Equatable {
    let top: CGFloat
    let bottom: CGFloat
    let leading: CGFloat
    let trailing: CGFloat

    static let zero = ScreenBars(top: 0, bottom: 0, leading: 0, trailing: 0)

    /// AppKit screen coordinates minus the visible work area gives the system
    /// bar thicknesses: menu bar on top and the Dock on bottom, left, or right.
    static func compute(frame: CGRect, visibleFrame: CGRect) -> ScreenBars {
        guard frame.width > 0, frame.height > 0 else { return .zero }
        return ScreenBars(
            top: max(0, frame.maxY - visibleFrame.maxY),
            bottom: max(0, visibleFrame.minY - frame.minY),
            leading: max(0, visibleFrame.minX - frame.minX),
            trailing: max(0, frame.maxX - visibleFrame.maxX)
        )
    }
}

enum DesktopSelectionRegion {
    /// Maps a pointer location hovering the desktop to its capture candidate
    /// in AppKit screen coordinates: near an edge the suggestion keeps the
    /// working area inside that edge (excluding the menu bar or Dock), while
    /// the middle suggests the entire screen.
    static func resolve(point: CGPoint, screenFrame: CGRect, bars: ScreenBars) -> CGRect? {
        guard screenFrame.contains(point) else { return nil }
        if bars.top > 0, point.y >= screenFrame.maxY - bars.top {
            return keepBottom(of: screenFrame, with: bars.top)
        }
        if bars.bottom > 0, point.y <= screenFrame.minY + bars.bottom {
            return keepTop(of: screenFrame, with: bars.bottom)
        }
        if bars.leading > 0, point.x <= screenFrame.minX + bars.leading {
            return keepTrailing(of: screenFrame, with: bars.leading)
        }
        if bars.trailing > 0, point.x >= screenFrame.maxX - bars.trailing {
            return keepLeading(of: screenFrame, with: bars.trailing)
        }
        return screenFrame
    }

    private static func keepBottom(of rect: CGRect, with inset: CGFloat) -> CGRect? {
        reduce(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - inset))
    }

    private static func keepTop(of rect: CGRect, with inset: CGFloat) -> CGRect? {
        reduce(CGRect(x: rect.minX, y: rect.minY + inset, width: rect.width, height: rect.height - inset))
    }

    private static func keepTrailing(of rect: CGRect, with inset: CGFloat) -> CGRect? {
        reduce(CGRect(x: rect.minX + inset, y: rect.minY, width: rect.width - inset, height: rect.height))
    }

    private static func keepLeading(of rect: CGRect, with inset: CGFloat) -> CGRect? {
        reduce(CGRect(x: rect.minX, y: rect.minY, width: rect.width - inset, height: rect.height))
    }

    private static func reduce(_ rect: CGRect) -> CGRect? {
        guard rect.width > 0, rect.height > 0 else { return nil }
        return rect
    }
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
