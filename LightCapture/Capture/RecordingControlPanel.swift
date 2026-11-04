import AppKit

@MainActor
final class RecordingControlPanel: NSPanel, NSWindowDelegate {
    var onStart: ((Bool) -> Void)?
    var onStop: (() -> Void)?
    var onDiscard: (() -> Void)?
    var onChangeRegion: (() -> Void)?
    var onCancelCountdown: (() -> Void)?

    private let status = NSTextField(labelWithString: "")
    private let recordDot = RecordingDotView()
    private let detail = NSTextField(wrappingLabelWithString: "")
    private let cursor = NSButton(checkboxWithTitle: L10n.gifCursor, target: nil, action: nil)
    private let start = NSButton(title: L10n.gifStart, target: nil, action: nil)
    private let stop = NSButton(title: L10n.gifStop, target: nil, action: nil)
    private let discard = NSButton(title: L10n.gifAbandon, target: nil, action: nil)
    private let change = NSButton(title: L10n.gifSelectAgain, target: nil, action: nil)
    private let cancelCountdown = NSButton(title: L10n.actionCancel, target: nil, action: nil)
    private var closing = false
    private let sizeText: String
    private let kind: RecordingKind

    init(screenFrame: CGRect, selection: CGRect, outputSize: CGSize, showsCursor: Bool, kind: RecordingKind = .gif) {
        self.kind = kind
        sizeText = "\(Int(outputSize.width)) × \(Int(outputSize.height)) px"
        super.init(contentRect: CGRect(x: 0, y: 0, width: min(540, screenFrame.width - 24), height: 205),
                   styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        title = kind.title
        delegate = self
        isFloatingPanel = true
        level = .statusBar
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        cursor.state = showsCursor ? .on : .off
        let buttons = [change, start, stop, cancelCountdown, discard]
        for (button, name, action) in [(start, "start", #selector(startAction)), (stop, "stop", #selector(stopAction)),
                                       (discard, "discard", #selector(discardAction)), (change, "changeRegion", #selector(changeAction)),
                                       (cancelCountdown, "cancelCountdown", #selector(countdownAction))]
        {
            button.target = self
            button.action = action
            button.bezelStyle = .rounded
            button.identifier = NSUserInterfaceItemIdentifier("capture.gif.\(name)")
            button.setAccessibilityLabel(button.title)
        }
        cursor.identifier = NSUserInterfaceItemIdentifier("capture.gif.cursor")
        status.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        detail.font = .systemFont(ofSize: 12)
        let statusRow = NSStackView(views: [recordDot, status])
        statusRow.orientation = .horizontal
        statusRow.spacing = 8
        let row = NSStackView(views: buttons)
        row.orientation = .horizontal
        row.spacing = 8
        row.detachesHiddenViews = true
        let stack = NSStackView(views: [statusRow, detail, cursor, row])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        let root = NSView()
        root.addSubview(stack)
        contentView = root
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -12),
            detail.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        let x = min(max(selection.midX - frame.width / 2, screenFrame.minX + 8), screenFrame.maxX - frame.width - 8)
        var y = selection.minY - frame.height - 8
        if y < screenFrame.minY { y = selection.maxY + 8 }
        y = min(max(y, screenFrame.minY + 8), screenFrame.maxY - frame.height - 8)
        setFrameOrigin(CGPoint(x: x, y: y))
        showReady()
    }

    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }

    func showReady() {
        status.stringValue = "\(kind.title) · \(sizeText)"
        detail.stringValue = "\(kind.parameters)\n\(kind.preparationHint)"
        show([start, change, discard])
        showDot(flashing: false)
        cursor.isHidden = false
        orderFrontRegardless()
    }

    func showCountdown(_ seconds: Int) {
        status.stringValue = seconds > 0 ? L10n.gifCountdown(seconds) : L10n.gifStarting
        detail.stringValue = sizeText
        show([cancelCountdown, discard])
        showDot(flashing: false)
        cursor.isHidden = true
    }

    func showRecording(_ seconds: Int) {
        status.stringValue = kind == .gif ? L10n.gifRunning(seconds) : L10n.videoRunning(seconds)
        detail.stringValue = sizeText
        show([stop, discard])
        showDot(flashing: true)
    }

    func showEnding() {
        status.stringValue = L10n.gifEnding
        show([])
        showDot(flashing: false)
        cursor.isHidden = true
    }

    func dismiss() {
        closing = true
        close()
    }

    func windowShouldClose(_: NSWindow) -> Bool {
        if closing { return true }
        onDiscard?()
        return false
    }

    private func show(_ visible: [NSButton]) {
        for button in [start, stop, discard, change, cancelCountdown] {
            button.isHidden = !visible.contains(button)
        }
    }

    private func showDot(flashing: Bool) {
        recordDot.isHidden = !flashing
        recordDot.setFlashing(flashing)
    }

    @objc private func startAction() {
        onStart?(cursor.state == .on)
    }

    @objc private func stopAction() {
        onStop?()
    }

    @objc private func discardAction() {
        onDiscard?()
    }

    @objc private func changeAction() {
        onChangeRegion?()
    }

    @objc private func countdownAction() {
        onCancelCountdown?()
    }
}

@MainActor
final class RecordingDotView: NSView {
    private(set) var isFlashing = false

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 12, height: 12))
        wantsLayer = true
        widthAnchor.constraint(equalToConstant: 12).isActive = true
        heightAnchor.constraint(equalToConstant: 12).isActive = true
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override func draw(_: NSRect) {
        NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5)).fill()
    }

    /// Idempotent on purpose: the 10 Hz recording ticker repeats this call and
    /// re-adding the animation each tick would reset it to the bright frame,
    /// freezing the blink instead of animating it.
    func setFlashing(_ flashing: Bool) {
        guard flashing != isFlashing else { return }
        isFlashing = flashing
        layer?.removeAnimation(forKey: "recording.dot.blink")
        guard flashing else { return }
        let blink = CABasicAnimation(keyPath: "opacity")
        blink.fromValue = Float(1.0)
        blink.toValue = Float(0.2)
        blink.duration = 0.75
        blink.autoreverses = true
        blink.repeatCount = Float.infinity
        layer?.add(blink, forKey: "recording.dot.blink")
    }
}

