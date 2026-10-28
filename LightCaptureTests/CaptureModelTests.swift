import AppKit
import CoreGraphics
import CoreMedia
import CoreVideo
@testable import LightCapture
import ScreenCaptureKit
import XCTest

final class CaptureModelTests: XCTestCase {
    func testThumbnailRespectsPixelBoundsWithoutUpscaling() throws {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 400,
            height: 200,
            bitsPerComponent: 8,
            bytesPerRow: 1600,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try XCTUnwrap(context.makeImage())

        let thumbnail = try XCTUnwrap(image.thumbnail(maxPixelSize: CGSize(width: 100, height: 100)))

        XCTAssertEqual(thumbnail.width, 100)
        XCTAssertEqual(thumbnail.height, 50)
    }

    func testDisplayTransformUsesActualScaleAndHandlesNegativeDisplayOrigin() throws {
        let transform = try DisplayTransform(
            screenFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
            pixelWidth: 3840,
            pixelHeight: 2160
        )
        let globalRect = CGRect(x: -1919.75, y: 1079.5, width: 1, height: 0.5)

        XCTAssertEqual(transform.pixelRect(fromGlobalScreenRect: globalRect), CGRect(x: 0, y: 0, width: 3, height: 1))
    }

    func testDisplayTransformClipsToScreenAndRejectsEmptySelections() throws {
        let transform = try DisplayTransform(
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            pixelWidth: 1707,
            pixelHeight: 960
        )

        XCTAssertNil(transform.pixelRect(fromGlobalScreenRect: .zero))
        XCTAssertNil(transform.pixelRect(fromGlobalScreenRect: CGRect(x: 2000, y: 10, width: 20, height: 20)))
        XCTAssertEqual(
            transform.pixelRect(fromGlobalScreenRect: CGRect(x: -20, y: 870, width: 40, height: 50)),
            CGRect(x: 0, y: 0, width: 24, height: 32)
        )
    }

