import AppKit
import Carbon.HIToolbox

enum LongCaptureMode: String {
    case manual
    case automatic

    var title: String {
        switch self {
        case .manual: L10n.longModeManual
        case .automatic: L10n.longModeAutomatic
        }
    }
}

@MainActor
final class LongCaptureControlPanel: NSPanel, NSWindowDelegate {
    private let rootView = LongCapturePanelRootView()
    private let statusLabel = NSTextField(labelWithString: L10n.longPreparing)
    private let detailLabel = NSTextField(wrappingLabelWithString: L10n.longPermissionHelp)
    private let previewImageView = NSImageView()
    private let manualButton = NSButton(title: L10n.longStartManual, target: nil, action: nil)
    private let automaticButton = NSButton(title: L10n.longStartAutomatic, target: nil, action: nil)
    private let pauseButton = NSButton(title: L10n.actionPause, target: nil, action: nil)
    private let resumeButton = NSButton(title: L10n.actionResume, target: nil, action: nil)
    private let switchToManualButton = NSButton(title: L10n.longSwitchManual, target: nil, action: nil)
    private let finishButton = NSButton(title: L10n.longPreview, target: nil, action: nil)
    private let usePartialButton = NSButton(title: L10n.longUsePartial, target: nil, action: nil)
    private let cancelButton = NSButton(title: L10n.actionCancel, target: nil, action: nil)

    var onStartManual: (() -> Void)?
    var onStartAutomatic: (() -> Void)?
    var onPause: (() -> Void)?
    var onResume: (() -> Void)?
    var onSwitchToManual: (() -> Void)?
    var onFinish: (() -> Void)?
    var onUsePartial: (() -> Void)?
    var onCancel: (() -> Void)?

    init(screenFrame: CGRect, selectedGlobalRect: CGRect) {
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: min(760, max(1, screenFrame.width - 16)), height: 210),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        title = L10n.longTitle
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        delegate = self
        contentView = rootView
        rootView.onEscape = { [weak self] in self?.onCancel?() }

        for (button, identifier) in [
            (manualButton, "manual"), (automaticButton, "automatic"), (pauseButton, "pause"),
            (resumeButton, "resume"), (switchToManualButton, "switchManual"), (finishButton, "preview"),
            (usePartialButton, "usePartial"), (cancelButton, "cancel"),
        ] {
            button.identifier = NSUserInterfaceItemIdentifier("capture.long.\(identifier)")
            button.setAccessibilityLabel(button.title)
        }
        configureContent()
        let panelSize = frame.size
        var x = selectedGlobalRect.midX - panelSize.width / 2
        var y = selectedGlobalRect.minY - panelSize.height - 8
        if y < screenFrame.minY + 8 { y = selectedGlobalRect.maxY + 8 }
        x = min(max(x, screenFrame.minX + 8), screenFrame.maxX - panelSize.width - 8)
        y = min(max(y, screenFrame.minY + 8), screenFrame.maxY - panelSize.height - 8)
        setFrameOrigin(NSPoint(x: x, y: y))
        showChoices()
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    func present() {
        makeKeyAndOrderFront(nil)
        makeFirstResponder(rootView)
    }

    func showChoices(message: String? = nil) {
        statusLabel.stringValue = L10n.longChooseMode
        detailLabel.stringValue = message ?? L10n.longSelectionHelp
        setVisible([manualButton, automaticButton, cancelButton])
    }

    func showRunning(mode: LongCaptureMode, height: Int, elapsed: TimeInterval) {
        finishButton.isEnabled = height > 0
        statusLabel.stringValue = L10n.longRunning(mode.title, height, Int(elapsed))
        detailLabel.stringValue = mode == .automatic
            ? L10n.longAutomaticHelp
            : L10n.longManualHelp
        if mode == .automatic {
            setVisible([pauseButton, switchToManualButton, finishButton, cancelButton])
        } else {
            setVisible([pauseButton, finishButton, cancelButton])
        }
    }

    func showWaitingForStableFrame() {
        detailLabel.stringValue = L10n.longWaiting
    }

    func showPaused(reason: String, height: Int, canResume: Bool, canSwitchToManual: Bool) {
        finishButton.isEnabled = height > 0
        statusLabel.stringValue = L10n.longPaused(height)
        detailLabel.stringValue = reason
        var visible: [NSButton] = [finishButton, cancelButton]
        if canResume { visible.insert(resumeButton, at: 0) }
        if canSwitchToManual { visible.insert(switchToManualButton, at: max(0, visible.count - 2)) }
        setVisible(visible)
    }

    func showPartial(reason: String, height: Int) {
        statusLabel.stringValue = L10n.longPartial(height)
        detailLabel.stringValue = reason
        setVisible([usePartialButton, cancelButton])
    }

