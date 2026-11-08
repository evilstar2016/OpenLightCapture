import AppKit

@MainActor
final class OCRResultWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate {
    let textView = OCRTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 340))
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let spinner = NSProgressIndicator()
    private let copyButton = NSButton()
    private let retryButton = NSButton()
    private let backButton = NSButton()
    private var canCopy = false
    private var dismissed = false

    var onReturn: (() -> Void)?
    var onRetry: (() -> Void)?
    var onCopy: (() -> Void)?

    init() {
        let window = OCRResultWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 520),
                                     styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = L10n.ocrTitle
        window.minSize = NSSize(width: 520, height: 360)
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.onCancel = { [weak self] in self?.onReturn?() }
        window.contentView = buildContent()
        textView.delegate = self
        textView.onReturn = { [weak self] in self?.onReturn?() }
        textView.onCopyFailure = { [weak self] in self?.showCopyError() }
    }

    required init?(coder _: NSCoder) {
        nil
    }

    func present(on screen: NSScreen?) {
        if let screen {
            let frame = screen.visibleFrame
            window?.setFrameOrigin(NSPoint(x: frame.midX - (window?.frame.width ?? 660) / 2,
                                           y: frame.midY - (window?.frame.height ?? 520) / 2))
        } else {
            window?.center()
        }
        bringForward()
    }

    func bringForward() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func showRecognizing() {
        canCopy = false
        textView.string = ""
        textView.undoManager?.removeAllActions()
        textView.isEditable = false
        statusLabel.stringValue = L10n.ocrRecognizing
        statusLabel.textColor = .secondaryLabelColor
        spinner.isHidden = false
        spinner.startAnimation(nil)
        retryButton.isHidden = true
        backButton.title = L10n.ocrCancelAndReturn
        updateCopyButton()
        window?.makeFirstResponder(backButton)
    }

    func showResult(_ text: String) {
        spinner.stopAnimation(nil)
        spinner.isHidden = true
        backButton.title = L10n.ocrReturn
        canCopy = !text.isEmpty
        textView.string = text
        textView.undoManager?.removeAllActions()
        textView.isEditable = canCopy
        retryButton.isHidden = canCopy
        statusLabel.stringValue = canCopy ? L10n.ocrResultHelp : L10n.ocrEmpty
        statusLabel.textColor = .secondaryLabelColor
        updateCopyButton()
        window?.makeFirstResponder(canCopy ? textView : backButton)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
    }

    func showError(_ message: String) {
        spinner.stopAnimation(nil)
        spinner.isHidden = true
        canCopy = false
        textView.isEditable = false
        statusLabel.stringValue = message
        statusLabel.textColor = .systemRed
        retryButton.isHidden = false
        backButton.title = L10n.ocrReturn
        updateCopyButton()
    }

    func showCopyError() {
        statusLabel.stringValue = L10n.errorClipboardRejected
        statusLabel.textColor = .systemRed
    }

    func dismiss() {
        dismissed = true
        spinner.stopAnimation(nil)
        textView.string = ""
        textView.undoManager?.removeAllActions()
        close()
    }

    func windowShouldClose(_: NSWindow) -> Bool {
        if dismissed { return true }
        onReturn?()
        return false
    }

    func textDidChange(_: Notification) {
        updateCopyButton()
    }

    private func updateCopyButton() {
        copyButton.isEnabled = canCopy && !textView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @objc private func returnToImage() {
        onReturn?()
    }

    @objc private func retry() {
        onRetry?()
    }

    @objc private func copyAndFinish() {
        onCopy?()
    }

    private func buildContent() -> NSView {
        let root = NSView()
        root.identifier = NSUserInterfaceItemIdentifier("capture.ocr.result")
        let help = NSTextField(wrappingLabelWithString: L10n.ocrLocalHelp)
        help.font = .systemFont(ofSize: 12)
        help.textColor = .secondaryLabelColor
        statusLabel.setAccessibilityIdentifier("capture.ocr.status")
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        let statusRow = NSStackView(views: [spinner, statusLabel])
        statusRow.orientation = .horizontal
        statusRow.alignment = .centerY
        statusRow.spacing = 8

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        textView.identifier = NSUserInterfaceItemIdentifier("capture.ocr.text")
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.containerSize = NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.font = .systemFont(ofSize: 14)
        textView.setAccessibilityLabel(L10n.ocrTitle)
        scroll.documentView = textView

        backButton.title = L10n.ocrReturn
        backButton.target = self
        backButton.action = #selector(returnToImage)
        backButton.identifier = NSUserInterfaceItemIdentifier("capture.ocr.return")
        retryButton.title = L10n.ocrRetry
        retryButton.target = self
        retryButton.action = #selector(retry)
        retryButton.identifier = NSUserInterfaceItemIdentifier("capture.ocr.retry")
        copyButton.title = L10n.ocrCopyAndFinish
        copyButton.target = self
        copyButton.action = #selector(copyAndFinish)
        copyButton.identifier = NSUserInterfaceItemIdentifier("capture.ocr.copy")
        for button in [backButton, retryButton, copyButton] {
            button.bezelStyle = .rounded
        }
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [backButton, spacer, retryButton, copyButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        for view in [help, statusRow, scroll, buttons] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
            view.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20).isActive = true
            view.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20).isActive = true
        }
        NSLayoutConstraint.activate([
            help.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            statusRow.topAnchor.constraint(equalTo: help.bottomAnchor, constant: 12),
            scroll.topAnchor.constraint(equalTo: statusRow.bottomAnchor, constant: 12),
            scroll.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -14),
            buttons.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
            spinner.widthAnchor.constraint(equalToConstant: 16),
            spinner.heightAnchor.constraint(equalToConstant: 16),
        ])
        return root
    }
}

@MainActor
final class OCRTextView: NSTextView {
    var onReturn: (() -> Void)?
    var onCopyFailure: (() -> Void)?
    var copyPasteboard: NSPasteboard = .general

    override func copy(_: Any?) {
        let selected = selectedRange()
        guard selected.length > 0, NSMaxRange(selected) <= (string as NSString).length else { return }
        let text = (string as NSString).substring(with: selected)
        copyPasteboard.clearContents()
        if !copyPasteboard.setString(text, forType: .string) { onCopyFailure?() }
    }

    override func cancelOperation(_ sender: Any?) {
        if hasMarkedText() { super.cancelOperation(sender) } else { onReturn?() }
    }
}

@MainActor
private final class OCRResultWindow: NSWindow {
    var onCancel: (() -> Void)?

    override func cancelOperation(_: Any?) {
        onCancel?()
    }
}
