import AppKit
import CoreGraphics
@testable import LightCapture
import XCTest

@MainActor
final class InlineAnnotationTests: XCTestCase {
    func testFinishingSelectionShowsDrawingToolsWithoutAnExtraEditor() throws {
        let overlay = try makeOverlay()
        defer { overlay.close() }
        let root = try XCTUnwrap(overlay.contentView)
        let toolbar = try plate("capture.annotation.toolbar", in: root)
        XCTAssertTrue(toolbar.isHidden)
        try select(CGRect(x: 120, y: 100, width: 500, height: 300), in: overlay)
        XCTAssertFalse(toolbar.isHidden)
        for title in ["capture.annotation.tool.1", "capture.annotation.tool.2", "capture.annotation.tool.3", "capture.annotation.tool.4", "capture.annotation.tool.6", "capture.annotation.tool.5", "capture.annotation.tool.7", "capture.action.rectangle.expand.vertical", "capture.action.square.and.arrow.down", "capture.action.checkmark"] {
            XCTAssertTrue(try button(title, in: root).isEnabled, title)
        }
        XCTAssertFalse(views(in: root).contains { ($0 as? NSButton)?.identifier?.rawValue == "capture.action.legacyAnnotation" })
        let text = try button("capture.annotation.tool.6", in: root)
        XCTAssertEqual(text.imagePosition, .noImage, "必须直接显示文字，不能显示本地化后的格式图标")
        XCTAssertNil(text.image)
        XCTAssertEqual(views(in: root).compactMap { $0 as? AnnotationCanvasView }.count, 1)
        XCTAssertTrue(try plate("capture.annotation.style", in: root).isHidden)
        XCTAssertFalse(try button("capture.action.arrow.uturn.backward", in: root).isEnabled, "首次框选不是一次标注编辑")
    }

    func testRetinaDrawingUsesOriginalImagePixelsAndUndoRedo() throws {
        let overlay = try makeOverlay(scale: 2)
        defer { overlay.close() }
        try select(CGRect(x: 120, y: 100, width: 500, height: 300), in: overlay)
        let root = try XCTUnwrap(overlay.contentView)
        try button("capture.annotation.tool.1", in: root).performClick(nil)
        root.layoutSubtreeIfNeeded()
        let canvas = try annotationCanvas(in: overlay)
        try drag(from: CGPoint(x: 30, y: 40), to: CGPoint(x: 180, y: 140), on: canvas, window: overlay)
        let mark = try XCTUnwrap(canvas.document.annotations.first)
        XCTAssertEqual(mark.bounds, CGRect(x: 300, y: 280, width: 300, height: 200))
        XCTAssertEqual(canvas.document.cropRect, CGRect(x: 240, y: 200, width: 1000, height: 600))
        XCTAssertFalse(try button("capture.action.rectangle.expand.vertical", in: root).isEnabled, "避免开始长图时无提示丢掉已画标注")
        try button("capture.action.arrow.uturn.backward", in: root).performClick(nil)
        XCTAssertTrue(canvas.document.annotations.isEmpty)
        XCTAssertTrue(try button("capture.action.rectangle.expand.vertical", in: root).isEnabled)
        try button("capture.action.arrow.uturn.forward", in: root).performClick(nil)
        XCTAssertEqual(canvas.document.annotations, [mark])
    }

    func testResizeSelectionKeepsMarksAnchoredToSourcePixelsAndCanBeUndone() throws {
        let overlay = try makeOverlay(scale: 2)
        defer { overlay.close() }
        try select(CGRect(x: 120, y: 100, width: 500, height: 300), in: overlay)
        let root = try XCTUnwrap(overlay.contentView)
        try button("capture.annotation.tool.3", in: root).performClick(nil)
        let canvas = try annotationCanvas(in: overlay)
        try drag(from: CGPoint(x: 30, y: 40), to: CGPoint(x: 180, y: 140), on: canvas, window: overlay)
        let marks = canvas.document.annotations
        try button("capture.annotation.tool.7", in: root).performClick(nil)
        let selector = try selectionCanvas(in: overlay)
        try drag(from: CGPoint(x: 620, y: 400), to: CGPoint(x: 720, y: 460), on: selector, window: overlay)
        XCTAssertEqual(canvas.document.annotations, marks)
        XCTAssertEqual(canvas.document.cropRect, CGRect(x: 240, y: 200, width: 1200, height: 720))
        try button("capture.action.arrow.uturn.backward", in: root).performClick(nil)
        XCTAssertEqual(canvas.document.cropRect, CGRect(x: 240, y: 200, width: 1000, height: 600))
        XCTAssertEqual(canvas.document.annotations, marks)
    }