    func showFailure(_ detail: String, canUsePartial: Bool) {
        statusLabel.stringValue = L10n.longFailure
        detailLabel.stringValue = detail
        setVisible(canUsePartial ? [usePartialButton, cancelButton] : [cancelButton])
    }

    func updateElapsed(mode: LongCaptureMode, height: Int, elapsed: TimeInterval) {
        guard isVisible else { return }
        statusLabel.stringValue = L10n.longRunning(mode.title, height, Int(elapsed))
    }

    func updatePreview(image: CGImage) {
        guard let thumbnail = image.thumbnail(maxPixelSize: CGSize(width: 180, height: 96)) else { return }
        previewImageView.image = NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height))
    }

    func windowShouldClose(_: NSWindow) -> Bool {
        onCancel?()
        return true
    }

    @objc private func startManual() {
        onStartManual?()
    }

    @objc private func startAutomatic() {
        onStartAutomatic?()
    }

    @objc private func pause() {
        onPause?()
    }

    @objc private func resume() {
        onResume?()
    }

    @objc private func switchToManual() {
        onSwitchToManual?()
    }

    @objc private func finish() {
        onFinish?()
    }

    @objc private func usePartial() {
        onUsePartial?()
    }

    @objc private func cancel() {
        onCancel?()
    }

    private func configureContent() {
        rootView.statusLabel = statusLabel
        rootView.detailLabel = detailLabel
        rootView.previewImageView = previewImageView
        rootView.buttons = [manualButton, automaticButton, pauseButton, resumeButton, switchToManualButton, finishButton, usePartialButton, cancelButton]
        for button in rootView.buttons {
            button.bezelStyle = .rounded
            button.controlSize = .regular
            button.target = self
        }
        manualButton.action = #selector(startManual)
        automaticButton.action = #selector(startAutomatic)
        pauseButton.action = #selector(pause)
        resumeButton.action = #selector(resume)
        switchToManualButton.action = #selector(switchToManual)
        finishButton.action = #selector(finish)
        usePartialButton.action = #selector(usePartial)
        cancelButton.action = #selector(cancel)
        rootView.configure()
    }

    private func setVisible(_ buttons: [NSButton]) {
        for button in rootView.buttons {
            button.isHidden = !buttons.contains(button)
        }
        rootView.needsLayout = true
        rootView.layoutSubtreeIfNeeded()
        setContentSize(rootView.fittingSize)
    }
}

@MainActor
private final class LongCapturePanelRootView: NSView {
    var statusLabel: NSTextField!
    var detailLabel: NSTextField!
    var buttons: [NSButton] = []
    var previewImageView: NSImageView!
    var onEscape: (() -> Void)?
    private let buttonStack = NSStackView()

    override var acceptsFirstResponder: Bool {
        true
    }

    func configure() {
        statusLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detailLabel.preferredMaxLayoutWidth = max(180, bounds.width - 220)
        detailLabel.maximumNumberOfLines = 4
        detailLabel.lineBreakMode = .byWordWrapping
        previewImageView.imageScaling = .scaleProportionallyUpOrDown
        previewImageView.wantsLayer = true
        previewImageView.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.75).cgColor
        previewImageView.layer?.cornerRadius = 5
        previewImageView.layer?.borderWidth = 1
        previewImageView.layer?.borderColor = NSColor.separatorColor.cgColor
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.distribution = .fill
        buttonStack.spacing = 8
        for button in buttons {
            buttonStack.addArrangedSubview(button)
        }

        let informationStack = NSStackView(views: [statusLabel, detailLabel, buttonStack])
        informationStack.orientation = .vertical
        informationStack.alignment = .leading
        informationStack.distribution = .fill
        informationStack.spacing = 8

        let previewCaption = NSTextField(labelWithString: L10n.longPreviewCaption)
        previewCaption.font = .systemFont(ofSize: 10)
        previewCaption.textColor = .secondaryLabelColor
        let previewStack = NSStackView(views: [previewCaption, previewImageView])
        previewStack.orientation = .vertical
        previewStack.alignment = .centerX
        previewStack.distribution = .fill
        previewStack.spacing = 4
        previewImageView.widthAnchor.constraint(equalToConstant: 180).isActive = true
        previewImageView.heightAnchor.constraint(equalToConstant: 96).isActive = true

        let content = NSStackView(views: [informationStack, previewStack])
        content.orientation = .horizontal
        content.alignment = .centerY
        content.distribution = .fill
        content.spacing = 12
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            content.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            onEscape?()
            return
        }
        super.keyDown(with: event)
    }
}