    func testRetinaCaptureUsesContentPointSizeTimesPixelScale() throws {
        let transform = try DisplayTransform(screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), capturePointSize: CGSize(width: 1440, height: 900), pointPixelScale: 2)
        XCTAssertEqual(transform.pixelWidth, 2880)
        XCTAssertEqual(transform.pixelHeight, 1800)
        XCTAssertEqual(transform.pixelRect(fromGlobalScreenRect: CGRect(x: 100, y: 700, width: 200, height: 100)), CGRect(x: 200, y: 200, width: 400, height: 200))
        XCTAssertThrowsError(try DisplayTransform(screenFrame: .zero, capturePointSize: CGSize(width: 100, height: 100), pointPixelScale: .infinity))
    }

    func testWindowCoordinatesConvertFromQuartzAcrossDisplayArrangements() {
        XCTAssertEqual(DisplayTransform.appKitRect(fromQuartzRect: CGRect(x: 100, y: 50, width: 400, height: 300), primaryScreenHeight: 900), CGRect(x: 100, y: 550, width: 400, height: 300))
        XCTAssertEqual(DisplayTransform.appKitRect(fromQuartzRect: CGRect(x: -1200, y: -800, width: 500, height: 400), primaryScreenHeight: 900), CGRect(x: -1200, y: 1300, width: 500, height: 400))
    }

    func testOverlappingWindowSelectionUsesFrontWindowRatherThanShareableContentOrder() throws {
        let back = CapturedWindow(id: 10, processIdentifier: 1, frame: CGRect(x: 100, y: 100, width: 600, height: 600))
        let front = CapturedWindow(id: 20, processIdentifier: 1, frame: CGRect(x: 122, y: 78, width: 600, height: 600))
        let overlap = CGPoint(x: 300, y: 300)

        let windows = CapturedWindow.frontToBack([back, front], onScreenWindowIDs: [99, 20, 10])

        XCTAssertEqual(try XCTUnwrap(windows.first { $0.frame.contains(overlap) }), front)
        XCTAssertEqual(windows.first { $0.processIdentifier == 1 }, front)
        XCTAssertEqual(windows.first { $0.frame.contains(CGPoint(x: 110, y: 300)) }, back)
    }

    func testWindowOrderingOmitsStaleCandidatesAndDuplicateIDs() {
        let visible = CapturedWindow(id: 20, processIdentifier: 1, frame: CGRect(x: 0, y: 0, width: 600, height: 600))
        let stale = CapturedWindow(id: 10, processIdentifier: 2, frame: visible.frame)

        XCTAssertEqual(CapturedWindow.frontToBack([stale, visible, visible], onScreenWindowIDs: [20, 20, 99]), [visible])
        XCTAssertTrue(CapturedWindow.frontToBack([stale, visible], onScreenWindowIDs: []).isEmpty)
    }

    @MainActor
    func testSelectionOverlayCanReceiveKeyboardInput() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 400, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let screenFrame = CGRect(x: 0, y: 0, width: 100, height: 100)
        let transform = try DisplayTransform(screenFrame: screenFrame, pixelWidth: 100, pixelHeight: 100)
        let overlay = SelectionOverlayWindow(screen: FrozenScreen(displayID: 0, screenFrame: screenFrame, image: image, transform: transform, windows: []), initialMode: .normal)
        defer { overlay.close() }
        XCTAssertTrue(overlay.canBecomeKey)
        let canvas = try XCTUnwrap(overlay.contentView?.subviews.first(where: { $0.acceptsFirstResponder }))
        XCTAssertTrue(overlay.makeFirstResponder(canvas))
        var cancelled = false
        overlay.onCancel = { cancelled = true }
        let escape = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: overlay.windowNumber, context: nil, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53))
        canvas.keyDown(with: escape)
        XCTAssertTrue(cancelled)
    }

    @MainActor
    func testSelectionToolbarMaintainsTextContrastAcrossAppearanceChanges() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 400, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let screenFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let transform = try DisplayTransform(screenFrame: screenFrame, pixelWidth: 100, pixelHeight: 100)
        let lightAppearance = try XCTUnwrap(NSAppearance(named: .aqua))
        var createdOverlay: SelectionOverlayWindow?
        lightAppearance.performAsCurrentDrawingAppearance {
            createdOverlay = SelectionOverlayWindow(screen: FrozenScreen(displayID: 0, screenFrame: screenFrame, image: image, transform: transform, windows: []), initialMode: .normal)
        }
        let overlay = try XCTUnwrap(createdOverlay)
        defer { overlay.close() }
        let root = try XCTUnwrap(overlay.contentView)
        let selectionCanvas = try XCTUnwrap(root.subviews.first { $0.identifier?.rawValue == "capture.selection.canvas" })
        for (type, point) in [(NSEvent.EventType.leftMouseDown, CGPoint(x: 100, y: 120)), (.leftMouseDragged, CGPoint(x: 700, y: 520)), (.leftMouseUp, CGPoint(x: 700, y: 520))] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: selectionCanvas.convert(point, to: nil), modifierFlags: [], timestamp: 0, windowNumber: overlay.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0))
            switch type {
            case .leftMouseDown: selectionCanvas.mouseDown(with: event)
            case .leftMouseDragged: selectionCanvas.mouseDragged(with: event)
            default: selectionCanvas.mouseUp(with: event)
            }
        }
        let toolbar = try XCTUnwrap(root.subviews.compactMap { $0 as? NSStackView }.first { $0.identifier?.rawValue == "capture.annotation.toolbar" })
        let badge = try XCTUnwrap(root.subviews.compactMap { $0 as? NSStackView }.first { $0.identifier?.rawValue == "capture.selection.size" })
        let status = try XCTUnwrap(badge.arrangedSubviews.compactMap { $0 as? NSTextField }.first)

        for name in [NSAppearance.Name.aqua, .darkAqua, .aqua] {
            overlay.appearance = try XCTUnwrap(NSAppearance(named: name))
            root.layoutSubtreeIfNeeded()
            root.displayIfNeeded()
            let background = try XCTUnwrap(NSColor(cgColor: XCTUnwrap(toolbar.layer?.backgroundColor))?.usingColorSpace(.sRGB))
            var resolvedText: NSColor?
            toolbar.effectiveAppearance.performAsCurrentDrawingAppearance {
                resolvedText = status.textColor?.usingColorSpace(.sRGB)
            }
            let text = try XCTUnwrap(resolvedText)
            // Check both extremes of the captured image beneath the translucent toolbar.
            for underlying: CGFloat in [0, 1] {
                let alpha = background.alphaComponent
                let backgroundLuminance = relativeLuminance([
                    background.redComponent * alpha + underlying * (1 - alpha),
                    background.greenComponent * alpha + underlying * (1 - alpha),
                    background.blueComponent * alpha + underlying * (1 - alpha),
                ])
                let textLuminance = relativeLuminance([text.redComponent, text.greenComponent, text.blueComponent])
                let contrast = (max(backgroundLuminance, textLuminance) + 0.05) / (min(backgroundLuminance, textLuminance) + 0.05)
                XCTAssertGreaterThanOrEqual(contrast, 4.5, "Unreadable toolbar in \(name.rawValue), underlying brightness \(underlying)")
            }
        }
    }

    private func relativeLuminance(_ components: [CGFloat]) -> CGFloat {
        let linear = components.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
    }

    func testCancelledGenerationCannotFinishANewerSession() async {
        let coordinator = await MainActor.run { CaptureSessionCoordinator() }
        let first = await coordinator.begin(mode: .normal, targetProcessID: 1)
        XCTAssertNotNil(first)
        guard let first else { return }
        let cancelled = await coordinator.cancel(sessionID: first.id, generation: first.generation)
        XCTAssertTrue(cancelled)

        let second = await coordinator.begin(mode: .long, targetProcessID: 2)
        XCTAssertNotNil(second)
        guard let second else { return }
        let staleFinish = await coordinator.finish(sessionID: first.id, generation: first.generation)
        let secondIsCurrent = await coordinator.isCurrent(sessionID: second.id, generation: second.generation)
        XCTAssertFalse(staleFinish)
        XCTAssertTrue(secondIsCurrent)
    }

    func testActivityClockExcludesPausesAndReachesThe180SecondLimit() {
        var clock = CaptureActivityClock()
        XCTAssertEqual(clock.elapsed(at: 100), 0)
        clock.start(at: 100)
        clock.pause(at: 140)
        clock.pause(at: 150)
        XCTAssertEqual(clock.elapsed(at: 1000), 40)
        clock.resume(at: 1140)
        clock.resume(at: 1200)
        XCTAssertEqual(clock.elapsed(at: 1279), 179)
        XCTAssertEqual(clock.elapsed(at: 1280), 180)
    }

    func testStationaryFramesAllowNoProgressChecksWithoutRacingTheWatchdog() {
        var timing = AutomaticScrollTiming()
        timing.sentStep(at: 100)
        XCTAssertFalse(timing.canConsumeFrame(at: 100.49))
        XCTAssertTrue(timing.canConsumeFrame(at: 100.5))
        XCTAssertFalse(timing.canCheckNoProgress(at: 101.99))
        // The timer may run before the next idle-frame callback at 102 seconds.
        XCTAssertFalse(timing.frameDeliveryTimedOut(at: 102))
        for time in stride(from: 102.0, through: 110.0, by: 0.1) {
            timing.receivedFrame(at: time)
            XCTAssertTrue(timing.canCheckNoProgress(at: time))
            XCTAssertFalse(timing.frameDeliveryTimedOut(at: time))
        }
    }

    func testAutomaticWatchdogStillStopsAStreamThatNeverDeliversOrStalls() {
        var timing = AutomaticScrollTiming()
        XCTAssertFalse(timing.frameDeliveryTimedOut(at: 1000))
        timing.sentStep(at: 100)
        XCTAssertFalse(timing.frameDeliveryTimedOut(at: 104.99))
        XCTAssertTrue(timing.frameDeliveryTimedOut(at: 105))
        timing.receivedFrame(at: 106)
        XCTAssertFalse(timing.frameDeliveryTimedOut(at: 110.99))
        XCTAssertTrue(timing.frameDeliveryTimedOut(at: 111))
        timing.sentStep(at: 112)
        XCTAssertFalse(timing.canConsumeFrame(at: 112.1))
        XCTAssertFalse(timing.canCheckNoProgress(at: 113.99))
        XCTAssertFalse(timing.frameDeliveryTimedOut(at: 116.99))
        XCTAssertTrue(timing.frameDeliveryTimedOut(at: 117))
    }

    @MainActor
    func testTargetedScrollKeepsGlobalCoordinatesWindowRoutingAndAnIsolatedEventSource() throws {
        let window = CapturedWindow(id: 123, processIdentifier: 42, frame: CGRect(x: 575, y: 0, width: 1200, height: 900))
        let target = try XCTUnwrap(AutomaticScrollTarget(window: window, selection: CGRect(x: 700, y: 200, width: 400, height: 400)))
        let event = try XCTUnwrap(AutomaticScrollEvent.make(pixels: 80, target: target, primaryScreenHeight: NSScreen.screens.first?.frame.maxY ?? 0))
        let decoded = try XCTUnwrap(NSEvent(cgEvent: event))
        XCTAssertEqual(event.type, .scrollWheel)
        XCTAssertEqual(event.getIntegerValueField(.eventSourceUserData), 123)
        XCTAssertEqual(event.location, CGPoint(x: 900, y: (NSScreen.screens.first?.frame.maxY ?? 0) - 400))
        XCTAssertEqual(decoded.scrollingDeltaY, -80)
        XCTAssertTrue(decoded.hasPreciseScrollingDeltas)
        XCTAssertEqual(decoded.scrollingDeltaX, 0)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), -80)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventDeltaAxis2), 0)
        XCTAssertEqual(event.flags, [])
        let source = try XCTUnwrap(CGEventSource(event: event))
        XCTAssertEqual(source.localEventsSuppressionInterval, 0)
        XCTAssertNotEqual(source.sourceStateID, .combinedSessionState)
        XCTAssertNotEqual(source.sourceStateID, .hidSystemState)
    }

    func testAutomaticWheelStepPreservesOverlapWithoutLineAccelerationAssumptions() throws {
        for height: CGFloat in [20, 100, 300, 645, 900, 2000] {
            let pixels = try XCTUnwrap(AutomaticScrollEvent.stepPixels(forViewportHeight: height))
            XCTAssertGreaterThan(pixels, 0)
            XCTAssertLessThanOrEqual(CGFloat(pixels), height * 0.35)
            XCTAssertLessThanOrEqual(pixels, 240)
        }
        XCTAssertEqual(AutomaticScrollEvent.stepPixels(forViewportHeight: 645), 225)
        XCTAssertNil(AutomaticScrollEvent.stepPixels(forViewportHeight: 0))
        XCTAssertNil(AutomaticScrollEvent.stepPixels(forViewportHeight: -1))
        XCTAssertNil(AutomaticScrollEvent.stepPixels(forViewportHeight: .infinity))
        XCTAssertNil(AutomaticScrollEvent.stepPixels(forViewportHeight: .nan))
    }

    @MainActor
    func testTargetedScrollUsesGlobalQuartzHitTestAcrossScreensAndWindowOrigins() throws {
        let screenHeight: CGFloat = 1080
        for (origin, expectedPoint) in [(CGPoint(x: 575, y: 80), CGPoint(x: 925, y: 600)),
                                        (CGPoint(x: -1600, y: -300), CGPoint(x: -1250, y: 980)),
                                        (CGPoint(x: 0, y: 1400), CGPoint(x: 350, y: -720))]
        {
            let window = CapturedWindow(id: 123, processIdentifier: 42, frame: CGRect(origin: origin, size: CGSize(width: 1200, height: 900)))
            let target = try XCTUnwrap(AutomaticScrollTarget(window: window, selection: CGRect(x: origin.x + 300, y: origin.y + 350, width: 100, height: 100)))
            let event = try XCTUnwrap(AutomaticScrollEvent.make(pixels: 80, target: target, primaryScreenHeight: screenHeight))
            XCTAssertEqual(event.location, expectedPoint)
            XCTAssertEqual(event.getIntegerValueField(.eventSourceUserData), 123)
        }
    }

    func testAutomaticTargetRejectsInvalidOrUnrelatedSelections() {
        let window = CapturedWindow(id: 123, processIdentifier: 42, frame: CGRect(x: 100, y: 100, width: 500, height: 500))
        for selection in [CGRect.zero, CGRect(x: 700, y: 200, width: 50, height: 50), CGRect(x: CGFloat.infinity, y: 200, width: 50, height: 50)] {
            XCTAssertNil(AutomaticScrollTarget(window: window, selection: selection))
        }
        XCTAssertNil(AutomaticScrollTarget(window: CapturedWindow(id: 0, processIdentifier: 42, frame: window.frame), selection: window.frame))
        XCTAssertNil(AutomaticScrollTarget(window: CapturedWindow(id: 123, processIdentifier: 0, frame: window.frame), selection: window.frame))
    }

    func testAreaTargetUsesTheFrontWindowAtTheSelectionCenter() throws {
        let narrowFront = CapturedWindow(id: 1, processIdentifier: 11, frame: CGRect(x: 0, y: 0, width: 120, height: 900))
        let front = CapturedWindow(id: 2, processIdentifier: 22, frame: CGRect(x: 122, y: 0, width: 700, height: 900))
        let back = CapturedWindow(id: 3, processIdentifier: 33, frame: CGRect(x: 0, y: 0, width: 1200, height: 900))
        let selection = CGRect(x: 100, y: 200, width: 600, height: 400)
        XCTAssertEqual(try XCTUnwrap(CapturedWindow.target(for: selection, in: [narrowFront, front, back])), front)
        XCTAssertNil(CapturedWindow.target(for: CGRect(x: 2000, y: 0, width: 50, height: 50), in: [front, back]))
    }

    func testPendingDeliveryDoesNotCountAsNoProgressAndSendingStillWaitsForSettling() {
        var timing = AutomaticScrollTiming()
        timing.requestStep()
        XCTAssertTrue(timing.isStepPending)
        XCTAssertFalse(timing.canConsumeFrame(at: 100))
        XCTAssertFalse(timing.canCheckNoProgress(at: 100))
        timing.sentStep(at: 100)
        timing.requestStep()
        for time in stride(from: 102.0, through: 120.0, by: 0.1) {
            timing.receivedFrame(at: time)
            XCTAssertFalse(timing.canConsumeFrame(at: time))
            XCTAssertFalse(timing.canCheckNoProgress(at: time))
            XCTAssertFalse(timing.frameDeliveryTimedOut(at: time))
        }
        timing.sentStep(at: 121)
        XCTAssertFalse(timing.isStepPending)
        XCTAssertFalse(timing.canConsumeFrame(at: 121.49))
        XCTAssertTrue(timing.canConsumeFrame(at: 121.5))
        XCTAssertFalse(timing.canCheckNoProgress(at: 122.99))
        XCTAssertTrue(timing.canCheckNoProgress(at: 123))
    }

    func testStartupWatchdogBoundsDynamicFirstFrameAndGivesRetriesANewActiveGracePeriod() {
        var clock = CaptureActivityClock()
        var watchdog = CaptureStartupWatchdog()
        clock.start(at: 100)
        watchdog.beginAttempt(activeElapsed: clock.elapsed(at: 100))
        XCTAssertFalse(watchdog.shouldPause(confirmedHeight: 0, activeElapsed: clock.elapsed(at: 104.99)))
        XCTAssertTrue(watchdog.shouldPause(confirmedHeight: 0, activeElapsed: clock.elapsed(at: 105)))
        XCTAssertFalse(watchdog.shouldPause(confirmedHeight: 1000, activeElapsed: clock.elapsed(at: 150)))
        clock.pause(at: 105)
        clock.resume(at: 1000)
        watchdog.beginAttempt(activeElapsed: clock.elapsed(at: 1000))
        XCTAssertFalse(watchdog.shouldPause(confirmedHeight: 0, activeElapsed: clock.elapsed(at: 1004.99)))
        XCTAssertTrue(watchdog.shouldPause(confirmedHeight: 0, activeElapsed: clock.elapsed(at: 1005)))
    }

    @MainActor
    func testLongCapturePanelDisablesPreviewWithoutReliablePixelsButAllowsRetry() throws {
        let panel = LongCaptureControlPanel(
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            selectedGlobalRect: CGRect(x: 100, y: 400, width: 500, height: 500)
        )
        defer { panel.close() }
        func buttons(in view: NSView) -> [NSButton] {
            (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { buttons(in: $0) }
        }
        let controls = try buttons(in: XCTUnwrap(panel.contentView))
        let preview = try XCTUnwrap(controls.first { $0.identifier?.rawValue == "capture.long.preview" })
        let retry = try XCTUnwrap(controls.first { $0.identifier?.rawValue == "capture.long.resume" })
        panel.showRunning(mode: .automatic, height: 0, elapsed: 0)
        XCTAssertFalse(preview.isEnabled)
        panel.showPaused(reason: "首屏持续变化", height: 0, canResume: true, canSwitchToManual: true)
        XCTAssertFalse(preview.isEnabled)
        XCTAssertFalse(retry.isHidden)
        panel.showRunning(mode: .manual, height: 1000, elapsed: 6)
        XCTAssertTrue(preview.isEnabled)
    }

    @MainActor
    func testAutomaticScrollMatchingWaitKeepsPauseAndPreviewActionsAvailable() throws {
        let panel = LongCaptureControlPanel(
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            selectedGlobalRect: CGRect(x: 100, y: 400, width: 500, height: 500)
        )
        defer { panel.close() }
        func buttons(in view: NSView) -> [NSButton] {
            (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { buttons(in: $0) }
        }
        let controls = try buttons(in: XCTUnwrap(panel.contentView))
        let pause = try XCTUnwrap(controls.first { $0.identifier?.rawValue == "capture.long.pause" })
        let preview = try XCTUnwrap(controls.first { $0.identifier?.rawValue == "capture.long.preview" })
        var didPause = false
        var didFinish = false
        panel.onPause = { didPause = true }
        panel.onFinish = { didFinish = true }
        panel.showRunning(mode: .automatic, height: 1000, elapsed: 6)
        panel.contentView?.layoutSubtreeIfNeeded()
        let pauseFrame = pause.frame
        let previewFrame = preview.frame
        panel.showWaitingForStableFrame()
        panel.contentView?.layoutSubtreeIfNeeded()
        XCTAssertFalse(pause.isHidden)
        XCTAssertFalse(preview.isHidden)
        XCTAssertTrue(pause.isEnabled)
        XCTAssertTrue(preview.isEnabled)
        XCTAssertEqual(pause.frame, pauseFrame)
        XCTAssertEqual(preview.frame, previewFrame)
        pause.performClick(nil)
        preview.performClick(nil)
        XCTAssertTrue(didPause)
        XCTAssertTrue(didFinish)
    }

    func testImageLimitsEnforceIndependentPixelAndHeightCapsWithoutOverflow() {
        XCTAssertTrue(CaptureImageLimits.contains(width: 1200, height: 50000))
        XCTAssertFalse(CaptureImageLimits.contains(width: 1201, height: 50000))
        XCTAssertFalse(CaptureImageLimits.contains(width: 1, height: 50001))
        XCTAssertFalse(CaptureImageLimits.contains(width: Int.max, height: Int.max))
        XCTAssertFalse(CaptureImageLimits.contains(width: 0, height: 1))
        XCTAssertFalse(CaptureImageLimits.contains(width: 1, height: 0))
    }

    @MainActor
    func testStreamRelayReusesConfirmedPixelsForIdleFramesAndIgnoresBlankFrames() async throws {
        var frames: [CGImage] = []
        let relay = ScreenCaptureStreamRelay(onFrame: { frames.append($0) }, onFailure: { _ in XCTFail("不应报告流错误") })
        try relay.receive(makeSampleBuffer(status: .blank))
        await Task.yield()
        XCTAssertTrue(frames.isEmpty)
        try relay.receive(makeSampleBuffer(status: .complete))
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        XCTAssertEqual(frames.count, 1)
        try relay.receive(makeSampleBuffer(status: .idle))
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        XCTAssertEqual(frames.count, 2)
        if frames.count == 2 { XCTAssertTrue(frames[0] === frames[1]) }
        relay.disable()
    }

    @MainActor
    func testDisabledStreamRelayDropsAFrameAlreadyQueuedForDelivery() async throws {
        var delivered = false
        let relay = ScreenCaptureStreamRelay(onFrame: { _ in delivered = true }, onFailure: { _ in XCTFail("取消后不应报告错误") })
        try relay.receive(makeSampleBuffer(status: .complete))
        relay.disable()
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        XCTAssertFalse(delivered)
    }

    private func makeSampleBuffer(status: SCFrameStatus) throws -> CMSampleBuffer {
        var pixelBuffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 16, 12, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixelBuffer), kCVReturnSuccess)
        let pixels = try XCTUnwrap(pixelBuffer)
        CVPixelBufferLockBaseAddress(pixels, [])
        if let base = CVPixelBufferGetBaseAddress(pixels) {
            memset(base, 255, CVPixelBufferGetBytesPerRow(pixels) * CVPixelBufferGetHeight(pixels))
        }
        CVPixelBufferUnlockBaseAddress(pixels, [])
        var format: CMVideoFormatDescription?
        XCTAssertEqual(CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixels, formatDescriptionOut: &format), noErr)
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        var buffer: CMSampleBuffer?
        XCTAssertEqual(try CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixels, formatDescription: XCTUnwrap(format), sampleTiming: &timing, sampleBufferOut: &buffer), noErr)
        let sample = try XCTUnwrap(buffer)
        let attachments = try XCTUnwrap(CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) as? [NSMutableDictionary])
        try XCTUnwrap(attachments.first)[SCStreamFrameInfo.status.rawValue] = status.rawValue
        return sample
    }

    func testEnvironmentMonitorReportsSleepLockDisplaySleepAndConfigurationChanges() async {
        let workspaceCenter = NotificationCenter()
        let applicationCenter = NotificationCenter()
        let expectedReasons = [
            L10n.interruptionSleep,
            L10n.interruptionDisplaySleep,
            L10n.interruptionSession,
            L10n.interruptionDisplayChange,
        ]
        let receivedMessages = await MainActor.run { InterruptionMessageRecorder() }
        let expectation = expectation(description: "每种系统中断均取消当前截图")
        expectation.expectedFulfillmentCount = expectedReasons.count
        let monitor = await MainActor.run {
            CaptureEnvironmentMonitor(
                workspaceNotificationCenter: workspaceCenter,
                applicationNotificationCenter: applicationCenter
            ) { reason in
                receivedMessages.messages.append(reason)
                expectation.fulfill()
            }
        }

        await MainActor.run {
            workspaceCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
            workspaceCenter.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
            workspaceCenter.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
            applicationCenter.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        }
        await fulfillment(of: [expectation], timeout: 2)
        let messages = await MainActor.run {
            monitor.stop()
            return receivedMessages.messages
        }

        XCTAssertEqual(Set(messages), Set(expectedReasons))
    }

    func testEnvironmentChangeCancelsAnActiveCaptureSessionOnce() async {
        let flow = await MainActor.run { CaptureFlowController() }
        let session = await flow.sessions.begin(mode: .long, targetProcessID: 42)
        XCTAssertNotNil(session)

        let firstCancellation = await flow.cancelForEnvironmentChange()
        let sessionAfterCancellation = await flow.sessions.activeSession
        let repeatedCancellation = await flow.cancelForEnvironmentChange()

        XCTAssertTrue(firstCancellation)
        XCTAssertNil(sessionAfterCancellation)
        XCTAssertFalse(repeatedCancellation)
    }

    func testScreenPermissionRevocationCancelsSessionAndRequestsHelpOnce() async {
        let helpRequests = await MainActor.run { InterruptionHelpRequestRecorder() }
        let flow = await MainActor.run {
            let flow = CaptureFlowController()
            flow.onScreenPermissionRevocation = { helpRequests.count += 1 }
            return flow
        }
        let session = await flow.sessions.begin(mode: .long, targetProcessID: 42)
        XCTAssertNotNil(session)

        let firstCancellation = await flow.cancelForScreenPermissionRevocation()
        let sessionAfterCancellation = await flow.sessions.activeSession
        let repeatedCancellation = await flow.cancelForScreenPermissionRevocation()
        let requestCount = await MainActor.run { helpRequests.count }

        XCTAssertTrue(firstCancellation)
        XCTAssertNil(sessionAfterCancellation)
        XCTAssertFalse(repeatedCancellation)
        XCTAssertEqual(requestCount, 1)
    }
}

@MainActor
private final class InterruptionMessageRecorder {
    var messages: [String] = []
}

@MainActor
private final class InterruptionHelpRequestRecorder {
    var count = 0
}