    func testColorAndWidthPropertiesAffectActualAnnotations() throws {
        let overlay = try makeOverlay()
        defer { overlay.close() }
        try select(CGRect(x: 120, y: 100, width: 500, height: 300), in: overlay)
        let root = try XCTUnwrap(overlay.contentView)
        try button("capture.annotation.tool.1", in: root).performClick(nil)
        let palette = try plate("capture.annotation.style", in: root)
        XCTAssertFalse(palette.isHidden)
        let blue = try XCTUnwrap(views(in: palette).compactMap { $0 as? AnnotationColorButton }.first { $0.identifier?.rawValue == "capture.annotation.color.4" })
        blue.performClick(nil)
        let width = try XCTUnwrap(views(in: palette).compactMap { $0 as? NSSegmentedControl }.first { !$0.isHidden })
        width.selectedSegment = 2
        _ = width.sendAction(width.action, to: width.target)
        let canvas = try annotationCanvas(in: overlay)
        try drag(from: CGPoint(x: 40, y: 40), to: CGPoint(x: 180, y: 140), on: canvas, window: overlay)
        guard case let .rectangle(_, color, lineWidth) = try XCTUnwrap(canvas.document.annotations.first).content else { return XCTFail("应创建矩形") }
        XCTAssertEqual(color, blue.annotationColor)
        XCTAssertEqual(lineWidth, 5)
    }

    func testTextClickStartsInlineIMEAndReturnDoesNotCompleteTheScreenshot() throws {
        let overlay = try makeOverlay()
        defer { overlay.close() }
        try select(CGRect(x: 120, y: 100, width: 500, height: 300), in: overlay)
        let root = try XCTUnwrap(overlay.contentView)
        try button("capture.annotation.tool.6", in: root).performClick(nil)
        let canvas = try annotationCanvas(in: overlay)
        try drag(from: CGPoint(x: 40, y: 40), to: CGPoint(x: 40, y: 40), on: canvas, window: overlay)
        let input = try XCTUnwrap(canvas.subviews.compactMap { $0 as? AnnotationInputTextView }.first)
        XCTAssertTrue(overlay.firstResponder === input)
        input.setMarkedText("zhongwen", selectedRange: NSRange(location: 8, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        let enter = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: overlay.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
        XCTAssertFalse(overlay.performKeyEquivalent(with: enter))
        XCTAssertTrue(overlay.firstResponder === input)
        input.unmarkText()
        input.string = "中文标注"
        input.onCommit?()
        guard case let .text(_, value, _, _) = try XCTUnwrap(canvas.document.annotations.first).content else { return XCTFail("应保存文字") }
        XCTAssertEqual(value, "中文标注")
    }

    func testTextCanBeDraggedWithoutChangingToolsAndDoubleClickedToEdit() throws {
        let overlay = try makeOverlay(scale: 2)
        defer { overlay.close() }
        try select(CGRect(x: 120, y: 100, width: 500, height: 300), in: overlay)
        let root = try XCTUnwrap(overlay.contentView)
        try button("capture.annotation.tool.6", in: root).performClick(nil)
        let canvas = try annotationCanvas(in: overlay)
        try drag(from: CGPoint(x: 40, y: 40), to: CGPoint(x: 40, y: 40), on: canvas, window: overlay)
        let input = try XCTUnwrap(canvas.subviews.compactMap { $0 as? AnnotationInputTextView }.first)
        input.string = "可拖动的文字"
        input.onCommit?()
        let original = try XCTUnwrap(canvas.document.annotations.first)
        XCTAssertEqual(canvas.tool, .text)
        try drag(from: CGPoint(x: 60, y: 50), to: CGPoint(x: 100, y: 80), on: canvas, window: overlay)
        let moved = try XCTUnwrap(canvas.document.annotations.first)
        XCTAssertEqual(moved, original.translated(dx: 80, dy: 60))
        XCTAssertEqual(canvas.document.annotations.count, 1)
        XCTAssertEqual(canvas.tool, .text)
        try button("capture.action.arrow.uturn.backward", in: root).performClick(nil)
        XCTAssertEqual(canvas.document.annotations, [original])
        try button("capture.action.arrow.uturn.forward", in: root).performClick(nil)
        XCTAssertEqual(canvas.document.annotations, [moved])
        let doubleClick = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: canvas.convert(CGPoint(x: 100, y: 80), to: nil), modifierFlags: [], timestamp: 2, windowNumber: overlay.windowNumber, context: nil, eventNumber: 0, clickCount: 2, pressure: 0))
        canvas.mouseDown(with: doubleClick)
        let editing = try XCTUnwrap(canvas.subviews.compactMap { $0 as? AnnotationInputTextView }.first)
        XCTAssertEqual(editing.string, "可拖动的文字")
        editing.string = "移动后继续编辑"
        editing.onCommit?()
        guard case let .text(rect, value, _, _) = try XCTUnwrap(canvas.document.annotations.first).content else { return XCTFail("应保留文字标注") }
        XCTAssertEqual(canvas.document.annotations.count, 1)
        XCTAssertEqual(canvas.document.annotations.first?.id, original.id)
        XCTAssertEqual(rect, moved.bounds)
        XCTAssertEqual(value, "移动后继续编辑")
    }

