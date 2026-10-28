import AppKit
import CoreGraphics
@testable import LightCapture
import XCTest

@MainActor
final class AnnotationDraggingTests: XCTestCase {
    func testEveryAnnotationCanBeMovedWithoutChangingTheActiveAnnotationTool() throws {
        let rect = CGRect(x: 40, y: 40, width: 60, height: 60)
        let contents: [AnnotationContent] = [
            .rectangle(rect: rect, color: .red, lineWidth: 3),
            .ellipse(rect: rect, color: .black, lineWidth: 5),
            .arrow(start: rect.origin, end: CGPoint(x: 100, y: 100), color: .red, lineWidth: 4),
            .brush(points: [rect.origin, CGPoint(x: 100, y: 100)], color: .black, lineWidth: 6),
            .text(rect: rect, value: "可移动", fontSize: 22, color: .red),
            .mosaic(rect: rect, blockSize: 12),
        ]
        for tool in AnnotationTool.allCases where tool != .crop {
            for content in contents {
                let canvas = try makeCanvas()
                canvas.tool = tool
                let original = Annotation(content: content)
                canvas.document.add(original)
                var changes = 0
                canvas.onDocumentChange = { changes += 1 }
                try canvas.mouseDown(with: event(.leftMouseDown, at: CGPoint(x: 60, y: 60), on: canvas))
                try canvas.mouseDragged(with: event(.leftMouseDragged, at: CGPoint(x: 65, y: 62), on: canvas))
                try canvas.mouseDragged(with: event(.leftMouseDragged, at: CGPoint(x: 80, y: 70), on: canvas))
                XCTAssertEqual(canvas.document.annotations, [original], "拖动预览不能提前修改文档")
                try canvas.mouseUp(with: event(.leftMouseUp, at: CGPoint(x: 80, y: 70), on: canvas))
                let moved = original.translated(dx: 20, dy: 10)
                XCTAssertEqual(canvas.document.annotations, [moved], "\(tool): \(content)")
                XCTAssertEqual(canvas.tool, tool)
                XCTAssertEqual(changes, 1)
                XCTAssertTrue(canvas.document.undo())
                XCTAssertEqual(canvas.document.annotations, [original])
                XCTAssertTrue(canvas.document.redo())
                XCTAssertEqual(canvas.document.annotations, [moved])
            }
        }
    }

