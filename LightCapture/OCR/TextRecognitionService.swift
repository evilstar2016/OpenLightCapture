import CoreGraphics
import CoreML
import Foundation
import ImageIO
import OSLog
import UniformTypeIdentifiers
import Vision

enum TextRecognitionError: LocalizedError {
    case unsupportedLanguages
    case imageTooLarge
    case incompleteBoundary
    case failed

    var errorDescription: String? {
        switch self {
        case .unsupportedLanguages: L10n.ocrUnsupportedLanguages
        case .imageTooLarge: L10n.ocrImageTooLarge
        case .incompleteBoundary: L10n.ocrIncompleteBoundary
        case .failed: L10n.ocrFailed
        }
    }
}

struct OCRLine {
    let text: String
    let bounds: CGRect
    let confidence: Float
    let clipped: Bool
}

struct OCRResult: Codable {
    let text: String
    let lineCount: Int
    let tileCount: Int
}

enum OCRExecution {
    /// Keep the compatibility revision within each isolated macOS 27 session.
    /// Revision selection alone does not repair a poisoned persistent runtime.
    static var requestRevision: Int {
        if #available(macOS 27.0, *) { return VNRecognizeTextRequestRevision2 }
        return VNRecognizeTextRequestRevision3
    }

    /// At most one CPU retry. Cancellation never starts another attempt.
    static func run<Result>(preferCPU: Bool, checkCancellation: () throws -> Void, operation: (Bool) throws -> Result) throws -> Result {
        try checkCancellation()
        if preferCPU { return try operation(true) }
        do {
            return try operation(false)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try checkCancellation()
            return try operation(true)
        }
    }
}

enum OCRLayout {
    static func regions(width: Int, height: Int) throws -> [CGRect] {
        guard CaptureImageLimits.contains(width: width, height: height) else { throw TextRecognitionError.imageTooLarge }
        let tileHeight = min(2048, 8_000_000 / width)
        guard tileHeight >= min(height, 64) else { throw TextRecognitionError.imageTooLarge }
        let overlap = min(128, tileHeight / 4)
        var regions: [CGRect] = []
        var y = 0
        while y < height {
            let length = min(tileHeight, height - y)
            regions.append(CGRect(x: 0, y: y, width: width, height: length))
            if y + length == height { break }
            y += tileHeight - overlap
        }
        return regions
    }

    static func uniqueLines(_ lines: [OCRLine]) -> [OCRLine] {
        var result: [OCRLine] = []
        var buckets: [Int: [Int]] = [:]
        for line in lines.sorted(by: { $0.bounds.minY < $1.bounds.minY }) {
            guard !line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  line.bounds.width > 0, line.bounds.height > 0 else { continue }
            let first = Int(floor(line.bounds.minY / 32))
            let last = Int(floor(line.bounds.maxY / 32))
            let candidates = Set((first ... last).flatMap { buckets[$0] ?? [] })
            if let index = candidates.sorted().first(where: { isDuplicate(line, result[$0]) }) {
                let previous = result[index]
                if (previous.clipped && !line.clipped)
                    || (previous.clipped == line.clipped && line.confidence > previous.confidence)
                    || (previous.clipped == line.clipped && line.confidence == previous.confidence && line.text.count > previous.text.count)
                {
                    result[index] = line
                    for key in first ... last {
                        buckets[key, default: []].append(index)
                    }
                }
            } else {
                let index = result.count
                result.append(line)
                for key in first ... last {
                    buckets[key, default: []].append(index)
                }
            }
        }
        return result
    }

    static func text(from lines: [OCRLine]) -> String {
        let sorted = lines.sorted {
            if $0.bounds.minY != $1.bounds.minY { return $0.bounds.minY < $1.bounds.minY }
            return $0.bounds.minX < $1.bounds.minX
        }
        var rows: [[OCRLine]] = []
        for line in sorted {
            if let last = rows.last, let anchor = last.first,
               verticalOverlap(line.bounds, anchor.bounds) >= 0.6,
               abs(line.bounds.midY - anchor.bounds.midY) <= min(line.bounds.height, anchor.bounds.height) * 0.4
            {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows.map { row in
            let chunks = row.sorted { $0.bounds.minX < $1.bounds.minX }
            var value = ""
            var previous: OCRLine?
            for line in chunks {
                if let previous, line.bounds.minX - previous.bounds.maxX > min(previous.bounds.height, line.bounds.height) * 0.2 {
                    value += " "
                }
                value += line.text
                previous = line
            }
            return value
        }.joined(separator: "\n")
    }

    private static func verticalOverlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        max(0, min(a.maxY, b.maxY) - max(a.minY, b.minY)) / min(a.height, b.height)
    }

    private static func isDuplicate(_ a: OCRLine, _ b: OCRLine) -> Bool {
        let overlap = a.bounds.intersection(b.bounds)
        guard !overlap.isNull, verticalOverlap(a.bounds, b.bounds) >= 0.65 else { return false }
        let area = overlap.width * overlap.height
        let coverage = area / min(a.bounds.width * a.bounds.height, b.bounds.width * b.bounds.height)
        let widthCoverage = overlap.width / max(a.bounds.width, b.bounds.width)
        return coverage >= 0.7 && widthCoverage >= 0.65
    }
}

/// Only the cancellation flag and the active request/process cross executors.
/// All request configuration and result reads stay on the serial worker.
final class OCRCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var request: VNRecognizeTextRequest?
    private var process: Process?

