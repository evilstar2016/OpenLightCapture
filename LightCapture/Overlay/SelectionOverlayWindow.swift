import AppKit
import Carbon.HIToolbox

typealias SelectionOutputHandler = @MainActor (CGImage, CGRect, CapturedWindow?, Bool) async -> Bool

@MainActor
final class SelectionOverlayWindow: NSPanel {
    private let rootView: SelectionOverlayRootView
    private let initialMode: CaptureMode

    var onCancel: (() -> Void)?
    var onOutput: SelectionOutputHandler?
    var onLongCapture: ((CGRect, CapturedWindow?, LongCaptureRegion) -> Void)?
    var onRecognizeText: ((AnnotationRenderSnapshot) -> Void)? {
        didSet { rootView.ocrAvailable = onRecognizeText != nil }
    }

    var onGIFCapture: ((CGRect, CapturedWindow?) -> Void)?
    var onVideoCapture: ((CGRect, CapturedWindow?) -> Void)?

    var watermarkSelection: WatermarkSelection? {
        rootView.watermarkSelection
    }

    init(screen: FrozenScreen, initialMode: CaptureMode, watermarkLibrary: WatermarkLibrarySnapshot = .empty) {
        self.initialMode = initialMode
        rootView = SelectionOverlayRootView(screen: screen, initialMode: initialMode, watermarkLibrary: watermarkLibrary)
        super.init(contentRect: screen.screenFrame, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        acceptsMouseMovedEvents = true
        rootView.onCancel = { [weak self] in self?.onCancel?() }
        rootView.onOutput = { [weak self] image, rect, window, save in
            guard let self else { return false }
            let wasVisible = isVisible
            // Native save/error dialogs must appear above the frozen overlay.
            if wasVisible { level = .floating }
            let succeeded = await onOutput?(image, rect, window, save) ?? false
            if succeeded {
                close()
            } else if wasVisible, rootView.canResume {
                level = .screenSaver
                makeKeyAndOrderFront(nil)
                makeFirstResponder(rootView.keyboardResponder)
            }
            return succeeded
        }
        rootView.onLongCapture = { [weak self] rect, window, region in
            self?.onLongCapture?(rect, window, region)
        }
        rootView.onRecognizeText = { [weak self] snapshot in self?.onRecognizeText?(snapshot) }
        rootView.onGIFCapture = { [weak self] rect, window in self?.onGIFCapture?(rect, window) }
        rootView.onVideoCapture = { [weak self] rect, window in self?.onVideoCapture?(rect, window) }
        contentView = rootView
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func close() {
        rootView.dismiss()
        super.close()
    }

    func present() {
        makeKeyAndOrderFront(nil)
        makeFirstResponder(rootView.keyboardResponder)
    }

    func isCurrentRevision(_ revision: UInt64) -> Bool {
        rootView.isCurrentRevision(revision)
    }

    func setOCRActive(_ active: Bool) {
        rootView.setOCRActive(active)
    }
}

@MainActor
private final class SelectionOverlayRootView: NSView {
    private let watermarkLibrary: WatermarkLibrarySnapshot
    private let watermarkPopover = WatermarkPopoverController()
    private var watermarkButton: NSButton!
    var watermarkSelection: WatermarkSelection? {
        document?.watermark
    }

    private let screen: FrozenScreen
    private let initialMode: CaptureMode
    private let canvas: SelectionCanvasView
    private let toolbar = CaptureToolbarPlate(frame: CGRect(x: 0, y: 0, width: 600, height: 38))
    private let palette = AnnotationStyleControls()
    private let badge = CaptureToolbarPlate(frame: CGRect(x: 0, y: 0, width: 130, height: 26))
    private let instructionBar = CaptureToolbarPlate(frame: CGRect(x: 0, y: 0, width: 440, height: 36))
    private let sizeLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: L10n.selectionHint)
    private let modeButton = NSButton(title: L10n.selectionArea, target: nil, action: nil)
    private var toolButtons: [NSButton] = []
    private var undoButton: NSButton!
    private var redoButton: NSButton!
    private var longButton: NSButton!
    private var headerButton: NSButton!
    private let headerView = LongCaptureHeaderView(frame: .zero)
    private var keepsHeader = false
    private var gifButton: NSButton!
    private var videoButton: NSButton!
    private var saveButton: NSButton!
    private var completeButton: NSButton!
    private var ocrButton: NSButton!
    private var annotationCanvas: AnnotationCanvasView?
    private var document: AnnotationDocument?
    private var currentTool: AnnotationTool = .crop
    private var textInput: AnnotationInputTextView?
    private var editingAnnotation: Annotation?
    private var editingColor: AnnotationColor = .red
    private var isFinishing = false
    private var isDismissed = false
    private var renderTask: Task<Void, Never>?
    private var ocrActive = false
    var ocrAvailable = false {
        didSet { updateToolState() }
    }

    var canResume: Bool {
        !isDismissed
    }

    var onCancel: (() -> Void)?
    var onOutput: SelectionOutputHandler?
    var onLongCapture: ((CGRect, CapturedWindow?, LongCaptureRegion) -> Void)?
    var onRecognizeText: ((AnnotationRenderSnapshot) -> Void)?
    var onGIFCapture: ((CGRect, CapturedWindow?) -> Void)?
    var onVideoCapture: ((CGRect, CapturedWindow?) -> Void)?

    var keyboardResponder: NSResponder {
        if let textInput { return textInput }
        if currentTool != .crop, let annotationCanvas { return annotationCanvas }
        return canvas
    }

    override var isFlipped: Bool {
        true
    }

    init(screen: FrozenScreen, initialMode: CaptureMode, watermarkLibrary: WatermarkLibrarySnapshot = .empty) {
        self.watermarkLibrary = watermarkLibrary
        self.screen = screen
        self.initialMode = initialMode
        canvas = SelectionCanvasView(screen: screen)
        super.init(frame: CGRect(origin: .zero, size: screen.screenFrame.size))
        wantsLayer = true
        addSubview(canvas)
        headerView.isHidden = true
        headerView.onUnhandledKeyDown = { [weak self] event in self?.canvas.keyDown(with: event) }
        addSubview(headerView)
        configureToolbar()
        configurePalette()
        sizeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        sizeLabel.textColor = .labelColor
        badge.addArrangedSubview(sizeLabel)
        badge.identifier = NSUserInterfaceItemIdentifier("capture.selection.size")
        hintLabel.stringValue = initialMode == .long ? L10n.selectionLongHint : L10n.selectionHint
        hintLabel.identifier = NSUserInterfaceItemIdentifier("capture.selection.hint")
        hintLabel.font = .systemFont(ofSize: 12)
        hintLabel.textColor = .labelColor
        modeButton.target = self
        modeButton.action = #selector(toggleSelectionMode)
        instructionBar.addArrangedSubview(hintLabel)
        instructionBar.addArrangedSubview(modeButton)
        instructionBar.addArrangedSubview(iconButton("xmark", title: L10n.actionCancel, action: #selector(cancelSelection)))
        for plate in [toolbar, palette, badge, instructionBar] {
            addSubview(plate)
        }
        toolbar.isHidden = true
        palette.isHidden = true
        badge.isHidden = true
        canvas.onSelectionChange = { [weak self] rect, _, mode in self?.selectionChanged(rect: rect, mode: mode) }
        canvas.onCancel = { [weak self] in self?.cancelSelection() }
        canvas.onComplete = { [weak self] _, _ in self?.publish(save: false) }
        canvas.onSaveRequested = { [weak self] in self?.publish(save: true) }
        canvas.onHistoryRequest = { [weak self] redo in self?.changeHistory(redo: redo) }
        updateAppearance()
    }

    required init?(coder _: NSCoder) {
        nil
    }

    func dismiss() {
        watermarkPopover.close()
        isDismissed = true
        renderTask?.cancel()
        renderTask = nil
        textInput?.removeFromSuperview()
        textInput = nil
    }

    func isCurrentRevision(_ revision: UInt64) -> Bool {
        !isDismissed && document?.revision == revision
    }

    func setOCRActive(_ active: Bool) {
        if active { watermarkPopover.close() }
        ocrActive = active
        updateToolState()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    override func layout() {
        super.layout()
        canvas.frame = bounds
        if let document, let selection = localRect(for: document.cropRect), !canvas.isDraggingSelection {
            annotationCanvas?.frame = selection
            headerView.frame = selection
            headerView.setHeaderHeight(headerView.headerHeight)
        }
        placeControls()
    }

    private func iconButton(_ symbol: String, title: String, action: Selector) -> NSButton {
        AnnotationToolbarStyle.button(symbol, title: title, target: self, action: action)
    }

    private func separator() -> NSView {
        AnnotationToolbarStyle.separator()
    }

    private func configureToolbar() {
        toolbar.identifier = NSUserInterfaceItemIdentifier("capture.annotation.toolbar")
        for tool in AnnotationToolbarStyle.tools {
            let button = AnnotationToolbarStyle.toolButton(tool, target: self, action: #selector(selectTool(_:)))
            toolButtons.append(button)
            toolbar.addArrangedSubview(button)
        }
        toolbar.addArrangedSubview(separator())
        watermarkButton = iconButton("drop.halffull", title: L10n.watermarkTitle, action: #selector(editWatermark(_:)))
        watermarkButton.identifier = NSUserInterfaceItemIdentifier("capture.action.watermark")
        toolbar.addArrangedSubview(watermarkButton)
        longButton = iconButton("rectangle.expand.vertical", title: initialMode == .long ? L10n.actionStartLong : L10n.longTitle, action: #selector(startLongCapture))
        toolbar.addArrangedSubview(longButton)
        headerButton = iconButton("rectangle.topthird.inset.filled", title: L10n.longKeepHeader, action: #selector(toggleFixedHeader))
        headerButton.identifier = NSUserInterfaceItemIdentifier("capture.long.keepHeader")
        headerButton.setButtonType(.toggle)
        toolbar.addArrangedSubview(headerButton)
        gifButton = iconButton("record.circle", title: L10n.gifTitle, action: #selector(startGIFCapture))
        gifButton.identifier = NSUserInterfaceItemIdentifier("capture.selection.gif")
        toolbar.addArrangedSubview(gifButton)
        videoButton = iconButton("video", title: L10n.videoTitle, action: #selector(startVideoCapture))
        videoButton.identifier = NSUserInterfaceItemIdentifier("capture.selection.video")
        toolbar.addArrangedSubview(videoButton)
        toolbar.addArrangedSubview(separator())
        undoButton = iconButton("arrow.uturn.backward", title: L10n.actionUndo, action: #selector(undo))
        redoButton = iconButton("arrow.uturn.forward", title: L10n.actionRedo, action: #selector(redo))
        toolbar.addArrangedSubview(undoButton)
        toolbar.addArrangedSubview(redoButton)
        toolbar.addArrangedSubview(separator())
        ocrButton = iconButton("text.viewfinder", title: L10n.ocrTitle, action: #selector(recognizeText))
        ocrButton.identifier = NSUserInterfaceItemIdentifier("capture.action.ocr")
        toolbar.addArrangedSubview(ocrButton)
        saveButton = iconButton("square.and.arrow.down", title: L10n.actionSave, action: #selector(saveSelection))
        toolbar.addArrangedSubview(saveButton)
        toolbar.addArrangedSubview(iconButton("xmark", title: L10n.actionCancel, action: #selector(cancelSelection)))
        completeButton = iconButton("checkmark", title: L10n.actionComplete, action: #selector(completeSelection))
        completeButton.contentTintColor = .controlAccentColor
        toolbar.addArrangedSubview(completeButton)
        if initialMode.isRecording {
            for button in toolButtons {
                button.isHidden = true
            }
            for button in [watermarkButton, longButton, headerButton, undoButton, redoButton, ocrButton, saveButton, completeButton] {
                button?.isHidden = true
            }
        }
    }

    private func configurePalette() {
        palette.onChange = { [weak self] change in self?.changeStyle(change) }
    }

    private func updateAppearance() {
        for plate in [toolbar, palette, badge, instructionBar] {
            plate.updateColors(appearance: effectiveAppearance)
        }
        updateToolState()
    }

    private func selectionChanged(rect: CGRect?, mode: SelectionMode) {
        guard !isDismissed else { return }
        modeButton.title = mode == .window ? L10n.selectionWindow : L10n.selectionArea
        guard let rect, let global = screen.transform.globalScreenRect(fromLocalTopLeftRect: rect),
              let pixels = screen.transform.pixelRect(fromGlobalScreenRect: global)
        else {
            keepsHeader = false
            headerView.isHidden = true
            annotationCanvas?.isHidden = true
            toolbar.isHidden = true
            palette.isHidden = true
            badge.isHidden = true
            instructionBar.isHidden = false
            needsLayout = true
            return
        }
        sizeLabel.stringValue = "\(Int(pixels.width)) × \(Int(pixels.height)) px"
        badge.isHidden = false
        instructionBar.isHidden = true
        if initialMode == .long {
            // The menu already chose scrolling capture. A completed region
            // goes straight to its mode panel, without screenshot editing.
            if !canvas.isDraggingSelection {
                document = AnnotationDocument(image: screen.image, cropRect: pixels, watermark: watermarkLibrary.defaultSelection)
                startLongCapture()
            }
            needsLayout = true
            return
        }
        if canvas.isDraggingSelection {
            finishTextEditing(commit: true)
            annotationCanvas?.isHidden = true
            toolbar.isHidden = true
            palette.isHidden = true
            headerView.isHidden = true
        } else {
            if let document {
                document.setCropRect(pixels)
            } else {
                let document = AnnotationDocument(image: screen.image, cropRect: pixels, watermark: initialMode.isRecording ? nil : watermarkLibrary.defaultSelection)
                self.document = document
                let annotations = AnnotationCanvasView(document: document)
                annotations.fillsBounds = true
                annotations.onDocumentChange = { [weak self] in self?.synchronizeDocument() }
                annotations.onTextRequest = { [weak self] rect, existing in self?.beginTextEditing(rect: rect, existing: existing) }
                annotations.onFinishTextEditing = { [weak self] in self?.finishTextEditing(commit: true) }
                annotations.onComplete = { [weak self] in self?.publish(save: false) }
                annotations.onSaveRequested = { [weak self] in self?.publish(save: true) }
                annotations.onCancel = { [weak self] in self?.cancelSelection() }
                annotationCanvas = annotations
                addSubview(annotations, positioned: .above, relativeTo: canvas)
            }
            synchronizeDocument()
            window?.makeFirstResponder(keyboardResponder)
        }
        needsLayout = true
    }

    private func localRect(for pixels: CGRect) -> CGRect? {
        screen.transform.globalScreenRect(fromPixelRect: pixels).flatMap { screen.transform.localTopLeftRect(fromGlobalScreenRect: $0) }
    }

    private func synchronizeDocument() {
        guard let document, let rect = localRect(for: document.cropRect), !canvas.isDraggingSelection else { return }
        canvas.selectionRect = rect
        canvas.needsDisplay = true
        annotationCanvas?.frame = rect
        annotationCanvas?.isHidden = false
        annotationCanvas?.needsDisplay = true
        headerView.frame = rect
        headerView.setHeaderHeight(headerView.headerHeight)
        if !LongCaptureHeaderView.canConfigure(in: rect.size) { keepsHeader = false }
        sizeLabel.stringValue = "\(Int(document.cropRect.width)) × \(Int(document.cropRect.height)) px"
        toolbar.isHidden = false
        badge.isHidden = false
        instructionBar.isHidden = true
        updateCanvasStyle()
        updateToolState()
        needsLayout = true
    }

    private var pixelScale: CGFloat {
        CGFloat(screen.image.width) / max(screen.screenFrame.width, 1)
    }

    private func updateCanvasStyle() {
        annotationCanvas?.style = palette.style(pixelScale: pixelScale)
    }

    private func updateToolState() {
        let enabled = document != nil && !isFinishing && !isDismissed && !ocrActive
        if let watermarkButton {
            AnnotationToolbarStyle.update(watermarkButton, selected: document?.watermark != nil, enabled: enabled && !initialMode.isRecording)
            watermarkButton.toolTip = L10n.watermarkTitle + ": " + (document?.watermark.map { $0.sourceName ?? L10n.watermarkCustom } ?? L10n.watermarkNone)
            watermarkButton.setAccessibilityLabel(watermarkButton.toolTip)
        }
        for button in toolButtons {
            let selected = button.tag == currentTool.rawValue
            AnnotationToolbarStyle.update(button, selected: selected, enabled: enabled)
        }
        annotationCanvas?.tool = currentTool == .crop ? .select : currentTool
        annotationCanvas?.passesMouseEventsThrough = currentTool == .crop
        annotationCanvas?.isInteractionEnabled = enabled
        canvas.isInteractionEnabled = !isFinishing && !ocrActive
        let hasMarks = document?.annotations.isEmpty == false
        AnnotationToolbarStyle.update(longButton, selected: false, enabled: enabled && !hasMarks)
        longButton?.toolTip = hasMarks ? L10n.selectionLongAfterMarks : L10n.longTitle
        let canSetHeader = enabled && !initialMode.isRecording && !hasMarks && canvas.selectionRect.map { LongCaptureHeaderView.canConfigure(in: $0.size) } == true
        if let headerButton {
            AnnotationToolbarStyle.update(headerButton, selected: keepsHeader, enabled: canSetHeader)
        }
        headerView.isHidden = !canSetHeader || !keepsHeader || currentTool != .crop || canvas.isDraggingSelection
        let hasRecordingEdits = hasMarks || document?.watermark != nil
        // Recording drops the screenshot editing layers, so the buttons stay
        // clickable and offer to clear the watermark and marks first.
        AnnotationToolbarStyle.update(gifButton, selected: false, enabled: enabled)
        gifButton?.toolTip = hasRecordingEdits ? L10n.recordingClearsEdits : L10n.gifTitle
        AnnotationToolbarStyle.update(videoButton, selected: false, enabled: enabled)
        videoButton?.toolTip = hasRecordingEdits ? L10n.recordingClearsEdits : L10n.videoTitle
        saveButton?.isEnabled = enabled
        completeButton?.isEnabled = enabled
        if let ocrButton {
            AnnotationToolbarStyle.update(ocrButton, selected: false, enabled: enabled && ocrAvailable && !initialMode.isRecording)
        }
        undoButton?.isEnabled = enabled && document?.canUndo == true
        redoButton?.isEnabled = enabled && document?.canRedo == true
        palette.update(for: currentTool, enabled: enabled)
        if initialMode.isRecording { palette.isHidden = true }
        palette.isHidden = palette.isHidden || toolbar.isHidden
    }

    private func placeControls() {
        guard let selection = canvas.selectionRect else {
            let size = instructionBar.fittingSize
            instructionBar.frame = CGRect(x: max(8, (bounds.width - size.width) / 2), y: max(16, bounds.height * 0.12), width: min(size.width, max(1, bounds.width - 16)), height: 36)
            return
        }
        let placement = SelectionToolbarLayout(
            bounds: bounds, selection: selection,
            toolbarSize: CGSize(width: toolbar.fittingSize.width, height: 38),
            // Reserve the style row so choosing a tool never makes the main
            // toolbar jump from below to above a selection near the screen edge.
            paletteSize: CGSize(width: palette.fittingSize.width, height: 36),
            badgeSize: CGSize(width: badge.fittingSize.width, height: 26)
        )
        toolbar.frame = placement.toolbar
        palette.frame = placement.palette
        if !palette.isHidden, let active = toolButtons.first(where: { $0.tag == currentTool.rawValue }) {
            let anchorX = toolbar.frame.minX + active.frame.minX
            palette.frame.origin.x = min(max(anchorX, 8), max(8, bounds.maxX - palette.frame.width - 8))
        }
        badge.frame = placement.sizeBadge
    }

    @objc private func selectTool(_ sender: NSButton) {
        guard !isFinishing, let tool = AnnotationTool(rawValue: sender.tag) else { return }
        finishTextEditing(commit: true)
        currentTool = tool
        updateToolState()
        needsLayout = true
        window?.makeFirstResponder(keyboardResponder)
    }

    private func changeStyle(_ change: AnnotationStyleChange) {
        updateCanvasStyle()
        if change == .color {
            editingColor = palette.selectedColor
            textInput?.textColor = editingColor.nsColor
        }
        if change == .fontSize, let textInput, let style = annotationCanvas?.style {
            textInput.pixelFontSize = style.fontSize
            textInput.updateDisplayScale(1 / pixelScale)
        }
        window?.makeFirstResponder(keyboardResponder)
    }

    @objc private func toggleSelectionMode() {
        guard !isFinishing else { return }
        finishTextEditing(commit: true)
        currentTool = .crop
        canvas.toggleSelectionMode()
        window?.makeFirstResponder(canvas)
    }

    @objc private func undo() {
        changeHistory(redo: false)
    }

    @objc private func redo() {
        changeHistory(redo: true)
    }

    private func changeHistory(redo: Bool) {
        guard !isFinishing else { return }
        finishTextEditing(commit: true)
        if redo { _ = document?.redo() } else { _ = document?.undo() }
        synchronizeDocument()
        window?.makeFirstResponder(keyboardResponder)
    }

    @objc private func startLongCapture() {
        guard !isFinishing, !isDismissed, !ocrActive, document?.annotations.isEmpty == true, let rect = canvas.selectionRect else { return }
        var headerPixels = 0
        if keepsHeader {
            let headerRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: headerView.headerHeight)
            guard let globalHeader = screen.transform.globalScreenRect(fromLocalTopLeftRect: headerRect),
                  let pixels = screen.transform.pixelRect(fromGlobalScreenRect: globalHeader),
                  let cropRect = document?.cropRect
            else { return }
            headerPixels = Int(pixels.maxY - cropRect.minY)
        }
        isFinishing = true
        updateToolState()
        watermarkPopover.close()
        onLongCapture?(rect, canvas.selectedWindow, LongCaptureRegion(fixedHeaderHeight: headerPixels))
    }

    @objc private func toggleFixedHeader() {
        guard headerButton.isEnabled else { return }
        finishTextEditing(commit: true)
        keepsHeader.toggle()
        currentTool = .crop
        if keepsHeader { headerView.setHeaderHeight(64) }
        updateToolState()
        window?.makeFirstResponder(keepsHeader ? headerView : keyboardResponder)
        needsLayout = true
    }

    @objc private func startGIFCapture() {
        recordSelection(mode: .gif)
    }

    @objc private func startVideoCapture() {
        recordSelection(mode: .video)
    }

    private func recordSelection(mode: CaptureMode) {
        guard !isFinishing, !isDismissed, !ocrActive, let rect = canvas.selectionRect else { return }
        finishTextEditing(commit: true)
        watermarkPopover.close()
        guard let document, document.annotations.isEmpty, document.watermark == nil else {
            confirmClearingRecordingEdits { [weak self] in self?.recordSelection(mode: mode) }
            return
        }
        if mode == .gif {
            onGIFCapture?(rect, canvas.selectedWindow)
        } else {
            onVideoCapture?(rect, canvas.selectedWindow)
        }
    }

    /// GIF/video cannot carry the screenshot editing layers, so clearing them
    /// always needs an explicit confirmation and never happens silently.
    private func confirmClearingRecordingEdits(then action: @escaping () -> Void) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = L10n.recordingClearTitle
        alert.informativeText = L10n.recordingClearDetail
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.recordingClearConfirm)
        alert.addButton(withTitle: L10n.actionCancel)
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self, !isDismissed, !isFinishing else { return }
            clearRecordingEdits()
            action()
        }
    }

    private func clearRecordingEdits() {
        guard let document else { return }
        for annotation in document.annotations {
            document.remove(id: annotation.id)
        }
        document.setWatermark(nil)
        synchronizeDocument()
    }

    @objc private func recognizeText() {
        guard !isFinishing, !isDismissed, !ocrActive, !initialMode.isRecording, ocrAvailable, let document else { return }
        guard textInput?.hasMarkedText() != true else {
            window?.makeFirstResponder(textInput)
            return
        }
        finishTextEditing(commit: true)
        onRecognizeText?(document.renderSnapshot())
    }

    @objc private func completeSelection() {
        publish(save: false)
    }

    @objc private func saveSelection() {
        publish(save: true)
    }

    @objc private func cancelSelection() {
        guard !isDismissed else { return }
        dismiss()
        onCancel?()
    }

    private func publish(save: Bool) {
        guard !ocrActive else { return }
        if initialMode == .long { startLongCapture(); return }
        if initialMode == .gif { startGIFCapture(); return }
        if initialMode == .video { startVideoCapture(); return }
        guard !isFinishing, !isDismissed, let document, let rect = canvas.selectionRect else { return }
        watermarkPopover.close()
        finishTextEditing(commit: true)
        isFinishing = true
        updateToolState()
        let snapshot = document.renderSnapshot()
        let selectedWindow = canvas.selectedWindow
        renderTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let image = try await AnnotationRenderer.render(snapshot)
                guard !isDismissed, !Task.isCancelled else { return }
                let succeeded = await onOutput?(image, rect, selectedWindow, save) ?? false
                guard !isDismissed else { return }
                if succeeded { dismiss() } else { isFinishing = false; updateToolState() }
            } catch {
                guard !isDismissed else { return }
                isFinishing = false
                updateToolState()
                let alert = NSAlert()
                alert.messageText = L10n.errorRenderTitle
                alert.informativeText = error.localizedDescription
                if let window { alert.beginSheetModal(for: window) { _ in } }
            }
        }
    }

    @objc private func editWatermark(_ sender: NSButton) {
        guard !isFinishing, !isDismissed, !initialMode.isRecording, let document else { return }
        finishTextEditing(commit: true)
        watermarkPopover.show(relativeTo: sender, selection: document.watermark, library: watermarkLibrary) { [weak self] selection in
            guard let self, !isFinishing, !isDismissed else { return }
            document.setWatermark(selection)
            synchronizeDocument()
        }
    }

    private func beginTextEditing(rect: CGRect, existing: Annotation?) {
        guard !isFinishing, let annotationCanvas else { return }
        finishTextEditing(commit: true)
        currentTool = .text
        editingAnnotation = existing
        let input = AnnotationInputTextView(frame: annotationCanvas.viewRect(forPixelRect: rect))
        input.pixelEditingRect = rect
        input.pixelFontSize = annotationCanvas.style.fontSize
        editingColor = palette.selectedColor
        if let existing, case let .text(_, value, fontSize, color) = existing.content {
            input.string = value
            input.pixelFontSize = fontSize
            editingColor = color
            palette.selectTextStyle(fontSize: fontSize, color: color, pixelScale: pixelScale)
            updateCanvasStyle()
        }
        input.minSize = CGSize(width: 20, height: 24)
        input.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        input.isVerticallyResizable = true
        input.isHorizontallyResizable = false
        input.textContainer?.widthTracksTextView = true
        input.textContainer?.heightTracksTextView = false
        input.updateDisplayScale(annotationCanvas.viewRect(forPixelRect: CGRect(x: 0, y: 0, width: 1, height: 1)).width)
        input.textColor = editingColor.nsColor
        input.insertionPointColor = .controlAccentColor
        input.drawsBackground = false
        input.onCommit = { [weak self] in self?.finishTextEditing(commit: true) }
        input.onCancel = { [weak self] in self?.finishTextEditing(commit: false) }
        textInput = input
        annotationCanvas.addSubview(input)
        updateToolState()
        needsLayout = true
        window?.makeFirstResponder(input)
        input.setSelectedRange(NSRange(location: input.string.utf16.count, length: 0))
    }

    private func finishTextEditing(commit: Bool) {
        guard let input = textInput, let document else { return }
        if commit {
            let value = input.string
            if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let rect = input.committedPixelRect(color: editingColor, crop: document.cropRect)
            {
                let annotation = Annotation(id: editingAnnotation?.id ?? UUID(), content: .text(rect: rect, value: value, fontSize: input.pixelFontSize, color: editingColor))
                if editingAnnotation == nil { document.add(annotation) } else { document.replace(annotation) }
            } else if let existing = editingAnnotation { document.remove(id: existing.id) }
        }
        input.removeFromSuperview()
        textInput = nil
        editingAnnotation = nil
        annotationCanvas?.needsDisplay = true
        updateToolState()
        window?.makeFirstResponder(keyboardResponder)
    }
}

private enum SelectionMode {
    case area
    case window
}

@MainActor
private final class SelectionCanvasView: NSView {
    private let screen: FrozenScreen
    private var mode: SelectionMode = .area
    private var dragState: DragState?
    private var highlightedWindow: CapturedWindow?
    private var highlightedDesktopFrame: CGRect?

    var selectionRect: CGRect?
    var selectedWindow: CapturedWindow?
    var isInteractionEnabled = true
    var isDraggingSelection: Bool {
        dragState != nil
    }

    var onSelectionChange: ((CGRect?, CapturedWindow?, SelectionMode) -> Void)?
    var onSaveRequested: (() -> Void)?
    var onHistoryRequest: ((Bool) -> Void)?
    var onCancel: (() -> Void)?
    var onComplete: ((CGRect, CapturedWindow?) -> Void)?

    override var isFlipped: Bool {
        true
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    init(screen: FrozenScreen) {
        self.screen = screen
        super.init(frame: CGRect(origin: .zero, size: screen.screenFrame.size))
        identifier = NSUserInterfaceItemIdentifier("capture.selection.canvas")
        let trackingArea = NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(trackingArea)
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override func draw(_: CGRect) {
        NSImage(cgImage: screen.image, size: screen.screenFrame.size).draw(in: bounds)

        let shade = NSBezierPath(rect: bounds)
        if let selectionRect {
            shade.append(NSBezierPath(rect: selectionRect))
            shade.windingRule = .evenOdd
        }
        NSColor.black.withAlphaComponent(0.38).setFill()
        shade.fill()

        if let selectionRect {
            NSColor.white.setStroke()
            let outline = NSBezierPath(rect: selectionRect.insetBy(dx: -1, dy: -1))
            outline.lineWidth = 2
            outline.stroke()

            drawResizeHandles(in: selectionRect)
        } else if mode == .window, let hoverFrame = highlightedDesktopFrame ?? highlightedWindow?.frame {
            if let rect = screen.transform.localTopLeftRect(fromGlobalScreenRect: hoverFrame) {
                NSColor.systemBlue.setStroke()
                let outline = NSBezierPath(rect: rect.insetBy(dx: -1, dy: -1))
                outline.lineWidth = 2
                outline.stroke()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard isInteractionEnabled else { return }
        let point = clampedPoint(convert(event.locationInWindow, from: nil))
        if mode == .window {
            selectWindow(at: point)
            return
        }

        selectedWindow = nil
        if let selectionRect, selectionRect.insetBy(dx: -8, dy: -8).contains(point) {
            if let edges = resizeEdges(at: point, in: selectionRect) {
                dragState = .resize(initial: selectionRect, edges: edges)
            } else {
                dragState = .move(offset: CGPoint(x: point.x - selectionRect.minX, y: point.y - selectionRect.minY))
            }
        } else {
            dragState = .create(start: point)
            selectionRect = CGRect(origin: point, size: .zero)
        }
        publishSelection()
        if event.clickCount == 2, let selectionRect {
            onComplete?(selectionRect, selectedWindow)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isInteractionEnabled, let dragState else { return }
        let point = clampedPoint(convert(event.locationInWindow, from: nil))
        switch dragState {
        case let .create(start):
            selectionRect = rect(from: start, to: point)
        case let .move(offset):
            guard let selectionRect else { return }
            let maxX = max(bounds.width - selectionRect.width, 0)
            let maxY = max(bounds.height - selectionRect.height, 0)
            let x = min(max(point.x - offset.x, 0), maxX)
            let y = min(max(point.y - offset.y, 0), maxY)
            self.selectionRect = CGRect(x: x, y: y, width: selectionRect.width, height: selectionRect.height)
        case let .resize(initial, edges):
            selectionRect = resized(initial, edges: edges, to: point)
        }
        publishSelection()
    }

    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        dragState = nil
        if selectionRect?.width == 0 || selectionRect?.height == 0 {
            selectionRect = nil
        }
        publishSelection()
    }

    override func mouseMoved(with event: NSEvent) {
        guard mode == .window else { return }
        updateHover(at: convert(event.locationInWindow, from: nil))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            onCancel?()
            return
        }
        guard isInteractionEnabled else { return }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "z" {
            onHistoryRequest?(event.modifierFlags.contains(.shift))
            return
        }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "s" {
            onSaveRequested?()
            return
        }
        if event.keyCode == UInt16(kVK_Space) {
            toggleSelectionMode()
            return
        }
        if event.keyCode == UInt16(kVK_Return) || event.keyCode == 76 ||
            (event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers?.lowercased() == "c")
        {
            if let selectionRect {
                onComplete?(selectionRect, selectedWindow)
            }
            return
        }
        super.keyDown(with: event)
    }

    func toggleSelectionMode() {
        mode = mode == .window ? .area : .window
        selectionRect = nil
        selectedWindow = nil
        highlightedWindow = nil
        highlightedDesktopFrame = nil
        if mode == .window {
            let location = NSEvent.mouseLocation
            updateHover(at: CGPoint(x: location.x - screen.screenFrame.minX, y: screen.screenFrame.maxY - location.y))
        }
        publishSelection()
    }

    private func selectWindow(at topLeftPoint: CGPoint) {
        if let window = windowAt(topLeftPoint: topLeftPoint),
           let rect = screen.transform.localTopLeftRect(fromGlobalScreenRect: window.frame)
        {
            selectedWindow = window
            selectionRect = rect
            publishSelection()
            return
        }
        if let region = desktopRegion(at: topLeftPoint),
           let rect = screen.transform.localTopLeftRect(fromGlobalScreenRect: region)
        {
            selectedWindow = nil
            selectionRect = rect
            publishSelection()
            return
        }
        selectionRect = nil
        selectedWindow = nil
        publishSelection()
    }

    private func desktopRegion(at topLeftPoint: CGPoint) -> CGRect? {
        let globalPoint = CGPoint(x: screen.screenFrame.minX + topLeftPoint.x, y: screen.screenFrame.maxY - topLeftPoint.y)
        return DesktopSelectionRegion.resolve(point: globalPoint, screenFrame: screen.screenFrame, bars: screen.bars)
    }

    private func updateHover(at topLeftPoint: CGPoint) {
        if let window = windowAt(topLeftPoint: topLeftPoint) {
            guard window != highlightedWindow || highlightedDesktopFrame != nil else { return }
            highlightedWindow = window
            highlightedDesktopFrame = nil
            needsDisplay = true
            return
        }
        let region = desktopRegion(at: topLeftPoint)
        guard region != highlightedDesktopFrame || highlightedWindow != nil else { return }
        highlightedWindow = nil
        highlightedDesktopFrame = region
        needsDisplay = true
    }

    private func windowAt(topLeftPoint: CGPoint) -> CapturedWindow? {
        let globalPoint = CGPoint(x: screen.screenFrame.minX + topLeftPoint.x, y: screen.screenFrame.maxY - topLeftPoint.y)
        return screen.windows.first { $0.frame.contains(globalPoint) }
    }

    private func publishSelection() {
        needsDisplay = true
        onSelectionChange?(selectionRect, selectedWindow, mode)
    }

    private func clampedPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, 0), bounds.width), y: min(max(point.y, 0), bounds.height))
    }

    private func rect(from first: CGPoint, to second: CGPoint) -> CGRect {
        CGRect(x: min(first.x, second.x), y: min(first.y, second.y), width: abs(second.x - first.x), height: abs(second.y - first.y))
    }

    private func resizeEdges(at point: CGPoint, in rect: CGRect) -> ResizeEdges? {
        var edges: ResizeEdges = []
        let margin: CGFloat = 8
        if abs(point.x - rect.minX) <= margin { edges.insert(.left) }
        if abs(point.x - rect.maxX) <= margin { edges.insert(.right) }
        if abs(point.y - rect.minY) <= margin { edges.insert(.top) }
        if abs(point.y - rect.maxY) <= margin { edges.insert(.bottom) }
        return edges.isEmpty ? nil : edges
    }

    private func resized(_ rect: CGRect, edges: ResizeEdges, to point: CGPoint) -> CGRect {
        var left = rect.minX
        var right = rect.maxX
        var top = rect.minY
        var bottom = rect.maxY
        if edges.contains(.left) { left = point.x }
        if edges.contains(.right) { right = point.x }
        if edges.contains(.top) { top = point.y }
        if edges.contains(.bottom) { bottom = point.y }
        return CGRect(x: min(left, right), y: min(top, bottom), width: abs(right - left), height: abs(bottom - top))
    }

    private func drawResizeHandles(in rect: CGRect) {
        let points = [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.midY), CGPoint(x: rect.maxX, y: rect.midY),
            CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.midX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY),
        ]
        NSColor.white.setFill()
        for point in points {
            NSBezierPath(ovalIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)).fill()
        }
    }
}

private enum DragState {
    case create(start: CGPoint)
    case move(offset: CGPoint)
    case resize(initial: CGRect, edges: ResizeEdges)
}

private struct ResizeEdges: OptionSet {
    let rawValue: Int
    static let left = ResizeEdges(rawValue: 1 << 0)
    static let right = ResizeEdges(rawValue: 1 << 1)
    static let top = ResizeEdges(rawValue: 1 << 2)
    static let bottom = ResizeEdges(rawValue: 1 << 3)
}