    func testOverlappingAnnotationsSelectTheTopmostAndAllowDeletingIt() throws {
        let canvas = try makeCanvas()
        canvas.tool = .rectangle
        let rect = CGRect(x: 40, y: 40, width: 60, height: 60)
        let bottom = Annotation(content: .rectangle(rect: rect, color: .red, lineWidth: 3))
        let top = Annotation(content: .mosaic(rect: rect, blockSize: 12))
        canvas.document.add(bottom)
        canvas.document.add(top)
        try drag(from: CGPoint(x: 60, y: 60), to: CGPoint(x: 80, y: 70), on: canvas)
        let moved = top.translated(dx: 20, dy: 10)
        XCTAssertEqual(canvas.document.annotations, [bottom, moved])
        let delete = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 1, windowNumber: 0, context: nil, characters: "\u{7F}", charactersIgnoringModifiers: "\u{7F}", isARepeat: false, keyCode: 51))
        canvas.keyDown(with: delete)
        XCTAssertEqual(canvas.document.annotations, [bottom])
        XCTAssertTrue(canvas.document.undo())
        XCTAssertEqual(canvas.document.annotations, [bottom, moved])
    }

    func testDraggingUsesTheMouseUpPositionEvenWithoutAnIntermediateDragEvent() throws {
        let canvas = try makeCanvas()
        canvas.tool = .mosaic
        let mark = Annotation(content: .mosaic(rect: CGRect(x: 40, y: 40, width: 60, height: 60), blockSize: 12))
        canvas.document.add(mark)
        try canvas.mouseDown(with: event(.leftMouseDown, at: CGPoint(x: 60, y: 60), on: canvas))
        try canvas.mouseUp(with: event(.leftMouseUp, at: CGPoint(x: 85, y: 75), on: canvas))
        XCTAssertEqual(canvas.document.annotations, [mark.translated(dx: 25, dy: 15)])
    }

    func testDraggingRespectsRetinaScaleCropOriginAndSelectionEdges() throws {
        let canvas = try makeCanvas(cropRect: CGRect(x: 20, y: 30, width: 200, height: 160))
        canvas.frame.size = CGSize(width: 100, height: 80)
        canvas.fillsBounds = true
        canvas.tool = .ellipse
        let mark = Annotation(content: .mosaic(rect: CGRect(x: 60, y: 70, width: 40, height: 40), blockSize: 8))
        canvas.document.add(mark)
        try drag(from: CGPoint(x: 30, y: 30), to: CGPoint(x: 40, y: 35), on: canvas)
        XCTAssertEqual(canvas.document.annotations, [mark.translated(dx: 20, dy: 10)])
        try drag(from: CGPoint(x: 40, y: 35), to: CGPoint(x: -100, y: -100), on: canvas)
        XCTAssertEqual(canvas.document.annotations.first?.bounds.origin, canvas.document.cropRect.origin)
        try drag(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 900, y: 900), on: canvas)
        let moved = try XCTUnwrap(canvas.document.annotations.first)
        XCTAssertEqual(moved.bounds.maxX, canvas.document.cropRect.maxX)
        XCTAssertEqual(moved.bounds.maxY, canvas.document.cropRect.maxY)
        XCTAssertEqual(canvas.document.annotations.count, 1)
    }

    func testPartiallyCroppedAnnotationDoesNotJumpOnSelectionAndCanStillMove() throws {
        let canvas = try makeCanvas(cropRect: CGRect(x: 50, y: 50, width: 100, height: 100))
        canvas.frame.size = CGSize(width: 100, height: 100)
        canvas.fillsBounds = true
        canvas.tool = .mosaic
        let mark = Annotation(content: .rectangle(rect: CGRect(x: 20, y: 40, width: 180, height: 60), color: .red, lineWidth: 3))
        canvas.document.add(mark)
        let revision = canvas.document.revision
        try drag(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 20, y: 20), on: canvas)
        XCTAssertEqual(canvas.document.annotations, [mark])
        XCTAssertEqual(canvas.document.revision, revision)
        try drag(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 30, y: 40), on: canvas)
        XCTAssertEqual(canvas.document.annotations, [mark.translated(dx: 10, dy: 20)])
    }

    func testHitToleranceStaysUsableWhenTheEditorIsZoomedOut() throws {
        let canvas = try makeCanvas()
        canvas.frame.size = CGSize(width: 60, height: 50)
        canvas.tool = .rectangle
        let mark = Annotation(content: .arrow(start: CGPoint(x: 40, y: 80), end: CGPoint(x: 160, y: 80), color: .red, lineWidth: 3))
        canvas.document.add(mark)
        // Five view points from the line is twenty original-image pixels.
        try drag(from: CGPoint(x: 20, y: 25), to: CGPoint(x: 25, y: 30), on: canvas)
        XCTAssertEqual(canvas.document.annotations, [mark.translated(dx: 20, dy: 20)])
    }

    func testArrowAndEllipseDoNotInterceptBlankCornersAndArrowWingsCanBeSelected() {
        let arrow = Annotation(content: .arrow(start: CGPoint(x: 20, y: 20), end: CGPoint(x: 100, y: 100), color: .red, lineWidth: 8))
        XCTAssertTrue(arrow.contains(CGPoint(x: 60, y: 60), tolerance: 0))
        XCTAssertTrue(arrow.contains(CGPoint(x: 70, y: 89), tolerance: 0))
        XCTAssertFalse(arrow.contains(CGPoint(x: 25, y: 90), tolerance: 6))
        let ellipse = Annotation(content: .ellipse(rect: CGRect(x: 20, y: 20, width: 80, height: 60), color: .red, lineWidth: 3))
        XCTAssertTrue(ellipse.contains(CGPoint(x: 60, y: 50), tolerance: 0))
        XCTAssertFalse(ellipse.contains(CGPoint(x: 20, y: 20), tolerance: 6))
    }

    func testOptionAllowsDrawingOverAnExistingAnnotationAndBlankSpaceStillCreates() throws {
        let canvas = try makeCanvas()
        canvas.tool = .rectangle
        let mark = Annotation(content: .mosaic(rect: CGRect(x: 40, y: 40, width: 60, height: 60), blockSize: 12))
        canvas.document.add(mark)
        try drag(from: CGPoint(x: 60, y: 60), to: CGPoint(x: 90, y: 90), on: canvas, modifiers: .option)
        XCTAssertEqual(canvas.document.annotations.count, 2)
        XCTAssertEqual(canvas.document.annotations.first, mark)
        XCTAssertEqual(canvas.document.annotations.last?.bounds, CGRect(x: 60, y: 60, width: 30, height: 30))
        try drag(from: CGPoint(x: 160, y: 120), to: CGPoint(x: 200, y: 150), on: canvas)
        XCTAssertEqual(canvas.document.annotations.count, 3)
        XCTAssertEqual(canvas.document.annotations.last?.bounds, CGRect(x: 160, y: 120, width: 40, height: 30))
    }

    func testCropToolAndDisabledCanvasDoNotMoveAnnotations() throws {
        let canvas = try makeCanvas()
        let mark = Annotation(content: .mosaic(rect: CGRect(x: 40, y: 40, width: 60, height: 60), blockSize: 12))
        canvas.document.add(mark)
        canvas.tool = .crop
        try drag(from: CGPoint(x: 60, y: 60), to: CGPoint(x: 140, y: 130), on: canvas)
        XCTAssertEqual(canvas.document.annotations, [mark])
        XCTAssertEqual(canvas.document.cropRect, CGRect(x: 60, y: 60, width: 80, height: 70))
        canvas.tool = .mosaic
        canvas.isInteractionEnabled = false
        try drag(from: CGPoint(x: 60, y: 60), to: CGPoint(x: 80, y: 70), on: canvas)
        XCTAssertEqual(canvas.document.annotations, [mark])
    }

    func testMovingMosaicRestoresItsOldRegionAndPixelatesItsNewRegion() throws {
        let canvas = try makeCanvas()
        canvas.tool = .mosaic
        let oldRect = CGRect(x: 40, y: 40, width: 40, height: 40)
        canvas.document.add(Annotation(content: .mosaic(rect: oldRect, blockSize: 12)))
        let before = try AnnotationRenderer.renderSynchronously(canvas.document.renderSnapshot())
        try drag(from: CGPoint(x: 60, y: 60), to: CGPoint(x: 140, y: 60), on: canvas)
        let after = try AnnotationRenderer.renderSynchronously(canvas.document.renderSnapshot())
        let newRect = oldRect.offsetBy(dx: 80, dy: 0)
        func pixels(_ image: CGImage, in rect: CGRect) throws -> [UInt8] {
            try XCTUnwrap(image.cropping(topLeftRect: rect).flatMap(RGBAFrame.init(image:))).bytes
        }
        XCTAssertNotEqual(try pixels(before, in: oldRect), try pixels(canvas.document.image, in: oldRect))
        XCTAssertEqual(try pixels(after, in: oldRect), try pixels(canvas.document.image, in: oldRect))
        XCTAssertNotEqual(try pixels(after, in: newRect), try pixels(canvas.document.image, in: newRect))
        XCTAssertTrue(canvas.document.undo())
        let undone = try AnnotationRenderer.renderSynchronously(canvas.document.renderSnapshot())
        XCTAssertEqual(RGBAFrame(image: undone)?.bytes, RGBAFrame(image: before)?.bytes)
    }

    private func makeCanvas(cropRect: CGRect? = nil) throws -> AnnotationCanvasView {
        let width = 240
        let height = 200
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0 ..< height {
            for x in 0 ..< width {
                let value: UInt8 = (x + y).isMultiple(of: 2) ? 255 : 0
                let offset = (y * width + x) * 4
                bytes[offset] = value
                bytes[offset + 1] = value
                bytes[offset + 2] = value
            }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        let image = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo.byteOrder32Big.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let canvas = AnnotationCanvasView(document: AnnotationDocument(image: image, cropRect: cropRect))
        canvas.frame = CGRect(x: 0, y: 0, width: width, height: height)
        return canvas
    }

    private func event(_ type: NSEvent.EventType, at point: CGPoint, on canvas: AnnotationCanvasView, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: modifiers, timestamp: 1, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0))
    }

    private func drag(from start: CGPoint, to end: CGPoint, on canvas: AnnotationCanvasView, modifiers: NSEvent.ModifierFlags = []) throws {
        try canvas.mouseDown(with: event(.leftMouseDown, at: start, on: canvas, modifiers: modifiers))
        try canvas.mouseDragged(with: event(.leftMouseDragged, at: end, on: canvas, modifiers: modifiers))
        try canvas.mouseUp(with: event(.leftMouseUp, at: end, on: canvas, modifiers: modifiers))
    }
}
