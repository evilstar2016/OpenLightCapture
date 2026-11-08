import AppKit
import ImageIO
@testable import LightCapture
import SwiftUI
import XCTest

@MainActor
final class WatermarkIntegrationTests: XCTestCase {
    func testDedicatedLongCaptureEntryKeepsTheDefaultWatermarkForItsResult() throws {
        let overlay = try makeOverlay(mode: .long)
        defer { overlay.close() }
        XCTAssertEqual(overlay.watermarkSelection, library().defaultSelection)
        XCTAssertFalse(try views(XCTUnwrap(overlay.contentView)).contains { $0 is AnnotationCanvasView }, "长图开始前不进入普通截图标注")
    }

    func testInlineDefaultAndFailedOutputRetryUseExactlyOneWatermark() async throws {
        let overlay = try makeOverlay()
        defer { overlay.close() }
        let canvas = try XCTUnwrap(try views(XCTUnwrap(overlay.contentView)).compactMap { $0 as? AnnotationCanvasView }.first)
        XCTAssertEqual(canvas.document.watermark, library().defaultSelection)
        XCTAssertTrue(canvas.document.annotations.isEmpty)
        let expected = try AnnotationRenderer.renderSynchronously(canvas.document.renderSnapshot())
        let complete = try button("capture.action.checkmark", in: XCTUnwrap(overlay.contentView))
        let first = XCTestExpectation(description: "First output failed")
        let second = XCTestExpectation(description: "Retry succeeded")
        var attempts = 0
        overlay.onOutput = { image, _, _, _ in
            attempts += 1
            XCTAssertEqual(RGBAFrame(image: image)?.bytes, RGBAFrame(image: expected)?.bytes)
            if attempts == 1 { first.fulfill(); return false }
            second.fulfill()
            return true
        }
        complete.performClick(nil)
        await fulfillment(of: [first], timeout: 5)
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        XCTAssertTrue(complete.isEnabled)
        XCTAssertEqual(canvas.document.watermark, library().defaultSelection)
        XCTAssertTrue(try button("capture.action.watermark", in: XCTUnwrap(overlay.contentView)).isEnabled)
        complete.performClick(nil)
        await fulfillment(of: [second], timeout: 5)
        XCTAssertEqual(attempts, 2)
    }

    func testWatermarkOnlySelectionCanStartLongCaptureAndCarriesCurrentValue() throws {
        let overlay = try makeOverlay()
        defer { overlay.close() }
        let root = try XCTUnwrap(overlay.contentView)
        let canvas = try XCTUnwrap(views(root).compactMap { $0 as? AnnotationCanvasView }.first)
        var selection = try XCTUnwrap(canvas.document.watermark)
        selection.text = "@changed-for-this-shot"
        canvas.document.setWatermark(selection)
        canvas.refresh()
        let long = try button("capture.action.rectangle.expand.vertical", in: root)
        XCTAssertTrue(long.isEnabled)
        var requested = false
        overlay.onLongCapture = { rect, _, _ in
            requested = true
            XCTAssertEqual(rect.size, CGSize(width: 500, height: 300))
            XCTAssertEqual(overlay.watermarkSelection, selection)
        }
        long.performClick(nil)
        XCTAssertTrue(requested)
    }

    func testRecordingButtonsOfferToClearEditsThenRecordImmediatelyWhenWatermarkExists() async throws {
        let overlay = try makeOverlay()
        defer { overlay.close() }
        let root = try XCTUnwrap(overlay.contentView)
        let canvas = try XCTUnwrap(views(root).compactMap { $0 as? AnnotationCanvasView }.first)
        let gif = try button("capture.selection.gif", in: root)
        let video = try button("capture.selection.video", in: root)
        XCTAssertEqual(canvas.document.watermark, library().defaultSelection)
        XCTAssertTrue(gif.isEnabled, "带水印时录制按钮保持可点，点击后询问是否清除")
        XCTAssertTrue(video.isEnabled)
        XCTAssertEqual(gif.toolTip, L10n.recordingClearsEdits)
        var requested: [CaptureMode] = []
        overlay.onGIFCapture = { _, _ in requested.append(.gif) }
        overlay.onVideoCapture = { _, _ in requested.append(.video) }

        gif.performClick(nil)
        _ = try await waitUntil { NSApp.windows.first { $0.sheetParent === overlay } != nil }
        let sheet = try XCTUnwrap(NSApp.windows.first { $0.sheetParent === overlay })
        let buttons = views(sheet.contentView ?? NSView()).compactMap { $0 as? NSButton }
        let cancel = try XCTUnwrap(buttons.first { $0.title == L10n.actionCancel })
        let confirm = try XCTUnwrap(buttons.first { $0.title == L10n.recordingClearConfirm })
        cancel.performClick(nil)
        try await waitUntil { NSApp.windows.first { $0.sheetParent === overlay } == nil }
        XCTAssertTrue(requested.isEmpty, "取消确认不会开始录制")
        XCTAssertEqual(canvas.document.watermark, library().defaultSelection, "取消确认保留水印")

        gif.performClick(nil)
        _ = try await waitUntil { NSApp.windows.first { $0.sheetParent === overlay } != nil }
        let secondSheet = try XCTUnwrap(NSApp.windows.first { $0.sheetParent === overlay })
        let secondButtons = views(secondSheet.contentView ?? NSView()).compactMap { $0 as? NSButton }
        try XCTUnwrap(secondButtons.first { $0.title == L10n.recordingClearConfirm }).performClick(nil)
        try await waitUntil { NSApp.windows.first { $0.sheetParent === overlay } == nil }
        try await waitUntil { requested == [.gif] }
        XCTAssertNil(canvas.document.watermark, "确认后清除水印")
        XCTAssertTrue(canvas.document.annotations.isEmpty, "确认后清除全部标注")
        XCTAssertEqual(gif.toolTip, L10n.gifTitle, "清除后恢复默认提示")

        video.performClick(nil)
        try await waitUntil { requested == [.gif, .video] }
    }

