import AppKit
import CoreGraphics

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var screenshotMenuItem: NSMenuItem?
    private var settingsWindowController: SettingsWindowController?
    private lazy var hotKeyService = HotKeyService()
    private let captureFlowController = CaptureFlowController()
    private let assetStore = AssetStore()
    private lazy var outputDeliveryService = OutputDeliveryService(assetStore: assetStore)
    private lazy var longCaptureController = LongCaptureController(captureFlowController: captureFlowController)
    private var instanceLockDescriptor: Int32 = -1
    private var captureRequestObserver: NSObjectProtocol?
    private var captureEnvironmentMonitor: CaptureEnvironmentMonitor?
    private var applicationActivationObserver: NSObjectProtocol?
    private var publishTipID = UUID()
    private var languageObserver: NSObjectProtocol?
    private var systemLanguageObservers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_: Notification) {
        // Hosted unit tests need AppKit, but must not contend with the real app's
        // instance lock, register shortcuts, or maintain the user's clipboard.
        guard NSClassFromString("XCTestCase") == nil else { return }
        guard acquireInstanceLock() else {
            NSApp.terminate(nil)
            return
        }

        LegacyPreferences.importOnce()
        CapturePermissionAuthorization.shared.startMonitoring()

        let ownPID = ProcessInfo.processInfo.processIdentifier
        if let frontmost = NSWorkspace.shared.frontmostApplication, frontmost.processIdentifier != ownPID {
            captureFlowController.lastExternalProcessID = frontmost.processIdentifier
        }
        applicationActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  application.processIdentifier != ownPID
            else { return }
            let pid = application.processIdentifier
            Task { @MainActor [weak self] in self?.captureFlowController.lastExternalProcessID = pid }
        }

        let localization = LocalizationStore.shared
        captureFlowController.onSessionActivityChange = { active in localization.setSessionActive(active) }
        languageObserver = NotificationCenter.default.addObserver(forName: LocalizationStore.didChange, object: localization, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshLocalization() }
        }
        for name in [NSApplication.didBecomeActiveNotification, NSLocale.currentLocaleDidChangeNotification] {
            systemLanguageObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in LocalizationStore.shared.refreshSystemLanguage() }
            })
        }
        installMenuBarItem()
        installApplicationMenu()
        settingsWindowController = SettingsWindowController(hotKeyService: hotKeyService)
        TileStore.cleanupAbandonedWorkspaces()
        assetStore.startMaintenance()
        outputDeliveryService.onPublished = { [weak self] in self?.showPublishedTip() }
        captureFlowController.onLongCaptureRequested = { [weak self] screen, rect, session in
            self?.longCaptureController.begin(screen: screen, pixelRect: rect, session: session)
        }
        captureFlowController.onSessionCancelled = { [weak self] in self?.longCaptureController.cancel() }
        captureFlowController.onImageReady = { [weak self] image, session in
            guard let self else { return false }
            return await outputDeliveryService.copy(image, startedAt: session.startedAt) {
                self.captureFlowController.isCurrent(sessionID: session.id, generation: session.generation)
            }
        }
        captureFlowController.onSaveImageRequested = { [weak self] image, session in
            guard let self else { return false }
            return await outputDeliveryService.saveAndCopy(
                image,
                startedAt: session.startedAt,
                parentWindow: captureFlowController.outputPanelParent,
                isCurrent: { self.captureFlowController.isCurrent(sessionID: session.id, generation: session.generation) }
            )
        }
        captureEnvironmentMonitor = CaptureEnvironmentMonitor { [weak self] reason in
            guard let self, captureFlowController.cancelForEnvironmentChange() else { return }
            showStatusTip(L10n.captureRestartHint(reason), duration: .seconds(20))
        }
        captureRequestObserver = NotificationCenter.default.addObserver(forName: .captureRequested, object: nil, queue: .main) { [weak self] notification in
            guard let mode = notification.object as? CaptureMode else { return }
            Task { @MainActor [weak self] in await self?.captureFlowController.begin(mode: mode) }
        }
        hotKeyService.onConfigurationChange = { [weak self] configuration in
            self?.screenshotMenuItem?.title = L10n.menuCaptureShortcut(configuration.displayName)
        }
        do {
            try hotKeyService.register(onPressed: { [weak self] in self?.beginCapture(nil) })
        } catch {
            showAlert(title: L10n.errorHotKeyTitle, message: error.localizedDescription)
        }
    }

    func applicationWillTerminate(_: Notification) {
        CapturePermissionAuthorization.shared.stopMonitoring()
        if let applicationActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(applicationActivationObserver)
            self.applicationActivationObserver = nil
        }
        if let captureRequestObserver {
            NotificationCenter.default.removeObserver(captureRequestObserver)
            self.captureRequestObserver = nil
        }
        if let languageObserver { NotificationCenter.default.removeObserver(languageObserver) }
        systemLanguageObservers.forEach { NotificationCenter.default.removeObserver($0) }
        systemLanguageObservers.removeAll()
        captureEnvironmentMonitor?.stop()
        captureEnvironmentMonitor = nil
        captureFlowController.cancelCurrentSession()
        assetStore.stopMaintenance()
        hotKeyService.unregister()
        if instanceLockDescriptor >= 0 {
            flock(instanceLockDescriptor, LOCK_UN)
            close(instanceLockDescriptor)
            instanceLockDescriptor = -1
        }
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        settingsWindowController?.showWindow()
        return false
    }

    private func installApplicationMenu() {
        let mainMenu = NSMenu()
        let applicationMenu = NSMenu(title: L10n.appName)
        for item in [
            NSMenuItem(title: L10n.menuCapture, action: #selector(beginCapture(_:)), keyEquivalent: ""),
            NSMenuItem(title: L10n.menuLongCapture, action: #selector(beginLongCapture(_:)), keyEquivalent: ""),
            NSMenuItem(title: L10n.menuSettings, action: #selector(openSettings), keyEquivalent: ","),
            NSMenuItem(title: L10n.menuPermissionHelp, action: #selector(openPermissionHelp), keyEquivalent: ""),
            NSMenuItem.separator(),
            NSMenuItem(title: L10n.menuQuit, action: #selector(quit), keyEquivalent: "q"),
        ] {
            if item.action != nil { item.target = self }
            applicationMenu.addItem(item)
        }
        let applicationItem = NSMenuItem()
        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)
        let editMenu = NSMenu(title: L10n.menuEdit)
        for (title, action, key) in [
            (L10n.actionUndo, "undo:", "z"), (L10n.actionRedo, "redo:", "Z"),
            (L10n.actionCut, "cut:", "x"), (L10n.actionCopy, "copy:", "c"),
            (L10n.actionPaste, "paste:", "v"), (L10n.actionSelectAll, "selectAll:", "a"),
        ] {
            editMenu.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: key))
        }
        let editItem = NSMenuItem(title: L10n.menuEdit, action: nil, keyEquivalent: "")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    private func installMenuBarItem() {
        let item = statusItem ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: L10n.appName)
        item.button?.toolTip = L10n.appName

        let menu = NSMenu()
        let screenshotItem = NSMenuItem(title: L10n.menuCaptureShortcut(hotKeyService.configuration.displayName), action: #selector(beginCapture(_:)), keyEquivalent: "")
        menu.addItem(screenshotItem)
        screenshotMenuItem = screenshotItem
        menu.addItem(NSMenuItem(title: L10n.menuLongCapture, action: #selector(beginLongCapture(_:)), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L10n.menuSettings, action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: L10n.menuPermissionHelp, action: #selector(openPermissionHelp), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L10n.menuQuit, action: #selector(quit), keyEquivalent: "q"))
        for menuItem in menu.items where menuItem.action != nil {
            menuItem.target = self
        }
        item.menu = menu
        statusItem = item
    }

    private func refreshLocalization() {
        publishTipID = UUID()
        installMenuBarItem()
        installApplicationMenu()
    }

    @objc private func beginCapture(_: Any?) {
        NotificationCenter.default.post(name: .captureRequested, object: CaptureMode.normal)
    }

    @objc private func beginLongCapture(_: Any?) {
        NotificationCenter.default.post(name: .captureRequested, object: CaptureMode.long)
    }

    @objc private func openSettings() {
        settingsWindowController?.showWindow()
    }

    @objc private func openPermissionHelp() {
        PermissionHelpWindowController.shared.showWindow()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.actionOk)
        alert.runModal()
    }

    private func showPublishedTip() {
        showStatusTip(L10n.captureCopied, duration: .seconds(2))
    }

    private func showStatusTip(_ message: String, duration: Duration) {
        let notificationID = UUID()
        publishTipID = notificationID
        let button = statusItem?.button
        button?.toolTip = message
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            guard let self, publishTipID == notificationID else { return }
            button?.toolTip = L10n.appName
        }
    }

    private func acquireInstanceLock() -> Bool {
        do {
            let supportDirectory = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appending(path: Bundle.main.bundleIdentifier ?? "io.github.evilstar2016.openlightcapture", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
            _ = chmod(supportDirectory.path, mode_t(S_IRWXU))
            let lockURL = supportDirectory.appending(path: "instance.lock")
            let descriptor = open(lockURL.path, O_CREAT | O_RDWR | O_CLOEXEC, mode_t(S_IRUSR | S_IWUSR))
            guard descriptor >= 0 else { return false }
            guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
                close(descriptor)
                return false
            }
            instanceLockDescriptor = descriptor
            return true
        } catch {
            return false
        }
    }
}

enum CaptureMode: Equatable {
    case normal
    case long
}

extension Notification.Name {
    static let captureRequested = Notification.Name("OpenLightCapture.captureRequested")
}
