import AppKit
import CoreGraphics
import os

@MainActor
final class CaptureFlowController {
    var onSessionActivityChange: ((Bool) -> Void)?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "io.github.evilstar2016.openlightcapture", category: "CaptureFlow")
    let sessions = CaptureSessionCoordinator()
    var lastExternalProcessID: Int32?

    private let captureService = ScreenCaptureService()
    private var focusedApplication: FocusContext?
    private var frozenScreens: [FrozenScreen] = []
    private var selectionWindows: [SelectionOverlayWindow] = []
    private var editorWindow: AnnotationEditorWindowController?

    var onLongCaptureRequested: ((FrozenScreen, CGRect, ActiveCaptureSession) -> Void)?
    var onImageReady: ((CGImage, ActiveCaptureSession) async -> Bool)?
    var onSaveImageRequested: ((CGImage, ActiveCaptureSession) async -> Bool)?
    var onSessionCancelled: (() -> Void)?
    var onScreenPermissionRevocation: () -> Void = {
        Task { @MainActor in _ = await CapturePermissionAuthorization.shared.ensureAccess(to: .screenCapture) }
    }

    var outputPanelParent: NSWindow? {
        editorWindow?.window ?? selectionWindows.first(where: { $0.isKeyWindow }) ?? selectionWindows.first(where: { $0.isVisible })
    }

    func begin(mode: CaptureMode) async {
        logger.info("Capture begin requested: \(String(describing: mode), privacy: .public)")
        if let current = sessions.activeSession {
            logger.info("Capture request reused active session in state \(String(describing: current.state), privacy: .public)")
            if current.state == .editing {
                editorWindow?.showWindow()
            } else {
                selectionWindows.forEach { $0.orderFrontRegardless() }
            }
            return
        }

        focusedApplication = FocusContext.capture(fallbackProcessID: lastExternalProcessID)
        guard let session = sessions.begin(mode: mode, targetProcessID: focusedApplication?.processIdentifier) else { return }
        onSessionActivityChange?(true)
        logger.info("Capture session started: \(session.id.uuidString, privacy: .public)")

        await captureDisplays(for: session)
    }

    func cancelCurrentSession(restoreFocus: Bool = true) {
        guard let session = sessions.activeSession else { return }
        _ = sessions.cancel(sessionID: session.id, generation: session.generation)
        onSessionCancelled?()
        closeSelectionWindows()
        editorWindow?.close()
        editorWindow = nil
        frozenScreens.removeAll(keepingCapacity: false)
        if restoreFocus { focusedApplication?.restore() }
        focusedApplication = nil
        notifySessionIdle()
    }

    @discardableResult
    func cancelForEnvironmentChange() -> Bool {
        guard sessions.activeSession != nil else { return false }
        cancelCurrentSession(restoreFocus: false)
        return true
    }

    @discardableResult
    func cancelForScreenPermissionRevocation() -> Bool {
        guard sessions.activeSession != nil else { return false }
        cancelCurrentSession(restoreFocus: false)
        onScreenPermissionRevocation()
        return true
    }

    private func captureDisplays(for session: ActiveCaptureSession) async {
        let hasScreenAccess = CGPreflightScreenCaptureAccess()
        logger.info("Screen capture preflight: \(hasScreenAccess, privacy: .public)")
        guard hasScreenAccess else {
            logger.error("Screen capture access was denied")
            _ = sessions.cancel(sessionID: session.id, generation: session.generation)
            frozenScreens.removeAll(keepingCapacity: false)
            focusedApplication?.restore()
            focusedApplication = nil
            _ = await CapturePermissionAuthorization.shared.ensureAccess(to: .screenCapture)
            notifySessionIdle()
            return
        }

        do {
            let capturedScreens = try await captureService.captureVisibleDisplays()
            logger.info("Captured visible displays: \(capturedScreens.count, privacy: .public)")
            guard sessions.isCurrent(sessionID: session.id, generation: session.generation) else { return }
            frozenScreens = capturedScreens
            guard sessions.transition(sessionID: session.id, generation: session.generation, to: .selecting) else { return }
            showSelection(for: session)
        } catch {
            guard sessions.isCurrent(sessionID: session.id, generation: session.generation) else { return }
            logger.error("Screen capture failed: \(error.localizedDescription, privacy: .public)")
            _ = sessions.cancel(sessionID: session.id, generation: session.generation)
            showError(L10n.errorCaptureTitle, detail: error.localizedDescription)
            focusedApplication?.restore()
            focusedApplication = nil
            notifySessionIdle()
        }
    }

    private func changeCaptureSource(to mode: CaptureMode) async {
        guard let previousSession = sessions.activeSession, previousSession.state == .editing else { return }
        editorWindow?.dismissForCaptureSourceChange()
        editorWindow = nil
        _ = sessions.cancel(sessionID: previousSession.id, generation: previousSession.generation)
        onSessionCancelled?()
        closeSelectionWindows()
        frozenScreens.removeAll(keepingCapacity: false)

        let targetProcessID = previousSession.targetProcessID ?? focusedApplication?.processIdentifier
        if let targetProcessID,
           let targetApplication = NSRunningApplication(processIdentifier: targetProcessID),
           !targetApplication.isTerminated
        {
            targetApplication.activate(options: [.activateAllWindows])
        } else {
            focusedApplication?.restore()
        }
        guard let session = sessions.begin(mode: mode, targetProcessID: targetProcessID) else { return }
        try? await Task.sleep(for: .milliseconds(150))
        guard !Task.isCancelled, sessions.isCurrent(sessionID: session.id, generation: session.generation) else { return }
        await captureDisplays(for: session)
    }

    private func showSelection(for session: ActiveCaptureSession) {
        closeSelectionWindows()
        let screens = frozenScreens.sorted { first, second in
            first.screenFrame.contains(NSEvent.mouseLocation) == false && second.screenFrame.contains(NSEvent.mouseLocation)
        }
        selectionWindows = screens.map { screen in
            let window = SelectionOverlayWindow(screen: screen, initialMode: session.mode)
            window.onCancel = { [weak self] in self?.cancelCurrentSession() }
            window.onOutput = { [weak self] image, rect, selectedWindow, save in
                await self?.publishInlineSelection(image: image, on: screen, localRect: rect, selectedWindow: selectedWindow, save: save) ?? false
            }
            window.onLongCapture = { [weak self] rect, selectedWindow in
                self?.completeSelection(on: screen, localRect: rect, selectedWindow: selectedWindow, useLongCapture: true)
            }
            return window
        }
        NSApp.activate(ignoringOtherApps: true)
        selectionWindows.forEach { $0.present() }
        let overlayCount = selectionWindows.count
        logger.info("Selection overlays presented: \(overlayCount, privacy: .public)")
    }

    func publishInlineSelection(image: CGImage, on screen: FrozenScreen, localRect: CGRect, selectedWindow: CapturedWindow?, save: Bool) async -> Bool {
        guard let session = sessions.activeSession, session.state == .selecting,
              let globalRect = screen.transform.globalScreenRect(fromLocalTopLeftRect: localRect)
        else { return false }
        if let target = selectedWindow ?? CapturedWindow.target(for: globalRect, in: screen.windows) {
            sessions.setTarget(sessionID: session.id, generation: session.generation, processID: target.processIdentifier, windowID: target.id)
        }
        guard sessions.transition(sessionID: session.id, generation: session.generation, to: .preparingOutput),
              let outputSession = sessions.activeSession
        else { return false }
        let succeeded = await deliver(image, session: outputSession, save: save)
        if !succeeded, sessions.isCurrent(sessionID: session.id, generation: session.generation) {
            _ = sessions.transition(sessionID: session.id, generation: session.generation, to: .selecting)
        }
        return succeeded
    }

    private func completeSelection(
        on screen: FrozenScreen,
        localRect: CGRect,
        selectedWindow: CapturedWindow?,
        useLongCapture: Bool,
        openEditor: Bool = false
    ) {
        guard let session = sessions.activeSession, session.state == .selecting,
              let globalRect = screen.transform.globalScreenRect(fromLocalTopLeftRect: localRect),
              let pixelRect = screen.transform.pixelRect(fromGlobalScreenRect: globalRect),
              pixelRect.width >= 1,
              pixelRect.height >= 1
        else {
            return
        }

        if let selectedWindow {
            sessions.setTarget(
                sessionID: session.id,
                generation: session.generation,
                processID: selectedWindow.processIdentifier,
                windowID: selectedWindow.id
            )
        } else if let targetWindow = CapturedWindow.target(for: globalRect, in: screen.windows) {
            sessions.setTarget(
                sessionID: session.id,
                generation: session.generation,
                processID: targetWindow.processIdentifier,
                windowID: targetWindow.id
            )
        }
        closeSelectionWindows()

        if useLongCapture {
            guard sessions.transition(sessionID: session.id, generation: session.generation, to: .scrollReady) else { return }
            guard let updatedSession = sessions.activeSession else { return }
            if let processID = updatedSession.targetProcessID,
               let targetApplication = NSRunningApplication(processIdentifier: processID),
               !targetApplication.isTerminated
            {
                targetApplication.activate(options: [.activateAllWindows])
            } else {
                focusedApplication?.restore()
            }
            frozenScreens.removeAll(keepingCapacity: false)
            if let onLongCaptureRequested {
                onLongCaptureRequested(screen, pixelRect, updatedSession)
            } else {
                showError(L10n.errorLongUnavailable, detail: L10n.errorLongService)
                cancelCurrentSession()
            }
            return
        }

        guard let croppedImage = screen.image.cropping(topLeftRect: pixelRect.integral) else {
            showError(L10n.errorSelectionTitle, detail: L10n.errorSelectionPixels)
            showSelection(for: session)
            return
        }
        if openEditor {
            guard sessions.transition(sessionID: session.id, generation: session.generation, to: .editing) else { return }
            presentEditor(image: croppedImage, session: session, annotationPixelScale: CGFloat(screen.image.width) / screen.screenFrame.width)
            return
        }

        guard sessions.transition(sessionID: session.id, generation: session.generation, to: .preparingOutput) else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            if await deliver(croppedImage, session: session, save: false) { return }
            guard sessions.isCurrent(sessionID: session.id, generation: session.generation),
                  sessions.transition(sessionID: session.id, generation: session.generation, to: .editing)
            else { return }
            presentEditor(image: croppedImage, session: session, bannerMessage: L10n.errorCopyRetained, annotationPixelScale: CGFloat(screen.image.width) / screen.screenFrame.width)
        }
    }

    func startLongCapture(sessionID: UUID, generation: UInt64) -> Bool {
        sessions.transition(sessionID: sessionID, generation: generation, to: .capturing)
    }

    func updateLongCaptureState(sessionID: UUID, generation: UInt64, state: CaptureSessionState) -> Bool {
        sessions.transition(sessionID: sessionID, generation: generation, to: state)
    }

    func isCurrent(sessionID: UUID, generation: UInt64) -> Bool {
        sessions.isCurrent(sessionID: sessionID, generation: generation)
    }

    func presentLongCaptureResult(image: CGImage, sessionID: UUID, generation: UInt64, bannerMessage: String?, annotationPixelScale: CGFloat = 1) {
        guard sessions.isCurrent(sessionID: sessionID, generation: generation),
              sessions.transition(sessionID: sessionID, generation: generation, to: .reviewing),
              sessions.transition(sessionID: sessionID, generation: generation, to: .editing),
              let session = sessions.activeSession
        else { return }
        presentEditor(image: image, session: session, bannerMessage: bannerMessage, annotationPixelScale: annotationPixelScale)
    }

    private func presentEditor(image: CGImage, session: ActiveCaptureSession, bannerMessage: String? = nil, annotationPixelScale: CGFloat = 1) {
        let saveHandler: ((CGImage) async -> Bool)? = onSaveImageRequested == nil ? nil : { [weak self] image in
            await self?.deliver(image, session: session, save: true) ?? false
        }
        editorWindow = AnnotationEditorWindowController(
            image: image,
            onCancel: { [weak self] in self?.cancelCurrentSession() },
            onComplete: { [weak self] image in
                await self?.deliver(image, session: session, save: false) ?? false
            },
            onSave: saveHandler,
            onChangeCaptureSource: { [weak self] mode in
                Task { @MainActor [weak self] in await self?.changeCaptureSource(to: mode) }
            },
            bannerMessage: bannerMessage,
            annotationPixelScale: annotationPixelScale
        )
        editorWindow?.showWindow()
    }

    private func deliver(_ image: CGImage, session: ActiveCaptureSession, save: Bool) async -> Bool {
        guard sessions.isCurrent(sessionID: session.id, generation: session.generation) else { return false }
        guard let handler = save ? onSaveImageRequested : onImageReady else {
            showError(L10n.errorOutputTitle, detail: save ? L10n.errorSaveService : L10n.errorClipboardService)
            return false
        }
        guard await handler(image, session),
              sessions.isCurrent(sessionID: session.id, generation: session.generation)
        else {
            return false
        }
        finishCurrentSession(session)
        return true
    }

    private func finishCurrentSession(_ session: ActiveCaptureSession) {
        _ = sessions.finish(sessionID: session.id, generation: session.generation)
        closeSelectionWindows()
        frozenScreens.removeAll(keepingCapacity: false)
        editorWindow?.dismissAfterCompletion()
        editorWindow = nil
        focusedApplication?.restore()
        focusedApplication = nil
        notifySessionIdle()
    }

    private func notifySessionIdle() {
        // Completion callbacks close their editor/overlay after deliver returns.
        // Defer notification until that synchronous cleanup has unwound.
        Task { @MainActor [weak self] in
            guard let self, sessions.activeSession == nil else { return }
            onSessionActivityChange?(false)
        }
    }

    private func closeSelectionWindows() {
        selectionWindows.forEach { $0.close() }
        selectionWindows.removeAll(keepingCapacity: false)
    }

    private func showError(_ title: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.actionOk)
        alert.runModal()
    }
}
