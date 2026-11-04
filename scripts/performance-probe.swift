import AppKit
import CoreGraphics
import Darwin
import Foundation
import ImageIO

/// Compiled together with the production core. This does not capture a screen,
/// create windows, post input, or use the user's general pasteboard.
@main
struct PerformanceProbe {
    @MainActor
    static func main() async throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let workspace = FileManager.default.temporaryDirectory.appending(path: "cut-paste-perf-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        if CommandLine.arguments.dropFirst(2).first == "watermark" {
            let result = try watermarks()
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: output.appending(path: "watermark-performance.json"), options: .atomic)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        if CommandLine.arguments.dropFirst(2).first == "video" {
            let result = try await videoCapacity(workspace: workspace)
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: output.appending(path: "video-performance.json"), options: .atomic)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        if CommandLine.arguments.dropFirst(2).first == "gif" {
            let result = try gifCapacity(workspace: workspace)
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: output.appending(path: "gif-performance.json"), options: .atomic)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        if CommandLine.arguments.dropFirst(2).first == "capacity" {
            let result = try maximumCapacity(workspace: workspace)
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: output.appending(path: "capacity-performance.json"), options: .atomic)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        var measurements: [[String: Any]] = []
        for highEntropy in [false, true] {
            var result = try ordinary(workspace: workspace, highEntropy: highEntropy)
            result["physical_footprint_after_phase_mib"] = physicalFootprintMiB()
            measurements.append(result)
            print("16 MP production render/encode/private publish, highEntropy=\(highEntropy): 30 samples complete.")
            fflush(nil)
        }
        var longResult = try longPreview(workspace: workspace)
        longResult["physical_footprint_after_phase_mib"] = physicalFootprintMiB()
        measurements.append(longResult)
        print("30 MP production reconstruction/preview pixels: 20 samples complete.")
        fflush(nil)
        var wideResult = try await widePage(workspace: workspace)
        wideResult["physical_footprint_after_phase_mib"] = physicalFootprintMiB()
        measurements.append(wideResult)
        let data = try JSONSerialization.data(withJSONObject: [
            "scope": "Optimized synchronous production core in an isolated process; no screen, input, UI dispatch/first-paint timing, or general pasteboard access. All repetitions, including the first, are included. Each action uses its own autorelease pool and private pasteboard; each phase releases its input before the next phase.",
            "p95_method": "nearest rank ceil(0.95*n)",
            "measurements": measurements,
        ], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: output.appending(path: "core-performance.json"), options: .atomic)
        print(String(decoding: data, as: UTF8.self))
    }

    private static func videoCapacity(workspace: URL) async throws -> [String: Any] {
        let width = 1920, height = 1920, count = 300
        let recorder = try VideoRecorder(width: width, height: height, root: workspace)
        let cancellation = RecordingCancellation()
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw VideoError.encoding }
        let started = Date()
        for index in 0 ..< count {
            let image = try autoreleasepool {
                context.setFillColor(CGColor(gray: 0.15, alpha: 1))
                context.fill(CGRect(x: 0, y: 0, width: width, height: height))
                context.setFillColor(CGColor(red: 0.2, green: 0.8, blue: 0.5, alpha: 1))
                context.fill(CGRect(x: index * 5 % 1500, y: index * 3 % 1500, width: 300, height: 300))
                guard let image = context.makeImage() else { throw VideoError.encoding }
                return image
            }
            _ = try await recorder.append(image, at: Double(index) / 30, cancellation: cancellation)
        }
        let result = try await recorder.finish(at: 600, cancellation: cancellation)
        return [
            "scope": "300 changing synthetic frames at 30 fps, 1920-square maximum size, then a static tail to the 600-second limit. Real H.264/MP4 output and AVFoundation inspection; no live screen, UI, sound, or clipboard. Not a full 10-minute real-time stress test.",
            "width": width, "height": height, "submitted_frames": count,
            "duration_seconds": result.duration, "encoded_bytes": result.byteCount,
            "write_and_finish_seconds": Date().timeIntervalSince(started),
            "physical_footprint_after_phase_mib": physicalFootprintMiB(),
        ]
    }

    private static func gifCapacity(workspace: URL) throws -> [String: Any] {
        let width = 1280, height = 1280, count = 300
        let first = workspace.appending(path: "frame-000000.rgba")
        var bytes = Data(count: width * height * 4)
        bytes.withUnsafeMutableBytes { raw in
            let pixels = raw.bindMemory(to: UInt8.self)
            for y in 0 ..< height {
                for x in 0 ..< width {
                    let index = (y * width + x) * 4
                    pixels[index] = UInt8((x / 5) % 256)
                    pixels[index + 1] = UInt8((y / 5) % 256)
                    pixels[index + 2] = UInt8(((x + y) / 7) % 256)
                    pixels[index + 3] = 255
                }
            }
        }
        try bytes.write(to: first)
        bytes = Data()
        // Hard links avoid writing 1.8 GiB for a memory/encoder capacity probe.
        // Each record still traverses the production native encoder and streamed container.
        for index in 1 ..< count {
            try FileManager.default.linkItem(at: first, to: workspace.appending(path: String(format: "frame-%06d.rgba", index)))
        }
        let frames = (0 ..< count).map { GIFFrameRecord(filename: String(format: "frame-%06d.rgba", $0), offset: Double($0) / 10) }
        let recording = GIFRecording(directory: workspace, width: width, height: height, frames: frames, duration: 30)
        let start = Date()
        let result = try GIFEncoder.encode(recording, cancellation: RecordingCancellation())
        return [
            "scope": "300 full-size native frames from one synthetic gradient, streamed GIF and full ImageIO frame inspection; no real screen, windows, input, or clipboard. Not a worst-case output-entropy or recording-I/O benchmark.",
            "width": width, "height": height, "frames": result.frameCount,
            "duration_seconds": result.duration, "encoded_bytes": result.byteCount,
            "encode_and_inspect_seconds": Date().timeIntervalSince(start),
            "physical_footprint_after_phase_mib": physicalFootprintMiB(),
        ]
    }

    @MainActor
    static func maximumCapacity(workspace: URL) throws -> [String: Any] {
        let store = try TileStore(width: 1500, sessionID: UUID(), rootURL: workspace.appending(path: "capacity"))
        for sequence in 0 ..< 40 {
            try autoreleasepool {
                let image = try makePage(width: 1500, height: 1000, rowOffset: sequence * 1000)
                guard let frame = RGBAFrame(image: image) else { throw ProbeError.invalidPixels }
                if sequence == 0 {
                    try store.appendFirstFrame(frame)
                } else {
                    _ = try store.appendBottomRows(from: frame, startY: 0, count: 1000, sequence: UInt64(sequence))
                }
            }
        }
        let started = ProcessInfo.processInfo.systemUptime
        let reconstructed = try store.renderImage()
        let snapshot = AnnotationRenderSnapshot(image: reconstructed, cropRect: CGRect(x: 0, y: 0, width: 1500, height: 40000), annotations: [], revision: 0)
        let rendered = try AnnotationRenderer.renderSynchronously(snapshot)
        let png = try OutputDeliveryService.encodePNGSynchronously(rendered)
        let board = NSPasteboard.withUniqueName()
        defer { board.clearContents(); board.releaseGlobally() }
        let publisher = ClipboardPublisher(assetStore: AssetStore(rootURL: workspace.appending(path: "assets")), pasteboard: board)
        _ = try publisher.publish(pngData: png, startedAt: Date())
        let elapsed = (ProcessInfo.processInfo.systemUptime - started) * 1000
        let beforeDecode = physicalFootprintMiB()
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil),
              decoded.width == 1500, decoded.height == 40000,
              board.pasteboardItems?.count == 1
        else { throw ProbeError.invalidPixels }
        for y in [0, 39999] {
            let rect = CGRect(x: 0, y: y, width: 64, height: 1)
            guard let expected = rendered.cropping(topLeftRect: rect), let actual = decoded.cropping(topLeftRect: rect),
                  RGBAFrame(image: expected)?.bytes == RGBAFrame(image: actual)?.bytes
            else { throw ProbeError.pixelMismatch }
        }
        return ["scope": "One synthetic maximum-capacity case, no GUI/SCK. Forty 1500x1000 tiles; no full-sized source retained. Decode and top/bottom strip checks occur after timing. Process peaks include validation. Not a P95 or an end-to-end resource acceptance.",
                "pixels": 60_000_000, "width": 1500, "height": 40000, "elapsed_ms": elapsed,
                "png_bytes": png.count, "top_bottom_strip_pixels_match": true,
                "physical_footprint_before_decode_mib": beforeDecode,
                "physical_footprint_after_phase_mib": physicalFootprintMiB()]
    }

    @MainActor
    static func ordinary(workspace: URL, highEntropy: Bool) throws -> [String: Any] {
        let ordinary = try makePage(width: 4000, height: 4000, highEntropy: highEntropy)
        let document = AnnotationDocument(image: ordinary)
        document.add(Annotation(content: .rectangle(rect: CGRect(x: 30, y: 40, width: 1200, height: 400), color: .red, lineWidth: 5)))
        document.add(Annotation(content: .text(rect: CGRect(x: 60, y: 80, width: 1000, height: 200), value: "截图性能验证 123", fontSize: 48, color: .black)))
        let snapshot = document.renderSnapshot()
        var samples: [Double] = []
        for iteration in 0 ..< 30 {
            try autoreleasepool {
                let board = NSPasteboard.withUniqueName()
                defer { board.releaseGlobally() }
                let store = AssetStore(rootURL: workspace.appending(path: "assets"))
                let publisher = ClipboardPublisher(assetStore: store, pasteboard: board)
                let started = ProcessInfo.processInfo.systemUptime
                let rendered = try AnnotationRenderer.renderSynchronously(snapshot)
                let png = try OutputDeliveryService.encodePNGSynchronously(rendered)
                let asset = try publisher.publish(pngData: png, startedAt: Date())
                samples.append((ProcessInfo.processInfo.systemUptime - started) * 1000)
                precondition(board.pasteboardItems?.count == 1)
                precondition(rendered.width == 4000 && rendered.height == 4000)
                if iteration == 0 {
                    guard let source = CGImageSourceCreateWithData(png as CFData, nil),
                          let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil),
                          RGBAFrame(image: decoded)?.bytes == RGBAFrame(image: rendered)?.bytes
                    else { throw ProbeError.pixelMismatch }
                }
                board.clearContents()
                // This private test board has been cleared. Remove only this
                // probe's published fixture; production discard intentionally
                // protects a currently published asset.
                try FileManager.default.removeItem(at: asset.directoryURL)
            }
        }
        var result = summary(highEntropy ? "ordinary_high_entropy_render_encode_private_publish" : "ordinary_pattern_render_encode_private_publish", samples: samples, pixels: 16_000_000)
        result["first_output_pixel_identical_to_render"] = true
        return result
    }

    @MainActor
    static func longPreview(workspace: URL) throws -> [String: Any] {
        let longImage = try makePage(width: 1500, height: 20000)
        guard let frame = RGBAFrame(image: longImage) else { throw ProbeError.invalidPixels }
        var samples: [Double] = []
        for _ in 0 ..< 20 {
            let store = try TileStore(width: 1500, sessionID: UUID(), rootURL: workspace.appending(path: "tiles"))
            try autoreleasepool {
                try store.appendFirstFrame(frame)
                let started = ProcessInfo.processInfo.systemUptime
                let reconstructed = try store.renderImage()
                let snapshot = AnnotationRenderSnapshot(image: reconstructed, cropRect: CGRect(x: 0, y: 0, width: 1500, height: 20000), annotations: [], revision: 0)
                let previewPixels = try AnnotationRenderer.renderSynchronously(snapshot)
                precondition(previewPixels.width == 1500 && previewPixels.height == 20000)
                samples.append((ProcessInfo.processInfo.systemUptime - started) * 1000)
            }
        }
        return summary("long_reconstruct_and_preview_pixels", samples: samples, pixels: 30_000_000)
    }

    @MainActor
    static func widePage(workspace: URL) async throws -> [String: Any] {
        let page = try makePage(width: 1000, height: 15000)
        let engine = LongCaptureEngine(sessionID: UUID(), workspaceRootURL: workspace.appending(path: "engine"))
        let first = try crop(page, y: 0)
        _ = await engine.consume(first)
        _ = await engine.consume(first)
        var offset = 0
        var accepted = 0
        var samples: [Double] = []
        while offset < 14000 {
            offset = min(14000, offset + 350)
            let next = try crop(page, y: offset)
            let started = ProcessInfo.processInfo.systemUptime
            let update = await engine.consume(next)
            samples.append((ProcessInfo.processInfo.systemUptime - started) * 1000)
            guard case .appended = update else { throw ProbeError.unexpectedMatch }
            accepted += 1
        }
        let final = try engine.finish()
        guard RGBAFrame(image: final)?.bytes == RGBAFrame(image: page)?.bytes else { throw ProbeError.pixelMismatch }
        var wide = summary("wide_match_and_append", samples: samples, pixels: 1_000_000)
        wide["result_width"] = final.width
        wide["result_height"] = final.height
        wide["accepted_steps"] = accepted
        wide["output_pixel_identical_to_source"] = true
        return wide
    }

    @MainActor
    static func watermarks() throws -> [String: Any] {
        var measurements: [[String: Any]] = []
        for (width, height) in [(4000, 4000), (1200, 50000)] {
            let measurement: [String: Any] = try autoreleasepool {
                guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else { throw ProbeError.invalidPixels }
                context.setFillColor(CGColor(gray: 1, alpha: 1))
                context.fill(CGRect(x: 0, y: 0, width: width, height: height))
                guard let image = context.makeImage() else { throw ProbeError.invalidPixels }
                let watermark = WatermarkSelection(text: "Alice · @example · Internal use only", style: WatermarkStyle(mode: .tiled, opacity: 0.15, angle: -30))
                let snapshot = AnnotationRenderSnapshot(image: image, cropRect: CGRect(x: 0, y: 0, width: width, height: height), annotations: [], revision: 0, watermark: watermark)
                let before = physicalFootprintMiB()
                let start = ProcessInfo.processInfo.systemUptime
                let output = try AnnotationRenderer.renderSynchronously(snapshot)
                let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1000
                let after = physicalFootprintMiB()
                for y in [0, height / 2, height - 1000] {
                    guard let strip = output.cropping(topLeftRect: CGRect(x: 0, y: y, width: width, height: 1000)),
                          let frame = RGBAFrame(image: strip), frame.bytes.contains(where: { $0 < 245 })
                    else { throw ProbeError.pixelMismatch }
                }
                return ["width": width, "height": height, "pixels": width * height, "render_ms": elapsed,
                        "physical_footprint_before_mib": before, "physical_footprint_after_mib": after,
                        "top_middle_bottom_contain_watermark": true]
            }
            measurements.append(measurement)
        }
        return ["scope": "One synthetic sample per size. Production tiled text render only; no screen capture, windows, clipboard, or PNG encoding. Timing excludes validation. Resource peaks include source/context and strip checks; not P95 or GUI latency.", "measurements": measurements]
    }

    static func physicalFootprintMiB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }

    static func summary(_ name: String, samples: [Double], pixels: Int) -> [String: Any] {
        let sorted = samples.sorted()
        return ["name": name, "samples_ms": samples, "sample_count": samples.count, "pixels": pixels,
                "mean_ms": samples.reduce(0, +) / Double(samples.count),
                "p95_ms": sorted[Int(ceil(Double(samples.count) * 0.95)) - 1], "maximum_ms": sorted.last!]
    }

    static func crop(_ page: CGImage, y: Int) throws -> CGImage {
        guard let image = page.cropping(topLeftRect: CGRect(x: 0, y: y, width: 1000, height: 1000)) else { throw ProbeError.invalidPixels }
        return image
    }

    static func makePage(width: Int, height: Int, highEntropy: Bool = false, rowOffset: Int = 0) throws -> CGImage {
        var bytes = Data(count: width * height * 4)
        bytes.withUnsafeMutableBytes { raw in
            let buffer = raw.bindMemory(to: UInt8.self)
            var randomState: UInt64 = 0x123_4567_89AB_CDEF
            for localY in 0 ..< height {
                let y = localY + rowOffset
                for x in 0 ..< width {
                    let index = (localY * width + x) * 4
                    if highEntropy {
                        randomState ^= randomState << 13
                        randomState ^= randomState >> 7
                        randomState ^= randomState << 17
                        buffer[index] = UInt8(truncatingIfNeeded: randomState)
                        buffer[index + 1] = UInt8(truncatingIfNeeded: randomState >> 8)
                        buffer[index + 2] = UInt8(truncatingIfNeeded: randomState >> 16)
                    } else {
                        buffer[index] = UInt8(truncatingIfNeeded: y + x * 11)
                        buffer[index + 1] = UInt8(truncatingIfNeeded: (y >> 8) + x * 7)
                        buffer[index + 2] = UInt8(truncatingIfNeeded: y * 13 + x * 3)
                    }
                    buffer[index + 3] = 255
                }
            }
        }
        guard let provider = CGDataProvider(data: bytes as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGBitmapInfo.byteOrder32Big.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { throw ProbeError.invalidPixels }
        return image
    }

    enum ProbeError: Error { case invalidPixels, unexpectedMatch, pixelMismatch }
}
