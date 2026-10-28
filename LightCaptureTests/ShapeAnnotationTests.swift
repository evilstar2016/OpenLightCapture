import AppKit
import CoreGraphics
@testable import LightCapture
import XCTest

@MainActor
final class ShapeAnnotationTests: XCTestCase {
    private let blue = AnnotationColor(red: 0, green: 0, blue: 1, alpha: 1)

    func testReverseEllipseDragProducesAnUnfilledEllipseWithSelectedStyle() throws {
        let canvas = try makeCanvas()
        canvas.tool = .ellipse
        canvas.style.color = blue
        canvas.style.lineWidth = 6
        try gesture([CGPoint(x: 100, y: 80), CGPoint(x: 20, y: 20)], on: canvas)
        guard case let .ellipse(rect, color, lineWidth) = try XCTUnwrap(canvas.document.annotations.first).content else { return XCTFail("应创建椭圆") }
        XCTAssertEqual(rect, CGRect(x: 20, y: 20, width: 80, height: 60))
        XCTAssertEqual(color, blue)
        XCTAssertEqual(lineWidth, 6)
        let output = try render(canvas.document)
        assertBlue(output, at: CGPoint(x: 60, y: 22))
        assertBlue(output, at: CGPoint(x: 22, y: 50))
        assertWhite(output, at: CGPoint(x: 60, y: 50))
        assertWhite(output, at: CGPoint(x: 22, y: 22))
        try gesture([CGPoint(x: 40, y: 40)], on: canvas)
        XCTAssertEqual(canvas.document.annotations.count, 1, "单击不能创建不可见椭圆")
        XCTAssertTrue(canvas.document.undo())
        XCTAssertTrue(canvas.document.annotations.isEmpty)
        XCTAssertTrue(canvas.document.redo())
        XCTAssertEqual(canvas.document.annotations.count, 1)
    }

    func testBrushKeepsEveryTurnAndCommitsOneUndoableStrokeOnMouseUp() throws {
        let canvas = try makeCanvas()
        canvas.tool = .brush
        canvas.style.color = blue
        canvas.style.lineWidth = 8
        let points = [CGPoint(x: 20, y: 20), CGPoint(x: 20, y: 80), CGPoint(x: 80, y: 80), CGPoint(x: 80, y: 20)]
        try canvas.mouseDown(with: event(.leftMouseDown, at: points[0], on: canvas))
        for point in points.dropFirst() {
            try canvas.mouseDragged(with: event(.leftMouseDragged, at: point, on: canvas))
        }
        XCTAssertTrue(canvas.document.annotations.isEmpty)
        XCTAssertFalse(canvas.document.canUndo, "拖动预览不能产生零碎历史")
        let preview = try preview(canvas)
        for point in [CGPoint(x: 20, y: 50), CGPoint(x: 50, y: 80), CGPoint(x: 80, y: 50)] {
            assertBlue(preview, at: point)
        }
        assertWhite(preview, at: CGPoint(x: 50, y: 20))
        try canvas.mouseUp(with: event(.leftMouseUp, at: XCTUnwrap(points.last), on: canvas))
        guard case let .brush(recorded, color, width) = try XCTUnwrap(canvas.document.annotations.first).content else { return XCTFail("应创建画笔笔迹") }
        XCTAssertEqual(recorded, points)
        XCTAssertEqual(color, blue)
        XCTAssertEqual(width, 8)
        let output = try render(canvas.document)
        for point in [CGPoint(x: 20, y: 50), CGPoint(x: 50, y: 80), CGPoint(x: 80, y: 50)] {
            assertBlue(output, at: point)
        }
        assertWhite(output, at: CGPoint(x: 50, y: 20))
        XCTAssertTrue(canvas.document.undo())
        XCTAssertTrue(canvas.document.annotations.isEmpty)
        XCTAssertFalse(canvas.document.canUndo)
        XCTAssertTrue(canvas.document.redo())
        XCTAssertEqual(canvas.document.annotations.count, 1)
    }

    func testBrushSupportsHorizontalVerticalAndSingleClickStrokesWithoutConnectingThem() throws {
        let canvas = try makeCanvas()
        canvas.tool = .brush
        canvas.style.color = blue
        canvas.style.lineWidth = 8
        let strokes = [[CGPoint(x: 20, y: 20), CGPoint(x: 60, y: 20)],
                       [CGPoint(x: 80, y: 30), CGPoint(x: 80, y: 70)], [CGPoint(x: 30, y: 80)]]
        for stroke in strokes {
            try gesture(stroke, on: canvas)
        }
        XCTAssertEqual(canvas.document.annotations.count, 3)
        let output = try render(canvas.document)
        assertBlue(output, at: CGPoint(x: 40, y: 20))
        assertBlue(output, at: CGPoint(x: 80, y: 50))
        assertBlue(output, at: CGPoint(x: 30, y: 80))
        assertWhite(output, at: CGPoint(x: 70, y: 25))
        assertWhite(output, at: CGPoint(x: 50, y: 50))
        assertWhite(output, at: CGPoint(x: 30, y: 86))
        let dot = try XCTUnwrap(canvas.document.annotations.last)
        XCTAssertEqual(dot.bounds, CGRect(x: 26, y: 76, width: 8, height: 8))
        XCTAssertTrue(dot.contains(CGPoint(x: 30, y: 80), tolerance: 0))
    }

