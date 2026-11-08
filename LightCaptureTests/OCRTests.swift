import AppKit
import CoreGraphics
@testable import LightCapture
import XCTest

@MainActor
final class OCRTests: XCTestCase {
    func testCPUFallbackRetriesOnceAndNeverRetriesCancellation() throws {
        var modes: [Bool] = []
        let result = try OCRExecution.run(preferCPU: false, checkCancellation: {}) { cpuOnly in
            modes.append(cpuOnly)
            if !cpuOnly { throw TextRecognitionError.failed }
            return 42
        }
        XCTAssertEqual(result, 42)
        XCTAssertEqual(modes, [false, true])
        modes = []
        XCTAssertThrowsError(try OCRExecution.run(preferCPU: false, checkCancellation: {}) { cpuOnly in
            modes.append(cpuOnly)
            throw CancellationError()
        }) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertEqual(modes, [false])
        modes = []
        var cancelled = false
        XCTAssertThrowsError(try OCRExecution.run(preferCPU: false, checkCancellation: {
            if cancelled { throw CancellationError() }
        }) { cpuOnly in
            modes.append(cpuOnly)
            cancelled = true
            throw TextRecognitionError.failed
        }) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertEqual(modes, [false])
        modes = []
        _ = try OCRExecution.run(preferCPU: true, checkCancellation: {}) { cpuOnly in modes.append(cpuOnly) }
        XCTAssertEqual(modes, [true])
    }

    func testTilePlanCoversEntireCapacityWithoutGapsOrOversizedTiles() throws {
        for (width, height) in [(900, 50000), (1200, 50000), (8000, 7500), (900, 600), (1, 1)] {
            let regions = try OCRLayout.regions(width: width, height: height)
            XCTAssertEqual(regions.first?.minY, 0)
            XCTAssertEqual(regions.last?.maxY, CGFloat(height))
            for (index, rect) in regions.enumerated() {
                XCTAssertEqual(rect.width, CGFloat(width))
                XCTAssertLessThanOrEqual(rect.width * rect.height, 8_000_000)
                if index > 0 {
                    XCTAssertLessThan(rect.minY, regions[index - 1].maxY)
                    XCTAssertGreaterThan(rect.maxY, regions[index - 1].maxY)
                }
            }
        }
        XCTAssertThrowsError(try OCRLayout.regions(width: 1201, height: 50000))
        XCTAssertThrowsError(try OCRLayout.regions(width: 0, height: 20))
    }

    func testSpatialDeduplicationKeepsRepeatedLinesAndPrefersCompleteSeamText() {
        let lines = [
            line("Repeated", x: 20, y: 100),
            line("Repeated", x: 20, y: 140),
            line("Seam", x: 20, y: 200, confidence: 1, clipped: true),
            line("Seam complete", x: 20, y: 200, confidence: 0.8),
            line("right", x: 300, y: 140),
        ]
        let unique = OCRLayout.uniqueLines(lines)
        XCTAssertEqual(unique.count, 4)
        XCTAssertEqual(OCRLayout.text(from: unique), "Repeated\nRepeated right\nSeam complete")
        XCTAssertFalse(unique.contains(where: \.clipped))
    }