    func check() throws {
        if lock.withLock({ cancelled }) { throw CancellationError() }
    }

    func install(_ request: VNRecognizeTextRequest?) throws {
        let shouldCancel = lock.withLock {
            self.request = request
            return cancelled
        }
        if shouldCancel {
            request?.cancel()
            throw CancellationError()
        }
    }

    func cancel() {
        let current = lock.withLock {
            cancelled = true
            if let process, process.isRunning { process.terminate() }
            return request
        }
        current?.cancel()
    }

    func installProcess(_ process: Process?) throws {
        try lock.withLock {
            self.process = process
            if cancelled {
                if let process, process.isRunning { process.terminate() }
                throw CancellationError()
            }
        }
    }
}

/// One local worker per OCR session. The same signed executable is launched
/// before AppKit/shortcuts/clipboard initialization; no extra app or permission.
enum OCRWorkerProcess {
    static let argument = "--ocr-worker"
    static var workspacePrefix: String {
        "OpenLightCaptureOCR-\(ProcessInfo.processInfo.processIdentifier)-"
    }

    static var isWorker: Bool {
        CommandLine.arguments.dropFirst().first == argument
    }

    private struct Response: Codable {
        let result: OCRResult?
        let failure: String?
    }

    /// Called before NSApplication is created. A fresh worker never inherits
    /// Vision's stale in-memory model cache from an earlier user session.
    static func runIfRequested() {
        guard isWorker else { return }
        guard CommandLine.arguments.count == 3 else { exit(2) }
        let input = URL(fileURLWithPath: CommandLine.arguments[2])
        Task.detached {
            let response: Response
            do {
                guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
                else { throw TextRecognitionError.failed }
                let snapshot = AnnotationRenderSnapshot(image: image, cropRect: CGRect(x: 0, y: 0, width: image.width, height: image.height),
                                                        annotations: [], revision: 0)
                let result = try await TextRecognitionService.recognize(snapshot: snapshot)
                response = Response(result: result, failure: nil)
            } catch {
                let failure = switch error as? TextRecognitionError {
                case .unsupportedLanguages: "unsupportedLanguages"
                case .imageTooLarge: "imageTooLarge"
                case .incompleteBoundary: "incompleteBoundary"
                default: "failed"
                }
                response = Response(result: nil, failure: failure)
            }
            do {
                try FileHandle.standardOutput.write(contentsOf: JSONEncoder().encode(response))
                exit(0)
            } catch {
                exit(1)
            }
        }
        dispatchMain()
    }

    fileprivate static func recognize(image: CGImage, cancellation: OCRCancellation) throws -> OCRResult {
        try cancellation.check()
        let root = FileManager.default.temporaryDirectory.appending(path: "\(workspacePrefix)\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appending(path: "input.png")
        guard FileManager.default.createFile(atPath: input.path, contents: nil, attributes: [.posixPermissions: 0o600]),
              let destination = CGImageDestinationCreateWithURL(input as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw TextRecognitionError.failed }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw TextRecognitionError.failed }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: input.path)
        try cancellation.check()
        let process = Process()
        guard let executable = Bundle.main.executableURL else { throw TextRecognitionError.failed }
        process.executableURL = executable
        process.arguments = [argument, input.path]
        let output = Pipe()
        defer { try? output.fileHandleForReading.close() }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer {
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
            try? cancellation.installProcess(nil)
        }
        try cancellation.installProcess(process)
        // Drain while running: a long text result can exceed the pipe buffer.
        let data = try output.fileHandleForReading.readToEnd() ?? Data()
        process.waitUntilExit()
        try cancellation.check()
        guard process.terminationStatus == 0 else { throw TextRecognitionError.failed }
        let response = try JSONDecoder().decode(Response.self, from: data)
        if let result = response.result { return result }
        switch response.failure {
        case "unsupportedLanguages": throw TextRecognitionError.unsupportedLanguages
        case "imageTooLarge": throw TextRecognitionError.imageTooLarge
        case "incompleteBoundary": throw TextRecognitionError.incompleteBoundary
        default: throw TextRecognitionError.failed
        }
    }
}

enum TextRecognitionService {
    private static let worker = OCRRecognitionWorker()

    static func recognize(snapshot: AnnotationRenderSnapshot) async throws -> OCRResult {
        let cancellation = OCRCancellation()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await worker.recognize(snapshot: snapshot, cancellation: cancellation)
        } onCancel: {
            cancellation.cancel()
        }
    }
}

