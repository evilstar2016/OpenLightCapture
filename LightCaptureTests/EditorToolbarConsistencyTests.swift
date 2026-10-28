import AppKit
import CoreGraphics
@testable import LightCapture
import XCTest

@MainActor
final class EditorToolbarConsistencyTests: XCTestCase {
    func testLongEditorMatchesSelectionToolOrderIconsAndActionAppearance() throws {
        let overlay = try makeOverlay()
        defer { overlay.close() }
        let normal = try toolbar(in: XCTUnwrap(overlay.contentView))
        let editor = try makeEditor()
        defer { editor.close() }
        let long = try toolbar(in: XCTUnwrap(editor.window?.contentView))
        let expected = ["capture.annotation.tool.7", "capture.annotation.tool.0", "capture.annotation.tool.1", "capture.annotation.tool.2", "capture.annotation.tool.3", "capture.annotation.tool.4", "capture.annotation.tool.5", "capture.annotation.tool.6"]
        XCTAssertEqual(toolButtons(in: normal).map { $0.identifier?.rawValue ?? "" }, expected)
        XCTAssertEqual(toolButtons(in: long).map { $0.identifier?.rawValue ?? "" }, expected)
        for title in expected + ["capture.action.arrow.uturn.backward", "capture.action.arrow.uturn.forward", "capture.action.square.and.arrow.down", "capture.action.xmark", "capture.action.checkmark"] {
            let a = try button(title, in: normal)
            let b = try button(title, in: long)
            XCTAssertFalse(b.isBordered, title)
            XCTAssertEqual(a.imagePosition, b.imagePosition, title)
            XCTAssertEqual(a.imageScaling, b.imageScaling, title)
            XCTAssertEqual(a.image?.tiffRepresentation, b.image?.tiffRepresentation, title)
            XCTAssertEqual(a.toolTip, b.toolTip, title)
            XCTAssertEqual(a.frame.width, b.frame.width, accuracy: 0.01, title)
            XCTAssertEqual(a.frame.height, b.frame.height, accuracy: 0.01, title)
        }
        XCTAssertEqual(normal.layer?.cornerRadius, long.layer?.cornerRadius)
        XCTAssertEqual(normal.spacing, long.spacing)
        XCTAssertEqual(try button("capture.annotation.tool.6", in: long).imagePosition, .noImage)
        XCTAssertNil(try button("capture.annotation.tool.6", in: long).image)
        XCTAssertEqual(long.arrangedSubviews.compactMap { ($0 as? NSButton)?.identifier?.rawValue }, expected + ["capture.action.rectangle.on.rectangle", "capture.action.arrow.uturn.backward", "capture.action.arrow.uturn.forward", "capture.action.square.and.arrow.down", "capture.action.xmark", "capture.action.checkmark"])
    }

    func testOnlyCurrentLongEditorToolIsSelectedAndTinted() throws {
        let editor = try makeEditor()
        defer { editor.close() }
        let root = try XCTUnwrap(editor.window?.contentView)
        let toolbar = try toolbar(in: root)
        let canvas = try canvas(in: root)
        for title in ["capture.annotation.tool.1", "capture.annotation.tool.2", "capture.annotation.tool.4", "capture.annotation.tool.6", "capture.annotation.tool.7", "capture.annotation.tool.0"] {
            let current = try button(title, in: toolbar)
            current.performClick(nil)
            XCTAssertEqual(canvas.tool.rawValue, current.tag)
            XCTAssertEqual(toolButtons(in: toolbar).filter { $0.state == .on }.map { $0.identifier?.rawValue ?? "" }, [title])
            for button in toolButtons(in: toolbar) {
                XCTAssertEqual(button.contentTintColor, button === current ? NSColor.controlAccentColor : .labelColor, button.title)
            }
        }
    }

    func testLongEditorIconActionsStillUndoRedoSaveAndComplete() async throws {
        for save in [false, true] {
            let published = XCTestExpectation(description: save ? "保存图标" : "完成图标")
            let image = try image()
            let output: (CGImage) async -> Bool = { rendered in
                XCTAssertEqual(rendered.width, image.width)
                XCTAssertEqual(rendered.height, image.height)
                XCTAssertNotEqual(RGBAFrame(image: rendered)?.bytes, RGBAFrame(image: image)?.bytes)
                published.fulfill()
                return true
            }
            let editor = AnnotationEditorWindowController(image: image, onCancel: {}, onComplete: { rendered in
                XCTAssertFalse(save, "保存按钮不能调用完成回调")
                return await output(rendered)
            }, onSave: { rendered in
                XCTAssertTrue(save, "完成按钮不能调用保存回调")
                return await output(rendered)
            })
            defer { editor.close() }
            let root = try XCTUnwrap(editor.window?.contentView)
            let canvas = try canvas(in: root)
            let mark = Annotation(content: .rectangle(rect: CGRect(x: 60, y: 70, width: 100, height: 60), color: .red, lineWidth: 4))
            canvas.document.add(mark)
            canvas.refresh()
            let toolbar = try toolbar(in: root)
            let undo = try button("capture.action.arrow.uturn.backward", in: toolbar)
            XCTAssertTrue(undo.isEnabled)
            undo.performClick(nil)
            XCTAssertTrue(canvas.document.annotations.isEmpty)
            XCTAssertFalse(undo.isEnabled)
            let redo = try button("capture.action.arrow.uturn.forward", in: toolbar)
            XCTAssertTrue(redo.isEnabled)
            redo.performClick(nil)
            XCTAssertEqual(canvas.document.annotations, [mark])
            try button(save ? "capture.action.square.and.arrow.down" : "capture.action.checkmark", in: toolbar).performClick(nil)
            let result = await XCTWaiter.fulfillment(of: [published], timeout: 5)
            XCTAssertEqual(result, .completed)
        }
    }

