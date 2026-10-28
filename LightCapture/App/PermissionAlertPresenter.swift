import AppKit

/// Standalone permission dialogs must not start a nested modal run loop inside
/// a MainActor task. Keep the window alive and resume only when it is dismissed.
@MainActor
final class PermissionAlertPresenter: NSObject, NSWindowDelegate {
    static let shared = PermissionAlertPresenter()

    private var alert: NSAlert?
    private var continuation: CheckedContinuation<Bool, Never>?
    private var presentationID: UUID?

    func present(_ alert: NSAlert) async -> Bool {
        let id = UUID()
        return await withTaskCancellationHandler {
            guard !Task.isCancelled else { return false }
            return await withCheckedContinuation { continuation in
                guard self.alert == nil else {
                    continuation.resume(returning: false)
                    return
                }
                self.alert = alert
                self.continuation = continuation
                presentationID = id
                for button in alert.buttons {
                    button.target = self
                    button.action = #selector(choose(_:))
                }
                alert.layout()
                let window = alert.window
                window.delegate = self
                window.level = .modalPanel
                window.hidesOnDeactivate = false
                window.isReleasedWhenClosed = false
                window.center()
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard self?.presentationID == id else { return }
                self?.finish(accepted: false)
            }
        }
    }

    func windowShouldClose(_: NSWindow) -> Bool {
        finish(accepted: false)
        return false
    }

    @objc private func choose(_ sender: NSButton) {
        finish(accepted: sender === alert?.buttons.first)
    }

    private func finish(accepted: Bool) {
        guard let continuation else { return }
        let window = alert?.window
        self.continuation = nil
        alert = nil
        presentationID = nil
        window?.orderOut(nil)
        window?.close()
        continuation.resume(returning: accepted)
    }
}