    func testBrushSelectionUsesTheStrokeAndMovingOrDeletingCanBeUndone() throws {
        let canvas = try makeCanvas()
        canvas.tool = .brush
        let points = [CGPoint(x: 20, y: 20), CGPoint(x: 20, y: 80), CGPoint(x: 80, y: 80)]
        try gesture(points, on: canvas)
        let original = try XCTUnwrap(canvas.document.annotations.first)
        XCTAssertTrue(original.contains(CGPoint(x: 20, y: 50), tolerance: 3))
        XCTAssertFalse(original.contains(CGPoint(x: 60, y: 30), tolerance: 3), "大笔迹包围盒的空白处不能拦截其他标注")
        canvas.tool = .select
        try gesture([CGPoint(x: 20, y: 50), CGPoint(x: 30, y: 60)], on: canvas)
        let moved = try XCTUnwrap(canvas.document.annotations.first)
        XCTAssertEqual(moved, original.translated(dx: 10, dy: 10))
        XCTAssertEqual(moved.id, original.id)
        XCTAssertTrue(canvas.document.undo())
        XCTAssertEqual(canvas.document.annotations, [original])
        XCTAssertTrue(canvas.document.redo())
        XCTAssertEqual(canvas.document.annotations, [moved])
        let delete = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 1, windowNumber: 0, context: nil, characters: "\u{7F}", charactersIgnoringModifiers: "\u{7F}", isARepeat: false, keyCode: 51))
        canvas.keyDown(with: delete)
        XCTAssertTrue(canvas.document.annotations.isEmpty)
        XCTAssertTrue(canvas.document.undo())
        XCTAssertEqual(canvas.document.annotations, [moved])
    }

    func testEllipseAndBrushKeepSourcePixelsAndClippingAfterCropping() throws {
        let canvas = try makeCanvas()
        let document = canvas.document
        document.add(Annotation(content: .ellipse(rect: CGRect(x: 20, y: 10, width: 90, height: 80), color: blue, lineWidth: 6)))
        document.add(Annotation(content: .brush(points: [CGPoint(x: 10, y: 60), CGPoint(x: 110, y: 60)], color: blue, lineWidth: 8)))
        let full = try AnnotationRenderer.renderSynchronously(document.renderSnapshot())
        let crop = CGRect(x: 30, y: 20, width: 70, height: 60)
        document.setCropRect(crop)
        let output = try render(document)
        let expected = try XCTUnwrap(full.cropping(topLeftRect: crop).flatMap(RGBAFrame.init(image:)))
        // Quartz can quantize the antialiased edge of a clipped ellipse one
        // RGB level differently. Geometry and solid stroke pixels must agree.
        let largestDifference = zip(output.bytes, expected.bytes).map { abs(Int($0) - Int($1)) }.max() ?? 0
        XCTAssertLessThanOrEqual(largestDifference, 1)
        XCTAssertEqual(output.width, 70)
        XCTAssertEqual(output.height, 60)
        assertBlue(output, at: CGPoint(x: 10, y: 40))
        assertWhite(output, at: CGPoint(x: 10, y: 20))
    }

    func testSwitchingToolsDiscardsOnlyTheUnfinishedBrushGesture() throws {
        let canvas = try makeCanvas()
        canvas.tool = .brush
        try gesture([CGPoint(x: 20, y: 20), CGPoint(x: 60, y: 20)], on: canvas)
        try canvas.mouseDown(with: event(.leftMouseDown, at: CGPoint(x: 20, y: 70), on: canvas))
        try canvas.mouseDragged(with: event(.leftMouseDragged, at: CGPoint(x: 90, y: 70), on: canvas))
        canvas.tool = .ellipse
        canvas.tool = .brush
        try canvas.mouseUp(with: event(.leftMouseUp, at: CGPoint(x: 90, y: 70), on: canvas))
        XCTAssertEqual(canvas.document.annotations.count, 1)
        XCTAssertTrue(canvas.document.undo())
        XCTAssertFalse(canvas.document.canUndo)
    }

    func testSmallEllipseStillRendersAndItsPreviewUsesTheSelectedColor() throws {
        let canvas = try makeCanvas()
        canvas.tool = .ellipse
        canvas.style.color = blue
        canvas.style.lineWidth = 6
        try canvas.mouseDown(with: event(.leftMouseDown, at: CGPoint(x: 20, y: 20), on: canvas))
        try canvas.mouseDragged(with: event(.leftMouseDragged, at: CGPoint(x: 100, y: 80), on: canvas))
        let live = try preview(canvas)
        assertBlue(live, at: CGPoint(x: 60, y: 22))
        assertWhite(live, at: CGPoint(x: 60, y: 50))
        XCTAssertTrue(canvas.document.annotations.isEmpty)
        try canvas.mouseUp(with: event(.leftMouseUp, at: CGPoint(x: 100, y: 80), on: canvas))
        try gesture([CGPoint(x: 10, y: 10), CGPoint(x: 12, y: 15)], on: canvas)
        let small = try XCTUnwrap(canvas.document.annotations.last)
        let output = try AnnotationRenderer.renderSynchronously(AnnotationRenderSnapshot(image: canvas.document.image, cropRect: CGRect(x: 8, y: 8, width: 8, height: 10), annotations: [small], revision: 0))
        let pixels = try XCTUnwrap(RGBAFrame(image: output))
        XCTAssertTrue(stride(from: 0, to: pixels.bytes.count, by: 4).contains { pixels.bytes[$0] < 220 && pixels.bytes[$0 + 2] > 220 })
    }

    func testLongImageEditorAlsoOffersEllipseAndBrushIcons() throws {
        let editor = try AnnotationEditorWindowController(image: whiteImage(), onCancel: {}, onComplete: { _ in true })
        defer { editor.close() }
        let root = try XCTUnwrap(editor.window?.contentView)
        func buttons(in view: NSView) -> [NSButton] {
            (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { buttons(in: $0) }
        }
        for title in ["capture.annotation.tool.2", "capture.annotation.tool.4"] {
            let button = try XCTUnwrap(buttons(in: root).first { $0.identifier?.rawValue == title })
            XCTAssertNotNil(button.image)
            XCTAssertTrue(button.isEnabled)
            button.performClick(nil)
            let canvas = try XCTUnwrap(root.subviews.compactMap { $0 as? NSScrollView }.first?.documentView as? AnnotationCanvasView)
            XCTAssertEqual(canvas.tool.rawValue, button.tag)
        }
    }

    private func whiteImage() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 120, height: 100, bitsPerComponent: 8, bytesPerRow: 480, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 120, height: 100))
        return try XCTUnwrap(context.makeImage())
    }

    private func makeCanvas() throws -> AnnotationCanvasView {
        let canvas = try AnnotationCanvasView(document: AnnotationDocument(image: whiteImage()))
        canvas.frame = CGRect(x: 0, y: 0, width: 120, height: 100)
        return canvas
    }

    private func event(_ type: NSEvent.EventType, at point: CGPoint, on canvas: AnnotationCanvasView) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [], timestamp: 1, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0))
    }

    private func gesture(_ points: [CGPoint], on canvas: AnnotationCanvasView) throws {
        let first = try XCTUnwrap(points.first)
        try canvas.mouseDown(with: event(.leftMouseDown, at: first, on: canvas))
        for point in points.dropFirst() {
            try canvas.mouseDragged(with: event(.leftMouseDragged, at: point, on: canvas))
        }
        try canvas.mouseUp(with: event(.leftMouseUp, at: points.last!, on: canvas))
    }

    private func render(_ document: AnnotationDocument) throws -> RGBAFrame {
        try XCTUnwrap(RGBAFrame(image: AnnotationRenderer.renderSynchronously(document.renderSnapshot())))
    }

    private func preview(_ canvas: AnnotationCanvasView) throws -> RGBAFrame {
        let bitmap = try XCTUnwrap(canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds))
        canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
        let image = try XCTUnwrap(bitmap.cgImage)
        // Normalize backing scale so sample positions stay in logical points.
        let context = try XCTUnwrap(CGContext(data: nil, width: 120, height: 100, bitsPerComponent: 8, bytesPerRow: 480, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 120, height: 100))
        return try XCTUnwrap(context.makeImage().flatMap(RGBAFrame.init(image:)))
    }

    private func assertBlue(_ frame: RGBAFrame, at point: CGPoint, file: StaticString = #filePath, line: UInt = #line) {
        let pixel = frame.pixel(x: Int(point.x), y: Int(point.y))
        XCTAssertLessThan(pixel >> 24, 80, file: file, line: line)
        XCTAssertLessThan((pixel >> 16) & 255, 80, file: file, line: line)
        XCTAssertGreaterThan((pixel >> 8) & 255, 230, file: file, line: line)
    }

    private func assertWhite(_ frame: RGBAFrame, at point: CGPoint, file: StaticString = #filePath, line: UInt = #line) {
        let pixel = frame.pixel(x: Int(point.x), y: Int(point.y))
        XCTAssertGreaterThan(pixel >> 24, 245, file: file, line: line)
        XCTAssertGreaterThan((pixel >> 16) & 255, 245, file: file, line: line)
        XCTAssertGreaterThan((pixel >> 8) & 255, 245, file: file, line: line)
    }
}