    private func waitUntil(_ predicate: @MainActor () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws -> Bool {
        for _ in 0 ..< 400 {
            if predicate() { return true }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for recording confirmation UI", file: file, line: line)
        return false
    }

    func testDirectRecordingSelectionExcludesDefaultWatermarkFromPreview() throws {
        for mode in [CaptureMode.gif, .video] {
            let overlay = try makeOverlay(mode: mode)
            defer { overlay.close() }
            let root = try XCTUnwrap(overlay.contentView)
            let canvas = try XCTUnwrap(views(root).compactMap { $0 as? AnnotationCanvasView }.first)
            XCTAssertNil(canvas.document.watermark)
            let watermark = try button("capture.action.watermark", in: root)
            XCTAssertTrue(watermark.isHidden)
            XCTAssertFalse(watermark.isEnabled)
            XCTAssertTrue(try button("capture.selection.gif", in: root).isEnabled)
            XCTAssertTrue(try button("capture.selection.video", in: root).isEnabled)
        }
    }

    func testLongEditorSaveAndCopyReceiveSameCompositionAndPreserveStateOnFailure() async throws {
        let source = try image(width: 400, height: 900)
        let selection = try XCTUnwrap(library().defaultSelection)
        let expected = try AnnotationRenderer.renderSynchronously(AnnotationDocument(image: source, watermark: selection).renderSnapshot())
        let saved = XCTestExpectation(description: "Save cancelled")
        let copied = XCTestExpectation(description: "Copied after cancel")
        let editor = AnnotationEditorWindowController(image: source, onCancel: {}, onComplete: { image in
            XCTAssertEqual(RGBAFrame(image: image)?.bytes, RGBAFrame(image: expected)?.bytes)
            copied.fulfill()
            return true
        }, onSave: { image in
            XCTAssertEqual(RGBAFrame(image: image)?.bytes, RGBAFrame(image: expected)?.bytes)
            saved.fulfill()
            return false
        }, bannerMessage: "Partial result", watermarkLibrary: library(), watermark: selection)
        defer { editor.close() }
        let root = try XCTUnwrap(editor.window?.contentView)
        let canvas = try XCTUnwrap(views(root).compactMap { $0 as? AnnotationCanvasView }.first)
        try button("capture.action.square.and.arrow.down", in: root).performClick(nil)
        XCTAssertFalse(try button("capture.action.watermark", in: root).isEnabled)
        await fulfillment(of: [saved], timeout: 5)
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        XCTAssertEqual(canvas.document.watermark, selection)
        XCTAssertTrue(try button("capture.action.watermark", in: root).isEnabled)
        try button("capture.action.checkmark", in: root).performClick(nil)
        await fulfillment(of: [copied], timeout: 5)
    }

    func testWatermarkedClipboardImageAndFileHaveIdenticalPNGData() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "watermark-output-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let document = try AnnotationDocument(image: image(width: 400, height: 300), watermark: library().defaultSelection)
        let rendered = try AnnotationRenderer.renderSynchronously(document.renderSnapshot())
        let service = OutputDeliveryService(assetStore: AssetStore(rootURL: directory), pasteboard: pasteboard)
        let succeeded = await service.copy(rendered, startedAt: Date())
        XCTAssertTrue(succeeded)
        let data = try XCTUnwrap(pasteboard.data(forType: AssetStore.pngPasteboardType))
        let url = try XCTUnwrap(URL(string: XCTUnwrap(pasteboard.string(forType: .fileURL))))
        XCTAssertEqual(data, try Data(contentsOf: url))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(RGBAFrame(image: decoded)?.bytes, RGBAFrame(image: rendered)?.bytes)
    }

    func testManagerDuplicatesBuiltinWithoutChangingItAndRendersNativeViews() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "watermark-ui-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WatermarkTemplateStore(directory: directory)
        let manager = WatermarkManagerWindowController(store: store)
        defer { manager.close() }
        let builtin = try XCTUnwrap(store.snapshot().templates.last)
        manager.model.select(builtin)
        manager.model.duplicate()
        manager.model.draft?.name = "Custom signature"
        manager.model.draft?.text = "Alice · @example"
        manager.model.save()
        XCTAssertNil(manager.model.error)
        XCTAssertFalse(manager.model.hasChanges)
        XCTAssertEqual(store.library.templates.count, 1)
        XCTAssertEqual(store.snapshot().templates.first { $0.id == builtin.id }, builtin)
        let custom = try XCTUnwrap(store.library.templates.first)
        XCTAssertNotEqual(custom.id, builtin.id)
        XCTAssertEqual(custom.text, "Alice · @example")
        try attach(XCTUnwrap(manager.window?.contentView), name: "Watermark-template-manager")
        let editor = try AnnotationEditorWindowController(image: image(width: 500, height: 1500), onCancel: {}, onComplete: { _ in false }, watermarkLibrary: store.snapshot(), watermark: custom.selection)
        defer { editor.close() }
        try attach(XCTUnwrap(editor.window?.contentView), name: "Watermark-long-editor")
        let overlay = try makeOverlay()
        defer { overlay.close() }
        try attach(XCTUnwrap(overlay.contentView), name: "Watermark-inline-editor")
        manager.model.delete()
        XCTAssertNil(manager.model.error)
        XCTAssertTrue(store.library.templates.isEmpty)
    }

