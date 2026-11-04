import Foundation
import ImageIO
import UniformTypeIdentifiers

enum GIFEncoder {
    /// ImageIO encodes each frame's palette/LZW. Only the GIF89a container is streamed here.
    /// A whole-animation ImageIO destination retains several GiB at our maximum dimensions.
    static func encode(_ recording: GIFRecording, cancellation: RecordingCancellation) throws -> GIFResult {
        try cancellation.check()
        guard !recording.frames.isEmpty, recording.frames.count <= RecordingOptions.maximumFrames else { throw GIFError.noFrames }
        let partial = recording.directory.appending(path: "result.gif.part")
        let final = recording.directory.appending(path: "result.gif")
        guard GIFFrameStore.isSafeDirectory(recording.directory) else { throw GIFError.invalidMaterial }
        try Data().write(to: partial, options: .atomic)
        guard chmod(partial.path, 0o600) == 0 else { throw GIFError.invalidMaterial }
        let file = try FileHandle(forWritingTo: partial)
        var succeeded = false
        defer {
            try? file.close()
            if !succeeded { try? FileManager.default.removeItem(at: partial) }
        }
        var header = Data("GIF89a".utf8)
        header.append(contentsOf: littleEndian(recording.width) + littleEndian(recording.height) + [0x70, 0, 0])
        // Netscape's loop extension: 0 means repeat indefinitely, as emitted by ImageIO.
        header.append(contentsOf: [0x21, 0xFF, 0x0B])
        header.append(Data("NETSCAPE2.0".utf8))
        header.append(contentsOf: [3, 1, 0, 0, 0])
        try file.write(contentsOf: header)
        let delays = recording.delays
        for index in recording.frames.indices {
            try cancellation.check()
            try autoreleasepool {
                let image = try recording.image(at: index)
                let data = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, 1, nil) else { throw GIFError.encoding }
                CGImageDestinationAddImage(destination, image, nil)
                guard CGImageDestinationFinalize(destination) else { throw GIFError.encoding }
                let block = try frameBlock(from: data as Data, width: recording.width, height: recording.height)
                let delay = min(65535, max(10, Int((delays[index] * 100).rounded())))
                try file.write(contentsOf: Data([0x21, 0xF9, 4, 4] + littleEndian(delay) + [0, 0]))
                try file.write(contentsOf: block)
            }
            if try file.offset() > RecordingOptions.maximumFileBytes { throw GIFError.tooLarge }
        }
        try cancellation.check()
        try file.write(contentsOf: Data([0x3B]))
        try file.synchronize()
        try file.close()
        let result = try inspect(url: partial, expectedFrames: recording.frames.count, cancellation: cancellation)
        guard abs(result.duration - delays.reduce(0, +)) < 0.02 else { throw GIFError.encoding }
        try cancellation.check()
        if FileManager.default.fileExists(atPath: final.path) { try FileManager.default.removeItem(at: final) }
        try FileManager.default.moveItem(at: partial, to: final)
        succeeded = true
        return GIFResult(url: final, width: result.width, height: result.height, frameCount: result.frameCount,
                         duration: result.duration, byteCount: result.byteCount)
    }

    static func inspect(url: URL, expectedFrames: Int? = nil, cancellation: RecordingCancellation = RecordingCancellation()) throws -> GIFResult {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetType(source) as String? == UTType.gif.identifier
        else { throw GIFError.invalidMaterial }
        let count = CGImageSourceGetCount(source)
        guard count > 0, count <= RecordingOptions.maximumFrames, expectedFrames.map({ $0 == count }) ?? true else { throw GIFError.invalidMaterial }
        var width = 0, height = 0
        var duration = 0.0
        for index in 0 ..< count {
            try cancellation.check()
            try autoreleasepool {
                guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                      let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int,
                      w > 0, h > 0, w <= 1280, h <= 1280,
                      let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any],
                      let delay = (gif[kCGImagePropertyGIFUnclampedDelayTime] ?? gif[kCGImagePropertyGIFDelayTime]) as? Double,
                      delay.isFinite, delay >= 0.1,
                      CGImageSourceCreateImageAtIndex(source, index, [kCGImageSourceShouldCache: false] as CFDictionary) != nil
                else { throw GIFError.invalidMaterial }
                if index == 0 { width = w; height = h }
                guard width == w, height == h else { throw GIFError.invalidMaterial }
                duration += delay
            }
        }
        let properties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
        let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        guard (gif?[kCGImagePropertyGIFLoopCount] as? Int) == 0, duration <= 30.2 else { throw GIFError.invalidMaterial }
        return GIFResult(url: url, width: width, height: height, frameCount: count, duration: duration, byteCount: values.fileSize ?? 0)
    }

    /// Accepts only a single complete opaque frame produced by our native encoder.
    /// Each image gets its own palette, so no global-palette mismatch can change its colors.
    static func frameBlock(from data: Data, width: Int, height: Int) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 14, ["GIF87a", "GIF89a"].contains(String(bytes: bytes.prefix(6), encoding: .ascii) ?? "") else { throw GIFError.encoding }
        var cursor = 13
        var palette: [UInt8] = []
        var paletteBits = bytes[10] & 7
        if bytes[10] & 0x80 != 0 {
            let size = 3 * (1 << (Int(paletteBits) + 1))
            guard cursor + size <= bytes.count else { throw GIFError.encoding }
            palette = Array(bytes[cursor ..< cursor + size]); cursor += size
        }
        while cursor < bytes.count {
            let marker = bytes[cursor]; cursor += 1
            if marker == 0x21 {
                guard cursor < bytes.count else { throw GIFError.encoding }
                cursor += 1 // Extension label; all extension payloads are size-prefixed blocks.
                try skipBlocks(bytes, cursor: &cursor)
            } else if marker == 0x2C {
                guard cursor + 9 < bytes.count else { throw GIFError.encoding }
                let descriptor = Array(bytes[cursor ..< cursor + 9]); cursor += 9
                func word(_ offset: Int) -> Int {
                    Int(descriptor[offset]) | Int(descriptor[offset + 1]) << 8
                }
                guard word(0) == 0, word(2) == 0, word(4) == width, word(6) == height else { throw GIFError.encoding }
                if descriptor[8] & 0x80 != 0 {
                    paletteBits = descriptor[8] & 7
                    let size = 3 * (1 << (Int(paletteBits) + 1))
                    guard cursor + size <= bytes.count else { throw GIFError.encoding }
                    palette = Array(bytes[cursor ..< cursor + size]); cursor += size
                }
                guard !palette.isEmpty, cursor < bytes.count else { throw GIFError.encoding }
                let start = cursor
                cursor += 1 // Native LZW minimum code size.
                try skipBlocks(bytes, cursor: &cursor)
                guard cursor < bytes.count, bytes[cursor] == 0x3B, cursor + 1 == bytes.count else { throw GIFError.encoding }
                var block = Data([0x2C] + Array(descriptor.prefix(8)) + [0x80 | (descriptor[8] & 0x40) | paletteBits])
                block.append(contentsOf: palette)
                block.append(contentsOf: bytes[start ..< cursor])
                return block
            } else { throw GIFError.encoding }
        }
        throw GIFError.encoding
    }

    private static func skipBlocks(_ bytes: [UInt8], cursor: inout Int) throws {
        while cursor < bytes.count {
            let count = Int(bytes[cursor]); cursor += 1
            if count == 0 { return }
            guard cursor + count <= bytes.count else { throw GIFError.encoding }
            cursor += count
        }
        throw GIFError.encoding
    }

    private static func littleEndian(_ value: Int) -> [UInt8] {
        [UInt8(value & 255), UInt8((value >> 8) & 255)]
    }
}