    func testShapesAndMosaicCanBeDrawnAndMovedInBothEditorsWithoutSwitchingTools() throws {
        let overlay = try makeOverlay(scale: 2)
        defer { overlay.close() }
        try select(CGRect(x: 120, y: 100, width: 500, height: 300), in: overlay)
        let editor = try AnnotationEditorWindowController(image: screen(scale: 2).image, onCancel: {}, onComplete: { _ in true })
        defer { editor.close() }
        let editorWindow = try XCTUnwrap(editor.window)
        for window in [overlay as NSWindow, editorWindow] {
            let root = try XCTUnwrap(window.contentView)
            root.layoutSubtreeIfNeeded()
            let canvas = try XCTUnwrap(views(in: root).compactMap { $0 as? AnnotationCanvasView }.first)
            let origin = canvas.document.cropRect.origin
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                canvas.viewRect(forPixelRect: CGRect(x: origin.x + x, y: origin.y + y, width: 1, height: 1)).origin
            }
            for tool in [AnnotationTool.rectangle, .ellipse, .arrow, .brush, .mosaic] {
                let toolButton = try button("capture.annotation.tool.\(tool.rawValue)", in: root)
                toolButton.performClick(nil)
                try drag(from: point(80, 80), to: point(160, 140), on: canvas, window: window)
                let original = try XCTUnwrap(canvas.document.annotations.first)
                try drag(from: point(120, 110), to: point(160, 130), on: canvas, window: window)
                let moved = try XCTUnwrap(canvas.document.annotations.first)
                XCTAssertEqual(moved.id, original.id)
                XCTAssertEqual(moved.bounds.minX, original.bounds.minX + 40, accuracy: 0.001)
                XCTAssertEqual(moved.bounds.minY, original.bounds.minY + 20, accuracy: 0.001)
                XCTAssertEqual(canvas.document.annotations.count, 1)
                XCTAssertEqual(canvas.tool, tool)
                XCTAssertEqual(toolButton.state, .on)
                XCTAssertTrue(window.firstResponder === canvas)
                let undo = try button("capture.action.arrow.uturn.backward", in: root)
                undo.performClick(nil)
                XCTAssertEqual(canvas.document.annotations, [original])
                try button("capture.action.arrow.uturn.forward", in: root).performClick(nil)
                XCTAssertEqual(canvas.document.annotations, [moved])
                undo.performClick(nil)
                undo.performClick(nil)
                XCTAssertTrue(canvas.document.annotations.isEmpty)
            }
        }
    }

    func testClickingCanvasCommitsCurrentTextBeforeMovingAnotherText() throws {
        let overlay = try makeOverlay()
        defer { overlay.close() }
        try select(CGRect(x: 120, y: 100, width: 500, height: 300), in: overlay)
        let root = try XCTUnwrap(overlay.contentView)
        try button("capture.annotation.tool.6", in: root).performClick(nil)
        let canvas = try annotationCanvas(in: overlay)
        try drag(from: CGPoint(x: 40, y: 40), to: CGPoint(x: 40, y: 40), on: canvas, window: overlay)
        try XCTUnwrap(canvas.subviews.compactMap { $0 as? AnnotationInputTextView }.first).string = "第一段"
        try drag(from: CGPoint(x: 300, y: 200), to: CGPoint(x: 300, y: 200), on: canvas, window: overlay)
        let original = try XCTUnwrap(canvas.document.annotations.first)
        let second = try XCTUnwrap(canvas.subviews.compactMap { $0 as? AnnotationInputTextView }.first)
        second.string = "第二段"
        try drag(from: CGPoint(x: 60, y: 50), to: CGPoint(x: 80, y: 60), on: canvas, window: overlay)
        XCTAssertEqual(canvas.document.annotations.count, 2)
        XCTAssertEqual(canvas.document.annotations.first, original.translated(dx: 20, dy: 10))
        XCTAssertTrue(canvas.subviews.compactMap { $0 as? AnnotationInputTextView }.isEmpty)
        guard case let .text(_, value, _, _) = try XCTUnwrap(canvas.document.annotations.last).content else { return XCTFail("应保存尚未回车的文字") }
        XCTAssertEqual(value, "第二段")
    }

    func testTextDraggingStopsAtSelectionEdges() throws {
        let overlay = try makeOverlay()
        defer { overlay.close() }
        try select(CGRect(x: 120, y: 100, width: 500, height: 300), in: overlay)
        let root = try XCTUnwrap(overlay.contentView)
        try button("capture.annotation.tool.6", in: root).performClick(nil)
        let canvas = try annotationCanvas(in: overlay)
        try drag(from: CGPoint(x: 40, y: 40), to: CGPoint(x: 40, y: 40), on: canvas, window: overlay)
        let input = try XCTUnwrap(canvas.subviews.compactMap { $0 as? AnnotationInputTextView }.first)
        input.string = "边缘文字"
        input.onCommit?()
        try drag(from: CGPoint(x: 60, y: 50), to: CGPoint(x: -100, y: -100), on: canvas, window: overlay)
        XCTAssertEqual(canvas.document.annotations.first?.bounds.origin, canvas.document.cropRect.origin)
        try drag(from: CGPoint(x: 20, y: 10), to: CGPoint(x: 900, y: 900), on: canvas, window: overlay)
        let rect = try XCTUnwrap(canvas.document.annotations.first).bounds
        XCTAssertEqual(rect.maxX, canvas.document.cropRect.maxX, accuracy: 0.001)
        XCTAssertEqual(rect.maxY, canvas.document.cropRect.maxY, accuracy: 0.001)
        XCTAssertEqual(canvas.document.annotations.count, 1)
    }

    func testLongEditorAlsoShowsTextLabelAndAllowsDraggingInTextTool() throws {
        let editor = try AnnotationEditorWindowController(image: screen().image, onCancel: {}, onComplete: { _ in true })
        defer { editor.close() }
        let window = try XCTUnwrap(editor.window)
        let root = try XCTUnwrap(window.contentView)
        let text = try button("capture.annotation.tool.6", in: root)
        XCTAssertEqual(text.imagePosition, .noImage)
        XCTAssertNil(text.image)
        text.performClick(nil)
        let scroll = try XCTUnwrap(root.subviews.compactMap { $0 as? NSScrollView }.first)
        let canvas = try XCTUnwrap(scroll.documentView as? AnnotationCanvasView)
        let start = canvas.viewRect(forPixelRect: CGRect(x: 200, y: 150, width: 1, height: 1)).origin
        try drag(from: start, to: start, on: canvas, window: window)
        let input = try XCTUnwrap(canvas.subviews.compactMap { $0 as? AnnotationInputTextView }.first)
        input.string = "长图文字"
        input.onCommit?()
        let original = try XCTUnwrap(canvas.document.annotations.first)
        let from = canvas.viewRect(forPixelRect: CGRect(x: 220, y: 160, width: 1, height: 1)).origin
        let to = canvas.viewRect(forPixelRect: CGRect(x: 260, y: 180, width: 1, height: 1)).origin
        try drag(from: from, to: to, on: canvas, window: window)
        let moved = try XCTUnwrap(canvas.document.annotations.first)
        XCTAssertEqual(moved.bounds.minX, original.bounds.minX + 40, accuracy: 0.001)
        XCTAssertEqual(moved.bounds.minY, original.bounds.minY + 20, accuracy: 0.001)
        XCTAssertEqual(moved.id, original.id)
        XCTAssertEqual(canvas.document.annotations.count, 1)
        XCTAssertEqual(canvas.tool, .text)
    }

    func testEllipseAndBrushFollowFeishuOrderAndUseRetinaColorAndWidthControls() throws {
        let overlay = try makeOverlay(scale: 2)
        defer { overlay.close() }
        try select(CGRect(x: 120, y: 100, width: 500, height: 300), in: overlay)
        let root = try XCTUnwrap(overlay.contentView)
        let toolbar = try plate("capture.annotation.toolbar", in: root)
        let drawingTitles = toolbar.arrangedSubviews.compactMap { ($0 as? NSButton)?.identifier?.rawValue }
            .filter { ["capture.annotation.tool.1", "capture.annotation.tool.2", "capture.annotation.tool.3", "capture.annotation.tool.4", "capture.annotation.tool.5", "capture.annotation.tool.6"].contains($0) }
        XCTAssertEqual(drawingTitles, ["capture.annotation.tool.1", "capture.annotation.tool.2", "capture.annotation.tool.3", "capture.annotation.tool.4", "capture.annotation.tool.5", "capture.annotation.tool.6"])
        let palette = try plate("capture.annotation.style", in: root)
        let canvas = try annotationCanvas(in: overlay)
        for title in ["capture.annotation.tool.2", "capture.annotation.tool.4"] {
            let tool = try button(title, in: root)
            XCTAssertNotNil(tool.image)
            tool.performClick(nil)
            root.layoutSubtreeIfNeeded()
            XCTAssertFalse(palette.isHidden)
            let green = try XCTUnwrap(views(in: palette).compactMap { $0 as? AnnotationColorButton }.first { $0.identifier?.rawValue == "capture.annotation.color.3" })
            green.performClick(nil)
            let width = try XCTUnwrap(views(in: palette).compactMap { $0 as? NSSegmentedControl }.first { !$0.isHidden })
            width.selectedSegment = 2
            _ = width.sendAction(width.action, to: width.target)
            root.layoutSubtreeIfNeeded()
            for item in palette.arrangedSubviews where !item.isHidden {
                XCTAssertTrue(palette.bounds.contains(item.frame), "样式控件不能溢出属性栏")
            }
            try drag(from: CGPoint(x: 40, y: 40), to: CGPoint(x: 180, y: 140), on: canvas, window: overlay)
            let mark = try XCTUnwrap(canvas.document.annotations.last)
            switch mark.content {
            case let .ellipse(rect, color, lineWidth):
                XCTAssertEqual(rect, CGRect(x: 320, y: 280, width: 280, height: 200))
                XCTAssertEqual(color, green.annotationColor)
                XCTAssertEqual(lineWidth, 10)
            case let .brush(points, color, lineWidth):
                XCTAssertEqual(points, [CGPoint(x: 320, y: 280), CGPoint(x: 600, y: 480)])
                XCTAssertEqual(color, green.annotationColor)
                XCTAssertEqual(lineWidth, 10)
            default: XCTFail("应创建所选的新工具标注")
            }
            let marks = canvas.document.annotations
            try button("capture.action.arrow.uturn.backward", in: root).performClick(nil)
            XCTAssertEqual(canvas.document.annotations.count, marks.count - 1)
            try button("capture.action.arrow.uturn.forward", in: root).performClick(nil)
            XCTAssertEqual(canvas.document.annotations, marks)
        }
    }

    func testCompletingInlineSelectionPublishesRenderedMarksAndSaveIntent() async throws {
        for save in [false, true] {
            let overlay = try makeOverlay(scale: 2)
            defer { overlay.close() }
            try select(CGRect(x: 120, y: 100, width: 500, height: 300), in: overlay)
            let root = try XCTUnwrap(overlay.contentView)
            try button("capture.annotation.tool.1", in: root).performClick(nil)
            let canvas = try annotationCanvas(in: overlay)
            try drag(from: CGPoint(x: 40, y: 40), to: CGPoint(x: 180, y: 140), on: canvas, window: overlay)
            for title in ["capture.annotation.tool.2", "capture.annotation.tool.4"] {
                try button(title, in: root).performClick(nil)
                try drag(from: CGPoint(x: 200, y: 60), to: CGPoint(x: 350, y: 200), on: canvas, window: overlay)
            }
            let expected = try AnnotationRenderer.renderSynchronously(canvas.document.renderSnapshot())
            let published = XCTestExpectation(description: "发布选区标注")
            overlay.onOutput = { image, rect, _, isSave in
                XCTAssertEqual(isSave, save)
                XCTAssertEqual(rect, CGRect(x: 120, y: 100, width: 500, height: 300))
                XCTAssertEqual(image.width, 1000)
                XCTAssertEqual(image.height, 600)
                XCTAssertEqual(RGBAFrame(image: image)?.bytes, RGBAFrame(image: expected)?.bytes)
                published.fulfill()
                return true
            }
            try button(save ? "capture.action.square.and.arrow.down" : "capture.action.checkmark", in: root).performClick(nil)
            let result = await XCTWaiter.fulfillment(of: [published], timeout: 5)
            XCTAssertEqual(result, .completed)
        }
    }

    func testOutputFailureKeepsMarksAndReenablesRetry() async throws {
        let overlay = try makeOverlay()
        defer { overlay.close() }
        try select(CGRect(x: 120, y: 100, width: 500, height: 300), in: overlay)
        let root = try XCTUnwrap(overlay.contentView)
        let complete = try button("capture.action.checkmark", in: root)
        let attempted = XCTestExpectation(description: "输出失败返回")
        overlay.onOutput = { _, _, _, _ in attempted.fulfill(); return false }
        complete.performClick(nil)
        let waited = await XCTWaiter.fulfillment(of: [attempted], timeout: 5)
        XCTAssertEqual(waited, .completed)
        for _ in 0 ..< 10 {
            await Task.yield()
        }
        XCTAssertTrue(complete.isEnabled)
        XCTAssertFalse(try plate("capture.annotation.toolbar", in: root).isHidden)
    }

    func testToolStyleRowDoesNotMoveMainToolbarAndBothFitNearScreenEdges() throws {
        let bounds = CGRect(x: 0, y: 0, width: 900, height: 650)
        for selection in [CGRect(x: 0, y: 0, width: 400, height: 300), CGRect(x: 500, y: 350, width: 400, height: 300), CGRect(x: 0, y: 0, width: 900, height: 650)] {
            let layout = SelectionToolbarLayout(bounds: bounds, selection: selection, toolbarSize: CGSize(width: 440, height: 38), paletteSize: CGSize(width: 340, height: 36), badgeSize: CGSize(width: 120, height: 26))
            XCTAssertTrue(bounds.contains(layout.toolbar))
            XCTAssertTrue(bounds.contains(layout.palette))
            XCTAssertTrue(bounds.contains(layout.sizeBadge))
        }
        let overlay = try makeOverlay()
        defer { overlay.close() }
        try select(CGRect(x: 400, y: 300, width: 450, height: 300), in: overlay)
        let root = try XCTUnwrap(overlay.contentView)
        let toolbar = try plate("capture.annotation.toolbar", in: root)
        root.layoutSubtreeIfNeeded()
        let frame = toolbar.frame
        try button("capture.annotation.tool.1", in: root).performClick(nil)
        root.layoutSubtreeIfNeeded()
        XCTAssertEqual(toolbar.frame, frame)
        for title in ["capture.annotation.tool.2", "capture.annotation.tool.4"] {
            try button(title, in: root).performClick(nil)
            root.layoutSubtreeIfNeeded()
            XCTAssertEqual(toolbar.frame, frame)
            XCTAssertTrue(root.bounds.contains(toolbar.frame))
            XCTAssertTrue(try root.bounds.contains(plate("capture.annotation.style", in: root).frame))
            let buttons = toolbar.arrangedSubviews.compactMap { $0 as? NSButton }
            for button in buttons {
                XCTAssertTrue(toolbar.bounds.contains(button.frame), button.title)
            }
        }
    }

    func testInlineToolbarRendersInLightAndDarkThemes() throws {
        let overlay = try makeOverlay()
        defer { overlay.close() }
        try select(CGRect(x: 160, y: 100, width: 580, height: 330), in: overlay)
        let root = try XCTUnwrap(overlay.contentView)
        try button("capture.annotation.tool.1", in: root).performClick(nil)
        let canvas = try annotationCanvas(in: overlay)
        try drag(from: CGPoint(x: 60, y: 70), to: CGPoint(x: 380, y: 180), on: canvas, window: overlay)
        try button("capture.annotation.tool.2", in: root).performClick(nil)
        try drag(from: CGPoint(x: 180, y: 100), to: CGPoint(x: 480, y: 260), on: canvas, window: overlay)
        try button("capture.annotation.tool.4", in: root).performClick(nil)
        try drag(from: CGPoint(x: 90, y: 220), to: CGPoint(x: 420, y: 250), on: canvas, window: overlay)
        try button("capture.annotation.tool.6", in: root).performClick(nil)
        try drag(from: CGPoint(x: 60, y: 270), to: CGPoint(x: 60, y: 270), on: canvas, window: overlay)
        let input = try XCTUnwrap(canvas.subviews.compactMap { $0 as? AnnotationInputTextView }.first)
        input.string = "拖动文字"
        input.onCommit?()
        try drag(from: CGPoint(x: 80, y: 280), to: CGPoint(x: 120, y: 285), on: canvas, window: overlay)
        for (name, appearance) in [("浅色", NSAppearance.Name.aqua), ("暗色", .darkAqua)] {
            overlay.appearance = try XCTUnwrap(NSAppearance(named: appearance))
            root.layoutSubtreeIfNeeded()
            root.displayIfNeeded()
            let bitmap = try XCTUnwrap(root.bitmapImageRepForCachingDisplay(in: root.bounds))
            root.cacheDisplay(in: root.bounds, to: bitmap)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
            attachment.name = "选区内标注-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertFalse(try plate("capture.annotation.toolbar", in: root).isHidden)
        }
    }

    func testInlineFlowFailureReturnsToSelectionAndSuccessFinishesSession() async throws {
        let flow = CaptureFlowController()
        let session = try XCTUnwrap(flow.sessions.begin(mode: .normal, targetProcessID: 42))
        XCTAssertTrue(flow.sessions.transition(sessionID: session.id, generation: session.generation, to: .selecting))
        let screen = try screen()
        var attempts = 0
        flow.onImageReady = { image, _ in attempts += 1; XCTAssertEqual(image.width, screen.image.width); return attempts > 1 }
        let rect = CGRect(x: 0, y: 0, width: 900, height: 650)
        let failed = await flow.publishInlineSelection(image: screen.image, on: screen, localRect: rect, selectedWindow: nil, save: false)
        XCTAssertFalse(failed)
        XCTAssertEqual(flow.sessions.activeSession?.state, .selecting)
        let succeeded = await flow.publishInlineSelection(image: screen.image, on: screen, localRect: rect, selectedWindow: nil, save: false)
        XCTAssertTrue(succeeded)
        XCTAssertNil(flow.sessions.activeSession)
        XCTAssertEqual(attempts, 2)
    }

    private func makeOverlay(scale: Int = 1) throws -> SelectionOverlayWindow {
        try SelectionOverlayWindow(screen: screen(scale: scale), initialMode: .normal)
    }

    private func screen(scale: Int = 1) throws -> FrozenScreen {
        let width = 900 * scale
        let height = 650 * scale
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 0.98, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(gray: 0.75, alpha: 1))
        for row in 0 ..< 18 {
            context.fill(CGRect(x: 200 * scale, y: (100 + row * 25) * scale, width: (250 + row % 4 * 40) * scale, height: 3 * scale))
        }
        let image = try XCTUnwrap(context.makeImage())
        let frame = CGRect(x: 0, y: 0, width: 900, height: 650)
        return try FrozenScreen(displayID: 0, screenFrame: frame, image: image, transform: DisplayTransform(screenFrame: frame, pixelWidth: width, pixelHeight: height), windows: [])
    }

    private func select(_ rect: CGRect, in overlay: SelectionOverlayWindow) throws {
        try drag(from: rect.origin, to: CGPoint(x: rect.maxX, y: rect.maxY), on: selectionCanvas(in: overlay), window: overlay)
        overlay.contentView?.layoutSubtreeIfNeeded()
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

    private func selectionCanvas(in overlay: SelectionOverlayWindow) throws -> NSView {
        try XCTUnwrap(overlay.contentView?.subviews.first { $0.identifier?.rawValue == "capture.selection.canvas" })
    }

    private func annotationCanvas(in overlay: SelectionOverlayWindow) throws -> AnnotationCanvasView {
        try XCTUnwrap(overlay.contentView?.subviews.compactMap { $0 as? AnnotationCanvasView }.first)
    }

    private func views(in view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { views(in: $0) }
    }

    private func button(_ title: String, in root: NSView) throws -> NSButton {
        try XCTUnwrap(views(in: root).compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == title })
    }

    private func plate(_ id: String, in root: NSView) throws -> NSStackView {
        try XCTUnwrap(root.subviews.compactMap { $0 as? NSStackView }.first { $0.identifier?.rawValue == id })
    }
}
