import AppKit
import Darwin

/// Native wheel input routed to a window without entering the global pointer stream.
enum AutomaticScrollEvent {
    /// CoreGraphics' per-process wheel routing uses this window tag. The public
    /// hit-window fields are read-only; keep this undocumented field isolated here.
    private static let windowRoutingField = CGEventField(rawValue: 51)!

    static func stepPixels(forViewportHeight height: CGFloat) -> Int32? {
        guard height.isFinite, height > 0 else { return nil }
        return Int32(max(1, min(240, floor(height * 0.35))))
    }

    static func make(
        pixels: Int32, target: AutomaticScrollTarget, primaryScreenHeight: CGFloat,
        setWindowLocation: (CGEvent, CGPoint) -> Bool = AutomaticScrollEvent.setWindowLocation
    ) -> CGEvent? {
        guard pixels > 0, primaryScreenHeight.isFinite,
              let source = CGEventSource(stateID: .privateState)
        else { return nil }
        source.localEventsSuppressionInterval = 0
        // This tag records our binding for validation, not WindowServer routing.
        source.userData = Int64(target.window.id)
        guard let event = CGEvent(
            scrollWheelEvent2Source: source, units: .pixel, wheelCount: 1,
            wheel1: -pixels, wheel2: 0, wheel3: 0
        ) else { return nil }
        event.location = CGPoint(x: target.globalPoint.x, y: primaryScreenHeight - target.globalPoint.y)
        event.setIntegerValueField(windowRoutingField, value: Int64(target.window.id))
        let localPoint = CGPoint(
            x: target.globalPoint.x - target.window.frame.minX,
            y: target.globalPoint.y - target.window.frame.minY
        )
        guard setWindowLocation(event, localPoint) else { return nil }
        event.flags = []
        return event
    }

    static func hasWindowRouting(_ event: CGEvent, to target: AutomaticScrollTarget) -> Bool {
        event.getIntegerValueField(windowRoutingField) == Int64(target.window.id)
    }

    private static func setWindowLocation(_ event: CGEvent, _ point: CGPoint) -> Bool {
        // A bare postToPid wheel is silently ignored by AppKit and Chromium.
        // Both the screen and window-local coordinates must be present. This
        // system entry point is not public SDK API: resolve it at runtime and
        // fail closed if unavailable, never fall back to a cursor-moving post.
        typealias Setter = @convention(c) (CGEvent, CGPoint) -> Void
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGEventSetWindowLocation")
        else { return false }
        unsafeBitCast(symbol, to: Setter.self)(event, point)
        return true
    }
}
