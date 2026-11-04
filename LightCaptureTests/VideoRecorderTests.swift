import AppKit
import AVFoundation
@testable import LightCapture
import XCTest

final class VideoRecorderTests: XCTestCase {
    func testMP4PreservesStaticSegmentsAndTailWithoutAudio() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = try VideoRecorder(width: 64, height: 48, root: root)
        let cancellation = RecordingCancellation()
        let first = try await recorder.append(image(red: 1), at: 100, cancellation: cancellation)
        let next = try await recorder.append(image(blue: 1), at: 104, cancellation: cancellation)
        XCTAssertTrue(first)
        XCTAssertTrue(next)
        let result = try await recorder.finish(at: 106, cancellation: cancellation)
        XCTAssertEqual(result.duration, 6, accuracy: 0.04)
        XCTAssertEqual(result.width, 64)
        XCTAssertEqual(result.height, 48)
        XCTAssertEqual(result.url.pathExtension, "mp4")
        XCTAssertGreaterThan(result.byteCount, 0)
        let samples = try await readFrames(result.url)
        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(samples[0].time, 0, accuracy: 0.01)
        XCTAssertEqual(samples[1].time, 4, accuracy: 0.01)
        XCTAssertGreaterThan(samples[0].red, samples[0].blue + 100)
        XCTAssertGreaterThan(samples[1].blue, samples[1].red + 100)
        await recorder.cleanup()
        XCTAssertFalse(FileManager.default.fileExists(atPath: result.url.path))
    }

    func testCompletelyStaticVideoRetainsItsFullDuration() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = try VideoRecorder(width: 64, height: 48, root: root)
        let cancellation = RecordingCancellation()
        _ = try await recorder.append(image(red: 1), at: 10, cancellation: cancellation)
        let result = try await recorder.finish(at: 20, cancellation: cancellation)
        XCTAssertEqual(result.duration, 10, accuracy: 0.04)
        let frames = try await readFrames(result.url)
        XCTAssertEqual(frames.count, 1)
        await recorder.cleanup()
    }

    func testVideoDimensionsUseEvenPixelsAndNeverUpscale() {
        let options = RecordingOptions.video
        XCTAssertEqual(options.outputSize(width: 3840, height: 2160), CGSize(width: 1920, height: 1080))
        XCTAssertEqual(options.outputSize(width: 641, height: 359), CGSize(width: 640, height: 358))
        XCTAssertEqual(options.outputSize(width: 640, height: 360), CGSize(width: 640, height: 360))
        XCTAssertEqual(options.outputSize(width: 1, height: 200), .zero)
        XCTAssertThrowsError(try VideoRecorder(width: 641, height: 359, root: temporaryRoot()))
    }

    func testCancelledVideoCannotFinishOrPublishAFile() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = try VideoRecorder(width: 64, height: 48, root: root)
        let cancellation = RecordingCancellation()
        _ = try await recorder.append(image(red: 1), at: 1, cancellation: cancellation)
        cancellation.cancel()
        do {
            _ = try await recorder.finish(at: 2, cancellation: cancellation)
            XCTFail("Cancelled video must not finish")
        } catch { XCTAssertTrue(error is CancellationError) }
        await recorder.cleanup()
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        XCTAssertTrue(files.isEmpty)
    }

    func testMaximumDurationIsClampedAndFrameTimesRemainIncreasing() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = try VideoRecorder(width: 64, height: 48, root: root)
        let cancellation = RecordingCancellation()
        let frame = try image(red: 1)
        _ = try await recorder.append(frame, at: 100, cancellation: cancellation)
        let backwards = try await recorder.append(frame, at: 99, cancellation: cancellation)
        let tooFast = try await recorder.append(frame, at: 100.001, cancellation: cancellation)
        let tooLate = try await recorder.append(frame, at: 701, cancellation: cancellation)
        XCTAssertFalse(backwards)
        XCTAssertFalse(tooFast)
        XCTAssertFalse(tooLate)
        let result = try await recorder.finish(at: 800, cancellation: cancellation)
        XCTAssertEqual(result.duration, 600, accuracy: 0.04)
        await recorder.cleanup()
    }

    func testConcurrentFrameDeliveryCannotWriteDuplicateOrDecreasingTimestamps() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = try VideoRecorder(width: 64, height: 48, root: root)
        let cancellation = RecordingCancellation()
        let frame = try image(red: 1)
        _ = try await recorder.append(frame, at: 0, cancellation: cancellation)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 1 ..< 90 {
                group.addTask { _ = try await recorder.append(frame, at: Double(index) / 30, cancellation: cancellation) }
            }
            try await group.waitForAll()
        }
        let result = try await recorder.finish(at: 3, cancellation: cancellation)
        let frames = try await readFrames(result.url)
        XCTAssertGreaterThanOrEqual(frames.count, 1)
        for pair in zip(frames, frames.dropFirst()) {
            XCTAssertLessThan(pair.0.time, pair.1.time)
        }
        XCTAssertEqual(result.duration, 3, accuracy: 0.04)
        await recorder.cleanup()
    }

    @MainActor
    func testSavingVideoAndOverwritingExistingFileDoNotChangeClipboard() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let result = try await makeResult(in: root.appending(path: "working"))
        let target = root.appending(path: "saved.mp4")
        try Data("old file".utf8).write(to: target)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("keep", forType: .string)
        let count = pasteboard.changeCount
        let service = OutputDeliveryService(assetStore: AssetStore(rootURL: root.appending(path: "assets")), pasteboard: pasteboard,
                                            videoSaveDestination: { target })
        let outcome = await service.saveVideo(result, startedAt: Date(), parentWindow: nil, isCurrent: { true })
        guard case let .saved(url) = outcome else { return XCTFail("Expected successful MP4 save") }
        XCTAssertEqual(url, target)
        let saved = try await VideoRecorder.inspect(url: target)
        XCTAssertEqual(saved.duration, result.duration, accuracy: 0.01)
        XCTAssertEqual(try Data(contentsOf: target), try Data(contentsOf: result.url))
        XCTAssertEqual(pasteboard.changeCount, count)
        XCTAssertEqual(pasteboard.string(forType: .string), "keep")
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertFalse(names.contains { $0.hasPrefix(".lightcapture-save-") })
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "assets").path))
    }

    @MainActor
    func testCancelledOrInvalidatedSaveRetainsVideoAndExistingDestination() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let result = try await makeResult(in: root.appending(path: "working"))
        let target = root.appending(path: "saved.mp4")
        let original = Data("keep existing destination".utf8)
        try original.write(to: target)
        var current = true
        let service = OutputDeliveryService(assetStore: AssetStore(rootURL: root.appending(path: "assets")), videoSaveDestination: {
            current = false
            return target
        })
        let outcome = await service.saveVideo(result, startedAt: Date(), parentWindow: nil, isCurrent: { current })
        guard case .cancelled = outcome else { return XCTFail("Stale save must be cancelled") }
        XCTAssertEqual(try Data(contentsOf: target), original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.url.path))
        let cancelled = OutputDeliveryService(assetStore: AssetStore(rootURL: root.appending(path: "assets")), videoSaveDestination: { nil })
        let second = await cancelled.saveVideo(result, startedAt: Date(), parentWindow: nil, isCurrent: { true })
        guard case .cancelled = second else { return XCTFail("Cancelling destination selection must keep the result") }
    }

    @MainActor
    func testSavingIntoManagedWorkspaceIsRejectedWithoutDeletingTheVideo() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let result = try await makeResult(in: root.appending(path: "working"))
        let service = OutputDeliveryService(assetStore: AssetStore(rootURL: root.appending(path: "assets")), videoSaveDestination: { result.url })
        let outcome = await service.saveVideo(result, startedAt: Date(), parentWindow: nil, isCurrent: { true })
        guard case .failed = outcome else { return XCTFail("Cannot save into a directory that will be cleaned") }
        _ = try await VideoRecorder.inspect(url: result.url)
    }

    @MainActor
    func testVideoControllerStopsPreviewsAndSavesWithinTheSharedSession() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appending(path: "saved.mp4")
        let stream = FakeVideoStream()
        let flow = CaptureFlowController()
        let session = try XCTUnwrap(flow.sessions.begin(mode: .video, targetProcessID: nil))
        let rectangle = CGRect(x: 0, y: 0, width: 800, height: 600)
        let frozen = try FrozenScreen(displayID: 0, screenFrame: rectangle, image: image(red: 1),
                                      transform: DisplayTransform(screenFrame: rectangle, pixelWidth: 64, pixelHeight: 48), windows: [])
        var options = RecordingOptions.video
        options.countdownSeconds = 0
        let output = OutputDeliveryService(assetStore: AssetStore(rootURL: root.appending(path: "assets")), videoSaveDestination: { target })
        let controller = RecordingController(flow: flow, output: output, options: options, stream: stream,
                                             hasScreenPermission: { true }, workingRoot: root.appending(path: "working"))
        controller.begin(display: CapturedDisplay(frozen), pixelRect: CGRect(x: 0, y: 0, width: 64, height: 48), session: session)
        controller.start(showsCursor: true)
        try await waitUntil { stream.handler != nil }
        try await stream.handler?(CaptureFrameEvent(image: image(red: 1), status: .complete, hostTime: CMClockGetTime(CMClockGetHostTimeClock()).seconds))
        XCTAssertEqual(flow.sessions.activeSession?.state, .recording)
        controller.stop()
        try await waitUntil { flow.sessions.activeSession?.state == .recordingPreviewing }
        XCTAssertFalse(controller.environmentChanged())
        let preview = try XCTUnwrap(NSApp.windows.first { $0.title == L10n.videoPreview && $0.isVisible })
        let button = try XCTUnwrap(descendants(XCTUnwrap(preview.contentView)).compactMap { $0 as? NSButton }.first { $0.title == L10n.videoSave })
        button.performClick(nil)
        try await waitUntil { flow.sessions.activeSession == nil }
        let result = try await VideoRecorder.inspect(url: target)
        XCTAssertGreaterThan(result.duration, 0)
        XCTAssertGreaterThan(stream.stops, 0)
        let workspaces = try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "working").path)
        XCTAssertTrue(workspaces.isEmpty)
    }

    @MainActor
    private func makeResult(in root: URL) async throws -> VideoResult {
        let recorder = try VideoRecorder(width: 64, height: 48, root: root)
        let cancellation = RecordingCancellation()
        _ = try await recorder.append(image(red: 1), at: 1, cancellation: cancellation)
        return try await recorder.finish(at: 3, cancellation: cancellation)
    }

    @MainActor
    private func waitUntil(_ predicate: @MainActor () -> Bool) async throws {
        for _ in 0 ..< 600 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for video state")
        throw VideoError.encoding
    }

    @MainActor
    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private func readFrames(_ url: URL) async throws -> [(time: Double, red: Int, blue: Int)] {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let reader = try AVAssetReader(asset: asset)
        let output = try AVAssetReaderTrackOutput(track: XCTUnwrap(tracks.first), outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        var frames: [(Double, Int, Int)] = []
        while let sample = output.copyNextSampleBuffer() {
            let pixels = try XCTUnwrap(CMSampleBufferGetImageBuffer(sample))
            CVPixelBufferLockBaseAddress(pixels, .readOnly)
            let bytes = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixels)).assumingMemoryBound(to: UInt8.self)
            frames.append((CMSampleBufferGetPresentationTimeStamp(sample).seconds, Int(bytes[2]), Int(bytes[0])))
            CVPixelBufferUnlockBaseAddress(pixels, .readOnly)
        }
        XCTAssertEqual(reader.status, .completed)
        return frames
    }

    private func image(red: CGFloat = 0, blue: CGFloat = 0) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 256,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: red, green: 0, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
        return try XCTUnwrap(context.makeImage())
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "VideoTests-" + UUID().uuidString)
    }
}

@MainActor
private final class FakeVideoStream: RecordingStream {
    var recordingDroppedFrames = 0
    var handler: ScreenCaptureEventRelay.Handler?
    var stops = 0

    func startRecording(display _: CapturedDisplay, sourceRect _: CGRect, width _: Int, height _: Int,
                        options _: RecordingOptions, onEvent: @escaping ScreenCaptureEventRelay.Handler,
                        onFailure _: @escaping ScreenCaptureStreamService.FailureHandler) async throws
    {
        handler = onEvent
    }

    func probeRecording() async throws -> CGImage {
        throw VideoError.encoding
    }

    func stop() async {
        stops += 1
    }
}
