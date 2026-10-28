import AppKit
@testable import LightCapture
import XCTest

@MainActor
final class AutomaticScrollAccessTests: XCTestCase {
    func testGrantedAccessPostsNativeWheelForTheVisibleBoundWindow() throws {
        let target = try target()
        var postedWindows: [CGWindowID] = []
        let access = AutomaticScrollAccess(preflight: { true }, resolveWindow: { _ in target.window }, resolveHitWindow: { _ in target.window }, postEvent: { event in
            postedWindows.append(CGWindowID(event.getIntegerValueField(.eventSourceUserData)))
            XCTAssertEqual(event.type, .scrollWheel)
            XCTAssertEqual(event.getIntegerValueField(.eventSourceUserData), Int64(target.window.id))
            XCTAssertEqual(event.location, CGPoint(x: 300, y: (NSScreen.screens.first?.frame.maxY ?? 0) - 300))
        })
        XCTAssertTrue(access.hasAccess)
        XCTAssertEqual(try access.postIfAllowed(scrollEvent(target), to: target), .posted)
        XCTAssertEqual(postedWindows, [123])
    }

    func testDeniedAccessNeverPostsOrRequestsPermissionFromTheScrollLoop() throws {
        let target = try target()
        var postedEvents = 0
        var windowLookups = 0
        let access = AutomaticScrollAccess(preflight: { false }, resolveWindow: { _ in windowLookups += 1; return target.window }, resolveHitWindow: { _ in target.window }, postEvent: { _ in postedEvents += 1 })
        let event = try scrollEvent(target)
        for _ in 0 ..< 20 {
            XCTAssertFalse(access.hasAccess)
            XCTAssertEqual(access.postIfAllowed(event, to: target), .permissionDenied)
        }
        XCTAssertEqual(postedEvents, 0)
        XCTAssertEqual(windowLookups, 0)
    }

    func testRevokedAccessBlocksFurtherScrollEvents() throws {
        let target = try target()
        var granted = true
        var postedEvents = 0
        let access = AutomaticScrollAccess(preflight: { granted }, resolveWindow: { _ in target.window }, resolveHitWindow: { _ in target.window }, postEvent: { _ in postedEvents += 1 })
        let event = try scrollEvent(target)
        XCTAssertEqual(access.postIfAllowed(event, to: target), .posted)
        granted = false
        for _ in 0 ..< 20 {
            XCTAssertEqual(access.postIfAllowed(event, to: target), .permissionDenied)
        }
        XCTAssertEqual(postedEvents, 1)
    }

    func testMovedClosedOrReusedWindowNeverReceivesAnEvent() throws {
        let target = try target()
        let event = try scrollEvent(target)
        let snapshots: [CapturedWindow?] = [nil,
                                            CapturedWindow(id: 124, processIdentifier: 42, frame: target.window.frame),
                                            CapturedWindow(id: 123, processIdentifier: 43, frame: target.window.frame),
                                            CapturedWindow(id: 123, processIdentifier: 42, frame: target.window.frame.offsetBy(dx: 1, dy: 0))]
        var posted = 0
        for snapshot in snapshots {
            let access = AutomaticScrollAccess(preflight: { true }, resolveWindow: { _ in snapshot }, resolveHitWindow: { _ in target.window }, postEvent: { _ in posted += 1 })
            XCTAssertEqual(access.postIfAllowed(event, to: target), .targetUnavailable)
        }
        XCTAssertEqual(posted, 0)
    }

    func testDisappearingTargetNeverFallsBackToAnotherWindow() throws {
        let target = try target()
        var currentWindow: CapturedWindow? = target.window
        var posted = 0
        let access = AutomaticScrollAccess(preflight: { true }, resolveWindow: { _ in currentWindow }, resolveHitWindow: { _ in target.window }, postEvent: { _ in posted += 1 })
        let event = try scrollEvent(target)
        XCTAssertEqual(access.postIfAllowed(event, to: target), .posted)
        currentWindow = nil
        for _ in 0 ..< 20 {
            XCTAssertEqual(access.postIfAllowed(event, to: target), .targetUnavailable)
        }
        XCTAssertEqual(posted, 1)
    }

    func testEventForAnotherWindowOrHitTestPointIsRejected() throws {
        let target = try target()
        var posted = 0
        let access = AutomaticScrollAccess(preflight: { true }, resolveWindow: { _ in target.window }, resolveHitWindow: { _ in target.window }, postEvent: { _ in posted += 1 })
        let otherWindow = CapturedWindow(id: 124, processIdentifier: 42, frame: target.window.frame)
        let other = try XCTUnwrap(AutomaticScrollTarget(window: otherWindow, selection: CGRect(x: 200, y: 200, width: 200, height: 200)))
        XCTAssertEqual(try access.postIfAllowed(scrollEvent(other), to: target), .invalidEvent)
        let offPoint = try scrollEvent(target)
        offPoint.location.x += 100
        XCTAssertEqual(access.postIfAllowed(offPoint, to: target), .invalidEvent)
        let mouse = try scrollEvent(target)
        mouse.type = .mouseMoved
        XCTAssertEqual(access.postIfAllowed(mouse, to: target), .invalidEvent)
        XCTAssertEqual(posted, 0)
    }

