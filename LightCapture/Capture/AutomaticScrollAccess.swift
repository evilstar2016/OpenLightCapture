import AppKit

enum AutomaticScrollDelivery: Equatable {
    case posted
    case permissionDenied
    case targetUnavailable
    case invalidEvent
}

@MainActor
final class AutomaticScrollAccess {
    private let preflight: () -> Bool
    private let resolveWindow: @MainActor (CGWindowID) -> CapturedWindow?
    private let resolveHitWindow: @MainActor (CGPoint) -> CapturedWindow?
    private let postEvent: (CGEvent, Int32) -> Void

    init(
        preflight: @escaping () -> Bool = { CGPreflightPostEventAccess() },
        resolveWindow: @escaping @MainActor (CGWindowID) -> CapturedWindow? = AutomaticScrollTarget.currentWindow,
        resolveHitWindow: @escaping @MainActor (CGPoint) -> CapturedWindow? = AutomaticScrollTarget.topmostWindow,
        postEvent: @escaping (CGEvent, Int32) -> Void = { $0.postToPid($1) }
    ) {
        self.preflight = preflight
        self.resolveWindow = resolveWindow
        self.resolveHitWindow = resolveHitWindow
        self.postEvent = postEvent
    }

    var hasAccess: Bool {
        preflight()
    }

    func postIfAllowed(_ event: CGEvent, to target: AutomaticScrollTarget) -> AutomaticScrollDelivery {
        guard hasAccess else { return .permissionDenied }
        guard target.window.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              target.matches(resolveWindow(target.window.id)),
              target.matches(resolveHitWindow(target.globalPoint))
        else { return .targetUnavailable }
        let primaryScreenHeight = NSScreen.screens.first?.frame.maxY ?? 0
        let expectedPoint = CGPoint(x: target.globalPoint.x, y: primaryScreenHeight - target.globalPoint.y)
        guard event.type == .scrollWheel,
              event.getIntegerValueField(.eventSourceUserData) == Int64(target.window.id),
              AutomaticScrollEvent.hasWindowRouting(event, to: target),
              abs(event.location.x - expectedPoint.x) < 0.01,
              abs(event.location.y - expectedPoint.y) < 0.01
        else { return .invalidEvent }
        postEvent(event, target.window.processIdentifier)
        return .posted
    }
}
