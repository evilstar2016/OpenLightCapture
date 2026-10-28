import AppKit
import CoreGraphics
import ImageIO
@testable import LightCapture
import UniformTypeIdentifiers
import XCTest

final class AssetStoreTests: XCTestCase {
    func testStagedAssetIsARealPNGAndOldPublishedAssetReapsOnlyAfterLease() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let png = makePNG()
        let createdAt = Date()
        let values = try await MainActor.run { () throws -> (URL, URL, URL) in
            let store = AssetStore(rootURL: root)
            let first = try store.prepare(pngData: png, startedAt: createdAt)
            try store.markPublished(first, changeCount: 1)
            let second = try store.prepare(pngData: png, startedAt: createdAt)
            try store.markPublished(second, changeCount: 2)
            store.reapRetiredAssets(now: Date().addingTimeInterval(899))
            XCTAssertTrue(FileManager.default.fileExists(atPath: first.imageURL.path), "被替换的资产至少保留十五分钟")
            store.reapRetiredAssets(now: Date().addingTimeInterval(901))
            return (first.imageURL, first.directoryURL, second.imageURL)
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: values.0.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: values.1.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: values.2.path))
        XCTAssertNotNil(CGImageSourceCreateWithURL(values.2 as CFURL, nil))
    }

    func testInvalidPNGDoesNotCreateAssetDirectory() async {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let error = await MainActor.run { () -> Error? in
            let store = AssetStore(rootURL: root)
            do {
                _ = try store.prepare(pngData: Data([0, 1, 2]), startedAt: Date())
                return nil
            } catch {
                return error
            }
        }

        XCTAssertTrue(error is AssetStoreError)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testFilenameAddsExplicitDuplicateIndex() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(FilenamePolicy.screenshotName(startedAt: date).hasSuffix(".png"))
        XCTAssertTrue(FilenamePolicy.screenshotName(startedAt: date, copyIndex: 2).hasSuffix(" (2).png"))
    }

    @MainActor
    func testAssetRootCannotRedirectWritesThroughASymbolicLink() throws {
        let parent = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: parent) }
        let outside = parent.appending(path: "outside", directoryHint: .isDirectory)
        let root = parent.appending(path: "Assets", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root, withDestinationURL: outside)
        XCTAssertThrowsError(try AssetStore(rootURL: root).prepare(pngData: makePNG(), startedAt: Date()))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }

    func testAssetFilesUseOwnerOnlyPermissions() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let png = makePNG()
        let urls = try await MainActor.run { () throws -> [URL] in
            let asset = try AssetStore(rootURL: root).prepare(pngData: png, startedAt: Date())
            return [asset.directoryURL, asset.imageURL, asset.directoryURL.appending(path: "asset.json")]
        }
        let attributes = try urls.map { try FileManager.default.attributesOfItem(atPath: $0.path) }
        XCTAssertEqual(((attributes[0][.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o777, 0o700)
        XCTAssertEqual(((attributes[1][.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o777, 0o600)
        XCTAssertEqual(((attributes[2][.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o777, 0o600)
    }

    @MainActor
    func testCancelledEncodingCannotPublishOrReplaceTheClipboard() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("原剪贴板", forType: .string)
        let originalChangeCount = pasteboard.changeCount
        let png = makePNG()
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let gate = TestPNGEncodingGate()
        let sessions = CaptureSessionCoordinator()
        let session = try XCTUnwrap(sessions.begin(mode: .normal, targetProcessID: nil))
        let service = OutputDeliveryService(assetStore: AssetStore(rootURL: root), pasteboard: pasteboard, encoder: { _ in await gate.encode() })
        let operation = Task { @MainActor in
            await service.copy(image, startedAt: session.startedAt) {
                sessions.isCurrent(sessionID: session.id, generation: session.generation)
            }
        }
        await gate.waitUntilStarted()
        _ = sessions.cancel(sessionID: session.id, generation: session.generation)
        _ = sessions.begin(mode: .normal, targetProcessID: nil)
        await gate.finish(with: png)
        let published = await operation.value
        XCTAssertFalse(published)
        XCTAssertEqual(pasteboard.changeCount, originalChangeCount)
        XCTAssertEqual(pasteboard.string(forType: .string), "原剪贴板")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    @MainActor
    func testOutputPublishesOneRealImageAndFileThatSurviveStoreRestart() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let source = try XCTUnwrap(CGImageSourceCreateWithData(makePNG() as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let store = AssetStore(rootURL: root)
        let service = OutputDeliveryService(assetStore: store, pasteboard: pasteboard)
        let published = await service.copy(image, startedAt: Date())
        XCTAssertTrue(published)
        XCTAssertEqual(pasteboard.pasteboardItems?.count, 1)
        let imageData = try XCTUnwrap(pasteboard.data(forType: AssetStore.pngPasteboardType))
        let fileString = try XCTUnwrap(pasteboard.string(forType: .fileURL))
        let fileURL = try XCTUnwrap(URL(string: fileString))
        XCTAssertEqual(try Data(contentsOf: fileURL), imageData)
        let decodedSource = try XCTUnwrap(CGImageSourceCreateWithData(imageData as CFData, nil))
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(decodedSource, 0, nil))
        XCTAssertEqual(RGBAFrame(image: decoded)?.bytes, RGBAFrame(image: image)?.bytes)
        let restartedStore = AssetStore(rootURL: root)
        restartedStore.startMaintenance(pasteboard: pasteboard)
        defer { restartedStore.stopMaintenance() }
        restartedStore.reapRetiredAssets(now: Date().addingTimeInterval(86400))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "当前剪贴板引用必须在退出/重启后继续有效")
    }

    func testPNGEncodingDropsOnlyFullyOpaqueAlphaAndPreservesPixels() async throws {
        try await verifyPNGEncoding(pixels: [255, 32, 16, 255, 16, 32, 255, 255, 20, 220, 80, 255, 255, 240, 10, 255], hasAlpha: false)
    }

    func testPNGEncodingPreservesRealTransparencyAndPixels() async throws {
        try await verifyPNGEncoding(pixels: [0, 0, 0, 0, 64, 32, 16, 128, 20, 60, 40, 64, 255, 240, 10, 255], hasAlpha: true)
    }

    func testPNGEncodingDropsOpaqueBGRACaptureAlphaAndPreservesPixels() async throws {
        try await verifyPNGEncoding(pixels: [16, 32, 255, 255, 255, 32, 16, 255, 80, 220, 20, 255, 10, 240, 255, 255], hasAlpha: false,
                                    bitmapInfo: CGBitmapInfo.byteOrder32Little.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)))
    }

    func testPNGEncodingPreservesBGRACaptureTransparencyAndPixels() async throws {
        try await verifyPNGEncoding(pixels: [0, 0, 0, 0, 16, 32, 64, 128, 40, 60, 20, 64, 10, 240, 255, 255], hasAlpha: true,
                                    bitmapInfo: CGBitmapInfo.byteOrder32Little.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)))
    }

    private func verifyPNGEncoding(pixels: [UInt8], hasAlpha: Bool,
                                   bitmapInfo: CGBitmapInfo = CGBitmapInfo.byteOrder32Big.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue))) async throws
    {
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        let image = try XCTUnwrap(CGImage(width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: bitmapInfo,
                                          provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let png = try await OutputDeliveryService.encodePNG(image)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
        XCTAssertEqual(properties[kCGImagePropertyHasAlpha as String] as? Bool ?? false, hasAlpha)
        XCTAssertEqual(RGBAFrame(image: decoded)?.bytes, RGBAFrame(image: image)?.bytes)
    }

    private func makePNG() -> Data {
        let bytes = Data([255, 32, 16, 255, 16, 32, 255, 255, 20, 220, 80, 255, 255, 240, 10, 255])
        let provider = CGDataProvider(data: bytes as CFData)!
        let info = CGBitmapInfo.byteOrder32Big.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = CGImage(
            width: 2,
            height: 2,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: 8,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: info,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
        let destinationData = NSMutableData()
        let destination = CGImageDestinationCreateWithData(destinationData, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        precondition(CGImageDestinationFinalize(destination))
        return destinationData as Data
    }
}

private actor TestPNGEncodingGate {
    private var didStart = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var resultWaiter: CheckedContinuation<Data, Never>?

    func encode() async -> Data {
        await withCheckedContinuation { continuation in
            resultWaiter = continuation
            didStart = true
            startWaiter?.resume()
            startWaiter = nil
        }
    }

    func waitUntilStarted() async {
        if didStart { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func finish(with data: Data) {
        resultWaiter?.resume(returning: data)
        resultWaiter = nil
    }
}