    func testTextPublishingReplacesImageTypesWithoutCreatingAnAsset() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setData(Data([1, 2, 3]), forType: .png)
        let output = OutputDeliveryService(assetStore: AssetStore(rootURL: root), pasteboard: pasteboard)
        var imageNotifications = 0
        output.onPublished = { imageNotifications += 1 }
        let text = "  修改后的文字\nHello 123!\n"
        try output.copyText(text)
        XCTAssertEqual(pasteboard.string(forType: .string), text)
        assertPlainText(pasteboard)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        XCTAssertEqual(imageNotifications, 0)
        XCTAssertThrowsError(try output.copyText(" \n"))
        XCTAssertEqual(pasteboard.string(forType: .string), text)
        XCTAssertThrowsError(try output.copyText("stale", isCurrent: { false }))
        XCTAssertEqual(pasteboard.string(forType: .string), text)
    }

    func testPreviewDoesNotPublishAndSelectionCopyKeepsPreviewOpen() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("previous", forType: .string)
        var finishedText: String?
        let controller = try OCRSessionController(snapshot: snapshot(), recognize: { _ in
            OCRResult(text: "Hello 测试文字", lineCount: 1, tileCount: 1)
        }, isCurrent: { true }, onReturn: {}, onCopy: { finishedText = $0 })
        defer { controller.dismiss() }
        controller.start()
        try await waitUntil { controller.state == .ready }
        XCTAssertEqual(pasteboard.string(forType: .string), "previous")
        let textView = controller.windowController.textView
        textView.copyPasteboard = pasteboard
        textView.setSelectedRange((textView.string as NSString).range(of: "测试文字"))
        textView.copy(nil)
        XCTAssertEqual(pasteboard.string(forType: .string), "测试文字")
        assertPlainText(pasteboard)
        XCTAssertEqual(controller.state, .ready)
        XCTAssertNil(finishedText)
        textView.string = "edited\n修改"
        controller.copyAndFinish()
        XCTAssertEqual(finishedText, "edited\n修改")
        XCTAssertEqual(controller.state, .dismissed)
    }

    func testCopyFailureKeepsUserEditsAndEmptyTextCannotFinish() async throws {
        var attempts = 0
        let controller = try OCRSessionController(snapshot: snapshot(), recognize: { _ in
            OCRResult(text: "original", lineCount: 1, tileCount: 1)
        }, isCurrent: { true }, onReturn: {}, onCopy: { _ in
            attempts += 1
            throw ClipboardPublishError.pasteboardRejected
        })
        defer { controller.dismiss() }
        controller.start()
        try await waitUntil { controller.state == .ready }
        controller.windowController.textView.string = "修改后"
        controller.copyAndFinish()
        XCTAssertEqual(controller.state, .ready)
        XCTAssertEqual(controller.windowController.textView.string, "修改后")
        XCTAssertEqual(attempts, 1)
        controller.windowController.textView.string = " \n"
        controller.copyAndFinish()
        XCTAssertEqual(attempts, 1)
    }

    func testEmptyAndFailureCanRetryWithoutDuplicatingRunningRequests() async throws {
        let sequence = OCRSequence()
        let controller = try OCRSessionController(snapshot: snapshot(), recognize: { _ in try await sequence.next() },
                                                  isCurrent: { true }, onReturn: {}, onCopy: { _ in })
        defer { controller.dismiss() }
        controller.start()
        controller.start()
        try await waitUntil { controller.state == .empty }
        controller.retry()
        try await waitUntil { controller.state == .failed }
        controller.retry()
        try await waitUntil { controller.state == .ready }
        let count = await sequence.count
        XCTAssertEqual(count, 3)
    }

    func testReturningToLongEditorPreservesItsDocumentFrameAndScroll() async throws {
        let (flow, editorWindow) = try makeFlow()
        defer { flow.cancelCurrentSession() }
        let root = try XCTUnwrap(editorWindow.contentView)
        let canvas = try XCTUnwrap(views(in: root).compactMap { $0 as? AnnotationCanvasView }.first)
        let mark = Annotation(content: .rectangle(rect: CGRect(x: 40, y: 50, width: 100, height: 60), color: .red, lineWidth: 3))
        canvas.document.add(mark)
        let frame = editorWindow.frame
        let scroll = try XCTUnwrap(views(in: root).compactMap { $0 as? NSScrollView }.first)
        scroll.contentView.scroll(to: CGPoint(x: 0, y: 200))
        let offset = scroll.contentView.bounds.origin
        try button("capture.action.ocr", in: root).performClick(nil)
        let ocr = try XCTUnwrap(flow.ocrController)
        XCTAssertFalse(editorWindow.isVisible)
        try await waitUntil { ocr.state == .ready }
        ocr.returnToImage()
        XCTAssertTrue(editorWindow.isVisible)
        XCTAssertEqual(flow.outputPanelParent, editorWindow)
        XCTAssertEqual(editorWindow.frame, frame)
        XCTAssertEqual(scroll.contentView.bounds.origin, offset)
        XCTAssertEqual(canvas.document.annotations, [mark])
        XCTAssertTrue(canvas.document.canUndo)
        XCTAssertNil(flow.ocrController)
        XCTAssertNotNil(flow.sessions.activeSession)
    }

    func testCopyingEditedTextEndsTheSameCaptureSession() async throws {
        let (flow, editor) = try makeFlow()
        defer { flow.cancelCurrentSession() }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        var copied: String?
        flow.onTextReady = { text, _ in
            copied = text
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }
        try button("capture.action.ocr", in: XCTUnwrap(editor.contentView)).performClick(nil)
        let ocr = try XCTUnwrap(flow.ocrController)
        try await waitUntil { ocr.state == .ready }
        ocr.windowController.textView.string = "最终全文\nFinal text"
        ocr.copyAndFinish()
        XCTAssertEqual(copied, "最终全文\nFinal text")
        XCTAssertNil(flow.sessions.activeSession)
        XCTAssertNil(flow.ocrController)
        XCTAssertFalse(editor.isVisible)
        assertPlainText(pasteboard)
    }

    func testInvalidatedSourceCanReturnWithoutLeavingAnOrphanOCRController() async throws {
        let (flow, editor) = try makeFlow()
        defer { flow.cancelCurrentSession() }
        let root = try XCTUnwrap(editor.contentView)
        let canvas = try XCTUnwrap(views(in: root).compactMap { $0 as? AnnotationCanvasView }.first)
        try button("capture.action.ocr", in: root).performClick(nil)
        let ocr = try XCTUnwrap(flow.ocrController)
        try await waitUntil { ocr.state == .ready }
        // Simulate a source invalidation independently of the disabled UI.
        canvas.document.add(Annotation(content: .rectangle(rect: CGRect(x: 20, y: 20, width: 30, height: 30), color: .red, lineWidth: 2)))
        ocr.returnToImage()
        XCTAssertEqual(ocr.state, .dismissed)
        XCTAssertNil(flow.ocrController)
        XCTAssertTrue(editor.isVisible)
        XCTAssertNotNil(flow.sessions.activeSession)
    }

    func testCancelledOldRequestCannotReopenOrPublishIntoNewSession() async throws {
        let gate = OCRGate()
        let (flow, editor) = try makeFlow(recognize: { _ in await gate.wait() })
        defer { flow.cancelCurrentSession() }
        var copied = false
        flow.onTextReady = { _, _ in copied = true }
        try button("capture.action.ocr", in: XCTUnwrap(editor.contentView)).performClick(nil)
        let old = try XCTUnwrap(flow.ocrController)
        try await waitUntil { await gate.started }
        flow.cancelCurrentSession()
        let next = try XCTUnwrap(flow.sessions.begin(mode: .normal, targetProcessID: nil))
        await gate.finish()
        for _ in 0 ..< 10 {
            await Task.yield()
        }
        old.copyAndFinish()
        XCTAssertEqual(old.state, .dismissed)
        XCTAssertFalse(old.windowController.window?.isVisible ?? true)
        XCTAssertEqual(flow.sessions.activeSession?.id, next.id)
        XCTAssertNil(flow.ocrController)
        XCTAssertFalse(copied)
    }

    func testResultWindowFitsBothThemesAndHasNoReturnDefaultButton() async throws {
        let controller = OCRResultWindowController()
        defer { controller.dismiss() }
        controller.showResult("本地文字识别\nEditable text 123\n\nOnly copying replaces the clipboard.")
        let window = try XCTUnwrap(controller.window)
        window.setContentSize(NSSize(width: 540, height: 380))
        controller.present(on: NSScreen.main)
        XCTAssertNil(window.defaultButtonCell)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: appearance)
            let root = try XCTUnwrap(window.contentView)
            root.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            try await Task.sleep(for: .milliseconds(30))
            for id in ["capture.ocr.return", "capture.ocr.copy"] {
                let button = try button(id, in: root)
                XCTAssertTrue(root.bounds.contains(root.convert(button.bounds, from: button)))
            }
            let bitmap = try XCTUnwrap(root.bitmapImageRepForCachingDisplay(in: root.bounds))
            root.cacheDisplay(in: root.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: "/tmp/lightcapture-ocr-preview-\(appearance.rawValue).png"))
        }
    }

    func testNormalSelectionOCRSubmitsCurrentCropAnnotationsAndWatermark() throws {
        let overlay = try selectedOverlay(mode: .normal)
        defer { overlay.close() }
        var requested: AnnotationRenderSnapshot?
        overlay.onRecognizeText = { requested = $0 }
        let root = try XCTUnwrap(overlay.contentView)
        let canvas = try XCTUnwrap(views(in: root).compactMap { $0 as? AnnotationCanvasView }.first)
        let annotation = Annotation(content: .mosaic(rect: CGRect(x: 150, y: 150, width: 80, height: 40), blockSize: 12))
        let watermark = WatermarkSelection(text: "SYNTHETIC", style: WatermarkStyle())
        canvas.document.add(annotation)
        canvas.document.setWatermark(watermark)
        try button("capture.action.ocr", in: root).performClick(nil)
        let snapshot = try XCTUnwrap(requested)
        XCTAssertEqual(snapshot.cropRect, canvas.document.cropRect)
        XCTAssertEqual(snapshot.annotations, [annotation])
        XCTAssertEqual(snapshot.watermark, watermark)
        XCTAssertEqual(snapshot.revision, canvas.document.revision)
        XCTAssertLessThan(snapshot.cropRect.width, 900)
    }

    func testRecordingSelectionHidesAndDisablesOCR() throws {
        for mode in [CaptureMode.gif, .video] {
            let overlay = try selectedOverlay(mode: mode)
            defer { overlay.close() }
            overlay.onRecognizeText = { _ in XCTFail("Recording must not start still-image OCR") }
            let ocr = try button("capture.action.ocr", in: XCTUnwrap(overlay.contentView))
            XCTAssertTrue(ocr.isHidden)
            XCTAssertFalse(ocr.isEnabled)
            ocr.performClick(nil)
        }
    }

    func testVisionRecognizesConsecutiveImagesAfterTemporaryObjectsAreReleased() async throws {
        // Each call drains the worker's autorelease pool. Exercise both later
        // sessions and small selections, rather than just the first request.
        for _ in 0 ..< 2 {
            for (width, height, fontSize) in [(2018, 1144, 36), (222, 44, 20), (178, 50, 16), (1338, 158, 36)] {
                let image = try image(width: width, height: height, lines: [("HELLO 123", 0)], fontSize: CGFloat(fontSize))
                let result = try await TextRecognitionService.recognize(snapshot: AnnotationDocument(image: image).renderSnapshot())
                XCTAssertTrue(result.text.contains("HELLO 123"), "Selection \(width)x\(height): \(result.text)")
                let temporaryItems = try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)
                XCTAssertFalse(temporaryItems.contains { $0.hasPrefix(OCRWorkerProcess.workspacePrefix) }, "OCR left a temporary image workspace")
            }
        }
    }

    func testVisionRecognizesDifferentTextAfterIdleBetweenSessions() async throws {
        for text in ["FIRST 本地文字识别", "SECOND 再次识别成功", "THIRD 连续识别测试"] {
            let image = try image(width: 1722, height: 1120, lines: [(text, 60), ("Hello World 12345", 180), ("测试中英文混排", 300)])
            let result = try await TextRecognitionService.recognize(snapshot: AnnotationDocument(image: image).renderSnapshot())
            XCTAssertTrue(result.text.contains(text), result.text)
            if text != "THIRD 连续识别测试" { try await Task.sleep(for: .seconds(25)) }
        }
    }

    func testWorkerCancellationTerminatesActiveAndLateInstalledProcesses() throws {
        for cancelBeforeInstall in [false, true] {
            let cancellation = OCRCancellation()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sleep")
            process.arguments = ["30"]
            try process.run()
            defer { if process.isRunning { process.terminate() }; process.waitUntilExit() }
            if cancelBeforeInstall {
                cancellation.cancel()
                XCTAssertThrowsError(try cancellation.installProcess(process)) { XCTAssertTrue($0 is CancellationError) }
            } else {
                try cancellation.installProcess(process)
                cancellation.cancel()
            }
            process.waitUntilExit()
            XCTAssertEqual(process.terminationReason, .uncaughtSignal)
            XCTAssertThrowsError(try cancellation.check()) { XCTAssertTrue($0 is CancellationError) }
        }
    }

    func testVisionReadsRetainedHeaderOnceAndEveryStitchedBodySection() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let header = try image(width: 1000, height: 200, lines: [("HEADER 13579", 40)])
        let page = try image(width: 1000, height: 2400, lines: [
            ("ALPHA 12345", 60), ("本地文字识别", 760), ("GAMMA 67890", 1460), ("OMEGA 54321", 2260),
        ])
        func frame(offset: Int) throws -> CGImage {
            let context = try XCTUnwrap(try CGContext(data: nil, width: 1000, height: 1200, bitsPerComponent: 8, bytesPerRow: 4000,
                                                      space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(header, in: CGRect(x: 0, y: 1000, width: 1000, height: 200))
            let body = try XCTUnwrap(page.cropping(topLeftRect: CGRect(x: 0, y: offset, width: 1000, height: 1000)))
            context.draw(body, in: CGRect(x: 0, y: 0, width: 1000, height: 1000))
            return try XCTUnwrap(context.makeImage())
        }
        let engine = LongCaptureEngine(sessionID: UUID(), workspaceRootURL: root, region: LongCaptureRegion(fixedHeaderHeight: 200),
                                       matcher: { _, _ in .accepted(verticalDisplacement: 700, horizontalDrift: 0) })
        _ = try await engine.consume(frame(offset: 0))
        _ = try await engine.consume(frame(offset: 700))
        _ = try await engine.consume(frame(offset: 1400))
        let stitched = try engine.finish()
        XCTAssertEqual(stitched.height, 2600)
        let result = try await TextRecognitionService.recognize(snapshot: AnnotationDocument(image: stitched).renderSnapshot())
        for text in ["HEADER 13579", "ALPHA 12345", "本地文字识别", "GAMMA 67890", "OMEGA 54321"] {
            XCTAssertEqual(result.text.components(separatedBy: text).count - 1, 1, result.text)
        }
        XCTAssertGreaterThan(result.tileCount, 1)
    }

    func testVisionReadsMixedTextAcrossLongImageIncludingBottom() async throws {
        let image = try image(width: 1000, height: 5000, lines: [
            ("ALPHA 12345", 60), ("本地文字识别", 2025), ("MIDDLE 67890", 3000), ("OMEGA 54321", 4800),
        ])
        let result = try await TextRecognitionService.recognize(snapshot: AnnotationDocument(image: image).renderSnapshot())
        XCTAssertGreaterThan(result.tileCount, 1)
        for text in ["ALPHA 12345", "本地文字识别", "MIDDLE 67890", "OMEGA 54321"] {
            XCTAssertTrue(result.text.contains(text), "Missing expected synthetic text: \(text). Result: \(result.text)")
            XCTAssertEqual(result.text.components(separatedBy: text).count - 1, 1)
        }
        XCTAssertLessThan(try XCTUnwrap(result.text.range(of: "ALPHA")).lowerBound, try XCTUnwrap(result.text.range(of: "OMEGA")).lowerBound)
    }

    func testVisionOnlyReadsCurrentCropAndRenderedAnnotations() async throws {
        let image = try image(width: 1000, height: 650, lines: [("OUTSIDE 99999", 40), ("INSIDE 12345", 350)])
        let document = AnnotationDocument(image: image, cropRect: CGRect(x: 0, y: 260, width: 1000, height: 350))
        document.add(Annotation(content: .text(rect: CGRect(x: 40, y: 440, width: 850, height: 80), value: "ADDED 67890", fontSize: 36, color: .red)))
        let result = try await TextRecognitionService.recognize(snapshot: document.renderSnapshot())
        XCTAssertTrue(result.text.contains("INSIDE 12345"), result.text)
        XCTAssertTrue(result.text.contains("ADDED 67890"), result.text)
        XCTAssertFalse(result.text.contains("OUTSIDE"), result.text)
    }

    private func selectedOverlay(mode: CaptureMode) throws -> SelectionOverlayWindow {
        let image = try image(width: 900, height: 650)
        let frame = CGRect(x: 0, y: 0, width: 900, height: 650)
        let screen = try FrozenScreen(displayID: 0, screenFrame: frame, image: image,
                                      transform: DisplayTransform(screenFrame: frame, pixelWidth: 900, pixelHeight: 650), windows: [])
        let overlay = SelectionOverlayWindow(screen: screen, initialMode: mode)
        let root = try XCTUnwrap(overlay.contentView)
        let selector = try XCTUnwrap(views(in: root).first { $0.identifier?.rawValue == "capture.selection.canvas" })
        for (type, point) in [(NSEvent.EventType.leftMouseDown, CGPoint(x: 120, y: 100)), (.leftMouseDragged, CGPoint(x: 620, y: 400)), (.leftMouseUp, CGPoint(x: 620, y: 400))] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: selector.convert(point, to: nil), modifierFlags: [],
                                                         timestamp: 1, windowNumber: overlay.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0))
            switch type {
            case .leftMouseDown: selector.mouseDown(with: event)
            case .leftMouseDragged: selector.mouseDragged(with: event)
            default: selector.mouseUp(with: event)
            }
        }
        return overlay
    }

    private func makeFlow(recognize: @escaping OCRSessionController.Recognizer = { _ in OCRResult(text: "Synthetic text", lineCount: 1, tileCount: 1) }) throws -> (CaptureFlowController, NSWindow) {
        let flow = CaptureFlowController()
        flow.textRecognizer = recognize
        let session = try XCTUnwrap(flow.sessions.begin(mode: .long, targetProcessID: nil))
        try flow.presentLongCaptureResult(image: image(width: 600, height: 2500), sessionID: session.id, generation: session.generation, bannerMessage: nil)
        return try (flow, XCTUnwrap(flow.outputPanelParent))
    }

    private func waitUntil(_ condition: @MainActor () async -> Bool) async throws {
        for _ in 0 ..< 1000 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for OCR state")
        throw CancellationError()
    }

    private func snapshot() throws -> AnnotationRenderSnapshot {
        try AnnotationDocument(image: image(width: 200, height: 100)).renderSnapshot()
    }

    private func line(_ text: String, x: CGFloat, y: CGFloat, confidence: Float = 0.9, clipped: Bool = false) -> OCRLine {
        OCRLine(text: text, bounds: CGRect(x: x, y: y, width: 200, height: 24), confidence: confidence, clipped: clipped)
    }

    private func image(width: Int, height: Int, lines: [(String, Int)] = [], fontSize: CGFloat = 36) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        for (text, y) in lines {
            (text as NSString).draw(at: NSPoint(x: 40, y: CGFloat(height - y) - fontSize - 14), withAttributes: [.font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: NSColor.black])
        }
        NSGraphicsContext.restoreGraphicsState()
        return try XCTUnwrap(context.makeImage())
    }

    private func views(in view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { views(in: $0) }
    }

    private func assertPlainText(_ pasteboard: NSPasteboard, file: StaticString = #filePath, line: UInt = #line) {
        // AppKit may advertise its legacy NSStringPboardType alias as well.
        let types = Set((pasteboard.types ?? []).map(\.rawValue))
        XCTAssertTrue(types.contains(NSPasteboard.PasteboardType.string.rawValue), file: file, line: line)
        XCTAssertTrue(types.isSubset(of: [NSPasteboard.PasteboardType.string.rawValue, "NSStringPboardType"]), file: file, line: line)
        XCTAssertNil(pasteboard.data(forType: .png), file: file, line: line)
        XCTAssertNil(pasteboard.string(forType: .fileURL), file: file, line: line)
        XCTAssertNil(pasteboard.string(forType: AssetStore.privatePasteboardType), file: file, line: line)
    }

    private func button(_ id: String, in root: NSView) throws -> NSButton {
        try XCTUnwrap(views(in: root).compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == id })
    }
}

private actor OCRSequence {
    private(set) var count = 0

    func next() throws -> OCRResult {
        count += 1
        if count == 2 { throw TextRecognitionError.failed }
        return OCRResult(text: count == 1 ? "" : "retry succeeded", lineCount: count == 1 ? 0 : 1, tileCount: 1)
    }
}

private actor OCRGate {
    private var continuation: CheckedContinuation<OCRResult, Never>?
    private(set) var started = false

    func wait() async -> OCRResult {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            started = true
        }
    }

    func finish() {
        continuation?.resume(returning: OCRResult(text: "STALE RESULT", lineCount: 1, tileCount: 1))
        continuation = nil
    }
}
