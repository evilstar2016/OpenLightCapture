import AppKit
import Carbon.HIToolbox

@MainActor
final class AnnotationEditorWindowController: NSWindowController, NSWindowDelegate {
    private let annotationDocument: AnnotationDocument
    private let onCancel: () -> Void
    private let onComplete: (CGImage) async -> Bool
    private let onSave: ((CGImage) async -> Bool)?
    private let onChangeCaptureSource: ((CaptureMode) -> Void)?
    private let bannerMessage: String?
    private let annotationPixelScale: CGFloat
    private var canvas: AnnotationCanvasView!
    private let scrollView = NSScrollView()
    private let sizeLabel = NSTextField(labelWithString: "")
    private var zoomControl: NSSegmentedControl!
    private var zoomMode: Int
    private var toolButtons: [NSButton] = []
    private let palette = AnnotationStyleControls()
    private let styleRow = NSView()
    private var undoButton: NSButton!
    private var redoButton: NSButton!
    private var changeSourceButton: NSButton!
    private var saveButton: NSButton!
    private var completeButton: NSButton!
    private var textView: AnnotationInputTextView?
    private var editingPixelRect: CGRect?
    private var editingAnnotation: Annotation?
    private var editingColor: AnnotationColor = .red
    private var isFinishing = false
    private var isDismissed = false

    init(
        image: CGImage,
        onCancel: @escaping () -> Void,
        onComplete: @escaping (CGImage) async -> Bool,
        onSave: ((CGImage) async -> Bool)? = nil,
        onChangeCaptureSource: ((CaptureMode) -> Void)? = nil,
        bannerMessage: String? = nil,
        annotationPixelScale: CGFloat = 1
    ) {
        annotationDocument = AnnotationDocument(image: image)
        zoomMode = image.height > image.width * 2 ? 1 : 0
        self.onCancel = onCancel
        self.onComplete = onComplete
        self.onSave = onSave
        self.onChangeCaptureSource = onChangeCaptureSource
        self.bannerMessage = bannerMessage
        self.annotationPixelScale = annotationPixelScale.isFinite && annotationPixelScale > 0 ? annotationPixelScale : 1

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.editorTitle
        window.minSize = NSSize(width: 760, height: 520)
        window.center()
        super.init(window: window)
        window.delegate = self
        window.contentView = buildContent(image: image)
        window.contentView?.layoutSubtreeIfNeeded()
        updateCanvasSize()
        window.initialFirstResponder = canvas
    }

    required init?(coder _: NSCoder) {
        nil
    }

    func showWindow() {
        if window?.isVisible != true {
            window?.center()
        }
        showWindow(nil)
        window?.contentView?.layoutSubtreeIfNeeded()
        updateCanvasSize()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        if let textView {
            window?.makeFirstResponder(textView)
        } else {
            window?.makeFirstResponder(canvas)
        }
    }

    func dismissForCaptureSourceChange() {
        dismissAfterCompletion()
    }

    func dismissAfterCompletion() {
        isDismissed = true
        isFinishing = true
        close()
    }

    func windowShouldClose(_: NSWindow) -> Bool {
        if !isDismissed {
            isDismissed = true
            onCancel()
        }
        return true
    }

    func windowDidResize(_: Notification) {
        window?.contentView?.layoutSubtreeIfNeeded()
        updateCanvasSize()
    }