    func testWindowRelativeCoordinatesUsedByTheOldSenderAreRejected() throws {
        let target = try target()
        var posted = 0
        let access = AutomaticScrollAccess(preflight: { true }, resolveWindow: { _ in target.window }, resolveHitWindow: { _ in target.window }, postEvent: { _ in posted += 1 })
        let event = try scrollEvent(target)
        event.location = CGPoint(x: 200, y: (NSScreen.screens.first?.frame.maxY ?? 0) - 200)
        XCTAssertEqual(access.postIfAllowed(event, to: target), .invalidEvent)
        XCTAssertEqual(posted, 0)
    }

    func testOcclusionBlocksSystemWheelInsteadOfScrollingAnotherWindow() throws {
        let target = try target()
        let occludingWindows: [CapturedWindow?] = [
            nil,
            CapturedWindow(id: 124, processIdentifier: 42, frame: target.window.frame),
            CapturedWindow(id: 125, processIdentifier: 43, frame: target.window.frame),
            CapturedWindow(id: 126, processIdentifier: ProcessInfo.processInfo.processIdentifier, frame: target.window.frame),
        ]
        var posted = 0
        for hitWindow in occludingWindows {
            let access = AutomaticScrollAccess(
                preflight: { true }, resolveWindow: { _ in target.window },
                resolveHitWindow: { point in
                    XCTAssertEqual(point, target.globalPoint)
                    return hitWindow
                }, postEvent: { _ in posted += 1 }
            )
            XCTAssertEqual(try access.postIfAllowed(scrollEvent(target), to: target), .targetUnavailable)
        }
        XCTAssertEqual(posted, 0)
    }

    func testOcclusionIsRecheckedBeforeEveryWheelStep() throws {
        let target = try target()
        var hitWindow = target.window
        var posted = 0
        let access = AutomaticScrollAccess(
            preflight: { true }, resolveWindow: { _ in target.window },
            resolveHitWindow: { _ in hitWindow }, postEvent: { _ in posted += 1 }
        )
        let event = try scrollEvent(target)
        XCTAssertEqual(access.postIfAllowed(event, to: target), .posted)
        hitWindow = CapturedWindow(id: 124, processIdentifier: 42, frame: target.window.frame)
        XCTAssertEqual(access.postIfAllowed(event, to: target), .targetUnavailable)
        XCTAssertEqual(posted, 1)
    }

    func testDeliveryHasNoPointerPositionIdleOrButtonPreconditions() throws {
        let target = try target()
        var posted = 0
        let access = AutomaticScrollAccess(preflight: { true }, resolveWindow: { _ in target.window }, resolveHitWindow: { _ in target.window }, postEvent: { _ in posted += 1 })
        // No waiting for mouse idleness between consecutive deliveries. The
        // interface deliberately has no physical-pointer/button parameters.
        for _ in 0 ..< 20 {
            XCTAssertEqual(try access.postIfAllowed(scrollEvent(target), to: target), .posted)
        }
        XCTAssertEqual(posted, 20)
    }

    func testControlPanelActivationDoesNotInvalidateTheTarget() throws {
        let target = try target()
        XCTAssertTrue(target.allowsForeground(processID: 42, controllerProcessID: 99, controlPanelVisible: false))
        XCTAssertTrue(target.allowsForeground(processID: 99, controllerProcessID: 99, controlPanelVisible: true))
        XCTAssertFalse(target.allowsForeground(processID: 99, controllerProcessID: 99, controlPanelVisible: false))
        XCTAssertFalse(target.allowsForeground(processID: 55, controllerProcessID: 99, controlPanelVisible: true))
        XCTAssertFalse(target.allowsForeground(processID: nil, controllerProcessID: 99, controlPanelVisible: true))
    }

    private func target() throws -> AutomaticScrollTarget {
        try XCTUnwrap(AutomaticScrollTarget(window: CapturedWindow(id: 123, processIdentifier: 42, frame: CGRect(x: 100, y: 100, width: 900, height: 800)), selection: CGRect(x: 200, y: 200, width: 200, height: 200)))
    }

    private func scrollEvent(_ target: AutomaticScrollTarget) throws -> CGEvent {
        try XCTUnwrap(AutomaticScrollEvent.make(pixels: 80, target: target, primaryScreenHeight: NSScreen.screens.first?.frame.maxY ?? 0))
    }
}
