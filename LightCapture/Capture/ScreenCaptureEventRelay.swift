import CoreImage
import Foundation
import ScreenCaptureKit

struct CaptureFrameEvent {
    let image: CGImage?
    let status: SCFrameStatus
    let hostTime: TimeInterval
}

/// Only one delivery task and one latest waiting event exist at any time.
final class ScreenCaptureEventRelay: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    typealias Handler = @MainActor @Sendable (CaptureFrameEvent) async -> Void
    private static let context = CIContext(options: [.cacheIntermediates: false])
    private let lock = NSLock()
    private let onEvent: Handler
    private let onFailure: ScreenCaptureStreamService.FailureHandler
    private var pending: CaptureFrameEvent?
    private var delivering = false
    private var disabled = false
    private var dropped = 0

    init(onEvent: @escaping Handler, onFailure: @escaping ScreenCaptureStreamService.FailureHandler) {
        self.onEvent = onEvent
        self.onFailure = onFailure
    }

    var droppedCount: Int {
        lock.withLock { dropped }
    }

    func stream(_: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        receive(sampleBuffer)
    }

    func receive(_ sample: CMSampleBuffer) {
        guard CMSampleBufferDataIsReady(sample),
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int, let status = SCFrameStatus(rawValue: raw),
              lock.withLock({ !disabled }) else { return }
        let received = CMClockGetTime(CMClockGetHostTimeClock()).seconds
        let displayTime = (attachments.first?[.displayTime] as? NSNumber)?.uint64Value
        let eventTime = displayTime.map { CMClockMakeHostTimeFromSystemUnits($0).seconds } ?? received
        let timestamp = eventTime.isFinite && eventTime > 0 && eventTime <= received + 0.1 ? eventTime : received
        let image: CGImage?
        if status == .complete || status == .started, let pixels = CMSampleBufferGetImageBuffer(sample) {
            let ciImage = CIImage(cvPixelBuffer: pixels)
            image = Self.context.createCGImage(ciImage, from: ciImage.extent)
        } else { image = nil }
        let event = CaptureFrameEvent(image: image, status: status, hostTime: timestamp)
        let shouldStart = lock.withLock {
            guard !disabled else { return false }
            if let waiting = pending, waiting.image != nil, image == nil, status == .idle { return false }
            if pending?.image != nil, image != nil { dropped += 1 }
            pending = event
            if delivering { return false }
            delivering = true
            return true
        }
        if shouldStart {
            Task { @MainActor [weak self] in
                guard let self else { return }
                while let next = takeNext() {
                    await onEvent(next)
                }
            }
        }
    }

    private func takeNext() -> CaptureFrameEvent? {
        lock.withLock {
            guard !disabled, let event = pending else {
                pending = nil
                delivering = false
                return nil
            }
            pending = nil
            return event
        }
    }

    func disable() {
        lock.withLock {
            disabled = true
            pending = nil
        }
    }

    func stream(_: SCStream, didStopWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in
            guard let self, lock.withLock({ !disabled }) else { return }
            onFailure(message)
        }
    }
}
