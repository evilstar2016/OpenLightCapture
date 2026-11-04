import AppKit
import CoreImage
import CoreVideo
import Foundation
import ScreenCaptureKit

@MainActor
final class ScreenCaptureStreamService {
    typealias FrameHandler = @MainActor @Sendable (CGImage) async -> Void
    typealias FailureHandler = @MainActor @Sendable (String) -> Void

    private var stream: SCStream?
    private var relay: ScreenCaptureStreamRelay?
    private var eventRelay: ScreenCaptureEventRelay?
    private var recordingSource: (SCContentFilter, SCStreamConfiguration)?
    private var recordingProbeRect: CGRect?
    private(set) var recordingDroppedFrames = 0

    func startRecording(display: CapturedDisplay, sourceRect: CGRect, width: Int, height: Int,
                        options: RecordingOptions, onEvent: @escaping ScreenCaptureEventRelay.Handler,
                        onFailure: @escaping FailureHandler) async throws
    {
        guard stream == nil else { throw ScreenCaptureStreamError.startFailed(L10n.gifStreamStopped) }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let target = content.displays.first(where: { $0.displayID == display.displayID }) else { throw ScreenCaptureStreamError.displayUnavailable }
        let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: target, excludingApplications: own, exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.sourceRect = sourceRect
        config.width = width
        config.height = height
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(options.targetFPS))
        config.queueDepth = 3
        config.showsCursor = options.showsCursor
        config.capturesAudio = false
        let receiver = ScreenCaptureEventRelay(onEvent: onEvent, onFailure: onFailure)
        let capture = SCStream(filter: filter, configuration: config, delegate: receiver)
        do {
            try capture.addStreamOutput(receiver, type: .screen, sampleHandlerQueue: DispatchQueue(label: "io.github.evilstar2016.openlightcapture.gif.frames", qos: .userInitiated))
            try await capture.startCapture()
            eventRelay = receiver
            stream = capture
            recordingSource = (filter, config)
            let primaryScreenHeight = NSScreen.screens.first?.frame.maxY ?? 0
            let displayQuartz = CGRect(x: display.screenFrame.minX, y: primaryScreenHeight - display.screenFrame.maxY,
                                       width: display.screenFrame.width, height: display.screenFrame.height)
            recordingProbeRect = CGRect(x: displayQuartz.minX + sourceRect.minX, y: displayQuartz.minY + sourceRect.minY,
                                        width: sourceRect.width, height: sourceRect.height)
            recordingDroppedFrames = 0
        } catch {
            receiver.disable()
            try? await capture.stopCapture()
            throw error
        }
    }

    func probeRecording() async throws -> CGImage {
        guard let (filter, config) = recordingSource else { throw GIFError.streamStopped }
        if #available(macOS 14.0, *) {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        }
        guard let rect = recordingProbeRect,
              let image = CGWindowListCreateImage(rect, [.optionOnScreenOnly, .excludeDesktopElements],
                                                  kCGNullWindowID, [.bestResolution])
        else {
            throw GIFError.streamStopped
        }
        return image
    }

    func start(
        display: CapturedDisplay,
        sourceRect: CGRect,
        outputWidth: Int,
        outputHeight: Int,
        onFrame: @escaping FrameHandler,
        onFailure: @escaping FailureHandler
    ) async throws {
        guard stream == nil else { return }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let shareableDisplay = content.displays.first(where: { $0.displayID == display.displayID }) else {
            throw ScreenCaptureStreamError.displayUnavailable
        }
        let ownProcessID = ProcessInfo.processInfo.processIdentifier
        let ownApplications = content.applications.filter { $0.processID == ownProcessID }
        let filter = SCContentFilter(display: shareableDisplay, excludingApplications: ownApplications, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = sourceRect
        configuration.width = outputWidth
        configuration.height = outputHeight
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 10)
        configuration.queueDepth = 3
        configuration.showsCursor = false
        configuration.capturesAudio = false

        let relay = ScreenCaptureStreamRelay(onFrame: onFrame, onFailure: onFailure)
        let captureStream = SCStream(filter: filter, configuration: configuration, delegate: relay)
        do {
            try captureStream.addStreamOutput(
                relay,
                type: .screen,
                sampleHandlerQueue: DispatchQueue(label: "io.github.evilstar2016.openlightcapture.capture.frames", qos: .userInitiated)
            )
            try await captureStream.startCapture()
            self.relay = relay
            stream = captureStream
        } catch {
            relay.disable()
            try? await captureStream.stopCapture()
            throw ScreenCaptureStreamError.startFailed(error.localizedDescription)
        }
    }

    func stop() async {
        guard let stream else { return }
        self.stream = nil
        relay?.disable()
        relay = nil
        recordingDroppedFrames = eventRelay?.droppedCount ?? recordingDroppedFrames
        eventRelay?.disable()
        eventRelay = nil
        recordingSource = nil
        recordingProbeRect = nil
        try? await stream.stopCapture()
    }

    func isWindowAvailable(_ windowID: CGWindowID, expectedFrame: CGRect? = nil) async -> Bool {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else { return false }
        guard let window = content.windows.first(where: { $0.windowID == windowID }), window.isOnScreen else { return false }
        guard let expectedFrame else { return true }
        let currentFrame = DisplayTransform.appKitRect(fromQuartzRect: window.frame, primaryScreenHeight: NSScreen.screens.first?.frame.maxY ?? 0)
        return currentFrame == expectedFrame
    }
}

