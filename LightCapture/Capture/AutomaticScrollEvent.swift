import AppKit

/// Native system wheel input at a locked screen point. Window routing is checked
/// immediately before delivery; posting a wheel never moves the physical pointer.
enum AutomaticScrollEvent {
    static func stepPixels(forViewportHeight height: CGFloat) -> Int32? {
        guard height.isFinite, height > 0 else { return nil }
        return Int32(max(1, min(240, floor(height * 0.35))))
    }

    static func make(pixels: Int32, target: AutomaticScrollTarget, primaryScreenHeight: CGFloat) -> CGEvent? {
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
        event.flags = []
        return event
    }
}
