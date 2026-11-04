import CoreGraphics
import Foundation

actor GIFFrameStore {
    private struct Manifest: Encodable {
        let width: Int
        let height: Int
        let frames: [GIFFrameRecord]
        let duration: TimeInterval
    }

    let directory: URL
    private let width: Int
    private let height: Int
    private let options: RecordingOptions
    private var frames: [GIFFrameRecord] = []
    private var firstTime: TimeInterval?
    private var sealed = false

    static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: Bundle.main.bundleIdentifier ?? "io.github.evilstar2016.openlightcapture")
            .appending(path: "WorkingGIF", directoryHint: .isDirectory)
    }

    init(width: Int, height: Int, options: RecordingOptions, root: URL = GIFFrameStore.defaultRoot) throws {
        guard width > 0, height > 0, width <= 1280, height <= 1280,
              options.targetFPS > 0, options.targetFPS <= 10, options.maxDuration > 0, options.maxDuration <= 30
        else { throw GIFError.invalidMaterial }
        self.width = width
        self.height = height
        self.options = options
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard Self.isSafeDirectory(root), chmod(root.path, 0o700) == 0 else { throw GIFError.invalidMaterial }
        let frameCount = min(RecordingOptions.maximumFrames, Int(ceil(options.maxDuration * Double(options.targetFPS))))
        let required = width * height * 4 * frameCount + RecordingOptions.maximumFileBytes + 64 * 1024 * 1024
        let available = try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
        guard required <= RecordingOptions.maximumWorkingBytes, available.map({ $0 >= required }) ?? true else { throw GIFError.insufficientStorage }
        directory = root.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        guard mkdir(directory.path, 0o700) == 0 else { throw GIFError.invalidMaterial }
    }

    /// A serial actor plus the stream's bounded mailbox prevents per-frame task accumulation.
    func append(_ image: CGImage, at time: TimeInterval, cancellation: RecordingCancellation) throws -> Bool {
        try cancellation.check()
        guard !sealed, time.isFinite, image.width == width, image.height == height else { throw GIFError.invalidMaterial }
        if firstTime == nil { firstTime = time }
        let offset = time - (firstTime ?? time)
        guard offset >= 0, offset < options.maxDuration,
              frames.count < RecordingOptions.maximumFrames,
              frames.last.map({ offset - $0.offset >= 1 / Double(options.targetFPS) - 0.000_001 }) ?? true
        else { return false }
        let filename = String(format: "frame-%06d.rgba", frames.count)
        let url = directory.appending(path: filename)
        try autoreleasepool {
            guard Self.isSafeDirectory(directory), let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
                  let pixels = context.data
            else { throw GIFError.invalidMaterial }
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            try cancellation.check()
            try Data(bytesNoCopy: pixels, count: width * height * 4, deallocator: .none).write(to: url, options: .atomic)
            guard chmod(url.path, 0o600) == 0 else { throw GIFError.invalidMaterial }
        }
        frames.append(GIFFrameRecord(filename: filename, offset: offset))
        return true
    }

    func seal(at stopTime: TimeInterval) throws -> GIFRecording {
        guard !frames.isEmpty, let firstTime, stopTime.isFinite else { throw GIFError.noFrames }
        sealed = true
        let duration = min(options.maxDuration, max(0.1, stopTime - firstTime))
        // A stop can race with an already queued frame. Drop frames beyond the user's cutoff.
        let visible = frames.filter { $0.offset < duration }
        guard !visible.isEmpty else { throw GIFError.noFrames }
        guard Self.isSafeDirectory(directory) else { throw GIFError.invalidMaterial }
        let manifest = Manifest(width: width, height: height, frames: visible, duration: duration)
        let manifestURL = directory.appending(path: "manifest.json")
        try JSONEncoder().encode(manifest).write(to: manifestURL, options: .atomic)
        guard chmod(manifestURL.path, 0o600) == 0 else { throw GIFError.invalidMaterial }
        return GIFRecording(directory: directory, width: width, height: height, frames: visible, duration: duration)
    }

    func cleanup() {
        sealed = true
        if Self.isSafeDirectory(directory) { try? FileManager.default.removeItem(at: directory) }
        frames.removeAll()
    }

    func removeRawFrames() {
        guard Self.isSafeDirectory(directory) else { return }
        for frame in frames {
            try? FileManager.default.removeItem(at: directory.appending(path: frame.filename))
        }
        frames.removeAll()
    }

    nonisolated static func isSafeDirectory(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return false }
        return values.isDirectory == true && values.isSymbolicLink != true
    }

    static func cleanupAbandoned(root: URL = defaultRoot) {
        guard isSafeDirectory(root), let children = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for child in children where UUID(uuidString: child.lastPathComponent) != nil && isSafeDirectory(child) {
            try? FileManager.default.removeItem(at: child)
        }
    }
}
