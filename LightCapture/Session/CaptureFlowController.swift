import AppKit
import CoreGraphics
import os

@MainActor
final class CaptureFlowController {
    private let watermarkStore: WatermarkTemplateStore
    private(set) var watermarkContext: CaptureWatermarkContext?

    init(watermarkStore: WatermarkTemplateStore = .shared) {
        self.watermarkStore = watermarkStore
    }

    func prepareWatermarks(for session: ActiveCaptureSession) {
        guard sessions.isCurrent(sessionID: session.id, generation: session.generation) else { return }
        let library = watermarkStore.snapshot()
        watermarkContext = CaptureWatermarkContext(sessionID: session.id, generation: session.generation, library: library, selection: library.defaultSelection)
    }

    private func watermarkLibrary(for session: ActiveCaptureSession) -> WatermarkLibrarySnapshot {
        guard let context = watermarkContext, context.sessionID == session.id, context.generation == session.generation else { return .empty }
        return context.library
    }

    var onSessionActivityChange: ((Bool) -> Void)?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "io.github.evilstar2016.openlightcapture", category: "CaptureFlow")
    let sessions = CaptureSessionCoordinator()
    var lastExternalProcessID: Int32?

    private let captureService = ScreenCaptureService()
    private var focusedApplication: FocusContext?
    private var frozenScreens: [FrozenScreen] = []
    private var selectionWindows: [SelectionOverlayWindow] = []
    private var editorWindow: AnnotationEditorWindowController?
    private(set) var ocrController: OCRSessionController?
    var textRecognizer: OCRSessionController.Recognizer = TextRecognitionService.recognize
    private weak var ocrSourceWindow: NSWindow?

    var onLongCaptureRequested: ((FrozenScreen, CGRect, ActiveCaptureSession, LongCaptureRegion) -> Void)?
    var onRecordingRequested: ((CapturedDisplay, CGRect, ActiveCaptureSession, Bool) -> Void)?
    var onRecordingPresent: (() -> Void)?
    var onRecordingCancel: (() -> Void)?
    var onRecordingEnvironmentChange: (() -> Bool)?
    var onImageReady: ((CGImage, ActiveCaptureSession) async -> Bool)?
    var onSaveImageRequested: ((CGImage, ActiveCaptureSession) async -> Bool)?
    var onTextReady: ((String, ActiveCaptureSession) throws -> Void)?
    var onSessionCancelled: (() -> Void)?
    var onScreenPermissionRevocation: () -> Void = {
        Task { @MainActor in _ = await CapturePermissionAuthorization.shared.ensureAccess(to: .screenCapture) }
    }

    var outputPanelParent: NSWindow? {
        ocrController?.windowController.window ?? editorWindow?.window ?? selectionWindows.first(where: { $0.isKeyWindow }) ?? selectionWindows.first(where: { $0.isVisible })
    }

    func begin(mode: CaptureMode) async {
        logger.info("Capture begin requested: \(String(describing: mode), privacy: .public)")
        if let ocrController {
            ocrController.windowController.bringForward()
            return
        }
        if let current = sessions.activeSession {
            logger.info("Capture request reused active session in state \(String(describing: current.state), privacy: .public)")
            if current.mode.isRecording, current.state != .selecting, current.state != .preparing {
                onRecordingPresent?()
            } else if current.state == .editing {
                editorWindow?.showWindow()
            } else {
                selectionWindows.forEach { $0.orderFrontRegardless() }
            }
            return
        }

        focusedApplication = FocusContext.capture(fallbackProcessID: lastExternalProcessID)
        guard let session = sessions.begin(mode: mode, targetProcessID: focusedApplication?.processIdentifier) else { return }
        prepareWatermarks(for: session)
        onSessionActivityChange?(true)
        logger.info("Capture session started: \(session.id.uuidString, privacy: .public)")

        await captureDisplays(for: session)
    }

    func cancelCurrentSession(restoreFocus: Bool = true) {
        guard let session = sessions.activeSession else { return }
        if session.mode.isRecording, let onRecordingCancel, session.state != .selecting, session.state != .preparing {
            onRecordingCancel()
            return
        }
        _ = sessions.cancel(sessionID: session.id, generation: session.generation)
        closeOCR()
        watermarkContext = nil
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
        if sessions.activeSession?.mode.isRecording == true, sessions.activeSession?.state != .selecting,
           sessions.activeSession?.state != .preparing, let onRecordingEnvironmentChange
        {
            return onRecordingEnvironmentChange()
        }
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

    /// Cancels a capture that has not produced content yet when the visible
    /// Space or Mission Control page switches, so the next hotkey press starts
    /// a fresh capture instead of reusing a selection the user can no longer
    /// see. Editor and recording states manage their own lifecycle.
    @discardableResult
    func cancelForSpaceChange() -> Bool {
        guard let session = sessions.activeSession else { return false }
        guard session.state == .selecting || session.state == .preparing else { return false }
        cancelCurrentSession(restoreFocus: false)
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
        guard ocrController == nil, let previousSession = sessions.activeSession, previousSession.state == .editing else { return }
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
        prepareWatermarks(for: session)
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
            let window = SelectionOverlayWindow(screen: screen, initialMode: session.mode, watermarkLibrary: watermarkLibrary(for: session))
            window.onCancel = { [weak self] in self?.cancelCurrentSession() }
            window.onOutput = { [weak self] image, rect, selectedWindow, save in
                await self?.publishInlineSelection(image: image, on: screen, localRect: rect, selectedWindow: selectedWindow, save: save) ?? false
            }
            window.onLongCapture = { [weak self, weak window] rect, selectedWindow, region in
                guard let self, let window, sessions.isCurrent(sessionID: session.id, generation: session.generation) else { return }
                watermarkContext?.selection = window.watermarkSelection
                completeSelection(on: screen, localRect: rect, selectedWindow: selectedWindow, useLongCapture: true, region: region)
            }
            window.onGIFCapture = { [weak self] rect, selectedWindow in
                self?.beginRecordingSelection(screen: screen, localRect: rect, selectedWindow: selectedWindow, mode: .gif)
            }
            window.onVideoCapture = { [weak self] rect, selectedWindow in
                self?.beginRecordingSelection(screen: screen, localRect: rect, selectedWindow: selectedWindow, mode: .video)
            }
            window.onRecognizeText = { [weak self, weak window] snapshot in
                guard let self, let window else { return }
                presentOCR(snapshot: snapshot, sourceWindow: window) { [weak window] in
                    window?.isCurrentRevision(snapshot.revision) == true
                }
            }
            return window
        }
        NSApp.activate(ignoringOtherApps: true)
        selectionWindows.forEach { $0.present() }
        let overlayCount = selectionWindows.count
        logger.info("Selection overlays presented: \(overlayCount, privacy: .public)")
    }

    private func beginRecordingSelection(screen: FrozenScreen, localRect: CGRect, selectedWindow: CapturedWindow?, mode: CaptureMode) {
        guard let session = sessions.activeSession, session.state == .selecting,
              let global = screen.transform.globalScreenRect(fromLocalTopLeftRect: localRect),
              let pixels = screen.transform.pixelRect(fromGlobalScreenRect: global), pixels.width >= 1, pixels.height >= 1
        else { return }
        if mode == .video, RecordingOptions.video.outputSize(width: Int(pixels.width), height: Int(pixels.height)) == .zero {
            showError(L10n.videoTitle, detail: L10n.videoSmallRegion)
            return
        }
        guard sessions.changeMode(sessionID: session.id, generation: session.generation, to: mode) else { return }
        if let target = selectedWindow ?? CapturedWindow.target(for: global, in: screen.windows) {
            sessions.setTarget(sessionID: session.id, generation: session.generation, processID: target.processIdentifier, windowID: target.id)
        }
        let display = CapturedDisplay(screen)
        closeSelectionWindows()
        frozenScreens.removeAll()
        _ = sessions.transition(sessionID: session.id, generation: session.generation, to: .recordingReady)
        guard let current = sessions.activeSession else { return }
        // Confirming a region through the record buttons is an explicit intent:
        // start the countdown right away instead of parking on the ready panel.
        onRecordingRequested?(display, pixels, current, true)
    }

    func restoreTargetFocus() {
        if let pid = sessions.activeSession?.targetProcessID,
           let target = NSRunningApplication(processIdentifier: pid), !target.isTerminated
        {
            target.activate(options: [.activateAllWindows])
        } else { focusedApplication?.restore() }
    }

    func reselectRecording(_ session: ActiveCaptureSession) async {
        guard sessions.isCurrent(sessionID: session.id, generation: session.generation) else { return }
        _ = sessions.transition(sessionID: session.id, generation: session.generation, to: .preparing)
        await captureDisplays(for: session)
    }

    func finishRecordingSession(_ session: ActiveCaptureSession, restoreFocus: Bool = true) {
        guard sessions.activeSession?.id == session.id, sessions.activeSession?.generation == session.generation else { return }
        if sessions.activeSession?.state == .cancelling {
            sessions.completeCancellation(sessionID: session.id, generation: session.generation)
        }
        finishCurrentSession(session, restoreFocus: restoreFocus)
    }

    func publishInlineSelection(image: CGImage, on screen: FrozenScreen, localRect: CGRect, selectedWindow: CapturedWindow?, save: Bool) async -> Bool {
        guard ocrController == nil, let session = sessions.activeSession, session.state == .selecting,
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
        openEditor: Bool = false,
        region: LongCaptureRegion = LongCaptureRegion()
    ) {
        guard let session = sessions.activeSession, session.state == .selecting,
              let globalRect = screen.transform.globalScreenRect(fromLocalTopLeftRect: localRect),
              let pixelRect = screen.transform.pixelRect(fromGlobalScreenRect: globalRect),
              pixelRect.width >= 1,
              pixelRect.height >= 1,
              region.bodyRect(width: Int(pixelRect.width), height: Int(pixelRect.height)) != nil
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
                onLongCaptureRequested(screen, pixelRect, updatedSession, region)
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
        let snapshot = AnnotationDocument(image: croppedImage, watermark: watermarkContext?.selection).renderSnapshot()
        Task { @MainActor [weak self] in
            guard let self else { return }
            var banner = L10n.errorCopyRetained
            do {
                let output = try await AnnotationRenderer.render(snapshot)
                if await deliver(output, session: session, save: false) { return }
            } catch {
                banner = error.localizedDescription
            }
            guard sessions.isCurrent(sessionID: session.id, generation: session.generation),
                  sessions.transition(sessionID: session.id, generation: session.generation, to: .editing)
            else { return }
            presentEditor(image: croppedImage, session: session, bannerMessage: banner, annotationPixelScale: CGFloat(screen.image.width) / screen.screenFrame.width)
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
            annotationPixelScale: annotationPixelScale,
            watermarkLibrary: watermarkLibrary(for: session),
            watermark: watermarkContext?.selection
        )
        editorWindow?.onRecognizeText = { [weak self] snapshot in
            guard let self, let editorWindow, let source = editorWindow.window else { return }
            presentOCR(snapshot: snapshot, sourceWindow: source) { [weak editorWindow] in
                editorWindow?.isCurrentRevision(snapshot.revision) == true
            }
        }
        editorWindow?.showWindow()
    }

    private func deliver(_ image: CGImage, session: ActiveCaptureSession, save: Bool) async -> Bool {
        guard ocrController == nil, sessions.isCurrent(sessionID: session.id, generation: session.generation) else { return false }
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

    private func finishCurrentSession(_ session: ActiveCaptureSession, restoreFocus: Bool = true) {
        closeOCR()
        _ = sessions.finish(sessionID: session.id, generation: session.generation)
        watermarkContext = nil
        closeSelectionWindows()
        frozenScreens.removeAll(keepingCapacity: false)
        editorWindow?.dismissAfterCompletion()
        editorWindow = nil
        if restoreFocus { focusedApplication?.restore() }
        focusedApplication = nil
        notifySessionIdle()
    }

    private func presentOCR(snapshot: AnnotationRenderSnapshot, sourceWindow: NSWindow, sourceIsCurrent: @escaping () -> Bool) {
        guard ocrController == nil, let session = sessions.activeSession,
              session.state == .selecting || session.state == .editing else { return }
        let isCurrent = { [weak self] in
            self?.sessions.isCurrent(sessionID: session.id, generation: session.generation) == true && sourceIsCurrent()
        }
        guard isCurrent() else { return }
        ocrSourceWindow = sourceWindow
        let screen = sourceWindow.screen
        selectionWindows.forEach { $0.setOCRActive(true); $0.orderOut(nil) }
        editorWindow?.setOCRActive(true)
        editorWindow?.window?.orderOut(nil)
        let controller = OCRSessionController(snapshot: snapshot, recognize: textRecognizer, isCurrent: isCurrent, onReturn: { [weak self] in
            self?.returnFromOCR(session: session)
        }, onCopy: { [weak self] text in
            guard let self, isCurrent(), let onTextReady else { throw CancellationError() }
            try onTextReady(text, session)
            guard isCurrent() else { throw CancellationError() }
            finishCurrentSession(session)
        })
        ocrController = controller
        controller.present(on: screen)
    }

    private func returnFromOCR(session: ActiveCaptureSession) {
        let source = ocrSourceWindow
        closeOCR()
        guard sessions.isCurrent(sessionID: session.id, generation: session.generation) else { return }
        selectionWindows.forEach { $0.setOCRActive(false); $0.orderFrontRegardless() }
        if let overlay = source as? SelectionOverlayWindow {
            overlay.present()
        } else {
            editorWindow?.resumeAfterOCR()
        }
    }

    private func closeOCR() {
        ocrController?.dismiss()
        ocrController = nil
        ocrSourceWindow = nil
    }

    private func notifySessionIdle() {
        // Completion callbacks close their editor/overlay after deliver returns.
        // Defer notification until that synchronous cleanup has unwound.
        Task { @MainActor [weak self] in
            guard let self, sessions.activeSession == nil else { return }
            watermarkContext = nil
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