/// Synchronous Vision work is serialized off MainActor, including cancelled work
/// that has not yet returned from the framework.
private actor OCRRecognitionWorker {
    private var preferCPU = false
    private let logger = Logger(subsystem: "io.github.evilstar2016.openlightcapture", category: "OCR")

    func recognize(snapshot: AnnotationRenderSnapshot, cancellation: OCRCancellation) throws -> OCRResult {
        try cancellation.check()
        let image = try autoreleasepool { try AnnotationRenderer.renderSynchronously(snapshot) }
        try cancellation.check()
        if #available(macOS 27.0, *), !OCRWorkerProcess.isWorker {
            return try OCRWorkerProcess.recognize(image: image, cancellation: cancellation)
        }
        let regions = try OCRLayout.regions(width: image.width, height: image.height)
        var lines: [OCRLine] = []
        for region in regions {
            lines += try recognizeRegion(region, in: image, cancellation: cancellation)
        }
        // Re-read clipped seam lines in a centered, bounded region. A genuine
        // top/bottom crop edge is not treated as a tile seam.
        let clipped = OCRLayout.uniqueLines(lines).filter(\.clipped)
        var repairedBands = Set<Int>()
        let bandHeight = Int(regions[0].height)
        for line in clipped {
            try cancellation.check()
            let y = max(0, min(image.height - min(image.height, bandHeight), Int(line.bounds.midY) - bandHeight / 2))
            guard repairedBands.insert(y / 32).inserted else { continue }
            let region = CGRect(x: 0, y: y, width: image.width, height: min(bandHeight, image.height - y))
            lines += try recognizeRegion(region, in: image, cancellation: cancellation)
        }
        try cancellation.check()
        let unique = OCRLayout.uniqueLines(lines)
        guard !unique.contains(where: \.clipped) else { throw TextRecognitionError.incompleteBoundary }
        return OCRResult(text: OCRLayout.text(from: unique), lineCount: unique.count, tileCount: regions.count + repairedBands.count)
    }

    private func recognizeRegion(_ region: CGRect, in image: CGImage, cancellation: OCRCancellation) throws -> [OCRLine] {
        try cancellation.check()
        return try autoreleasepool {
            guard let tile = image.cropping(topLeftRect: region) else { throw TextRecognitionError.failed }
            defer { try? cancellation.install(nil) }
            let request: VNRecognizeTextRequest
            do {
                request = try OCRExecution.run(preferCPU: preferCPU, checkCancellation: cancellation.check) { cpuOnly in
                    let request = try makeRequest(cpuOnly: cpuOnly)
                    try cancellation.install(request)
                    do {
                        try VNImageRequestHandler(cgImage: tile, orientation: .up).perform([request])
                    } catch {
                        let diagnostic = error as NSError
                        logger.error("Vision OCR failed: revision=\(request.revision, privacy: .public), cpu=\(cpuOnly, privacy: .public), domain=\(diagnostic.domain, privacy: .public), code=\(diagnostic.code, privacy: .public)")
                        throw error
                    }
                    // Do not retry a broken accelerator for every tile or image.
                    if cpuOnly { preferCPU = true }
                    return request
                }
            } catch {
                try cancellation.check()
                if let error = error as? TextRecognitionError { throw error }
                throw TextRecognitionError.failed
            }
            try cancellation.check()
            return (request.results ?? []).compactMap { observation in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                let box = observation.boundingBox
                let localY = (1 - box.maxY) * region.height
                let bounds = CGRect(x: box.minX * region.width, y: localY + region.minY,
                                    width: box.width * region.width, height: box.height * region.height)
                let clipped = (region.minY > 0 && localY <= 2)
                    || (region.maxY < CGFloat(image.height) && localY + bounds.height >= region.height - 2)
                return OCRLine(text: candidate.string, bounds: bounds, confidence: candidate.confidence, clipped: clipped)
            }
        }
    }

    private func makeRequest(cpuOnly: Bool) throws -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.revision = OCRExecution.requestRevision
        request.recognitionLevel = .accurate
        request.minimumTextHeight = 0
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = false
        let languages = ["zh-Hans", "en-US"]
        let supported = try request.supportedRecognitionLanguages()
        guard languages.allSatisfy(supported.contains) else { throw TextRecognitionError.unsupportedLanguages }
        request.recognitionLanguages = languages
        if cpuOnly {
            if #available(macOS 14.0, *) {
                let stages = try request.supportedComputeStageDevices
                guard !stages.isEmpty else { throw TextRecognitionError.failed }
                for (stage, devices) in stages {
                    guard let cpu = devices.first(where: { if case .cpu = $0 { true } else { false } }) else {
                        throw TextRecognitionError.failed
                    }
                    request.setComputeDevice(cpu, for: stage)
                }
            } else {
                request.usesCPUOnly = true
            }
        }
        return request
    }
}
