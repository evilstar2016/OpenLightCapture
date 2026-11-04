import AppKit
import CoreMedia
import ImageIO
@testable import LightCapture
import ScreenCaptureKit
import UniformTypeIdentifiers
import XCTest

final class GIFCaptureTests: XCTestCase {
    func testStreamedGIFKeepsIndependentPalettesTimingAndLoopMetadata() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try GIFFrameStore(width: 16, height: 12, options: RecordingOptions(), root: root)
        let cancellation = RecordingCancellation()
        _ = try await store.append(image(red: 1), at: 10, cancellation: cancellation)
        _ = try await store.append(image(green: 1), at: 10.2, cancellation: cancellation)
        _ = try await store.append(image(blue: 1), at: 15.2, cancellation: cancellation)
        let recording = try await store.seal(at: 15.4)
        let result = try GIFEncoder.encode(recording, cancellation: cancellation)
        XCTAssertEqual(result.frameCount, 3)
        XCTAssertEqual(result.duration, 5.4, accuracy: 0.01)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(result.url as CFURL, nil))
        let originals = try [image(red: 1), image(green: 1), image(blue: 1)]
        for (index, original) in originals.enumerated() {
            let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, index, nil))
            let pixels = try XCTUnwrap(RGBAFrame(image: decoded))
            // GIF quantization and color conversion are native behavior. Compare with
            // an independently encoded native still, rather than claiming PNG fidelity.
            let nativeData = NSMutableData()
            let destination = try XCTUnwrap(CGImageDestinationCreateWithData(nativeData, UTType.gif.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, original, nil)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
            let nativeSource = try XCTUnwrap(CGImageSourceCreateWithData(nativeData, nil))
            let native = try XCTUnwrap(CGImageSourceCreateImageAtIndex(nativeSource, 0, nil))
            XCTAssertEqual(pixels.bytes, RGBAFrame(image: native)?.bytes, "Each frame must retain its own native palette")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: recording.directory.appending(path: "result.gif.part").path))
        await store.cleanup()
    }

    func testStaticRecordingRetainsItsRealDurationAndShortTailHasMinimumDelay() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try GIFFrameStore(width: 16, height: 12, options: RecordingOptions(), root: root)
        let cancellation = RecordingCancellation()
        _ = try await store.append(image(red: 1), at: 100, cancellation: cancellation)
        let recording = try await store.seal(at: 107)
        XCTAssertEqual(recording.delays, [7])
        let result = try GIFEncoder.encode(recording, cancellation: cancellation)
        XCTAssertEqual(result.duration, 7, accuracy: 0.01)
        let short = GIFRecording(directory: recording.directory, width: 16, height: 12, frames: recording.frames, duration: 0.01)
        XCTAssertEqual(short.delays, [0.1])
        await store.cleanup()
    }

    func testSamplerRejectsOutOfOrderFastAndBeyondLimitFrames() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var options = RecordingOptions()
        options.maxDuration = 1
        let store = try GIFFrameStore(width: 16, height: 12, options: options, root: root)
        let cancellation = RecordingCancellation()
        let frame = try image(red: 1)
        let first = try await store.append(frame, at: 5, cancellation: cancellation)
        let backwards = try await store.append(frame, at: 4, cancellation: cancellation)
        let tooFast = try await store.append(frame, at: 5.05, cancellation: cancellation)
        let next = try await store.append(frame, at: 5.1, cancellation: cancellation)
        let tooLate = try await store.append(frame, at: 6, cancellation: cancellation)
        XCTAssertTrue(first)
        XCTAssertFalse(backwards)
        XCTAssertFalse(tooFast)
        XCTAssertTrue(next)
        XCTAssertFalse(tooLate)
        let recording = try await store.seal(at: 6.5)
        XCTAssertEqual(recording.frames.count, 2)
        XCTAssertEqual(recording.duration, 1)
        await store.cleanup()
    }

    func testCancelledEncoderDoesNotCreateAResult() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try GIFFrameStore(width: 16, height: 12, options: RecordingOptions(), root: root)
        let cancellation = RecordingCancellation()
        _ = try await store.append(image(red: 1), at: 1, cancellation: cancellation)
        let recording = try await store.seal(at: 2)
        cancellation.cancel()
        XCTAssertThrowsError(try GIFEncoder.encode(recording, cancellation: cancellation)) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: recording.directory.appending(path: "result.gif").path))
        await store.cleanup()
    }

    func testCorruptRawFrameCannotBeEncodedAndPartialResultIsRemoved() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try GIFFrameStore(width: 16, height: 12, options: RecordingOptions(), root: root)
        let cancellation = RecordingCancellation()
        _ = try await store.append(image(red: 1), at: 1, cancellation: cancellation)
        let recording = try await store.seal(at: 2)
        try Data([0]).write(to: recording.directory.appending(path: recording.frames[0].filename))
        XCTAssertThrowsError(try GIFEncoder.encode(recording, cancellation: cancellation))
        XCTAssertFalse(FileManager.default.fileExists(atPath: recording.directory.appending(path: "result.gif.part").path))
        await store.cleanup()
    }

    func testGIFFrameParserRejectsTruncatedOrUnsupportedNativeOutput() {
        for bytes: [UInt8] in [[], Array("GIF89a".utf8), Array(repeating: 0, count: 40), Array("GIF89a".utf8) + Array(repeating: 0, count: 8)] {
            XCTAssertThrowsError(try GIFEncoder.frameBlock(from: Data(bytes), width: 16, height: 12))
        }
    }

    func testOutputDimensionsPreserveAspectRatioWithoutUpscaling() {
        let options = RecordingOptions()
        XCTAssertEqual(options.outputSize(width: 3840, height: 2160), CGSize(width: 1280, height: 720))
        XCTAssertEqual(options.outputSize(width: 600, height: 400), CGSize(width: 600, height: 400))
        XCTAssertEqual(options.outputSize(width: 1, height: 2000), CGSize(width: 1, height: 1280))
        XCTAssertEqual(options.outputSize(width: 0, height: 400), .zero)
    }

    func testWorkspaceRejectsSymbolicLinksAndOnlyCleansOwnedDirectories() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let outside = root.appending(path: "outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let link = root.appending(path: "link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        XCTAssertThrowsError(try GIFFrameStore(width: 16, height: 12, options: RecordingOptions(), root: link))
        let owned = root.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: owned, withIntermediateDirectories: true)
        GIFFrameStore.cleanupAbandoned(root: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: owned.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    @MainActor
    func testGIFClipboardPublishesOneRealAnimationAndFileAndProtectsItsLease() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try GIFFrameStore(width: 16, height: 12, options: RecordingOptions(), root: root.appending(path: "working"))
        let cancellation = RecordingCancellation()
        _ = try await store.append(image(red: 1), at: 1, cancellation: cancellation)
        _ = try await store.append(image(blue: 1), at: 1.2, cancellation: cancellation)
        let recording = try await store.seal(at: 2)
        let result = try GIFEncoder.encode(recording, cancellation: cancellation)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let assets = root.appending(path: "assets")
        let delivery = OutputDeliveryService(assetStore: AssetStore(rootURL: assets), pasteboard: pasteboard)
        let outcome = await delivery.deliverGIF(result, startedAt: Date(), save: false, parentWindow: nil, isCurrent: { true })
        guard case .completed = outcome else { return XCTFail("GIF copy failed") }
        XCTAssertEqual(pasteboard.pasteboardItems?.count, 1)
        XCTAssertNil(pasteboard.data(forType: AssetStore.pngPasteboardType))
        let data = try XCTUnwrap(pasteboard.data(forType: AssetStore.gifPasteboardType))
        let url = try XCTUnwrap(URL(string: XCTUnwrap(pasteboard.string(forType: .fileURL))))
        XCTAssertEqual(url.pathExtension, "gif")
        XCTAssertEqual(try Data(contentsOf: url), data)
        let copied = try GIFEncoder.inspect(url: url)
        XCTAssertEqual(copied.frameCount, 2)
        let restarted = AssetStore(rootURL: assets)
        restarted.startMaintenance(pasteboard: pasteboard)
        restarted.reapRetiredAssets(now: Date().addingTimeInterval(86400))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        restarted.stopMaintenance()
        await store.cleanup()
    }

    @MainActor
    func testInvalidatedGIFOutputDoesNotTouchClipboard() async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("keep", forType: .string)
        let changeCount = pasteboard.changeCount
        let root = temporaryRoot()
        let result = GIFResult(url: root, width: 16, height: 12, frameCount: 1, duration: 1, byteCount: 10)
        let service = OutputDeliveryService(assetStore: AssetStore(rootURL: root), pasteboard: pasteboard)
        let outcome = await service.deliverGIF(result, startedAt: Date(), save: false, parentWindow: nil, isCurrent: { false })
        guard case .cancelled = outcome else { return XCTFail("Stale output must be cancelled") }
        XCTAssertEqual(pasteboard.changeCount, changeCount)
        XCTAssertEqual(pasteboard.string(forType: .string), "keep")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    @MainActor
    func testCancellingGIFSaveDialogPreservesResultAndClipboard() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let result = try await makeResult(in: root.appending(path: "working"))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("keep", forType: .string)
        let change = pasteboard.changeCount
        let assets = root.appending(path: "assets")
        let service = OutputDeliveryService(assetStore: AssetStore(rootURL: assets), pasteboard: pasteboard, gifSaveDestination: { nil })
        let outcome = await service.deliverGIF(result, startedAt: Date(), save: true, parentWindow: nil, isCurrent: { true })
        guard case .cancelled = outcome else { return XCTFail("Save dialog cancellation must not publish") }
        XCTAssertEqual(pasteboard.changeCount, change)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: assets.path))
    }

    @MainActor
    func testSavedGIFSurvivesCopyFailureAndRetryDoesNotSaveAgain() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let result = try await makeResult(in: root.appending(path: "working"))
        let destination = root.appending(path: "saved.gif")
        let assets = root.appending(path: "assets")
        try Data([0]).write(to: assets)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("keep", forType: .string)
        var selections = 0
        let service = OutputDeliveryService(assetStore: AssetStore(rootURL: assets), pasteboard: pasteboard, gifSaveDestination: {
            selections += 1
            return destination
        })
        let failed = await service.deliverGIF(result, startedAt: Date(), save: true, parentWindow: nil, isCurrent: { true })
        guard case let .failed(savedURL, _) = failed else { return XCTFail("Expected saved-file/copy partial success") }
        XCTAssertEqual(savedURL, destination)
        XCTAssertEqual(try Data(contentsOf: destination), try Data(contentsOf: result.url))
        XCTAssertEqual(pasteboard.string(forType: .string), "keep")
        try FileManager.default.removeItem(at: assets)
        let completed = await service.deliverGIF(result, startedAt: Date(), save: true, previouslySavedURL: savedURL, parentWindow: nil, isCurrent: { true })
        guard case .completed = completed else { return XCTFail("Retry should publish the existing result") }
        XCTAssertEqual(selections, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    }

    @MainActor
    func testGIFControlsFitBothLanguagesAndProduceSyntheticPreviews() async throws {
        let original = LocalizationContext.current
        defer { LocalizationRuntime.shared.install(original) }
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let result = try await makeResult(in: root.appending(path: "working"))
        let snapshots = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "build/gif-previews")
        try FileManager.default.createDirectory(at: snapshots, withIntermediateDirectories: true)
        for language in ["en", "zh-Hans"] {
            LocalizationRuntime.shared.install(LocalizationContext(languageIdentifier: language))
            let panel = RecordingControlPanel(screenFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
                                              selection: CGRect(x: 200, y: 300, width: 300, height: 200),
                                              outputSize: CGSize(width: 600, height: 400), showsCursor: true)
            defer { panel.dismiss() }
            let content = try XCTUnwrap(panel.contentView)
            content.layoutSubtreeIfNeeded()
            try savePreview(content, at: snapshots.appending(path: "ready-\(language).png"))
            for button in descendants(content).compactMap({ $0 as? NSButton }) where !button.isHidden {
                XCTAssertTrue(content.bounds.contains(content.convert(button.bounds, from: button)), button.title)
                XCTAssertGreaterThanOrEqual(button.frame.width + 1, button.intrinsicContentSize.width, button.title)
            }
            panel.showRecording(12)
            content.layoutSubtreeIfNeeded()
            try savePreview(content, at: snapshots.appending(path: "recording-\(language).png"))
            let preview = RecordingPreviewWindowController()
            defer { preview.dismiss() }
            preview.show(source: .gif(result), text: L10n.gifLimitReached, canPublish: true)
            preview.window.setContentSize(CGSize(width: 540, height: 460))
            let view = try XCTUnwrap(preview.window.contentView)
            view.layoutSubtreeIfNeeded()
            await Task.yield()
            view.layoutSubtreeIfNeeded()
            for button in descendants(view).compactMap({ $0 as? NSButton }) where !button.isHidden {
                XCTAssertTrue(view.bounds.contains(view.convert(button.bounds, from: button)), button.title)
                XCTAssertGreaterThanOrEqual(button.frame.width + 1, button.intrinsicContentSize.width, button.title)
            }
            try savePreview(view, at: snapshots.appending(path: "preview-\(language).png"))
        }
    }

    @MainActor
    func testGIFModeChangeIsRestrictedToSelectionAndCancellationKeepsSessionOccupied() throws {
        let sessions = CaptureSessionCoordinator()
        let session = try XCTUnwrap(sessions.begin(mode: .normal, targetProcessID: nil))
        XCTAssertFalse(sessions.changeMode(sessionID: session.id, generation: session.generation, to: .gif))
        _ = sessions.transition(sessionID: session.id, generation: session.generation, to: .selecting)
        XCTAssertTrue(sessions.changeMode(sessionID: session.id, generation: session.generation, to: .gif))
        _ = sessions.transition(sessionID: session.id, generation: session.generation, to: .cancelling)
        XCTAssertEqual(sessions.begin(mode: .normal, targetProcessID: nil)?.id, session.id)
        XCTAssertFalse(sessions.isCurrent(sessionID: session.id, generation: session.generation))
        sessions.completeCancellation(sessionID: session.id, generation: session.generation)
        XCTAssertNil(sessions.activeSession)
    }

    @MainActor
    func testCancellationWaitsForLateStreamStartAndRejectsLateFrames() async throws {
        let stream = FakeGIFStream()
        stream.holdStart = true
        let (controller, flow, root) = try makeController(stream: stream)
        defer { try? FileManager.default.removeItem(at: root) }
        controller.start(showsCursor: true)
        try await waitUntil { stream.handler != nil }
        let lateHandler = try XCTUnwrap(stream.handler)
        controller.cancel()
        XCTAssertEqual(flow.sessions.activeSession?.state, .cancelling)
        await Task.yield()
        XCTAssertTrue(NSApp.windows.contains { $0 is RecordingControlPanel && $0.isVisible }, "Keep a finishing indicator until the in-flight start releases resources")
        stream.releaseStart()
        try await waitUntil { flow.sessions.activeSession == nil }
        try await lateHandler(CaptureFrameEvent(image: image(red: 1), status: .complete, hostTime: CMClockGetTime(CMClockGetHostTimeClock()).seconds))
        XCTAssertNil(flow.sessions.activeSession)
        XCTAssertGreaterThan(stream.stops, 0)
    }

    @MainActor
    func testAutoStartSkipsReadyPanelCountdownButtonsAndRecordsImmediately() async throws {
        let stream = FakeGIFStream()
        let (controller, flow, root) = try makeController(stream: stream, startsImmediately: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let dimmer = try XCTUnwrap(NSApp.windows.compactMap { $0 as? RecordingRegionDimmer }.first, "倒计时一开始就变暗选区外区域")
        XCTAssertTrue(dimmer.isVisible)
        XCTAssertFalse(dimmer.hidesOnDeactivate, "切换到目标应用后遮罩保持可见")
        XCTAssertTrue(dimmer.collectionBehavior.contains(.canJoinAllSpaces), "跨空间保持遮罩可见")
        try await waitUntil { stream.handler != nil }
        let panel = try XCTUnwrap(NSApp.windows.compactMap { $0 as? RecordingControlPanel }.first)
        let content = try XCTUnwrap(panel.contentView)
        let start = descendants(content).compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "capture.gif.start" }
        let changeRegion = descendants(content).compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "capture.gif.changeRegion" }
        let discard = descendants(content).compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "capture.gif.discard" }
        XCTAssertTrue(start?.isHidden ?? false, "自动开始后不再等待“开始录制”确认")
        XCTAssertTrue(changeRegion?.isHidden ?? false)
        XCTAssertEqual(discard?.isHidden, false, "倒计时阶段保留放弃出口")
        let handler = try XCTUnwrap(stream.handler)
        try await handler(CaptureFrameEvent(image: image(green: 1), status: .complete, hostTime: CMClockGetTime(CMClockGetHostTimeClock()).seconds))
        try await waitUntil { flow.sessions.activeSession?.state == .recording }
        XCTAssertNil(dimmer.contentView?.layer?.animation(forKey: "recording.border.pulse"), "进入录制后选区外变暗常亮，停止呼吸闪动")
        controller.stop()
        try await waitUntil { flow.sessions.activeSession?.state == .recordingPreviewing }
        XCTAssertFalse(dimmer.isVisible, "停止录制后区域遮罩立即移除")
        controller.cancel()
        try await waitUntil { flow.sessions.activeSession == nil }
    }

    @MainActor
    func testRecordingPanelFlashesWhileRecordingAndStaysQuietOtherwise() throws {
        let panel = RecordingControlPanel(screenFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
                                          selection: CGRect(x: 200, y: 300, width: 300, height: 200),
                                          outputSize: CGSize(width: 600, height: 400), showsCursor: true)
        defer { panel.dismiss() }
        let content = try XCTUnwrap(panel.contentView)
        let dot = try XCTUnwrap(descendants(content).compactMap { $0 as? RecordingDotView }.first)
        func pulseKey() throws {
            try XCTUnwrap(dot.layer?.animation(forKey: "recording.dot.blink"))
        }

        panel.showReady()
        XCTAssertTrue(dot.isHidden)
        panel.showCountdown(2)
        XCTAssertTrue(dot.isHidden)
        panel.showRecording(3)
        XCTAssertFalse(dot.isHidden, "录制中显示红点")
        XCTAssertTrue(dot.isFlashing, "重复的 ticker 调用不重置闪烁状态")
        try pulseKey()
        panel.showRecording(4)
        XCTAssertTrue(dot.isFlashing)
        try pulseKey()
        panel.showEnding()
        XCTAssertTrue(dot.isHidden)
        XCTAssertNil(dot.layer?.animation(forKey: "recording.dot.blink"))
    }

    @MainActor
    func testRecordingStopPreviewAndRerecordReuseOneSessionAndIgnoreOldAttempt() async throws {
        let stream = FakeGIFStream()
        let (controller, flow, root) = try makeController(stream: stream)
        defer { try? FileManager.default.removeItem(at: root) }
        let originalID = flow.sessions.activeSession?.id
        controller.start(showsCursor: false)
        try await waitUntil { stream.handler != nil }
        let handler = try XCTUnwrap(stream.handler)
        try await handler(CaptureFrameEvent(image: image(green: 1), status: .complete, hostTime: CMClockGetTime(CMClockGetHostTimeClock()).seconds))
        XCTAssertEqual(flow.sessions.activeSession?.state, .recording)
        controller.stop()
        try await waitUntil { flow.sessions.activeSession?.state == .recordingPreviewing }
        XCTAssertFalse(controller.environmentChanged(), "Already captured results survive permission/display interruptions")
        controller.resetAttempt()
        try await waitUntil { flow.sessions.activeSession?.state == .recordingReady }
        XCTAssertEqual(flow.sessions.activeSession?.id, originalID)
        try await handler(CaptureFrameEvent(image: image(blue: 1), status: .complete, hostTime: CMClockGetTime(CMClockGetHostTimeClock()).seconds))
        XCTAssertEqual(flow.sessions.activeSession?.state, .recordingReady)
        controller.cancel()
        try await waitUntil { flow.sessions.activeSession == nil }
    }

    @MainActor
    private func makeController(stream: FakeGIFStream, startsImmediately: Bool = false) throws -> (RecordingController, CaptureFlowController, URL) {
        let root = temporaryRoot()
        let flow = CaptureFlowController()
        let session = try XCTUnwrap(flow.sessions.begin(mode: .gif, targetProcessID: nil))
        let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let frozen = try FrozenScreen(displayID: 0, screenFrame: frame, image: image(red: 1),
                                      transform: DisplayTransform(screenFrame: frame, pixelWidth: 16, pixelHeight: 12), windows: [])
        var options = RecordingOptions()
        options.countdownSeconds = 0
        let controller = RecordingController(flow: flow, output: OutputDeliveryService(assetStore: AssetStore(rootURL: root)),
                                             options: options, stream: stream, hasScreenPermission: { true }, workingRoot: root.appending(path: "working"))
        controller.begin(display: CapturedDisplay(frozen), pixelRect: CGRect(x: 0, y: 0, width: 16, height: 12), session: session, startsImmediately: startsImmediately)
        return (controller, flow, root)
    }

    @MainActor
    private func waitUntil(_ predicate: @MainActor () -> Bool) async throws {
        for _ in 0 ..< 400 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for asynchronous GIF state")
        throw GIFError.streamStopped
    }

    @MainActor
    private func makeResult(in root: URL) async throws -> GIFResult {
        let store = try GIFFrameStore(width: 16, height: 12, options: RecordingOptions(), root: root)
        let cancellation = RecordingCancellation()
        _ = try await store.append(image(red: 1), at: 1, cancellation: cancellation)
        _ = try await store.append(image(blue: 1), at: 1.2, cancellation: cancellation)
        return try await GIFEncoder.encode(store.seal(at: 2), cancellation: cancellation)
    }

    @MainActor
    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    @MainActor
    private func savePreview(_ view: NSView, at url: URL) throws {
        // Render the AppKit print representation; cached window surfaces can be blank in hosted tests.
        let provider = try XCTUnwrap(CGDataProvider(data: view.dataWithPDF(inside: view.bounds) as CFData))
        let document = try XCTUnwrap(CGPDFDocument(provider))
        let page = try XCTUnwrap(document.page(at: 1))
        let context = try XCTUnwrap(CGContext(data: nil, width: Int(view.bounds.width), height: Int(view.bounds.height),
                                              bitsPerComponent: 8, bytesPerRow: Int(view.bounds.width) * 4,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.windowBackgroundColor.cgColor)
        context.fill(view.bounds)
        context.drawPDFPage(page)
        let bitmap = try NSBitmapImageRep(cgImage: XCTUnwrap(context.makeImage()))
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "GIFTests-" + UUID().uuidString)
    }

    private func image(red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 16, height: 12, bitsPerComponent: 8, bytesPerRow: 64,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 16, height: 12))
        // An asymmetric mark also catches accidental vertical flips during raw-frame storage.
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 3))
        return try XCTUnwrap(context.makeImage())
    }
}

@MainActor
private final class FakeGIFStream: RecordingStream {
    var recordingDroppedFrames = 0
    var handler: ScreenCaptureEventRelay.Handler?
    var holdStart = false
    var stops = 0
    private var continuation: CheckedContinuation<Void, Never>?

    func startRecording(display _: CapturedDisplay, sourceRect _: CGRect, width _: Int, height _: Int,
                        options _: RecordingOptions, onEvent: @escaping ScreenCaptureEventRelay.Handler,
                        onFailure _: @escaping ScreenCaptureStreamService.FailureHandler) async throws
    {
        handler = onEvent
        if holdStart { await withCheckedContinuation { continuation = $0 } }
    }

    func releaseStart() {
        continuation?.resume(); continuation = nil
    }

    func probeRecording() async throws -> CGImage {
        throw GIFError.streamStopped
    }

    func stop() async {
        stops += 1
    }
}
