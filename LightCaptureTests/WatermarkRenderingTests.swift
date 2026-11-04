import AppKit
@testable import LightCapture
import XCTest

@MainActor
final class WatermarkRenderingTests: XCTestCase {
    func testWatermarkOnlyOutputIsVisibleAndAnchorsToAllNinePositions() throws {
        for anchor in WatermarkAnchor.allCases {
            var selection = watermark()
            selection.style.anchor = anchor
            let output = try render(selection, size: CGSize(width: 400, height: 300))
            let bounds = try darkBounds(output)
            switch anchor.column {
            case 0: XCTAssertLessThan(bounds.maxX, 150)
            case 1: XCTAssertEqual(bounds.midX, 200, accuracy: 4)
            default: XCTAssertGreaterThan(bounds.minX, 250)
            }
            switch anchor.row {
            case 0: XCTAssertLessThan(bounds.maxY, 100)
            case 1: XCTAssertEqual(bounds.midY, 150, accuracy: 8)
            default: XCTAssertGreaterThan(bounds.minY, 200)
            }
        }
    }

    func testCropOriginDoesNotMoveWatermarkAndRemovingItRestoresOriginal() throws {
        let base = try image(width: 700, height: 600)
        let document = AnnotationDocument(image: base, cropRect: CGRect(x: 125, y: 80, width: 400, height: 300))
        let original = try AnnotationRenderer.renderSynchronously(document.renderSnapshot())
        document.setWatermark(watermark())
        let cropped = try AnnotationRenderer.renderSynchronously(document.renderSnapshot())
        XCTAssertEqual(RGBAFrame(image: cropped)?.bytes, try RGBAFrame(image: render(watermark(), size: CGSize(width: 400, height: 300)))?.bytes)
        document.setWatermark(nil)
        let restored = try AnnotationRenderer.renderSynchronously(document.renderSnapshot())
        XCTAssertEqual(RGBAFrame(image: restored)?.bytes, RGBAFrame(image: original)?.bytes)
    }

    func testOpacityAndRotationAffectPixelsWithoutChangingDimensions() throws {
        var selection = watermark()
        selection.style.anchor = .center
        let opaque = try render(selection, size: CGSize(width: 400, height: 300))
        selection.style.opacity = 0.15
        let faint = try render(selection, size: CGSize(width: 400, height: 300))
        XCTAssertGreaterThan(try minimumChannel(faint), try minimumChannel(opaque))
        selection.style.angle = -30
        let rotated = try render(selection, size: CGSize(width: 400, height: 300))
        XCTAssertGreaterThan(try darkBounds(rotated).height, try darkBounds(faint).height)
        XCTAssertEqual(rotated.width, 400)
        XCTAssertEqual(rotated.height, 300)
    }

    func testTilingCoversTopMiddleAndBottomAndUsesWidthForLongImageSizing() throws {
        var selection = watermark()
        selection.style.mode = .tiled
        selection.style.angle = -30
        let size = CGSize(width: 320, height: 4000)
        let output = try render(selection, size: size)
        for rect in [CGRect(x: 0, y: 0, width: 320, height: 320), CGRect(x: 0, y: 1800, width: 320, height: 320), CGRect(x: 0, y: 3680, width: 320, height: 320)] {
            XCTAssertNoThrow(try darkBounds(XCTUnwrap(output.cropping(to: rect))))
        }
        let long = try WatermarkLayout(selection: selection, outputSize: size)
        let short = try WatermarkLayout(selection: selection, outputSize: CGSize(width: 320, height: 500))
        XCTAssertEqual(long.fontSize, short.fontSize)
        XCTAssertEqual(long.unitSize, short.unitSize)
    }

