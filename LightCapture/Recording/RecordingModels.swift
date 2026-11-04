import CoreGraphics
import Foundation

enum RecordingKind {
    case gif, video

    var title: String {
        self == .gif ? L10n.gifTitle : L10n.videoTitle
    }

    var parameters: String {
        self == .gif ? L10n.gifParameters : L10n.videoParameters
    }

    var preparationHint: String {
        self == .gif ? L10n.gifPrepareHint : L10n.videoPrepareHint
    }
}

struct RecordingOptions {
    var kind: RecordingKind = .gif
    var countdownSeconds = 3
    var targetFPS = 10
    var maxDuration: TimeInterval = 30
    var maxPixelEdge = 1280
    var showsCursor = true

    static let maximumFrames = 300
    static let maximumFileBytes = 50 * 1024 * 1024
    static let maximumWorkingBytes = 2 * 1024 * 1024 * 1024

    static var video: RecordingOptions {
        var options = RecordingOptions()
        options.kind = .video
        options.targetFPS = 30
        options.maxDuration = 600
        options.maxPixelEdge = 1920
        return options
    }

    func outputSize(width: Int, height: Int) -> CGSize {
        guard width > 0, height > 0 else { return .zero }
        let scale = min(1, Double(maxPixelEdge) / Double(max(width, height)))
        let outputWidth = max(1, Int(floor(Double(width) * scale)))
        let outputHeight = max(1, Int(floor(Double(height) * scale)))
        if kind == .video {
            guard outputWidth >= 2, outputHeight >= 2 else { return .zero }
            return CGSize(width: outputWidth - outputWidth % 2, height: outputHeight - outputHeight % 2)
        }
        return CGSize(width: outputWidth, height: outputHeight)
    }
}

/// Cancellation is checked between frames, including inside background ImageIO work.
final class RecordingCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.withLock { cancelled = true }
    }

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func check() throws {
        if isCancelled { throw CancellationError() }
    }
}

struct GIFFrameRecord: Codable {
    let filename: String
    let offset: TimeInterval
}

struct GIFRecording {
    let directory: URL
    let width: Int
    let height: Int
    let frames: [GIFFrameRecord]
    let duration: TimeInterval

    var delays: [TimeInterval] {
        frames.indices.map { index in
            let start = Int((frames[index].offset * 100).rounded())
            let end = Int(((index + 1 < frames.count ? frames[index + 1].offset : duration) * 100).rounded())
            return Double(max(10, end - start)) / 100
        }
    }

    func image(at index: Int) throws -> CGImage {
        guard frames.indices.contains(index), GIFFrameStore.isSafeDirectory(directory) else { throw GIFError.invalidMaterial }
        let filename = frames[index].filename
        guard filename == String(format: "frame-%06d.rgba", index) else { throw GIFError.invalidMaterial }
        let url = directory.appending(path: filename)
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              values.fileSize == width * height * 4,
              let provider = CGDataProvider(url: url as CFURL),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: width * 4, space: space,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { throw GIFError.invalidMaterial }
        return image
    }
}

struct GIFResult {
    let url: URL
    let width: Int
    let height: Int
    let frameCount: Int
    let duration: TimeInterval
    let byteCount: Int

    var canPublish: Bool {
        byteCount <= RecordingOptions.maximumFileBytes
    }
}

enum GIFError: LocalizedError, Equatable {
    case invalidMaterial
    case insufficientStorage
    case noFrames
    case encoding
    case streamStopped
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .invalidMaterial: L10n.gifInvalidMaterial
        case .insufficientStorage: L10n.gifStorage
        case .noFrames: L10n.gifNoFrames
        case .encoding: L10n.gifEncodingFailed
        case .streamStopped: L10n.gifStreamStopped
        case .tooLarge: L10n.gifTooLarge
        }
    }
}
