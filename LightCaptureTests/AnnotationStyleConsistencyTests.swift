import AppKit
import CoreGraphics
@testable import LightCapture
import XCTest

@MainActor
final class AnnotationStyleConsistencyTests: XCTestCase {
    func testNormalAndLongCaptureOfferTheSameContextualStyleOptions() throws {
        let overlay = try makeOverlay()
        defer { overlay.close() }
        let normal = try XCTUnwrap(overlay.contentView)
        let editor = try makeEditor()
        defer { editor.close() }
        let long = try XCTUnwrap(editor.window?.contentView)
        let a = try palette(in: normal)
        let b = try palette(in: long)
        for tool in ["capture.annotation.tool.1", "capture.annotation.tool.2", "capture.annotation.tool.3", "capture.annotation.tool.4", "capture.annotation.tool.6", "capture.annotation.tool.5", "capture.annotation.tool.0", "capture.annotation.tool.7"] {
            try button(tool, in: normal).performClick(nil)
            try button(tool, in: long).performClick(nil)
            normal.layoutSubtreeIfNeeded()
            long.layoutSubtreeIfNeeded()
            XCTAssertEqual(a.isHidden, b.isHidden, tool)
            for id in ["width", "font", "mosaic"] {
                let x = try control(id, in: a)
                let y = try control(id, in: b)
                XCTAssertEqual(x.isHidden, y.isHidden, tool)
                XCTAssertEqual((0 ..< x.segmentCount).map { x.label(forSegment: $0) }, (0 ..< y.segmentCount).map { y.label(forSegment: $0) })
                XCTAssertEqual(x.selectedSegment, y.selectedSegment)
                XCTAssertEqual(x.frame.width, y.frame.width, accuracy: 0.01)
            }
            let expectedColors = ["capture.annotation.color.0", "capture.annotation.color.1", "capture.annotation.color.2", "capture.annotation.color.3", "capture.annotation.color.4", "capture.annotation.color.5", "capture.annotation.color.6"]
            XCTAssertEqual(colorButtons(in: a).compactMap { $0.identifier?.rawValue }, expectedColors)
            XCTAssertEqual(colorButtons(in: b).compactMap { $0.identifier?.rawValue }, expectedColors)
            XCTAssertEqual(a.spacing, b.spacing)
            XCTAssertEqual(a.layer?.cornerRadius, b.layer?.cornerRadius)
        }
        XCTAssertEqual(try canvas(in: normal).style.fontSize, try canvas(in: long).style.fontSize)
        XCTAssertEqual(try canvas(in: normal).style.lineWidth, try canvas(in: long).style.lineWidth)
    }

    func testLongShapesAndMosaicUseSelectedColorSizeAndCapturePixelScale() throws {
        let editor = try makeEditor(scale: 2)
        defer { editor.close() }
        let root = try XCTUnwrap(editor.window?.contentView)
        let panel = try palette(in: root)
        let canvas = try canvas(in: root)
        for title in ["capture.annotation.tool.1", "capture.annotation.tool.2", "capture.annotation.tool.3", "capture.annotation.tool.4"] {
            try button(title, in: root).performClick(nil)
            try color("capture.annotation.color.4", in: panel).performClick(nil)
            try setSegment(2, control: control("width", in: panel))
            try draw(from: CGPoint(x: 40, y: 50), to: CGPoint(x: 160, y: 130), on: canvas)
            let content = try XCTUnwrap(canvas.document.annotations.last).content
            let expectedColor = try color("capture.annotation.color.4", in: panel).annotationColor
            switch content {
            case let .rectangle(_, color, width), let .ellipse(_, color, width), let .arrow(_, _, color, width), let .brush(_, color, width):
                XCTAssertEqual(color, expectedColor)
                XCTAssertEqual(width, 10)
            default: XCTFail("应创建所选绘图标注")
            }
        }
        try button("capture.annotation.tool.5", in: root).performClick(nil)
        try setSegment(2, control: control("mosaic", in: panel))
        try draw(from: CGPoint(x: 40, y: 200), to: CGPoint(x: 140, y: 260), on: canvas)
        guard case let .mosaic(_, size) = try XCTUnwrap(canvas.document.annotations.last).content else { return XCTFail("应创建马赛克") }
        XCTAssertEqual(size, 40)
    }

