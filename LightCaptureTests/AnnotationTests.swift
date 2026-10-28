import AppKit
import CoreGraphics
import ImageIO
@testable import LightCapture
import UniformTypeIdentifiers
import XCTest

final class AnnotationTests: XCTestCase {
    @MainActor
    func testAnnotationEditorInitializesItsCanvasBeforeToolbarState() {
        let image = solidImage(width: 16, height: 12, color: (240, 240, 240, 255))
        let editor = AnnotationEditorWindowController(
            image: image,
            onCancel: {},
            onComplete: { _ in true }
        )

        XCTAssertEqual(editor.window?.title, L10n.editorTitle)
        XCTAssertNotNil(editor.window?.contentView)
    }

    @MainActor
    func testReshowingEditorKeepsActiveTextInputAndMarkedText() throws {
        let (editor, window, input) = try makeTextEditingEditor()
        defer { editor.close() }
        input.setMarkedText("zhongwen", selectedRange: NSRange(location: 8, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(window.firstResponder === input)
        XCTAssertTrue(input.hasMarkedText())

        editor.showWindow()

        XCTAssertTrue(window.firstResponder === input, "重新唤起现有编辑器不能把键盘焦点移回画布")
        XCTAssertTrue(input.hasMarkedText(), "重新唤起不能丢弃正在组合的文字")
    }

    @MainActor
    func testDefaultReturnButtonDoesNotBypassTextComposition() throws {
        let (editor, window, input) = try makeTextEditingEditor()
        defer { editor.close() }
        input.setMarkedText("zhongwen", selectedRange: NSRange(location: 8, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 1,
            windowNumber: window.windowNumber, context: nil,
            characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36
        ))

        XCTAssertFalse(window.performKeyEquivalent(with: event), "输入法选词的回车必须交给文字框，不能触发整图完成")
        XCTAssertTrue(window.firstResponder === input)
    }

    @MainActor
    private func makeTextEditingEditor() throws -> (AnnotationEditorWindowController, NSWindow, AnnotationInputTextView) {
        let editor = AnnotationEditorWindowController(
            image: solidImage(width: 1000, height: 600, color: (240, 240, 240, 255)),
            onCancel: {}, onComplete: { _ in true }
        )
        editor.showWindow()
        let window = try XCTUnwrap(editor.window)
        let root = try XCTUnwrap(window.contentView)
        let scroll = try XCTUnwrap(root.subviews.compactMap { $0 as? NSScrollView }.first)
        let canvas = try XCTUnwrap(scroll.documentView as? AnnotationCanvasView)
        canvas.onTextRequest?(CGRect(x: 10, y: 10, width: 300, height: 80), nil)
        let input = try XCTUnwrap(canvas.subviews.compactMap { $0 as? AnnotationInputTextView }.first)
        return (editor, window, input)
    }

    @MainActor
    func testDocumentTracksPendingMarksAndCropForSourceChangePrompt() {
        let document = AnnotationDocument(image: solidImage(width: 16, height: 12, color: (240, 240, 240, 255)))
        XCTAssertFalse(document.hasUncommittedChanges)

        document.add(Annotation(content: .rectangle(rect: CGRect(x: 2, y: 3, width: 5, height: 4), color: .red, lineWidth: 2)))
        XCTAssertTrue(document.hasUncommittedChanges)
        XCTAssertTrue(document.undo())
        XCTAssertFalse(document.hasUncommittedChanges)

        document.setCropRect(CGRect(x: 1, y: 1, width: 10, height: 8))
        XCTAssertTrue(document.hasUncommittedChanges)
        XCTAssertTrue(document.undo())
        XCTAssertFalse(document.hasUncommittedChanges)
    }

    @MainActor
    func testCommandHistoryRestoresAnnotationsAndCropWithoutCopyingImage() {
        let image = solidImage(width: 16, height: 12, color: (240, 240, 240, 255))
        let document = AnnotationDocument(image: image)
        let rectangle = Annotation(content: .rectangle(rect: CGRect(x: 2, y: 3, width: 5, height: 4), color: .red, lineWidth: 2))
        document.add(rectangle)
        document.setCropRect(CGRect(x: 1, y: 1, width: 10, height: 8))

        XCTAssertEqual(document.annotations, [rectangle])
        XCTAssertEqual(document.cropRect, CGRect(x: 1, y: 1, width: 10, height: 8))
        XCTAssertTrue(document.undo())
        XCTAssertEqual(document.cropRect, CGRect(x: 0, y: 0, width: 16, height: 12))
        XCTAssertTrue(document.undo())
        XCTAssertTrue(document.annotations.isEmpty)
        XCTAssertTrue(document.redo())
        XCTAssertEqual(document.annotations, [rectangle])
        XCTAssertTrue(document.redo())
        XCTAssertEqual(document.cropRect, CGRect(x: 1, y: 1, width: 10, height: 8))
    }

    func testRendererPreservesTopLeftPixelCoordinatesWhenCropping() throws {
        let image = rowColorImage(width: 4, height: 4)
        let topHalf = try XCTUnwrap(image.cropping(topLeftRect: CGRect(x: 0, y: 0, width: 4, height: 2)))
        let bottomHalf = try XCTUnwrap(image.cropping(topLeftRect: CGRect(x: 0, y: 2, width: 4, height: 2)))
        XCTAssertNotEqual(pngData(topHalf), pngData(bottomHalf))
        let snapshot = AnnotationRenderSnapshot(
            image: image,
            cropRect: CGRect(x: 0, y: 0, width: 4, height: 2),
            annotations: [],
            revision: 0
        )

        let rendered = try AnnotationRenderer.renderSynchronously(snapshot)
        XCTAssertEqual(rendered.width, 4)
        XCTAssertEqual(rendered.height, 2)
        XCTAssertEqual(pngData(rendered), pngData(topHalf))
    }

    func testUnannotatedCropPreservesNativeProfileAndTransparency() throws {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        let provider = try XCTUnwrap(CGDataProvider(data: Data([0, 0, 0, 0, 64, 32, 16, 128, 20, 60, 40, 64, 255, 240, 10, 255]) as CFData))
        let image = try XCTUnwrap(CGImage(width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8,
                                          space: space, bitmapInfo: CGBitmapInfo.byteOrder32Big.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)),
                                          provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let crop = CGRect(x: 0, y: 0, width: 2, height: 1)
        let expected = try XCTUnwrap(image.cropping(topLeftRect: crop))
        let rendered = try AnnotationRenderer.renderSynchronously(AnnotationRenderSnapshot(image: image, cropRect: crop, annotations: [], revision: 0))
        XCTAssertEqual(rendered.colorSpace?.name, space.name)
        XCTAssertEqual(rendered.alphaInfo, image.alphaInfo)
        XCTAssertEqual(RGBAFrame(image: rendered)?.bytes, RGBAFrame(image: expected)?.bytes)
    }

    func testTopLeftCropSelectsTheKnownTopRows() throws {
        let image = rowColorImage(width: 4, height: 6)
        let top = try XCTUnwrap(image.cropping(topLeftRect: CGRect(x: 0, y: 0, width: 4, height: 2)))
        let expected = solidImage(width: 4, height: 2, color: (255, 0, 0, 255))
        XCTAssertEqual(pngData(top), pngData(expected), "裁剪顶端必须保留红色顶行，不能取到底部蓝色行")
    }

    @MainActor
    func testCanvasPreviewKeepsTheKnownTopRowsAtTheTop() throws {
        let canvas = AnnotationCanvasView(document: AnnotationDocument(image: rowColorImage(width: 40, height: 60)))
        canvas.frame = CGRect(x: 0, y: 0, width: 40, height: 60)
        let bitmap = try XCTUnwrap(canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds))
        canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
        let frame = try XCTUnwrap(bitmap.cgImage.flatMap(RGBAFrame.init(image:)))
        let top = frame.pixel(x: frame.width / 2, y: frame.height / 4)
        let bottom = frame.pixel(x: frame.width / 2, y: frame.height * 3 / 4)
        // AppKit may color-convert through the display profile; compare the
        // dominant channels, independently of the source cropping helper.
        XCTAssertGreaterThan(top >> 24, 240)
        XCTAssertLessThan((top >> 8) & 255, 20)
        XCTAssertGreaterThan((bottom >> 8) & 255, 240)
        XCTAssertLessThan(bottom >> 24, 20)
    }

    @MainActor
    func testCanvasCanCreateHorizontalAndVerticalArrows() throws {
        let document = AnnotationDocument(image: solidImage(width: 100, height: 100, color: (255, 255, 255, 255)))
        let canvas = AnnotationCanvasView(document: document)
        canvas.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        canvas.tool = .arrow
        for (start, end) in [(CGPoint(x: 20, y: 20), CGPoint(x: 80, y: 20)), (CGPoint(x: 20, y: 50), CGPoint(x: 20, y: 80))] {
            let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: start, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: end, modifierFlags: [], timestamp: 1, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 0))
            canvas.mouseDown(with: down)
            canvas.mouseUp(with: up)
        }
        XCTAssertEqual(document.annotations.count, 2)
    }

    @MainActor
    func testLongCapturePreviewUpdatesTheImageViewInThePanel() {
        let panel = LongCaptureControlPanel(screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), selectedGlobalRect: CGRect(x: 100, y: 100, width: 400, height: 400))
        defer { panel.close() }
        panel.updatePreview(image: solidImage(width: 40, height: 30, color: (255, 0, 0, 255)))
        func imageViews(in view: NSView) -> [NSImageView] {
            (view as? NSImageView).map { [$0] } ?? view.subviews.flatMap { imageViews(in: $0) }
        }
        let views = panel.contentView.map { imageViews(in: $0) } ?? []
        XCTAssertEqual(views.count, 1)
        XCTAssertNotNil(views.first?.image, "缩略图必须更新可见控件")
    }

    @MainActor
    func testLongImageEditorProvidesReadableScrollableContent() throws {
        let editor = AnnotationEditorWindowController(image: solidImage(width: 100, height: 2000, color: (255, 255, 255, 255)), onCancel: {}, onComplete: { _ in true })
        defer { editor.close() }
        let root = try XCTUnwrap(editor.window?.contentView)
        root.layoutSubtreeIfNeeded()
        editor.windowDidResize(Notification(name: NSWindow.didResizeNotification))
        let scroll = try XCTUnwrap(root.subviews.compactMap { $0 as? NSScrollView }.first)
        XCTAssertTrue(scroll.hasVerticalScroller)
        XCTAssertGreaterThan(try XCTUnwrap(scroll.documentView).frame.height, scroll.contentView.bounds.height * 2)
    }

    @MainActor
    func testClosingEditorWhileRenderingStillCancelsTheSession() throws {
        var cancellations = 0
        let editor = AnnotationEditorWindowController(image: solidImage(width: 40, height: 30, color: (255, 255, 255, 255)), onCancel: { cancellations += 1 }, onComplete: { _ in true })
        defer { editor.close() }
        func completeButton(in view: NSView) -> NSButton? {
            if let button = view as? NSButton, button.identifier?.rawValue == "capture.action.checkmark" { return button }
            return view.subviews.lazy.compactMap { completeButton(in: $0) }.first
        }
        let window = try XCTUnwrap(editor.window)
        try XCTUnwrap(window.contentView.flatMap { completeButton(in: $0) }).performClick(nil)
        XCTAssertTrue(editor.windowShouldClose(window))
        XCTAssertEqual(cancellations, 1)
    }

    func testRendererKeepsAnnotationAtTheSamePixelsAfterCropping() throws {
        let image = solidImage(width: 20, height: 18, color: (245, 245, 245, 255))
        let cropRect = CGRect(x: 4, y: 3, width: 12, height: 10)
        let globalAnnotation = Annotation(content: .rectangle(
            rect: CGRect(x: 8, y: 7, width: 5, height: 3),
            color: .red,
            lineWidth: 2
        ))
        let croppedImage = try XCTUnwrap(image.cropping(topLeftRect: cropRect))
        let fromFullDocument = try AnnotationRenderer.renderSynchronously(AnnotationRenderSnapshot(
            image: image,
            cropRect: cropRect,
            annotations: [globalAnnotation],
            revision: 1
        ))
        let fromAlreadyCroppedDocument = try AnnotationRenderer.renderSynchronously(AnnotationRenderSnapshot(
            image: croppedImage,
            cropRect: CGRect(origin: .zero, size: CGSize(width: croppedImage.width, height: croppedImage.height)),
            annotations: [globalAnnotation.translated(dx: -cropRect.minX, dy: -cropRect.minY)],
            revision: 1
        ))

        XCTAssertEqual(pngData(fromFullDocument), pngData(fromAlreadyCroppedDocument))
    }

    func testRendererAppliesMosaicInsideItsSelectedRegion() throws {
        let image = checkerImage(width: 16, height: 16)
        let crop = CGRect(x: 4, y: 4, width: 8, height: 8)
        let snapshot = AnnotationRenderSnapshot(
            image: image,
            cropRect: CGRect(x: 0, y: 0, width: 16, height: 16),
            annotations: [Annotation(content: .mosaic(rect: crop, blockSize: 6))],
            revision: 1
        )

        let rendered = try AnnotationRenderer.renderSynchronously(snapshot)
        XCTAssertEqual(rendered.width, image.width)
        XCTAssertEqual(rendered.height, image.height)
        XCTAssertNotEqual(pngData(rendered), pngData(image))
    }

    func testCroppingPreservesTheMosaicPixelsVisibleBeforeTheCrop() throws {
        let image = checkerImage(width: 24, height: 24)
        let crop = CGRect(x: 7, y: 6, width: 12, height: 10)
        let annotations = [Annotation(content: .mosaic(rect: CGRect(x: 2, y: 1, width: 18, height: 18), blockSize: 7))]
        let full = try AnnotationRenderer.renderSynchronously(AnnotationRenderSnapshot(image: image, cropRect: CGRect(x: 0, y: 0, width: 24, height: 24), annotations: annotations, revision: 1))
        let expected = try XCTUnwrap(full.cropping(topLeftRect: crop))
        let cropped = try AnnotationRenderer.renderSynchronously(AnnotationRenderSnapshot(image: image, cropRect: crop, annotations: annotations, revision: 2))
        XCTAssertEqual(RGBAFrame(image: cropped)?.bytes, RGBAFrame(image: expected)?.bytes)
    }

    private func solidImage(width: Int, height: Int, color: (UInt8, UInt8, UInt8, UInt8)) -> CGImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for index in stride(from: 0, to: bytes.count, by: 4) {
            bytes[index] = color.0
            bytes[index + 1] = color.1
            bytes[index + 2] = color.2
            bytes[index + 3] = color.3
        }
        return makeImage(bytes: bytes, width: width, height: height)
    }

    private func rowColorImage(width: Int, height: Int) -> CGImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0 ..< height {
            let color: (UInt8, UInt8, UInt8) = y < height / 2 ? (255, 0, 0) : (0, 0, 255)
            for x in 0 ..< width {
                let offset = (y * width + x) * 4
                bytes[offset] = color.0
                bytes[offset + 1] = color.1
                bytes[offset + 2] = color.2
                bytes[offset + 3] = 255
            }
        }
        return makeImage(bytes: bytes, width: width, height: height)
    }

    private func checkerImage(width: Int, height: Int) -> CGImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0 ..< height {
            for x in 0 ..< width {
                let value: UInt8 = ((x + y).isMultiple(of: 2)) ? 255 : 0
                let offset = (y * width + x) * 4
                bytes[offset] = value
                bytes[offset + 1] = value
                bytes[offset + 2] = value
                bytes[offset + 3] = 255
            }
        }
        return makeImage(bytes: bytes, width: width, height: height)
    }

    private func makeImage(bytes: [UInt8], width: Int, height: Int) -> CGImage {
        let data = Data(bytes) as CFData
        let provider = CGDataProvider(data: data)!
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue))
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }

    private func pngData(_ image: CGImage) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
