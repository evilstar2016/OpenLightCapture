import AppKit
import AVKit

@MainActor
final class RecordingPreviewWindowController: NSObject, NSWindowDelegate {
    let window: NSWindow
    var onCopy: ((Bool) -> Void)?
    var onRerecord: (() -> Void)?
    var onDiscard: (() -> Void)?
    var onRetry: (() -> Void)?
    private let imageView = NSImageView()
    private let videoView = AVPlayerView()
    private let help = NSTextField(wrappingLabelWithString: "")
    private let summary = NSTextField(labelWithString: "")
    private let message = NSTextField(wrappingLabelWithString: "")
    private let play = NSButton(title: L10n.actionPause, target: nil, action: nil)
    private let copy = NSButton(title: L10n.gifCopy, target: nil, action: nil)
    private let save = NSButton(title: L10n.gifSaveCopy, target: nil, action: nil)
    private let retry = NSButton(title: L10n.gifRetryEncoding, target: nil, action: nil)
    private let rerecord = NSButton(title: L10n.gifRerecord, target: nil, action: nil)
    private let discard = NSButton(title: L10n.gifAbandon, target: nil, action: nil)
    private let player = GIFPreviewPlayer()
    private var closing = false
    private var kind: RecordingKind = .gif

    override init() {
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 740, height: 600),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        super.init()
        window.title = L10n.gifPreview
        window.isReleasedWhenClosed = false
        window.minSize = CGSize(width: 540, height: 400)
        window.delegate = self
        imageView.imageScaling = .scaleProportionallyDown
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        message.font = .systemFont(ofSize: 12)
        summary.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        help.stringValue = L10n.gifPasteHelp
        help.font = .systemFont(ofSize: 11)
        help.textColor = .secondaryLabelColor
        videoView.isHidden = true
        videoView.controlsStyle = .inline
        let controls = NSStackView(views: [play, copy, save, retry])
        controls.spacing = 8
        controls.detachesHiddenViews = true
        let actions = NSStackView(views: [rerecord, discard])
        actions.spacing = 8
        for (button, name, action) in [(play, "play", #selector(playAction)), (copy, "copy", #selector(copyAction)),
                                       (save, "save", #selector(saveAction)), (retry, "retry", #selector(retryAction)),
                                       (rerecord, "rerecord", #selector(rerecordAction)), (discard, "discard", #selector(discardAction))]
        {
            button.target = self
            button.action = action
            button.bezelStyle = .rounded
            button.identifier = NSUserInterfaceItemIdentifier("capture.gif.\(name)")
            button.setAccessibilityLabel(button.title)
        }
        let stack = NSStackView(views: [imageView, videoView, summary, message, controls, actions, help])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        let root = NSView()
        root.addSubview(stack)
        window.contentView = root
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
            imageView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            imageView.heightAnchor.constraint(greaterThanOrEqualToConstant: 140),
            videoView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            videoView.heightAnchor.constraint(greaterThanOrEqualToConstant: 140),
            message.widthAnchor.constraint(equalTo: stack.widthAnchor),
            help.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        player.onImage = { [weak self] image in
            self?.imageView.image = NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height))
        }
        player.onError = { [weak self] text in self?.message.stringValue = text }
        window.center()
    }

    func show(source: GIFPreviewSource, text: String, canPublish: Bool, canRetry: Bool = false) {
        kind = .gif
        window.title = L10n.gifPreview
        imageView.isHidden = false
        videoView.isHidden = true
        videoView.player?.pause()
        videoView.player = nil
        play.isHidden = false
        copy.isHidden = false
        save.title = L10n.gifSaveCopy
        save.setAccessibilityLabel(save.title)
        help.stringValue = L10n.gifPasteHelp
        player.load(source)
        play.title = L10n.actionPause
        switch source {
        case let .gif(result): summary.stringValue = L10n.gifSummary(duration: result.duration, width: result.width, height: result.height, bytes: result.byteCount)
        case let .raw(recording): summary.stringValue = L10n.gifSummary(duration: recording.duration, width: recording.width, height: recording.height, bytes: nil)
        }
        message.stringValue = text
        copy.isEnabled = canPublish
        save.isEnabled = canPublish
        retry.isHidden = !canRetry
        rerecord.isEnabled = true
        discard.isEnabled = true
        play.isEnabled = true
        present()
    }

    func showVideo(_ result: VideoResult, text: String) {
        kind = .video
        window.title = L10n.videoPreview
        player.stop()
        imageView.isHidden = true
        videoView.isHidden = false
        videoView.player?.pause()
        videoView.player = AVPlayer(url: result.url)
        summary.stringValue = L10n.videoSummary(result)
        message.stringValue = text
        help.stringValue = L10n.videoHelp
        play.isHidden = true
        copy.isHidden = true
        retry.isHidden = true
        save.title = L10n.videoSave
        save.setAccessibilityLabel(save.title)
        for button in [save, rerecord, discard] {
            button.isEnabled = true
        }
        present()
    }

    func showFinishingVideo() {
        kind = .video
        window.title = L10n.videoPreview
        stopPlayback()
        imageView.image = nil
        imageView.isHidden = false
        videoView.isHidden = true
        summary.stringValue = ""
        help.stringValue = L10n.videoHelp
        play.isHidden = true
        copy.isHidden = true
        retry.isHidden = true
        save.title = L10n.videoSave
        save.setAccessibilityLabel(save.title)
        setBusy(true, text: L10n.videoFinishing, allowDiscard: true)
        present()
    }

    func setBusy(_ value: Bool, text: String, allowDiscard: Bool = false) {
        message.stringValue = text
        for button in [copy, save, retry, rerecord] {
            button.isEnabled = !value
        }
        // Closing during an external save/publish could race with a committed file.
        discard.isEnabled = !value || allowDiscard
    }

    func showFailure(_ text: String, canPublish: Bool) {
        message.stringValue = text
        copy.isEnabled = canPublish
        save.isEnabled = canPublish
        rerecord.isEnabled = true
        discard.isEnabled = true
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func pauseForSleep() {
        player.pause()
        videoView.player?.pause()
    }

    func stopPlayback() {
        player.stop()
        imageView.image = nil
        videoView.player?.pause()
        videoView.player?.replaceCurrentItem(with: nil)
        videoView.player = nil
    }

    func stopPlaybackAndWait() async {
        await player.stopAndWait()
        stopPlayback()
    }

    func reposition() {
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(window.frame) }) { window.center() }
    }

    func dismiss() {
        closing = true
        stopPlayback()
        window.close()
    }

    func windowShouldClose(_: NSWindow) -> Bool {
        if closing { return true }
        guard discard.isEnabled else { return false }
        discardAction()
        return false
    }

    private func confirm(_ text: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = text
        alert.addButton(withTitle: L10n.gifAbandon)
        alert.addButton(withTitle: L10n.actionCancel)
        return alert.runModal() == .alertFirstButtonReturn
    }

    @objc private func playAction() {
        player.toggle()
        play.title = player.isPlaying ? L10n.actionPause : L10n.actionResume
    }

    @objc private func copyAction() {
        onCopy?(false)
    }

    @objc private func saveAction() {
        onCopy?(true)
    }

    @objc private func retryAction() {
        onRetry?()
    }

    @objc private func rerecordAction() {
        if confirm(kind == .gif ? L10n.gifRerecordPrompt : L10n.videoRerecordPrompt) { onRerecord?() }
    }

    @objc private func discardAction() {
        if confirm(kind == .gif ? L10n.gifDiscardPrompt : L10n.videoDiscardPrompt) { onDiscard?() }
    }
}
