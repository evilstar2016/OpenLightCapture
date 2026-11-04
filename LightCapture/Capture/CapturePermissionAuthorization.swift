import AppKit
import ApplicationServices
import CoreGraphics

enum CapturePermissionKind: Hashable {
    case screenCapture
    case automaticScroll

    var title: String {
        switch self {
        case .screenCapture: L10n.permissionScreenTitle
        case .automaticScroll: L10n.permissionControlTitle(CapturePermissionGuidance.controlPermissionName)
        }
    }

    var explanation: String {
        let purpose = switch self {
        case .screenCapture: L10n.permissionScreenPurpose
        case .automaticScroll: L10n.permissionControlPurpose
        }
        return L10n.permissionMessage(purpose)
    }

    var settingsURL: URL {
        let pane = switch self {
        case .screenCapture: "Privacy_ScreenCapture"
        case .automaticScroll: "Privacy_Accessibility"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
    }
}

@MainActor
final class CapturePermissionAuthorization {
    static let shared = makeShared()

    private static func makeShared() -> CapturePermissionAuthorization {
        CapturePermissionAuthorization(grantPreflight: { permission in
            await CapturePermissionSystemAccess.isPermissionEnabled(permission)
        })
    }

    private let preflight: @MainActor (CapturePermissionKind) async -> Bool
    private let grantPreflight: @MainActor (CapturePermissionKind) async -> Bool
    private let request: @MainActor (CapturePermissionKind) async -> Void
    private let confirmRestart: @MainActor () async -> Bool
    private let restartApplication: () -> Void
    private var awaitingPermissions: Set<CapturePermissionKind> = []
    private var restartRequiredPermissions: Set<CapturePermissionKind> = []
    private var isPresenting = false
    private var isAuthorizing = false
    private var isRequestingSystemAccess = false
    private var isCheckingPermissions = false
    private var settingsVisitID = UUID()
    private var isMonitoring = false
    private var pollingTask: Task<Void, Never>?
    private var restartPromptTask: Task<Void, Never>?
    private var registrations: [(NotificationCenter, NSObjectProtocol)] = []

    init(
        preflight: @escaping @MainActor (CapturePermissionKind) async -> Bool = { permission in
            await CapturePermissionSystemAccess.hasAccess(to: permission)
        },
        request: @escaping @MainActor (CapturePermissionKind) async -> Void = { permission in
            await CapturePermissionSystemAccess.request(permission)
        },
        grantPreflight: (@MainActor (CapturePermissionKind) async -> Bool)? = nil,
        confirmRestart: @escaping @MainActor () async -> Bool = {
            let alert = CapturePermissionAuthorization.makeRestartAlert()
            return await PermissionAlertPresenter.shared.present(alert)
        },
        restartApplication: @escaping () -> Void = { AppRelauncher.restart() }
    ) {
        self.preflight = preflight
        self.grantPreflight = grantPreflight ?? preflight
        self.request = request
        self.confirmRestart = confirmRestart
        self.restartApplication = restartApplication
    }

    func hasAccess(to permission: CapturePermissionKind) async -> Bool {
        guard !awaitingPermissions.contains(permission), !restartRequiredPermissions.contains(permission) else { return false }
        let allowed = await preflight(permission)
        return allowed && !awaitingPermissions.contains(permission) && !restartRequiredPermissions.contains(permission)
    }

    /// Called by capture actions, never by the frame or automatic-scroll loop.
    /// Returning from Settings does not restart the interrupted capture.
    func ensureAccess(to permission: CapturePermissionKind) async -> Bool {
        guard !isPresenting, !isAuthorizing else { return false }
        isAuthorizing = true
        defer { isAuthorizing = false }
        await checkForPermissionChanges()
        guard !Task.isCancelled else { return false }
        if await hasAccess(to: permission) { return !Task.isCancelled && !isPresenting }
        guard !Task.isCancelled else { return false }
        guard !restartRequiredPermissions.contains(permission) else { return false }
        isRequestingSystemAccess = true
        defer { isRequestingSystemAccess = false }
        if permission == .screenCapture {
            // macOS owns the lock dialog, its Open System Settings / Deny
            // actions, and the relaunch prompt after the user enables access.
            // The request can return while that dialog is still open: do not
            // open Settings or schedule an app-owned restart reminder here.
            // Let macOS decide whether to show the native prompt on each
            // explicit capture attempt, including attempts after a denial.
            await request(permission)
            return false
        }
        awaitingPermissions.insert(permission)
        let visitID = UUID()
        settingsVisitID = visitID
        // The native control-access dialog owns Open System Settings / Deny,
        // just like the screen-recording dialog. A returned request is not a
        // grant and must not trigger a Settings jump or a restart reminder.
        await request(permission)
        guard !Task.isCancelled, settingsVisitID == visitID, awaitingPermissions.contains(permission) else { return false }
        beginPollingIfNeeded()
        return false
    }