final class ScreenCaptureStreamRelay: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    private let onFrame: ScreenCaptureStreamService.FrameHandler
    private let onFailure: ScreenCaptureStreamService.FailureHandler
    private let lock = NSLock()
    private var frameDeliveryPending = false
    private var isDisabled = false
    private var lastCompleteImage: CGImage?

    init(onFrame: @escaping ScreenCaptureStreamService.FrameHandler, onFailure: @escaping ScreenCaptureStreamService.FailureHandler) {
        self.onFrame = onFrame
        self.onFailure = onFailure
    }

    func stream(_: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        receive(sampleBuffer)
    }

    func receive(_ sampleBuffer: CMSampleBuffer) {
        guard CMSampleBufferDataIsReady(sampleBuffer),
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: rawStatus),
              status == .complete || status == .idle
        else { return }

        lock.lock()
        guard !isDisabled, !frameDeliveryPending else {
            lock.unlock()
            return
        }
        frameDeliveryPending = true
        let cachedImage = lastCompleteImage
        lock.unlock()

        let image: CGImage?
        if status == .idle {
            image = cachedImage
        } else if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            image = Self.context.createCGImage(ciImage, from: ciImage.extent)
        } else {
            image = nil
        }
        guard let image else {
            finishFrameDelivery()
            return
        }
        lock.lock()
        if !isDisabled { lastCompleteImage = image }
        lock.unlock()
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { finishFrameDelivery() }
            guard isEnabled else { return }
            await onFrame(image)
        }
    }

    func stream(_: SCStream, didStopWithError error: Error) {
        let shouldReport: Bool
        lock.lock()
        shouldReport = !isDisabled
        lock.unlock()
        guard shouldReport else { return }
        Task { @MainActor [weak self] in
            guard let self, isEnabled else { return }
            onFailure(error.localizedDescription)
        }
    }

    func disable() {
        lock.lock()
        isDisabled = true
        lastCompleteImage = nil
        lock.unlock()
    }

    private var isEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !isDisabled
    }

    private func finishFrameDelivery() {
        lock.lock()
        frameDeliveryPending = false
        lock.unlock()
    }
}

enum ScreenCaptureStreamError: LocalizedError {
    case displayUnavailable
    case startFailed(String)

    var errorDescription: String? {
        switch self {
        case .displayUnavailable: L10n.errorDisplayUnavailable
        case let .startFailed(detail): L10n.errorStreamStart(detail)
        }
    }
}