@MainActor
final class RecordingRegionDimmer: NSPanel {
    private let region: CGRect
    private let screenFrame: CGRect

    init(screenFrame: CGRect, region: CGRect) {
        self.screenFrame = screenFrame
        self.region = region
        super.init(contentRect: screenFrame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        level = .statusBar
        // No hidesOnDeactivate override needed: panel defaults hide on app
        // deactivation, which happens the moment recording focuses the target
        // app. Keep the dimming visible across spaces/app switches too.
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = RecordingDimmingView(screenFrame: screenFrame, region: region)
    }

    /// Breathing shade while the countdown is still running.
    func startPulsing() {
        guard let layer = contentView?.layer else { return }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = Float(1.0)
        pulse.toValue = Float(0.5)
        pulse.duration = 0.9
        pulse.autoreverses = true
        pulse.repeatCount = Float.infinity
        layer.add(pulse, forKey: "recording.border.pulse")
    }

    func stopPulsing() {
        contentView?.layer?.removeAnimation(forKey: "recording.border.pulse")
    }
}

@MainActor
private final class RecordingDimmingView: NSView {
    private let screenFrame: CGRect
    private let region: CGRect

    init(screenFrame: CGRect, region: CGRect) {
        self.screenFrame = screenFrame
        self.region = region
        super.init(frame: NSRect(origin: .zero, size: screenFrame.size))
        wantsLayer = true
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override func draw(_: NSRect) {
        // `region` and `screenFrame` share the bottom-left screen space, so the
        // view coordinates are just the offsets inside the screen rect.
        let regionInView = CGRect(x: region.minX - screenFrame.minX,
                                  y: region.minY - screenFrame.minY,
                                  width: region.width, height: region.height)
        let dimming = NSBezierPath(rect: bounds)
        dimming.append(NSBezierPath(rect: regionInView))
        dimming.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.38).setFill()
        dimming.fill()
        let outline = NSBezierPath(rect: regionInView)
        outline.lineWidth = 2
        NSColor.white.setStroke()
        outline.stroke()
    }
}