    func startMonitoring(
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        applicationNotificationCenter: NotificationCenter = .default
    ) {
        guard !isMonitoring else { return }
        isMonitoring = true
        let workspaceObserver = workspaceNotificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            let bundleIdentifier = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            Task { @MainActor [weak self] in await self?.applicationDidActivate(bundleIdentifier: bundleIdentifier) }
        }
        registrations.append((workspaceNotificationCenter, workspaceObserver))
        let applicationObserver = applicationNotificationCenter.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, isMonitoring else { return }
                await checkForPermissionChanges()
            }
        }
        registrations.append((applicationNotificationCenter, applicationObserver))
        beginPollingIfNeeded()
    }

    func stopMonitoring() {
        isMonitoring = false
        pollingTask?.cancel()
        pollingTask = nil
        restartPromptTask?.cancel()
        restartPromptTask = nil
        for (center, observer) in registrations {
            center.removeObserver(observer)
        }
        registrations.removeAll()
        awaitingPermissions.removeAll()
        settingsVisitID = UUID()
    }

    func applicationDidActivate(bundleIdentifier: String?) async {
        guard isMonitoring, !awaitingPermissions.isEmpty else { return }
        if bundleIdentifier == "com.apple.systempreferences" || bundleIdentifier == Bundle.main.bundleIdentifier {
            await checkForPermissionChanges()
        }
    }

    func checkForPermissionChanges() async {
        guard !isPresenting, !isRequestingSystemAccess, !awaitingPermissions.isEmpty else { return }
        guard !isCheckingPermissions else { return }
        let visitID = settingsVisitID
        var granted: Set<CapturePermissionKind> = []
        // Keep checking while Settings is active so enabling its switch can
        // show the reminder without requiring a return to the capture panel.
        // A settings visit or a returned native request alone is never a grant.
        isCheckingPermissions = true
        for permission in awaitingPermissions {
            if await grantPreflight(permission) { granted.insert(permission) }
        }
        isCheckingPermissions = false
        guard !Task.isCancelled, settingsVisitID == visitID, !isPresenting, !isRequestingSystemAccess,
              !awaitingPermissions.isEmpty, !granted.isEmpty else { return }
        restartRequiredPermissions.formUnion(granted)
        // Clear the pending visit before showing the reminder.
        awaitingPermissions.removeAll()
        pollingTask?.cancel()
        pollingTask = nil
        isPresenting = true
        // Polling may be the caller we just cancelled. Present in a separate
        // task so cancelling the watcher cannot cancel its own reminder.
        let promptTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let confirmed = await confirmRestart()
            isPresenting = false
            restartPromptTask = nil
            if confirmed, !Task.isCancelled, settingsVisitID == visitID { restartApplication() }
        }
        restartPromptTask = promptTask
        await promptTask.value
    }

    static func makeRestartAlert() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = L10n.permissionRestartHeading
        alert.informativeText = L10n.permissionRestartPrompt
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.permissionRestartNow)
        alert.addButton(withTitle: L10n.permissionRestartLater)
        alert.window.level = .modalPanel
        return alert
    }

    private func beginPollingIfNeeded() {
        guard isMonitoring, !awaitingPermissions.isEmpty, pollingTask == nil else { return }
        pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                guard let self, isMonitoring, !awaitingPermissions.isEmpty else { return }
                await checkForPermissionChanges()
            }
        }
    }
}

/// TCC queries and native requests may wait on a system service. Use a dedicated
/// queue, not the main thread or a blocking Swift concurrency executor thread.
enum CapturePermissionSystemAccess {
    private static let queue = DispatchQueue(label: "io.github.evilstar2016.openlightcapture.permissions", qos: .userInitiated)

    static func hasAccess(to permission: CapturePermissionKind) async -> Bool {
        await perform {
            switch permission {
            case .screenCapture: CGPreflightScreenCaptureAccess()
            case .automaticScroll: CGPreflightPostEventAccess()
            }
        }
    }

    static func isPermissionEnabled(_ permission: CapturePermissionKind) async -> Bool {
        await perform {
            switch permission {
            case .screenCapture: CGPreflightScreenCaptureAccess()
            case .automaticScroll:
                // Accessibility trust reflects the control-permission grant.
                // Event-posting access in this process can still need a
                // relaunch. This result only schedules a restart; scrolling
                // continues to require CGPreflightPostEventAccess().
                AXIsProcessTrusted() || CGPreflightPostEventAccess()
            }
        }
    }

    static func request(_ permission: CapturePermissionKind) async {
        _ = await perform {
            switch permission {
            case .screenCapture: CGRequestScreenCaptureAccess()
            case .automaticScroll: CGRequestPostEventAccess()
            }
        }
    }

    static func perform(_ operation: @escaping @Sendable () -> Bool) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: operation()) }
        }
    }
}