    private func buildContent(image: CGImage) -> NSView {
        let root = AnnotationEditorContentView()
        canvas = AnnotationCanvasView(document: annotationDocument)
        canvas.onCancel = { [weak self] in self?.cancel() }
        canvas.onComplete = { [weak self] in self?.completeCapture() }
        canvas.onSaveRequested = { [weak self] in self?.save() }
        canvas.onTextRequest = { [weak self] rect, annotation in self?.beginTextEditing(rect: rect, annotation: annotation) }
        canvas.onFinishTextEditing = { [weak self] in self?.finishTextEditing(commit: true) }
        canvas.onDocumentChange = { [weak self] in
            self?.updateHistoryButtons()
            self?.updateCanvasSize()
        }
        palette.onChange = { [weak self] change in self?.changeStyle(change) }
        updateCanvasStyle()
        let toolbar = makeToolbar(image: image)
        styleRow.identifier = NSUserInterfaceItemIdentifier("capture.annotation.style.row")
        styleRow.translatesAutoresizingMaskIntoConstraints = false
        styleRow.addSubview(palette)
        root.onLayout = { [weak self] in self?.placeStyleControls() }

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = canvas
        zoomControl = NSSegmentedControl(labels: [L10n.editorFitWindow, L10n.editorFitWidth, "100%"], trackingMode: .selectOne, target: self, action: #selector(changeZoom(_:)))
        zoomControl.selectedSegment = zoomMode
        zoomControl.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(toolbar)
        root.addSubview(styleRow)
        root.addSubview(scrollView)
        root.addSubview(zoomControl)
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            toolbar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            toolbar.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
            toolbar.heightAnchor.constraint(equalToConstant: 38),
            styleRow.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            styleRow.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            styleRow.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 6),
            styleRow.heightAnchor.constraint(equalToConstant: 36),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: styleRow.bottomAnchor, constant: 6),
            scrollView.bottomAnchor.constraint(equalTo: zoomControl.topAnchor, constant: -6),
            zoomControl.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            zoomControl.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8),
        ])
        return root
    }

    @objc private func changeZoom(_ sender: NSSegmentedControl) {
        finishTextEditing(commit: true)
        zoomMode = sender.selectedSegment
        updateCanvasSize()
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        window?.makeFirstResponder(canvas)
    }

    private func updateCanvasSize() {
        let viewport = scrollView.contentView.bounds.size
        let crop = annotationDocument.cropRect.size
        sizeLabel.stringValue = "\(Int(crop.width)) × \(Int(crop.height)) px"
        guard viewport.width > 0, viewport.height > 0, crop.width > 0, crop.height > 0 else { return }
        let scale: CGFloat = switch zoomMode {
        case 1: viewport.width / crop.width
        case 2: 1 / (window?.screen?.backingScaleFactor ?? 1)
        default: min(viewport.width / crop.width, viewport.height / crop.height)
        }
        canvas.displayScale = scale
        canvas.setFrameSize(CGSize(width: max(viewport.width, crop.width * scale), height: max(viewport.height, crop.height * scale)))
        canvas.needsLayout = true
        canvas.needsDisplay = true
    }

    private func makeToolbar(image: CGImage) -> NSView {
        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.distribution = .fill
        header.spacing = 12
        header.translatesAutoresizingMaskIntoConstraints = false
        let toolbar = CaptureToolbarPlate(frame: .zero)
        toolbar.identifier = NSUserInterfaceItemIdentifier("capture.annotation.toolbar")

        sizeLabel.stringValue = "\(image.width) × \(image.height) px"
        sizeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        sizeLabel.textColor = .secondaryLabelColor
        sizeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        header.addArrangedSubview(sizeLabel)
        if let bannerMessage, !bannerMessage.isEmpty {
            let banner = NSTextField(labelWithString: bannerMessage)
            banner.textColor = .systemOrange
            banner.lineBreakMode = .byTruncatingTail
            banner.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            header.addArrangedSubview(banner)
        }
        header.addArrangedSubview(NSView())

        for tool in AnnotationToolbarStyle.tools {
            let button = AnnotationToolbarStyle.toolButton(tool, target: self, action: #selector(selectTool(_:)))
            toolButtons.append(button)
            toolbar.addArrangedSubview(button)
        }

        toolbar.addArrangedSubview(AnnotationToolbarStyle.separator())
        changeSourceButton = iconButton("rectangle.on.rectangle", title: L10n.editorChangeSource, action: #selector(changeCaptureSource))
        changeSourceButton.isEnabled = onChangeCaptureSource != nil
        toolbar.addArrangedSubview(changeSourceButton)
        toolbar.addArrangedSubview(AnnotationToolbarStyle.separator())
        undoButton = iconButton("arrow.uturn.backward", title: L10n.actionUndo, action: #selector(undo))
        undoButton.keyEquivalent = "z"
        undoButton.keyEquivalentModifierMask = [.command]
        redoButton = iconButton("arrow.uturn.forward", title: L10n.actionRedo, action: #selector(redo))
        redoButton.keyEquivalent = "z"
        redoButton.keyEquivalentModifierMask = [.command, .shift]
        saveButton = iconButton("square.and.arrow.down", title: L10n.actionSave, action: #selector(save))
        saveButton.isEnabled = onSave != nil
        let cancelButton = iconButton("xmark", title: L10n.actionCancel, action: #selector(cancel))
        completeButton = iconButton("checkmark", title: L10n.actionComplete, action: #selector(completeCapture))
        completeButton.contentTintColor = .controlAccentColor
        // Canvas and text input handle Return according to their own state.
        // A window-level default button would steal IME candidate confirmation.
        toolbar.addArrangedSubview(undoButton)
        toolbar.addArrangedSubview(redoButton)
        toolbar.addArrangedSubview(AnnotationToolbarStyle.separator())
        toolbar.addArrangedSubview(saveButton)
        toolbar.addArrangedSubview(cancelButton)
        toolbar.addArrangedSubview(completeButton)
        header.addArrangedSubview(toolbar)
        updateHistoryButtons()
        updateToolButtons()
        return header
    }

    private func iconButton(_ symbol: String, title: String, action: Selector) -> NSButton {
        AnnotationToolbarStyle.button(symbol, title: title, target: self, action: action)
    }

    private func placeStyleControls() {
        let width = min(palette.fittingSize.width, max(styleRow.bounds.width, 1))
        let active = toolButtons.first { $0.tag == canvas.tool.rawValue }
        let x = active.map { styleRow.convert($0.bounds, from: $0).minX } ?? 0
        palette.frame = CGRect(x: min(max(x, 0), max(styleRow.bounds.width - width, 0)), y: 0, width: width, height: 36)
    }

    private func updateCanvasStyle() {
        canvas.style = palette.style(pixelScale: annotationPixelScale)
    }

    private func changeStyle(_ change: AnnotationStyleChange) {
        guard !isFinishing, !isDismissed else { return }
        updateCanvasStyle()
        if change == .color {
            editingColor = palette.selectedColor
            textView?.textColor = editingColor.nsColor
        }
        if change == .fontSize, let textView {
            textView.pixelFontSize = canvas.style.fontSize
            textView.updateDisplayScale(canvas.viewRect(forPixelRect: CGRect(x: 0, y: 0, width: 1, height: 1)).width)
        }
        window?.contentView?.needsLayout = true
        if let textView { window?.makeFirstResponder(textView) } else { window?.makeFirstResponder(canvas) }
    }

    @objc private func selectTool(_ sender: NSButton) {
        guard !isFinishing, !isDismissed, let tool = AnnotationTool(rawValue: sender.tag) else { return }
        finishTextEditing(commit: true)
        canvas.tool = tool
        updateToolButtons()
        window?.makeFirstResponder(canvas)
    }

    @objc private func undo() {
        guard !isFinishing, !isDismissed else { return }
        finishTextEditing(commit: true)
        _ = annotationDocument.undo()
        canvas.refresh()
        updateHistoryButtons()
    }

    @objc private func redo() {
        guard !isFinishing, !isDismissed else { return }
        finishTextEditing(commit: true)
        _ = annotationDocument.redo()
        canvas.refresh()
        updateHistoryButtons()
    }

    @objc private func changeCaptureSource() {
        guard !isFinishing, !isDismissed, onChangeCaptureSource != nil else { return }
        let alert = NSAlert()
        alert.messageText = L10n.editorSourceTitle
        alert.informativeText = hasPendingEdits
            ? L10n.editorDiscardChanges
            : L10n.editorSourceHelp
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.editorReselect)
        alert.addButton(withTitle: L10n.actionStartLong)
        alert.addButton(withTitle: L10n.editorKeepEditing)
        guard let window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            guard response == .alertFirstButtonReturn || response == .alertSecondButtonReturn else { return }
            finishTextEditing(commit: false)
            setFinishing(true)
            onChangeCaptureSource?(response == .alertFirstButtonReturn ? .normal : .long)
        }
    }

    private var hasPendingEdits: Bool {
        annotationDocument.hasUncommittedChanges
            || !(textView?.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    @objc private func cancel() {
        guard !isDismissed else { return }
        isDismissed = true
        onCancel()
        close()
    }

    @objc private func completeCapture() {
        guard !isFinishing, !isDismissed else { return }
        finishTextEditing(commit: true)
        setFinishing(true)
        let snapshot = annotationDocument.renderSnapshot()
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let output = try await AnnotationRenderer.render(snapshot)
                guard !isDismissed else { return }
                if await onComplete(output) {
                    isDismissed = true
                    close()
                } else {
                    if !isDismissed { setFinishing(false) }
                }
            } catch {
                guard !isDismissed else { return }
                setFinishing(false)
                showError(L10n.errorRenderTitle, detail: error.localizedDescription)
            }
        }
    }

    @objc private func save() {
        guard !isFinishing, !isDismissed, let onSave else { return }
        finishTextEditing(commit: true)
        setFinishing(true)
        let snapshot = annotationDocument.renderSnapshot()
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let output = try await AnnotationRenderer.render(snapshot)
                guard !isDismissed else { return }
                if await onSave(output) {
                    isDismissed = true
                    close()
                } else {
                    if !isDismissed { setFinishing(false) }
                }
            } catch {
                guard !isDismissed else { return }
                setFinishing(false)
                showError(L10n.errorRenderTitle, detail: error.localizedDescription)
            }
        }
    }

    private func beginTextEditing(rect: CGRect, annotation: Annotation?) {
        guard !isFinishing, !isDismissed else { return }
        finishTextEditing(commit: true)
        canvas.tool = .text
        editingPixelRect = rect
        editingAnnotation = annotation
        if let annotation, case let .text(_, _, fontSize, color) = annotation.content {
            palette.selectTextStyle(fontSize: fontSize, color: color, pixelScale: annotationPixelScale)
        }
        updateCanvasStyle()
        let input = AnnotationInputTextView(frame: canvas.viewRect(forPixelRect: rect).insetBy(dx: -2, dy: -2))
        input.pixelEditingRect = rect
        input.pixelFontSize = canvas.style.fontSize
        editingColor = palette.selectedColor
        input.minSize = NSSize(width: 100, height: 34)
        input.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        input.isVerticallyResizable = true
        input.isHorizontallyResizable = false
        input.autoresizingMask = [.width]
        input.textContainer?.widthTracksTextView = true
        input.textContainer?.heightTracksTextView = false
        if let annotation, case let .text(_, _, fontSize, _) = annotation.content {
            input.pixelFontSize = fontSize
        }
        input.updateDisplayScale(canvas.viewRect(forPixelRect: CGRect(x: 0, y: 0, width: 1, height: 1)).width)
        input.textColor = editingColor.nsColor
        input.insertionPointColor = .controlAccentColor
        input.drawsBackground = true
        input.backgroundColor = .textBackgroundColor.withAlphaComponent(0.94)
        input.string = annotation.flatMap { value -> String? in
            if case let .text(_, text, _, _) = value.content { return text }
            return nil
        } ?? ""
        input.onCommit = { [weak self] in self?.finishTextEditing(commit: true) }
        input.onCancel = { [weak self] in self?.cancel() }
        textView = input
        canvas.addSubview(input)
        updateToolButtons()
        window?.makeFirstResponder(input)
        input.setSelectedRange(NSRange(location: input.string.utf16.count, length: 0))
    }

    private func finishTextEditing(commit: Bool) {
        guard let input = textView else { return }
        if commit,
           let rect = editingPixelRect,
           !input.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            let existing = editingAnnotation
            let updated = Annotation(id: existing?.id ?? UUID(), content: .text(rect: rect, value: input.string, fontSize: input.pixelFontSize, color: editingColor))
            if existing == nil { annotationDocument.add(updated) } else { annotationDocument.replace(updated) }
        } else if commit, let existing = editingAnnotation {
            annotationDocument.remove(id: existing.id)
        }
        input.removeFromSuperview()
        textView = nil
        editingPixelRect = nil
        editingAnnotation = nil
        canvas.refresh()
        updateHistoryButtons()
        window?.makeFirstResponder(canvas)
    }

    private func updateHistoryButtons() {
        undoButton?.isEnabled = !isFinishing && annotationDocument.canUndo
        redoButton?.isEnabled = !isFinishing && annotationDocument.canRedo
    }

    private func setFinishing(_ value: Bool) {
        isFinishing = value
        completeButton.isEnabled = !value
        saveButton.isEnabled = !value && onSave != nil
        changeSourceButton.isEnabled = !value && onChangeCaptureSource != nil
        toolButtons.forEach { $0.isEnabled = !value }
        zoomControl.isEnabled = !value
        canvas.isInteractionEnabled = !value
        updateToolButtons()
        updateHistoryButtons()
    }

    private func updateToolButtons() {
        for button in toolButtons {
            AnnotationToolbarStyle.update(button, selected: button.tag == canvas.tool.rawValue, enabled: !isFinishing && !isDismissed)
        }
        palette.update(for: canvas.tool, enabled: !isFinishing && !isDismissed)
        window?.contentView?.needsLayout = true
    }

    private func showError(_ title: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.actionOk)
        alert.beginSheetModal(for: window!)
    }
}

@MainActor
private final class AnnotationEditorContentView: NSView {
    var onLayout: (() -> Void)?

    override func layout() {
        super.layout()
        onLayout?()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateToolbarAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateToolbarAppearance()
    }

    private func updateToolbarAppearance() {
        func update(_ view: NSView) {
            if let plate = view as? CaptureToolbarPlate { plate.updateColors(appearance: effectiveAppearance) }
            view.subviews.forEach(update)
        }
        subviews.forEach(update)
    }
}
