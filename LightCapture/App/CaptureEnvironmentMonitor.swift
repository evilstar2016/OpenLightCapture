import AppKit

@MainActor
final class CaptureEnvironmentMonitor {
    private var registrations: [(NotificationCenter, NSObjectProtocol)] = []
    private var isRunning = true

    init(
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        applicationNotificationCenter: NotificationCenter = .default,
        onInterruption: @escaping @MainActor (String) -> Void
    ) {
        observe(
            center: workspaceNotificationCenter,
            name: NSWorkspace.willSleepNotification,
            reason: L10n.interruptionSleep,
            handler: onInterruption
        )
        observe(
            center: workspaceNotificationCenter,
            name: NSWorkspace.screensDidSleepNotification,
            reason: L10n.interruptionDisplaySleep,
            handler: onInterruption
        )
        observe(
            center: workspaceNotificationCenter,
            name: NSWorkspace.sessionDidResignActiveNotification,
            reason: L10n.interruptionSession,
            handler: onInterruption
        )
        observe(
            center: applicationNotificationCenter,
            name: NSApplication.didChangeScreenParametersNotification,
            reason: L10n.interruptionDisplayChange,
            handler: onInterruption
        )
    }

    func stop() {
        isRunning = false
        for (center, observer) in registrations {
            center.removeObserver(observer)
        }
        registrations.removeAll()
    }

    private func observe(
        center: NotificationCenter,
        name: Notification.Name,
        reason: @autoclosure @escaping @Sendable () -> String,
        handler: @escaping @MainActor (String) -> Void
    ) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard self?.isRunning == true else { return }
                handler(reason())
            }
        }
        registrations.append((center, observer))
    }
}
