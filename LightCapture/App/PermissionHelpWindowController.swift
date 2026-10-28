import AppKit
import Combine
import CoreGraphics
import SwiftUI

enum CapturePermissionGuidance {
    static var controlPermissionName: String {
        if #available(macOS 27.0, *) { L10n.permissionDeviceControl } else { L10n.permissionAccessibility }
    }

    static var automaticCaptureMessage: String {
        L10n.permissionAutomaticGuidance(controlPermissionName)
    }

    static var controlAccessLostMessage: String {
        L10n.permissionControlLost
    }
}

@MainActor
final class PermissionHelpWindowController: NSWindowController {
    static let shared = PermissionHelpWindowController()
    private var languageObserver: AnyCancellable?

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.permissionTitle
        window.center()
        window.contentView = NSHostingView(rootView: PermissionHelpView())
        super.init(window: window)
        languageObserver = NotificationCenter.default.publisher(for: LocalizationStore.didChange).sink { [weak self] _ in
            self?.window?.title = L10n.permissionTitle
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

private struct PermissionHelpView: View {
    @ObservedObject private var localization = LocalizationStore.shared
    @State private var screenPermission = CGPreflightScreenCaptureAccess()
    @State private var controlPermission = CGPreflightPostEventAccess()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(verbatim: L10n.permissionHeading)
                    .font(.title2.bold())

                permissionSection(
                    name: L10n.permissionScreenRecording,
                    available: screenPermission,
                    explanation: L10n.permissionScreenHelp,
                    buttonTitle: L10n.permissionOpenScreen,
                    pane: "Privacy_ScreenCapture"
                )
                permissionSection(
                    name: CapturePermissionGuidance.controlPermissionName,
                    available: controlPermission,
                    explanation: L10n.permissionControlHelp,
                    buttonTitle: L10n.permissionOpenControl,
                    pane: "Privacy_Accessibility"
                )

                VStack(alignment: .leading, spacing: 8) {
                    Label(L10n.permissionRestartHeading, systemImage: "arrow.clockwise")
                        .font(.headline)
                    Text(verbatim: L10n.permissionRestartHelp)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button(L10n.menuQuit) { NSApp.terminate(nil) }
                        Text(verbatim: L10n.permissionQuitWarning)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

                HStack {
                    Button(L10n.permissionRefresh) { refreshPermissions() }
                    Button(L10n.permissionRevealApp) {
                        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                    }
                }
                Text(verbatim: L10n.permissionStatusHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: L10n.permissionPrivacy)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(Bundle.main.bundleURL.path)
                    .font(.caption2).textSelection(.enabled).foregroundStyle(.secondary)
                    .lineLimit(3)
                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .frame(width: 560, height: 640)
        .environment(\.locale, Locale(identifier: localization.effectiveLanguage))
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissions()
        }
    }

    private func permissionSection(name: String, available: Bool, explanation: String, buttonTitle: String, pane: String) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(name).font(.headline)
                    Spacer()
                    Text(available ? L10n.permissionAvailable : L10n.permissionUnavailable)
                        .font(.caption)
                        .foregroundStyle(available ? Color.green : Color.orange)
                }
                Text(explanation)
                    .fixedSize(horizontal: false, vertical: true)
                Button(buttonTitle) {
                    if let settings = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
                        NSWorkspace.shared.open(settings)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }

    private func refreshPermissions() {
        screenPermission = CGPreflightScreenCaptureAccess()
        controlPermission = CGPreflightPostEventAccess()
    }
}
