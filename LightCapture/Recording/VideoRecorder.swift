import AVFoundation
import CoreGraphics
import Foundation

struct VideoResult {
    let url: URL
    let width: Int
    let height: Int
    let duration: TimeInterval
    let byteCount: Int
}

enum VideoError: LocalizedError {
    case invalidMaterial, encoding, noFrames, tooLarge, backpressure

    var errorDescription: String? {
        switch self {
        case .invalidMaterial: L10n.videoInvalidMaterial
        case .encoding: L10n.videoEncodingFailed
        case .noFrames: L10n.gifNoFrames
        case .tooLarge: L10n.videoTooLarge
        case .backpressure: L10n.videoBackpressure
        }
    }
}

/// Serial ownership of a writer and one pending frame; no full-length raw-frame spool.
actor VideoRecorder {
    static let maximumFileBytes = 1024 * 1024 * 1024
    static var defaultRoot: URL {
        RecordingOptions.videoWorkingRoot
    }

    let directory: URL
    private let partial: URL
    private let width: Int
    private let height: Int
    private let options: RecordingOptions
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var pending: (pixels: CVPixelBuffer, offset: TimeInterval)?
    private var firstTime: TimeInterval?
    private var ending = false
    private var appending = false
    private var cancelled = false
    private(set) var droppedFrames = 0

    init(width: Int, height: Int, options: RecordingOptions = .video, root: URL = VideoRecorder.defaultRoot) throws {
        guard options.kind == .video, width >= 2, height >= 2, width <= 1920, height <= 1920,
              width % 2 == 0, height % 2 == 0, options.targetFPS > 0, options.targetFPS <= 30,
              options.maxDuration > 0, options.maxDuration <= 600 else { throw VideoError.invalidMaterial }
        self.width = width
        self.height = height
        self.options = options
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard GIFFrameStore.isSafeDirectory(root), chmod(root.path, 0o700) == 0 else { throw VideoError.invalidMaterial }
        let available = try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
        guard available.map({ $0 >= 64 * 1024 * 1024 }) ?? true else { throw GIFError.insufficientStorage }
        directory = root.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        guard mkdir(directory.path, 0o700) == 0 else { throw VideoError.invalidMaterial }
        partial = directory.appending(path: "recording-incomplete.mp4")
        do {
            let writer = try AVAssetWriter(outputURL: partial, fileType: .mp4)
            let settings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width, AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: min(12_000_000, max(1_000_000, width * height * 5)),
                    AVVideoExpectedSourceFrameRateKey: options.targetFPS,
                    AVVideoMaxKeyFrameIntervalDurationKey: 2,
                    AVVideoAllowFrameReorderingKey: false,
                ],
            ]
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.expectsMediaDataInRealTime = true
            guard writer.canApply(outputSettings: settings, forMediaType: .video), writer.canAdd(input) else { throw VideoError.encoding }
            writer.add(input)
            writer.shouldOptimizeForNetworkUse = true
            guard writer.startWriting() else { throw writer.error ?? VideoError.encoding }
            writer.startSession(atSourceTime: .zero)
            self.writer = writer
            self.input = input
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    func append(_ image: CGImage, at time: TimeInterval, cancellation: RecordingCancellation) async throws -> Bool {
        try cancellation.check()
        if cancelled { throw CancellationError() }
        guard !ending, time.isFinite, image.width == width, image.height == height else { throw VideoError.invalidMaterial }
        guard !appending else { droppedFrames += 1; return false }
        appending = true
        defer { appending = false }
        if firstTime == nil { firstTime = time }
        let offset = time - (firstTime ?? time)
        guard offset >= 0, offset < options.maxDuration else { return false }
        if let previous = pending {
            guard offset - previous.offset >= 1 / Double(options.targetFPS) - 0.000_001 else { return false }
            try await write(previous.pixels, offset: previous.offset, duration: offset - previous.offset, cancellation: cancellation)
        }
        try cancellation.check()
        if cancelled { throw CancellationError() }
        pending = try (makePixels(image), offset)
        try checkSize()
        return true
    }

    func finish(at stopTime: TimeInterval, cancellation: RecordingCancellation) async throws -> VideoResult {
        try cancellation.check()
        if cancelled { throw CancellationError() }
        guard !ending, let firstTime, stopTime.isFinite else { throw VideoError.noFrames }
        ending = true
        while appending {
            try cancellation.check()
            try await Task.sleep(for: .milliseconds(2))
        }
        guard !cancelled, let pending else { throw VideoError.noFrames }
        guard let writer, let input else { throw VideoError.encoding }
        let end = min(options.maxDuration, max(1 / Double(options.targetFPS), stopTime - firstTime))
        guard end > pending.offset else { throw VideoError.invalidMaterial }
        try await write(pending.pixels, offset: pending.offset, duration: end - pending.offset, cancellation: cancellation)
        self.pending = nil
        writer.endSession(atSourceTime: CMTime(seconds: end, preferredTimescale: 60000))
        input.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }
        try cancellation.check()
        if cancelled { throw CancellationError() }
        guard writer.status == .completed else { throw writer.error ?? VideoError.encoding }
        guard chmod(partial.path, 0o600) == 0 else { throw VideoError.invalidMaterial }
        let checked = try await Self.inspect(url: partial)
        guard checked.width == width, checked.height == height, abs(checked.duration - end) <= 0.1 else { throw VideoError.invalidMaterial }
        try cancellation.check()
        let final = directory.appending(path: "recording.mp4")
        try FileManager.default.moveItem(at: partial, to: final)
        // A preview only needs the file. Release the encoder and its pixel-buffer queues now.
        self.writer = nil
        self.input = nil
        return VideoResult(url: final, width: width, height: height, duration: checked.duration, byteCount: checked.byteCount)
    }

    private func write(_ pixels: CVPixelBuffer, offset: Double, duration: Double, cancellation: RecordingCancellation) async throws {
        guard let writer, let input else { throw VideoError.encoding }
        let began = ProcessInfo.processInfo.systemUptime
        while !input.isReadyForMoreMediaData {
            try cancellation.check()
            guard writer.status == .writing else { throw writer.error ?? VideoError.encoding }
            guard ProcessInfo.processInfo.systemUptime - began < 5 else { throw VideoError.backpressure }
            try await Task.sleep(for: .milliseconds(2))
        }
        try cancellation.check()
        guard writer.status == .writing else { throw writer.error ?? VideoError.encoding }
        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixels, formatDescriptionOut: &format) == noErr,
              let format else { throw VideoError.encoding }
        var timing = CMSampleTimingInfo(duration: CMTime(seconds: duration, preferredTimescale: 60000),
                                        presentationTimeStamp: CMTime(seconds: offset, preferredTimescale: 60000), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixels,
                                                       formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sample) == noErr,
            let sample, input.append(sample) else { throw writer.error ?? VideoError.encoding }
    }

    private func makePixels(_ image: CGImage) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let attributes: CFDictionary = [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attributes, &buffer) == kCVReturnSuccess,
              let buffer else { throw VideoError.encoding }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer), let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: base, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: space,
                                      bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue)
        else { throw VideoError.encoding }
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }

    private func checkSize() throws {
        guard let writer, writer.status == .writing else { throw writer?.error ?? VideoError.encoding }
        // URL resource values cache sizes; recording files grow after each query.
        let bytes = (try? FileManager.default.attributesOfItem(atPath: partial.path)[.size] as? Int) ?? 0
        guard bytes <= Self.maximumFileBytes else { throw VideoError.tooLarge }
    }

    func cancelWriting() {
        ending = true
        cancelled = true
        if let writer, writer.status == .writing { writer.cancelWriting() }
        writer = nil
        input = nil
        pending = nil
    }

    func cleanup() {
        cancelWriting()
        if GIFFrameStore.isSafeDirectory(directory) { try? FileManager.default.removeItem(at: directory) }
    }

    static func inspect(url: URL) async throws -> VideoResult {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let bytes = attributes[.size] as? Int, bytes > 0 else { throw VideoError.invalidMaterial }
        guard bytes <= maximumFileBytes else { throw VideoError.tooLarge }
        let file = try FileHandle(forReadingFrom: url)
        let header = try file.read(upToCount: 64) ?? Data()
        try file.close()
        guard header.count >= 16,
              String(data: header.subdata(in: 4 ..< 8), encoding: .ascii) == "ftyp",
              ["isom", "mp41", "mp42", "avc1", "iso2"].contains(String(data: header.subdata(in: 8 ..< 12), encoding: .ascii) ?? "")
        else { throw VideoError.invalidMaterial }
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let videos = try await asset.loadTracks(withMediaType: .video)
        let audios = try await asset.loadTracks(withMediaType: .audio)
        guard videos.count == 1, audios.isEmpty, let track = videos.first else { throw VideoError.invalidMaterial }
        let size = try await track.load(.naturalSize)
        let formats = try await track.load(.formatDescriptions)
        let duration = try await asset.load(.duration).seconds
        let playable = try await asset.load(.isPlayable)
        guard playable, duration.isFinite, duration > 0, duration <= 600.1,
              size.width >= 2, size.height >= 2, size.width <= 1920, size.height <= 1920,
              formats.contains(where: { CMFormatDescriptionGetMediaSubType($0) == kCMVideoCodecType_H264 }) else { throw VideoError.invalidMaterial }
        return VideoResult(url: url, width: Int(size.width), height: Int(size.height), duration: duration, byteCount: bytes)
    }
}

extension RecordingOptions {
    static var videoWorkingRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: Bundle.main.bundleIdentifier ?? "io.github.evilstar2016.openlightcapture")
            .appending(path: "WorkingVideo", directoryHint: .isDirectory)
    }
}