    func testPopoverLayoutKeepsStyleControlsVisible() throws {
        let view = NSHostingView(rootView: WatermarkSelectionView(selection: library().defaultSelection, library: library(), onApply: { _ in }, onCancel: {}))
        view.frame.size = view.fittingSize
        XCTAssertEqual(view.frame.width, 420, accuracy: 1)
        XCTAssertGreaterThan(view.frame.height, 500)
        XCTAssertLessThan(view.frame.height, 700)
        try attach(view, name: "Watermark-selection-popover")
    }

    func testSettingsWatermarkSectionUsesInjectedLibraryAndFitsSettingsWidth() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "watermark-settings-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WatermarkTemplateStore(directory: directory)
        let template = WatermarkTemplate(name: String(repeating: "署名", count: 20), text: "Alice")
        try store.save(template)
        try store.setDefault(id: template.id)
        let view = NSHostingView(rootView: SettingsWatermarkSection(store: store).frame(width: 512).padding(24))
        view.frame.size = view.fittingSize
        XCTAssertEqual(view.frame.width, 560, accuracy: 1)
        XCTAssertLessThan(view.frame.height, 220)
        try attach(view, name: "Watermark-settings-section")
        XCTAssertEqual(store.snapshot().defaultSelection?.text, "Alice")
    }

    private func library() -> WatermarkLibrarySnapshot {
        let templates = WatermarkTemplate.builtins(in: LocalizationContext(languageIdentifier: "en"))
        return WatermarkLibrarySnapshot(templates: templates, defaultTemplateID: templates[0].id)
    }

    private func makeOverlay(mode: CaptureMode = .normal) throws -> SelectionOverlayWindow {
        let frame = CGRect(x: 0, y: 0, width: 900, height: 650)
        let screen = try FrozenScreen(displayID: 0, screenFrame: frame, image: image(width: 1800, height: 1300), transform: DisplayTransform(screenFrame: frame, pixelWidth: 1800, pixelHeight: 1300), windows: [])
        let overlay = SelectionOverlayWindow(screen: screen, initialMode: mode, watermarkLibrary: library())
        let root = try XCTUnwrap(overlay.contentView)
        let selector = try XCTUnwrap(views(root).first { $0.identifier?.rawValue == "capture.selection.canvas" })
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

    private func image(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    private func views(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(views)
    }

    private func button(_ id: String, in view: NSView) throws -> NSButton {
        try XCTUnwrap(views(view).compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == id })
    }

    private func attach(_ view: NSView, name: String) throws {
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let attachment = try XCTAttachment(data: XCTUnwrap(bitmap.representation(using: .png, properties: [:])), uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