    func testLongTextStyleUpdatesLiveInputAndSurvivesEditingAndUndo() throws {
        let editor = try makeEditor(scale: 2)
        defer { editor.close() }
        let window = try XCTUnwrap(editor.window)
        let root = try XCTUnwrap(window.contentView)
        let panel = try palette(in: root)
        let canvas = try canvas(in: root)
        try button("capture.annotation.tool.6", in: root).performClick(nil)
        try setSegment(3, control: control("font", in: panel))
        try color("capture.annotation.color.4", in: panel).performClick(nil)
        canvas.onTextRequest?(CGRect(x: 10, y: 200, width: 220, height: 180), nil)
        let input = try input(in: canvas)
        XCTAssertEqual(input.pixelFontSize, 64)
        input.setMarkedText("zhongwen", selectedRange: NSRange(location: 8, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        try color("capture.annotation.color.3", in: panel).performClick(nil)
        try setSegment(2, control: control("font", in: panel))
        XCTAssertTrue(window.firstResponder === input)
        XCTAssertTrue(input.hasMarkedText(), "调整文字属性不能丢掉输入法组合")
        XCTAssertEqual(input.pixelFontSize, 48)
        let displayScale = canvas.viewRect(forPixelRect: CGRect(x: 0, y: 0, width: 1, height: 1)).width
        XCTAssertEqual(try XCTUnwrap(input.font).pointSize, 48 * displayScale, accuracy: 0.001)
        XCTAssertEqual(input.textColor, try color("capture.annotation.color.3", in: panel).annotationColor.nsColor)
        input.unmarkText()
        input.string = "中文样式"
        input.onCommit?()
        let original = try XCTUnwrap(canvas.document.annotations.first)
        guard case let .text(_, _, fontSize, green) = original.content else { return XCTFail("应创建文字") }
        XCTAssertEqual(fontSize, 48)
        XCTAssertEqual(green, try color("capture.annotation.color.3", in: panel).annotationColor)
        canvas.onTextRequest?(original.bounds, original)
        XCTAssertEqual(try control("font", in: panel).selectedSegment, 2)
        XCTAssertEqual(try self.input(in: canvas).pixelFontSize, 48)
        try color("capture.annotation.color.5", in: panel).performClick(nil)
        try setSegment(1, control: control("font", in: panel))
        try self.input(in: canvas).onCommit?()
        let changed = try XCTUnwrap(canvas.document.annotations.first)
        guard case let .text(_, value, size, black) = changed.content else { return XCTFail("应更新同一文字") }
        XCTAssertEqual(changed.id, original.id)
        XCTAssertEqual(value, "中文样式")
        XCTAssertEqual(size, 36)
        XCTAssertEqual(black, .black)
        try button("capture.action.arrow.uturn.backward", in: root).performClick(nil)
        XCTAssertEqual(canvas.document.annotations, [original])
        try button("capture.action.arrow.uturn.forward", in: root).performClick(nil)
        XCTAssertEqual(canvas.document.annotations, [changed])
    }

    func testLongStyleRowFitsBothThemesAndZoomDoesNotChangeAnnotationSizes() throws {
        let editor = try makeEditor(scale: 2)
        defer { editor.close() }
        let window = try XCTUnwrap(editor.window)
        window.setContentSize(CGSize(width: 760, height: 520))
        let root = try XCTUnwrap(window.contentView)
        editor.windowDidResize(Notification(name: NSWindow.didResizeNotification))
        let panel = try palette(in: root)
        let toolbar = try XCTUnwrap(views(in: root).first { $0.identifier?.rawValue == "capture.annotation.toolbar" })
        let scroll = try XCTUnwrap(root.subviews.compactMap { $0 as? NSScrollView }.first)
        let viewportSize = scroll.frame.size
        let toolbarFrame = toolbar.frame
        for title in ["capture.annotation.tool.1", "capture.annotation.tool.6", "capture.annotation.tool.5", "capture.annotation.tool.0", "capture.annotation.tool.2"] {
            try button(title, in: root).performClick(nil)
            root.layoutSubtreeIfNeeded()
            XCTAssertEqual(scroll.frame.size, viewportSize)
            XCTAssertEqual(toolbar.frame, toolbarFrame)
            if !panel.isHidden {
                XCTAssertTrue(root.bounds.contains(root.convert(panel.bounds, from: panel)))
                for item in panel.arrangedSubviews where !item.isHidden {
                    XCTAssertTrue(panel.bounds.contains(item.frame))
                }
            }
        }
        try button("capture.annotation.tool.6", in: root).performClick(nil)
        try setSegment(3, control: control("font", in: panel))
        let canvas = try canvas(in: root)
        let zoom = try XCTUnwrap(root.subviews.compactMap { $0 as? NSSegmentedControl }.first)
        for segment in 0 ..< zoom.segmentCount {
            try setSegment(segment, control: zoom)
            XCTAssertEqual(canvas.style.fontSize, 64, "字号应基于原截图比例，不能随编辑器缩放变化")
            XCTAssertEqual(canvas.style.lineWidth, 6)
        }
        for (name, appearance) in [("浅色", NSAppearance.Name.aqua), ("暗色", .darkAqua)] {
            window.appearance = try XCTUnwrap(NSAppearance(named: appearance))
            root.layoutSubtreeIfNeeded()
            root.displayIfNeeded()
            var expected: CGColor?
            root.effectiveAppearance.performAsCurrentDrawingAppearance { expected = NSColor.windowBackgroundColor.withAlphaComponent(0.98).cgColor }
            XCTAssertEqual(panel.layer?.backgroundColor, expected)
            let bitmap = try XCTUnwrap(root.bitmapImageRepForCachingDisplay(in: root.bounds))
            root.cacheDisplay(in: root.bounds, to: bitmap)
            let attachment = try XCTAttachment(data: XCTUnwrap(bitmap.representation(using: .png, properties: [:])), uniformTypeIdentifier: "public.png")
            attachment.name = "长图统一属性栏-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testSavedAndCopiedImagesContainSelectedShapeAndTextColors() async throws {
        for save in [false, true] {
            let delivered = XCTestExpectation(description: save ? "保存样式" : "复制样式")
            let output: (CGImage) async -> Bool = { image in
                guard let frame = RGBAFrame(image: image) else {
                    XCTFail("无法读取输出像素")
                    delivered.fulfill()
                    return false
                }
                let blue = frame.pixel(x: 100, y: 72)
                XCTAssertLessThan(blue >> 24, 80)
                XCTAssertGreaterThan((blue >> 8) & 255, 210)
                let greenText = (200 ..< 300).contains { y in
                    (0 ..< 240).contains { x in
                        let pixel = frame.pixel(x: x, y: y)
                        return pixel >> 24 < 100 && (pixel >> 16) & 255 > 130 && (pixel >> 8) & 255 < 150
                    }
                }
                XCTAssertTrue(greenText, "输出必须保留所选绿色文字，不能恢复为固定红色")
                delivered.fulfill()
                return true
            }
            let editor = try AnnotationEditorWindowController(image: image(), onCancel: {}, onComplete: { image in
                XCTAssertFalse(save)
                return await output(image)
            }, onSave: { image in
                XCTAssertTrue(save)
                return await output(image)
            })
            defer { editor.close() }
            let root = try XCTUnwrap(editor.window?.contentView)
            let panel = try palette(in: root)
            let canvas = try canvas(in: root)
            try button("capture.annotation.tool.1", in: root).performClick(nil)
            try color("capture.annotation.color.4", in: panel).performClick(nil)
            try setSegment(2, control: control("width", in: panel))
            try draw(from: CGPoint(x: 60, y: 70), to: CGPoint(x: 160, y: 130), on: canvas)
            try button("capture.annotation.tool.6", in: root).performClick(nil)
            try color("capture.annotation.color.3", in: panel).performClick(nil)
            try setSegment(3, control: control("font", in: panel))
            canvas.onTextRequest?(CGRect(x: 0, y: 200, width: 240, height: 100), nil)
            let input = try input(in: canvas)
            XCTAssertEqual(input.pixelFontSize, 32)
            input.string = "文字样式"
            try button(save ? "capture.action.square.and.arrow.down" : "capture.action.checkmark", in: root).performClick(nil)
            let result = await XCTWaiter.fulfillment(of: [delivered], timeout: 5)
            XCTAssertEqual(result, .completed)
        }
    }

    func testOutputFailureReenablesStyleControlsAndKeepsSelectedValues() async throws {
        let attempted = XCTestExpectation(description: "发布返回失败")
        let editor = try AnnotationEditorWindowController(image: image(), onCancel: {}, onComplete: { _ in attempted.fulfill(); return false })
        defer { editor.close() }
        let root = try XCTUnwrap(editor.window?.contentView)
        let panel = try palette(in: root)
        try button("capture.annotation.tool.6", in: root).performClick(nil)
        try setSegment(3, control: control("font", in: panel))
        try color("capture.annotation.color.3", in: panel).performClick(nil)
        try button("capture.action.checkmark", in: root).performClick(nil)
        XCTAssertFalse(try control("font", in: panel).isEnabled)
        XCTAssertTrue(colorButtons(in: panel).allSatisfy { !$0.isEnabled })
        let result = await XCTWaiter.fulfillment(of: [attempted], timeout: 5)
        XCTAssertEqual(result, .completed)
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        XCTAssertTrue(try control("font", in: panel).isEnabled)
        XCTAssertEqual(try control("font", in: panel).selectedSegment, 3)
        XCTAssertEqual(try canvas(in: root).style.color, try color("capture.annotation.color.3", in: panel).annotationColor)
    }

    func testCaptureFlowPassesOriginalPixelScaleIntoTheLongEditor() throws {
        let flow = CaptureFlowController()
        let session = try XCTUnwrap(flow.sessions.begin(mode: .long, targetProcessID: nil))
        defer { flow.cancelCurrentSession(restoreFocus: false) }
        try flow.presentLongCaptureResult(image: image(), sessionID: session.id, generation: session.generation, bannerMessage: nil, annotationPixelScale: 2)
        let root = try XCTUnwrap(flow.outputPanelParent?.contentView)
        let canvas = try canvas(in: root)
        XCTAssertEqual(canvas.style.lineWidth, 6)
        XCTAssertEqual(canvas.style.fontSize, 36)
        XCTAssertEqual(flow.sessions.activeSession?.state, .editing)
    }

    private func image(width: Int = 240, height: Int = 700) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 0.98, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    private func makeEditor(scale: CGFloat = 1) throws -> AnnotationEditorWindowController {
        try AnnotationEditorWindowController(image: image(), onCancel: {}, onComplete: { _ in true }, annotationPixelScale: scale)
    }

    private func makeOverlay() throws -> SelectionOverlayWindow {
        let frame = CGRect(x: 0, y: 0, width: 900, height: 650)
        let screen = try FrozenScreen(displayID: 0, screenFrame: frame, image: image(width: 900, height: 650), transform: DisplayTransform(screenFrame: frame, pixelWidth: 900, pixelHeight: 650), windows: [])
        let overlay = SelectionOverlayWindow(screen: screen, initialMode: .normal)
        let root = try XCTUnwrap(overlay.contentView)
        let selector = try XCTUnwrap(root.subviews.first { $0.identifier?.rawValue == "capture.selection.canvas" })
        try drag(from: CGPoint(x: 120, y: 100), to: CGPoint(x: 620, y: 400), on: selector, window: overlay)
        root.layoutSubtreeIfNeeded()
        return overlay
    }

    private func views(in view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { views(in: $0) }
    }

    private func palette(in root: NSView) throws -> AnnotationStyleControls {
        try XCTUnwrap(views(in: root).compactMap { $0 as? AnnotationStyleControls }.first)
    }

    private func canvas(in root: NSView) throws -> AnnotationCanvasView {
        try XCTUnwrap(views(in: root).compactMap { $0 as? AnnotationCanvasView }.first)
    }

    private func input(in canvas: AnnotationCanvasView) throws -> AnnotationInputTextView {
        try XCTUnwrap(canvas.subviews.compactMap { $0 as? AnnotationInputTextView }.first)
    }

    private func control(_ id: String, in root: NSView) throws -> NSSegmentedControl {
        try XCTUnwrap(views(in: root).compactMap { $0 as? NSSegmentedControl }.first { $0.identifier?.rawValue == "capture.annotation.\(id)" })
    }

    private func colorButtons(in root: NSView) -> [AnnotationColorButton] {
        views(in: root).compactMap { $0 as? AnnotationColorButton }
    }

    private func color(_ name: String, in root: NSView) throws -> AnnotationColorButton {
        try XCTUnwrap(colorButtons(in: root).first { $0.identifier?.rawValue == name })
    }

    private func button(_ title: String, in root: NSView) throws -> NSButton {
        try XCTUnwrap(views(in: root).compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == title })
    }

    private func setSegment(_ segment: Int, control: NSSegmentedControl) throws {
        control.selectedSegment = segment
        XCTAssertTrue(control.sendAction(control.action, to: control.target))
        control.window?.contentView?.layoutSubtreeIfNeeded()
    }

    private func draw(from start: CGPoint, to end: CGPoint, on canvas: AnnotationCanvasView) throws {
        let window = try XCTUnwrap(canvas.window)
        let a = canvas.viewRect(forPixelRect: CGRect(origin: start, size: CGSize(width: 1, height: 1))).origin
        let b = canvas.viewRect(forPixelRect: CGRect(origin: end, size: CGSize(width: 1, height: 1))).origin
        try drag(from: a, to: b, on: canvas, window: window)
    }

    private func drag(from start: CGPoint, to end: CGPoint, on view: NSView, window: NSWindow) throws {
        for (type, point) in [(NSEvent.EventType.leftMouseDown, start), (.leftMouseDragged, end), (.leftMouseUp, end)] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil), modifierFlags: [], timestamp: 1, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0))
            switch type {
            case .leftMouseDown: view.mouseDown(with: event)
            case .leftMouseDragged: view.mouseDragged(with: event)
            default: view.mouseUp(with: event)
            }
        }
    }
}
