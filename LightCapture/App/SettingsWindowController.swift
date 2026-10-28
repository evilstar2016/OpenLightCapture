import AppKit
import Carbon.HIToolbox
import Combine
import ServiceManagement
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    private var languageObserver: AnyCancellable?

    init(hotKeyService: HotKeyService, localization: LocalizationStore = .shared) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.title = L10n.settingsTitle
        window.identifier = NSUserInterfaceItemIdentifier("settings.window")
        window.center()
        window.contentView = NSHostingView(rootView: SettingsView(
            hotKeyService: hotKeyService, windowIdentifier: ObjectIdentifier(window), localization: localization
        ))
        super.init(window: window)
        languageObserver = NotificationCenter.default.publisher(for: LocalizationStore.didChange).sink { [weak self] _ in
            self?.window?.title = L10n.settingsTitle
        }
    }

    required init?(coder _: NSCoder) {
        nil
    }

    func showWindow() {
        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
private struct SettingsView: View {
    let hotKeyService: HotKeyService
    let windowIdentifier: ObjectIdentifier
    @ObservedObject var localization: LocalizationStore
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: Error?
    @State private var isRecordingShortcut = false
    @State private var shortcutFeedback: ShortcutFeedback = .current

    private enum ShortcutFeedback {
        case current, restored, updated, recording
        case failed(Error)
    }

    private var shortcutMessage: String {
        switch shortcutFeedback {
        case .current: hotKeyService.configuration.displayName
        case .restored: L10n.settingsShortcutRestored(hotKeyService.configuration.displayName)
        case .updated: L10n.settingsShortcutSet(hotKeyService.configuration.displayName)
        case .recording: L10n.settingsShortcutRecording
        case let .failed(error): error.localizedDescription
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 16) {
                    sectionTitle(L10n.settingsLanguage)
                    Spacer(minLength: 16)
                    Picker(selection: Binding(get: { localization.preference }, set: { localization.setPreference($0) })) {
                        Text(verbatim: L10n.settingsFollowSystem).tag("system")
                        ForEach(localization.configuration.languages) { language in
                            Text(verbatim: language.nativeName).tag(language.identifier)
                        }
                    } label: {
                        Text(verbatim: L10n.settingsLanguage)
                    }
                    .labelsHidden()
                    .frame(width: 196, alignment: .trailing)
                    .accessibilityIdentifier("settings.language")
                    .disabled(isRecordingShortcut)
                }
                if localization.pendingLanguage != nil {
                    explanation(L10n.settingsLanguagePending)
                } else if localization.preference == "system" {
                    let name = localization.configuration.languages.first { $0.identifier == localization.effectiveLanguage }?.nativeName ?? localization.effectiveLanguage
                    explanation(L10n.settingsCurrentLanguageValue(name))
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                sectionTitle(L10n.settingsShortcuts)
                HStack(spacing: 10) {
                    Text(verbatim: L10n.menuCapture)
                    Spacer(minLength: 16)
                    if isRecordingShortcut {
                        ShortcutRecorderView(onShortcut: recordShortcut, onCancel: cancelRecording)
                            .frame(width: 220, height: 28)
                    } else {
                        Button(action: beginRecording) {
                            Text(verbatim: hotKeyService.configuration.displayName)
                                .monospaced()
                                .frame(width: 156)
                        }
                        .accessibilityIdentifier("settings.shortcut")
                    }
                    Button(L10n.settingsRestore) {
                        do {
                            try hotKeyService.update(.default)
                            shortcutFeedback = .restored
                        } catch { shortcutFeedback = .failed(error) }
                    }
                    .fixedSize()
                    .disabled(isRecordingShortcut)
                }
                if showsShortcutFeedback {
                    explanation(shortcutMessage)
                }
                VStack(alignment: .leading, spacing: 4) {
                    explanation(L10n.settingsShortcutConflict)
                    explanation(L10n.settingsShortcutFallback)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                sectionTitle(L10n.settingsStartup)
                Toggle(L10n.settingsLaunchAtLogin, isOn: Binding(
                    get: { launchAtLogin }, set: { updateLoginItem(enabled: $0) }
                ))
                .toggleStyle(.checkbox)
                explanation(loginError.map { L10n.settingsLoginError($0.localizedDescription) } ?? loginItemStatusText)
                    .padding(.leading, 20)
            }

            Divider()

            HStack {
                explanation(L10n.settingsFollowAuthor)
                Spacer(minLength: 16)
                Link(destination: URL(string: "https://x.com/EverSeenU")!) {
                    HStack(spacing: 6) {
                        Text(verbatim: "X · @EverSeenU")
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                    }
                }
                .fixedSize()
                .help(L10n.settingsAuthorLinkHelp)
                .accessibilityLabel(Text(verbatim: L10n.settingsAuthorLinkHelp))
                .accessibilityIdentifier("settings.author.x")
            }
        }
        .controlSize(.regular)
        .padding(24)
        .frame(width: 560, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.locale, Locale(identifier: localization.effectiveLanguage))
        .onAppear {
            loginStatus = SMAppService.mainApp.status
            launchAtLogin = loginStatus == .enabled || loginStatus == .requiresApproval
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
            guard let window = notification.object as? NSWindow,
                  ObjectIdentifier(window) == windowIdentifier, isRecordingShortcut
            else { return }
            cancelRecording()
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(verbatim: title)
            .font(.headline)
    }

    private func explanation(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var showsShortcutFeedback: Bool {
        switch shortcutFeedback {
        case .current, .recording: false
        case .restored, .updated, .failed: true
        }
    }

    private func updateLoginItem(enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginError = nil
            loginStatus = SMAppService.mainApp.status
            launchAtLogin = enabled
        } catch {
            loginStatus = SMAppService.mainApp.status
            launchAtLogin = loginStatus == .enabled
            loginError = error
        }
    }

    private var loginItemStatusText: String {
        switch loginStatus {
        case .enabled: L10n.settingsLoginEnabled
        case .requiresApproval: L10n.settingsLoginApproval
        case .notRegistered: L10n.settingsLoginDisabled
        case .notFound: L10n.settingsLoginNotFound
        @unknown default: L10n.settingsLoginUnknown
        }
    }

    private func beginRecording() {
        shortcutFeedback = .recording
        hotKeyService.suspend()
        isRecordingShortcut = true
        localization.setShortcutRecording(true)
    }

    private func cancelRecording() {
        isRecordingShortcut = false
        shortcutFeedback = .current
        do { try hotKeyService.resume() }
        catch { shortcutFeedback = .failed(error) }
        localization.setShortcutRecording(false)
    }

    private func recordShortcut(_ configuration: HotKeyConfiguration) {
        do {
            try hotKeyService.update(configuration)
            shortcutFeedback = .updated
            try hotKeyService.resume()
        } catch {
            shortcutFeedback = .failed(error)
            try? hotKeyService.resume()
        }
        isRecordingShortcut = false
        localization.setShortcutRecording(false)
    }
}

@MainActor
private struct ShortcutRecorderView: NSViewRepresentable {
    let onShortcut: (HotKeyConfiguration) -> Void
    let onCancel: () -> Void

    func makeNSView(context _: Context) -> ShortcutRecorderNSView {
        let view = ShortcutRecorderNSView()
        view.onShortcut = onShortcut
        view.onCancel = onCancel
        return view
    }

    func updateNSView(_ view: ShortcutRecorderNSView, context _: Context) {
        view.onShortcut = onShortcut
        view.onCancel = onCancel
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
    }
}

@MainActor
private final class ShortcutRecorderNSView: NSView {
    var onShortcut: ((HotKeyConfiguration) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func draw(_: NSRect) {
        NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
        bounds.fill()
        let text = L10n.settingsShortcutPrompt
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor,
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attributes)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        capture(event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        capture(event)
    }

    private func capture(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            onCancel?()
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        guard modifiers != 0 else { return }
        let keyName = event.charactersIgnoringModifiers?.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = ""
        onShortcut?(HotKeyConfiguration(keyCode: event.keyCode, carbonModifiers: modifiers, keyName: keyName?.isEmpty == false ? keyName! : fallbackName))
    }
}