    func testLongEditorToolbarFitsMinimumWindowAndTracksBothThemes() throws {
        let editor = try makeEditor(banner: String(repeating: "部分长图仅包含已确认内容。", count: 10))
        defer { editor.close() }
        let window = try XCTUnwrap(editor.window)
        window.setContentSize(CGSize(width: 760, height: 520))
        let root = try XCTUnwrap(window.contentView)
        editor.windowDidResize(Notification(name: NSWindow.didResizeNotification))
        let toolbar = try toolbar(in: root)
        try button("capture.annotation.tool.2", in: toolbar).performClick(nil)
        for (name, appearance) in [("浅色", NSAppearance.Name.aqua), ("暗色", .darkAqua)] {
            window.appearance = try XCTUnwrap(NSAppearance(named: appearance))
            root.layoutSubtreeIfNeeded()
            root.displayIfNeeded()
            XCTAssertTrue(root.bounds.contains(root.convert(toolbar.bounds, from: toolbar)))
            for button in toolbar.arrangedSubviews.compactMap({ $0 as? NSButton }) {
                XCTAssertTrue(toolbar.bounds.contains(button.frame), button.title)
            }
            var expectedColor: CGColor?
            root.effectiveAppearance.performAsCurrentDrawingAppearance {
                expectedColor = NSColor.windowBackgroundColor.withAlphaComponent(0.98).cgColor
            }
            XCTAssertEqual(toolbar.layer?.backgroundColor, expectedColor)
            let bitmap = try XCTUnwrap(root.bitmapImageRepForCachingDisplay(in: root.bounds))
            root.cacheDisplay(in: root.bounds, to: bitmap)
            let attachment = try XCTAttachment(data: XCTUnwrap(bitmap.representation(using: .png, properties: [:])), uniformTypeIdentifier: "public.png")
            attachment.name = "长图统一工具栏-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func image() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 240, height: 700, bitsPerComponent: 8, bytesPerRow: 960, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 0.98, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 240, height: 700))
        return try XCTUnwrap(context.makeImage())
    }

    private func makeEditor(banner: String? = nil) throws -> AnnotationEditorWindowController {
        try AnnotationEditorWindowController(image: image(), onCancel: {}, onComplete: { _ in true }, onSave: { _ in true }, onChangeCaptureSource: { _ in }, bannerMessage: banner)
    }

    private func makeOverlay() throws -> SelectionOverlayWindow {
        let context = try XCTUnwrap(CGContext(data: nil, width: 900, height: 650, bitsPerComponent: 8, bytesPerRow: 3600, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let frame = CGRect(x: 0, y: 0, width: 900, height: 650)
        let screen = try FrozenScreen(displayID: 0, screenFrame: frame, image: image, transform: DisplayTransform(screenFrame: frame, pixelWidth: 900, pixelHeight: 650), windows: [])
        let overlay = SelectionOverlayWindow(screen: screen, initialMode: .normal)
        let root = try XCTUnwrap(overlay.contentView)
        let selector = try XCTUnwrap(root.subviews.first { $0.identifier?.rawValue == "capture.selection.canvas" })
        for (type, point) in [(NSEvent.EventType.leftMouseDown, CGPoint(x: 120, y: 100)), (.leftMouseDragged, CGPoint(x: 620, y: 400)), (.leftMouseUp, CGPoint(x: 620, y: 400))] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: selector.convert(point, to: nil), modifierFlags: [], timestamp: 1, windowNumber: overlay.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0))
            switch type {
            case .leftMouseDown: selector.mouseDown(with: event)
            case .leftMouseDragged: selector.mouseDragged(with: event)
            default: selector.mouseUp(with: event)
            }
        }
        root.layoutSubtreeIfNeeded()
        return overlay
    }

    private func views(in view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { views(in: $0) }
    }

    private func toolbar(in view: NSView) throws -> NSStackView {
        try XCTUnwrap(views(in: view).compactMap { $0 as? NSStackView }.first { $0.identifier?.rawValue == "capture.annotation.toolbar" })
    }

    private func toolButtons(in toolbar: NSStackView) -> [NSButton] {
        toolbar.arrangedSubviews.compactMap { $0 as? NSButton }.filter { $0.identifier?.rawValue.hasPrefix("capture.annotation.tool.") == true }
    }

    private func button(_ title: String, in view: NSView) throws -> NSButton {
        try XCTUnwrap(views(in: view).compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == title })
    }

    private func canvas(in root: NSView) throws -> AnnotationCanvasView {
        try XCTUnwrap(views(in: root).compactMap { $0 as? AnnotationCanvasView }.first)
    }
}
