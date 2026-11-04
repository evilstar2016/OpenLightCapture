import AppKit
import ImageIO

enum GIFPreviewSource {
    case gif(GIFResult)
    case raw(GIFRecording)
}

private actor GIFPreviewDecoder {
    private let source: GIFPreviewSource
    private var imageSource: CGImageSource?

    init(source: GIFPreviewSource) {
        self.source = source
    }

    func delays() throws -> [Double] {
        try Task.checkCancellation()
        switch source {
        case let .raw(recording): return recording.delays
        case let .gif(result):
            guard let images = CGImageSourceCreateWithURL(result.url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { throw GIFError.invalidMaterial }
            imageSource = images
            return try (0 ..< CGImageSourceGetCount(images)).map { index in
                guard let props = CGImageSourceCopyPropertiesAtIndex(images, index, nil) as? [CFString: Any],
                      let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any],
                      let delay = (gif[kCGImagePropertyGIFUnclampedDelayTime] ?? gif[kCGImagePropertyGIFDelayTime]) as? Double,
                      delay.isFinite, delay > 0 else { throw GIFError.invalidMaterial }
                return delay
            }
        }
    }

    func image(_ index: Int) throws -> CGImage {
        try Task.checkCancellation()
        return try autoreleasepool {
            let image: CGImage
            switch source {
            case let .raw(recording): image = try recording.image(at: index)
            case .gif:
                guard let imageSource, let decoded = CGImageSourceCreateImageAtIndex(imageSource, index, [kCGImageSourceShouldCache: false] as CFDictionary) else { throw GIFError.invalidMaterial }
                image = decoded
            }
            // UI rendering must not lazily reopen a workspace after re-recording removes it.
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                          bytesPerRow: image.width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { throw GIFError.invalidMaterial }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            guard let rendered = context.makeImage() else { throw GIFError.invalidMaterial }
            return rendered
        }
    }
}

@MainActor
final class GIFPreviewPlayer {
    private var task: Task<Void, Never>?
    private var runID = UUID()
    private var decoder: GIFPreviewDecoder?
    private var delays: [Double] = []
    private var offset = 0.0
    private var startedAt = 0.0
    private(set) var isPlaying = false
    var onImage: ((CGImage) -> Void)?
    var onError: ((String) -> Void)?

    func load(_ source: GIFPreviewSource) {
        stop()
        let decoder = GIFPreviewDecoder(source: source)
        self.decoder = decoder
        let id = runID
        task = Task { [weak self] in
            guard !Task.isCancelled else { return }
            do {
                let delays = try await decoder.delays()
                guard let self, runID == id, !Task.isCancelled, !delays.isEmpty else { return }
                self.delays = delays
                play()
            } catch {
                guard let self, runID == id, !Task.isCancelled else { return }
                onError?(error.localizedDescription)
            }
        }
    }

    func toggle() {
        isPlaying ? pause() : play()
    }

    func pause() {
        guard isPlaying else { return }
        offset += ProcessInfo.processInfo.systemUptime - startedAt
        isPlaying = false
        task?.cancel()
    }

    private func play() {
        guard let decoder, !delays.isEmpty, !isPlaying else { return }
        isPlaying = true
        startedAt = ProcessInfo.processInfo.systemUptime
        let id = runID
        let total = delays.reduce(0, +)
        task = Task { [weak self] in
            var previous = -1
            while let self, runID == id, isPlaying, !Task.isCancelled {
                let position = (offset + ProcessInfo.processInfo.systemUptime - startedAt).truncatingRemainder(dividingBy: total)
                var end = 0.0
                var index = 0
                for (i, delay) in delays.enumerated() {
                    end += delay
                    index = i
                    if end > position { break }
                }
                if index != previous {
                    do {
                        let image = try await decoder.image(index)
                        guard runID == id, !Task.isCancelled else { return }
                        onImage?(image)
                        previous = index
                    } catch {
                        guard runID == id, !Task.isCancelled else { return }
                        onError?(error.localizedDescription)
                        pause()
                        return
                    }
                }
                do { try await Task.sleep(for: .seconds(min(0.1, max(0.01, end - position)))) } catch { return }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        runID = UUID()
        decoder = nil
        delays = []
        offset = 0
        isPlaying = false
    }

    func stopAndWait() async {
        let previous = task
        stop()
        await previous?.value
    }
}