    func testPreviewDrawsSamePixelsAsOutputInFlippedCoordinates() throws {
        let selection = watermark()
        let document = try AnnotationDocument(image: image(width: 400, height: 300), watermark: selection)
        let canvas = AnnotationCanvasView(document: document)
        canvas.fillsBounds = true
        canvas.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        let window = NSWindow(contentRect: canvas.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = canvas
        defer { window.close() }
        let bitmap = try XCTUnwrap(canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds))
        canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
        let preview = try XCTUnwrap(bitmap.cgImage)
        let output = try AnnotationRenderer.renderSynchronously(document.renderSnapshot())
        let a = try darkBounds(preview)
        let b = try darkBounds(output)
        let scale = CGFloat(preview.width) / CGFloat(output.width)
        XCTAssertEqual(a.midX / scale, b.midX, accuracy: 2)
        XCTAssertEqual(a.midY / scale, b.midY, accuracy: 2)
        XCTAssertEqual(a.width / scale, b.width, accuracy: 2)
        XCTAssertEqual(a.height / scale, b.height, accuracy: 2)
    }

    func testDocumentHistoryUsesInitialDefaultAsBaselineAndSnapshotIsImmutable() throws {
        let initial = watermark()
        let document = try AnnotationDocument(image: image(width: 400, height: 300), watermark: initial)
        XCTAssertFalse(document.canUndo)
        XCTAssertFalse(document.hasUncommittedChanges)
        let snapshot = document.renderSnapshot()
        document.setWatermark(nil)
        XCTAssertTrue(document.hasUncommittedChanges)
        XCTAssertTrue(document.undo())
        XCTAssertEqual(document.watermark, initial)
        XCTAssertFalse(document.hasUncommittedChanges)
        XCTAssertTrue(document.redo())
        XCTAssertNil(document.watermark)
        XCTAssertEqual(snapshot.watermark, initial)
        XCTAssertNoThrow(try darkBounds(AnnotationRenderer.renderSynchronously(snapshot)))
    }

    func testTooSmallAndInvalidStylesFailInsteadOfSilentlyDroppingWatermark() throws {
        XCTAssertThrowsError(try render(watermark(), size: CGSize(width: 2, height: 2)))
        var invalid = watermark()
        invalid.style.opacity = .infinity
        XCTAssertThrowsError(try render(invalid, size: CGSize(width: 400, height: 300)))
        let base = try image(width: 2, height: 2)
        XCTAssertNoThrow(try AnnotationRenderer.renderSynchronously(AnnotationDocument(image: base).renderSnapshot()))
    }

    func testMultilineTextShrinksToFitRotatedSingleWatermark() throws {
        var selection = watermark()
        selection.text = "署名 Alice\r\n账号 @sample\r\n仅供内部审阅"
        selection.style.fontRatio = 0.2
        selection.style.angle = 45
        let output = try render(selection, size: CGSize(width: 320, height: 240))
        let bounds = try darkBounds(output)
        XCTAssertGreaterThan(bounds.minX, 0)
        XCTAssertGreaterThan(bounds.minY, 0)
        XCTAssertLessThan(bounds.maxX, 320)
        XCTAssertLessThan(bounds.maxY, 240)
    }

    private func watermark() -> WatermarkSelection {
        var style = WatermarkStyle()
        style.opacity = 1
        style.fontRatio = 0.08
        style.color = WatermarkColor(red: 0, green: 0, blue: 0)
        return WatermarkSelection(text: "Alice", style: style)
    }

    private func render(_ selection: WatermarkSelection, size: CGSize) throws -> CGImage {
        try AnnotationRenderer.renderSynchronously(AnnotationDocument(image: image(width: Int(size.width), height: Int(size.height)), watermark: selection).renderSnapshot())
    }

    private func image(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    private func darkBounds(_ image: CGImage) throws -> CGRect {
        let frame = try XCTUnwrap(RGBAFrame(image: image))
        var result = CGRect.null
        for y in 0 ..< frame.height {
            for x in 0 ..< frame.width where frame.bytes[(y * frame.width + x) * 4] < 245 {
                result = result.union(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        XCTAssertFalse(result.isNull)
        return result
    }

    private func minimumChannel(_ image: CGImage) throws -> UInt8 {
        let frame = try XCTUnwrap(RGBAFrame(image: image))
        return stride(from: 0, to: frame.bytes.count, by: 4).map { frame.bytes[$0] }.min() ?? 255
    }
}
