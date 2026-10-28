import AppKit
import CoreGraphics
import ScreenCaptureKit

@MainActor
final class LongCaptureController {
    private let captureFlowController: CaptureFlowController
    private let streamService = ScreenCaptureStreamService()
    private let automaticScrollAccess = AutomaticScrollAccess()
    private let permissionAuthorization: CapturePermissionAuthorization
    private var display: CapturedDisplay?
    private var selectionPixelRect: CGRect?
    private var targetWindowFrame: CGRect?
    private var automaticTarget: AutomaticScrollTarget?
    private var session: ActiveCaptureSession?
    private var engine: LongCaptureEngine?
    private var controlPanel: LongCaptureControlPanel?
    private var mode: LongCaptureMode = .manual
    private var acceptingFrames = false
    private var intakeGeneration: UInt64 = 0
    private var cancelRequested = false
    private var partialReason: String?
    private var activityClock = CaptureActivityClock()
    private var startupWatchdog = CaptureStartupWatchdog()
    private var automaticTiming = AutomaticScrollTiming()
    private var stableFrameCount = 0
    private var noProgressSteps = 0
    private var activityTask: Task<Void, Never>?
    private var targetValidationTask: Task<Void, Never>?
    private var startTask: Task<Void, Never>?
    private var startTaskID: UUID?
    private var streamStopTask: Task<Void, Never>?
    private var streamStopTaskID: UUID?

    init(captureFlowController: CaptureFlowController, permissionAuthorization: CapturePermissionAuthorization = .shared) {
        self.captureFlowController = captureFlowController
        self.permissionAuthorization = permissionAuthorization
    }

    func begin(screen: FrozenScreen, pixelRect: CGRect, session: ActiveCaptureSession) {
        guard controlPanel == nil else { return }
        display = CapturedDisplay(screen)
        selectionPixelRect = pixelRect.integral
        targetWindowFrame = screen.windows.first(where: { $0.id == session.targetWindowID })?.frame
        self.session = session
        cancelRequested = false
        let selectedScreenRect = screen.transform.globalScreenRect(fromPixelRect: pixelRect) ?? screen.screenFrame
        automaticTarget = screen.windows.first(where: {
            $0.id == session.targetWindowID && $0.processIdentifier == session.targetProcessID
        }).flatMap { AutomaticScrollTarget(window: $0, selection: selectedScreenRect) }
        let panel = LongCaptureControlPanel(screenFrame: screen.screenFrame, selectedGlobalRect: selectedScreenRect)
        panel.onStartManual = { [weak self] in self?.queueStart(mode: .manual) }
        panel.onStartAutomatic = { [weak self] in self?.queueStart(mode: .automatic) }
        panel.onPause = { [weak self] in
            Task { @MainActor in await self?.pause(reason: L10n.longUserPaused, canResume: true) }
        }
        panel.onResume = { [weak self] in Task { @MainActor in await self?.resume() } }
        panel.onSwitchToManual = { [weak self] in self?.switchToManual() }
        panel.onFinish = { [weak self] in Task { @MainActor in await self?.finishAndPresent(banner: self?.partialReason) } }
        panel.onUsePartial = { [weak self] in Task { @MainActor in await self?.finishAndPresent(banner: self?.partialReason ?? L10n.longPartialContent) } }
        panel.onCancel = { [weak self] in self?.cancelFromPanel() }
        controlPanel = panel
        panel.present()
    }

    func cancel() {
        guard !cancelRequested else { return }
        cancelRequested = true
        acceptingFrames = false
        intakeGeneration &+= 1
        activityTask?.cancel()
        targetValidationTask?.cancel()
        activityTask = nil
        targetValidationTask = nil
        let panel = controlPanel
        controlPanel = nil
        panel?.orderOut(nil)
        let engine = engine
        let pendingStart = startTask
        pendingStart?.cancel()
        let previousStop = streamStopTask
        let stopTaskID = UUID()
        streamStopTaskID = stopTaskID
        clearSessionReferences()
        cancelRequested = true
        streamStopTask = Task { @MainActor in
            await previousStop?.value
            await pendingStart?.value
            await streamService.stop()
            engine?.cancel()
            panel?.close()
        }
    }

    private func cancelFromPanel() {
        cancel()
        captureFlowController.cancelCurrentSession()
    }

    private func start(mode selectedMode: LongCaptureMode) async {
        guard let display, let selectionPixelRect, let session,
              captureFlowController.isCurrent(sessionID: session.id, generation: session.generation)
        else { return }
        if selectedMode == .automatic, await !permissionAuthorization.ensureAccess(to: .automaticScroll) {
            controlPanel?.showChoices(message: CapturePermissionGuidance.automaticCaptureMessage)
            return
        }
        guard !Task.isCancelled, captureFlowController.isCurrent(sessionID: session.id, generation: session.generation) else { return }
        if selectedMode == .automatic, automaticTarget == nil {
            controlPanel?.showChoices(message: L10n.longTargetNotLocked)
            return
        }
        guard validFrontmostTarget(session) else {
            controlPanel?.showChoices(message: L10n.longReturnToTarget)
            return
        }
        guard captureFlowController.startLongCapture(sessionID: session.id, generation: session.generation) else { return }

        mode = selectedMode
        self.session = captureFlowController.sessions.activeSession ?? session
        engine = LongCaptureEngine(sessionID: session.id)
        partialReason = nil
        activityClock.start()
        startupWatchdog.beginAttempt(activeElapsed: activeElapsed)
        automaticTiming = AutomaticScrollTiming()
        stableFrameCount = 0
        noProgressSteps = 0
        acceptingFrames = true

        let expectedSessionID = session.id
        let expectedGeneration = session.generation
        guard let selectedGlobalRect = display.transform.globalScreenRect(fromPixelRect: selectionPixelRect),
              let sourceRect = display.transform.localTopLeftRect(fromGlobalScreenRect: selectedGlobalRect),
              sourceRect.width > 0, sourceRect.height > 0
        else {
            acceptingFrames = false
            engine?.cancel()
            engine = nil
            _ = captureFlowController.updateLongCaptureState(sessionID: session.id, generation: session.generation, state: .scrollReady)
            controlPanel?.showChoices(message: L10n.longInvalidSelection)
            return
        }
        do {
            try await streamService.start(
                display: display,
                sourceRect: sourceRect,
                outputWidth: Int(selectionPixelRect.width),
                outputHeight: Int(selectionPixelRect.height),
                onFrame: { [weak self] image in
                    await self?.consumeDisplayFrame(image, sessionID: expectedSessionID, generation: expectedGeneration)
                },
                onFailure: { [weak self] message in
                    guard let self else { return }
                    Task { @MainActor in
                        guard self.session?.id == expectedSessionID,
                              self.captureFlowController.isCurrent(sessionID: expectedSessionID, generation: expectedGeneration)
                        else { return }
                        guard CGPreflightScreenCaptureAccess() else {
                            _ = self.captureFlowController.cancelForScreenPermissionRevocation()
                            return
                        }
                        await self.stopWithPartial(reason: L10n.longStreamStopped(message))
                    }
                }
            )
            guard !Task.isCancelled, !cancelRequested,
                  controlPanel != nil,
                  self.session?.id == session.id,
                  captureFlowController.isCurrent(sessionID: session.id, generation: session.generation)
            else {
                await streamService.stop()
                return
            }
            controlPanel?.showRunning(mode: mode, height: engineHeight, elapsed: activeElapsed)
            startActivityTimer()
            startTargetValidation()
        } catch {
            guard !cancelRequested,
                  self.session?.id == session.id,
                  captureFlowController.isCurrent(sessionID: session.id, generation: session.generation)
            else { return }
            acceptingFrames = false
            engine?.cancel()
            engine = nil
            _ = captureFlowController.updateLongCaptureState(sessionID: session.id, generation: session.generation, state: .scrollReady)
            controlPanel?.showChoices(message: selectedMode == .automatic ? L10n.longStartFailureAutomatic(error.localizedDescription) : L10n.longStartFailureManual(error.localizedDescription))
        }
    }

    private func consumeDisplayFrame(_ displayImage: CGImage, sessionID: UUID, generation: UInt64) async {
        guard acceptingFrames, let rect = selectionPixelRect,
              let session, let engine,
              session.id == sessionID,
              session.generation == generation,
              captureFlowController.isCurrent(sessionID: session.id, generation: session.generation)
        else { return }
        guard validFrontmostTarget(session) else {
            await stopWithPartial(reason: L10n.longTargetSwitched)
            return
        }
        controlPanel?.updatePreview(image: displayImage)
        guard displayImage.width == Int(rect.width), displayImage.height == Int(rect.height) else {
            await stopWithPartial(reason: L10n.longAreaChanged)
            return
        }
        // A matching intermediate frame is not confirmation that a smooth wheel
        // animation has finished. Otherwise each intermediate append posts another
        // wheel event, accumulating enough movement to lose the required overlap.
        if mode == .automatic {
            let now = ProcessInfo.processInfo.systemUptime
            automaticTiming.receivedFrame(at: now)
            if !automaticTiming.canConsumeFrame(at: now) { return }
        }

        let expectedIntakeGeneration = intakeGeneration
        let update = await engine.consume(displayImage)
        guard acceptingFrames,
              intakeGeneration == expectedIntakeGeneration,
              self.session?.id == session.id,
              self.engine === engine,
              captureFlowController.isCurrent(sessionID: session.id, generation: session.generation)
        else { return }
        switch update {
        case .waitingForStableFrame:
            controlPanel?.showWaitingForStableFrame()
            controlPanel?.updateElapsed(mode: mode, height: engineHeight, elapsed: activeElapsed)
        case let .initialized(height):
            cachedEngineHeight = height
            controlPanel?.showRunning(mode: mode, height: engineHeight, elapsed: activeElapsed)
            if mode == .automatic { sendAutomaticScrollStep() }
        case let .unchanged(height):
            cachedEngineHeight = height
            controlPanel?.showRunning(mode: mode, height: engineHeight, elapsed: activeElapsed)
            if mode == .automatic { handleAutomaticNoProgress() }
            controlPanel?.updateElapsed(mode: mode, height: engineHeight, elapsed: activeElapsed)
        case let .appended(height, _):
            cachedEngineHeight = height
            noProgressSteps = 0
            stableFrameCount = 0
            controlPanel?.showRunning(mode: mode, height: engineHeight, elapsed: activeElapsed)
            if mode == .automatic { sendAutomaticScrollStep() }
        case let .paused(reason, height):
            cachedEngineHeight = height
            partialReason = reason
            await pause(reason: reason, canResume: height > 0)
        case let .capacityReached(height):
            cachedEngineHeight = height
            partialReason = L10n.longCapacityPartial
            await stopStreamOnly()
            _ = captureFlowController.updateLongCaptureState(sessionID: session.id, generation: session.generation, state: .partialReview)
            controlPanel?.showPartial(reason: partialReason ?? L10n.longCapacityReached, height: height)
        }
    }

    private func handleAutomaticNoProgress() {
        guard automaticTiming.canCheckNoProgress(at: ProcessInfo.processInfo.systemUptime)
        else { return }
        stableFrameCount += 1
        guard stableFrameCount >= 2 else { return }
        stableFrameCount = 0
        noProgressSteps += 1
        if noProgressSteps >= 3 {
            partialReason = L10n.longBottomUnconfirmed
            Task { @MainActor in await stopWithPartial(reason: partialReason ?? L10n.longNoMoreContent) }
        } else {
            sendAutomaticScrollStep()
        }
    }

    private func sendAutomaticScrollStep() {
        guard acceptingFrames, mode == .automatic else { return }
        guard automaticScrollAccess.hasAccess else {
            pauseForMissingControlAccess()
            return
        }
        guard let session, let display, let rect = selectionPixelRect, let automaticTarget,
              validFrontmostTarget(session)
        else {
            Task { @MainActor in await pause(reason: L10n.longAutoTargetChanged, canResume: engineHeight > 0) }
            return
        }
        let scale = CGFloat(display.pixelHeight) / max(display.screenFrame.height, 1)
        let logicalHeight = rect.height / max(scale, 0.1)
        guard let pixels = AutomaticScrollEvent.stepPixels(forViewportHeight: logicalHeight),
              let event = AutomaticScrollEvent.make(
                  pixels: pixels, target: automaticTarget,
                  primaryScreenHeight: NSScreen.screens.first?.frame.maxY ?? 0
              )
        else {
            Task { @MainActor in await pause(reason: L10n.longEventFailed, canResume: engineHeight > 0) }
            return
        }
        automaticTiming.requestStep()
        switch automaticScrollAccess.postIfAllowed(event, to: automaticTarget) {
        case .posted:
            break
        case .permissionDenied:
            pauseForMissingControlAccess()
            return
        case .targetUnavailable, .invalidEvent:
            Task { @MainActor in
                await pause(reason: L10n.longTargetDeliveryFailed, canResume: false)
            }
            return
        }
        automaticTiming.sentStep(at: ProcessInfo.processInfo.systemUptime)
        stableFrameCount = 0
        controlPanel?.showRunning(mode: mode, height: engineHeight, elapsed: activeElapsed)
    }

    private func pauseForMissingControlAccess() {
        Task { @MainActor in
            guard acceptingFrames else { return }
            await pause(reason: CapturePermissionGuidance.controlAccessLostMessage, canResume: engineHeight > 0)
        }
    }

    private func pause(reason: String, canResume: Bool) async {
        guard acceptingFrames else { return }
        acceptingFrames = false
        intakeGeneration &+= 1
        engine?.pauseIntake(reason: reason)
        activityClock.pause()
        partialReason = reason
        _ = captureFlowController.updateLongCaptureState(
            sessionID: session?.id ?? UUID(),
            generation: session?.generation ?? 0,
            state: .paused
        )
        controlPanel?.showPaused(reason: reason, height: engineHeight, canResume: canResume, canSwitchToManual: mode == .automatic)
    }

    private func resume() async {
        guard let session, captureFlowController.isCurrent(sessionID: session.id, generation: session.generation) else { return }
        if mode == .automatic, await !permissionAuthorization.ensureAccess(to: .automaticScroll) { return }
        guard !Task.isCancelled, !acceptingFrames,
              captureFlowController.isCurrent(sessionID: session.id, generation: session.generation)
        else { return }
        intakeGeneration &+= 1
        activityClock.resume()
        startupWatchdog.beginAttempt(activeElapsed: activeElapsed)
        automaticTiming = AutomaticScrollTiming()
        stableFrameCount = 0
        engine?.resume()
        acceptingFrames = true
        partialReason = nil
        _ = captureFlowController.updateLongCaptureState(sessionID: session.id, generation: session.generation, state: .capturing)
        controlPanel?.showRunning(mode: mode, height: engineHeight, elapsed: activeElapsed)
        if mode == .automatic { sendAutomaticScrollStep() }
    }

    private func switchToManual() {
        guard mode == .automatic, let session else { return }
        intakeGeneration &+= 1
        mode = .manual
        automaticTiming = AutomaticScrollTiming()
        engine?.resume(discardUnconfirmedCandidate: true)
        activityClock.resume()
        startupWatchdog.beginAttempt(activeElapsed: activeElapsed)
        acceptingFrames = true
        partialReason = nil
        _ = captureFlowController.updateLongCaptureState(sessionID: session.id, generation: session.generation, state: .capturing)
        controlPanel?.showRunning(mode: mode, height: engineHeight, elapsed: activeElapsed)
    }

    private func finishAndPresent(banner: String?) async {
        guard let session, captureFlowController.isCurrent(sessionID: session.id, generation: session.generation), let engine else { return }
        engine.pauseIntake(reason: L10n.longEnded)
        await stopStreamOnly()
        guard self.session?.id == session.id,
              self.engine === engine,
              captureFlowController.isCurrent(sessionID: session.id, generation: session.generation)
        else { return }
        do {
            let image = try engine.finish()
            controlPanel?.close()
            controlPanel = nil
            self.engine = nil
            captureFlowController.presentLongCaptureResult(
                image: image,
                sessionID: session.id,
                generation: session.generation,
                bannerMessage: banner,
                annotationPixelScale: display.map { CGFloat($0.pixelWidth) / $0.screenFrame.width } ?? 1
            )
            clearSessionReferences(keepEngine: false)
        } catch {
            controlPanel?.showFailure(error.localizedDescription, canUsePartial: engineHeight > 0)
        }
    }

    private func stopWithPartial(reason: String) async {
        guard let session, captureFlowController.isCurrent(sessionID: session.id, generation: session.generation) else { return }
        acceptingFrames = false
        partialReason = reason
        engine?.pauseIntake(reason: reason)
        await stopStreamOnly()
        guard self.session?.id == session.id,
              captureFlowController.isCurrent(sessionID: session.id, generation: session.generation)
        else { return }
        _ = captureFlowController.updateLongCaptureState(sessionID: session.id, generation: session.generation, state: .partialReview)
        guard engineHeight > 0 else {
            controlPanel?.showFailure(L10n.longNoPreview(reason), canUsePartial: false)
            return
        }
        controlPanel?.showPartial(reason: reason, height: engineHeight)
    }

    private func stopStreamOnly() async {
        acceptingFrames = false
        activityTask?.cancel()
        targetValidationTask?.cancel()
        activityTask = nil
        targetValidationTask = nil
        await streamService.stop()
    }

    private func queueStart(mode: LongCaptureMode) {
        guard controlPanel != nil else { return }
        if let startTask, !startTask.isCancelled {
            controlPanel?.showChoices(message: L10n.longStartPending)
            return
        }

        let previousStart = startTask
        let previousStop = streamStopTask
        let previousStopID = streamStopTaskID
        let taskID = UUID()
        startTaskID = taskID
        startTask = Task { @MainActor [weak self] in
            await previousStart?.value
            await previousStop?.value
            guard let self else { return }
            if streamStopTaskID == previousStopID {
                streamStopTask = nil
                streamStopTaskID = nil
            }
            guard !Task.isCancelled, startTaskID == taskID, controlPanel != nil else { return }
            await start(mode: mode)
            if startTaskID == taskID {
                startTask = nil
                startTaskID = nil
            }
        }
    }

    private func startActivityTimer() {
        activityTask?.cancel()
        activityTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                guard acceptingFrames else { continue }
                controlPanel?.updateElapsed(mode: mode, height: engineHeight, elapsed: activeElapsed)
                if activeElapsed >= 180 {
                    await stopWithPartial(reason: L10n.longTimeLimit)
                    return
                }
                if startupWatchdog.shouldPause(confirmedHeight: engineHeight, activeElapsed: activeElapsed) {
                    await pause(reason: L10n.longStartupTimeout, canResume: true)
                    continue
                }
                if mode == .automatic, automaticTiming.isStepPending {
                    sendAutomaticScrollStep()
                }
                if mode == .automatic,
                   automaticTiming.frameDeliveryTimedOut(at: ProcessInfo.processInfo.systemUptime)
                {
                    await pause(reason: L10n.longFrameTimeout, canResume: engineHeight > 0)
                }
            }
        }
    }

    private func startTargetValidation() {
        targetValidationTask?.cancel()
        targetValidationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, !Task.isCancelled else { return }
                guard let session, validFrontmostTarget(session) else {
                    await stopWithPartial(reason: L10n.longTargetClosed)
                    return
                }
                if let windowID = session.targetWindowID {
                    let isAvailable = await streamService.isWindowAvailable(windowID, expectedFrame: targetWindowFrame)
                    guard !Task.isCancelled,
                          self.session?.id == session.id,
                          captureFlowController.isCurrent(sessionID: session.id, generation: session.generation)
                    else { return }
                    if !isAvailable {
                        await stopWithPartial(reason: L10n.longWindowChanged)
                        return
                    }
                }
                guard let display,
                      NSScreen.screens.contains(where: { candidate in
                          guard let number = candidate.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
                          return number.uint32Value == display.displayID && candidate.frame == display.screenFrame
                      })
                else {
                    await stopWithPartial(reason: L10n.longDisplayChanged)
                    return
                }
            }
        }
    }

    private var engineHeight: Int {
        cachedEngineHeight
    }

    private var cachedEngineHeight = 0

    private var activeElapsed: TimeInterval {
        activityClock.elapsed()
    }

    private func validFrontmostTarget(_ session: ActiveCaptureSession) -> Bool {
        guard let targetPID = session.targetProcessID,
              let frontmost = NSWorkspace.shared.frontmostApplication,
              let target = NSRunningApplication(processIdentifier: targetPID),
              !target.isTerminated
        else { return false }
        if let automaticTarget, automaticTarget.window.processIdentifier == targetPID {
            return automaticTarget.allowsForeground(
                processID: frontmost.processIdentifier,
                controllerProcessID: ProcessInfo.processInfo.processIdentifier,
                controlPanelVisible: controlPanel?.isVisible == true
            )
        }
        return frontmost.processIdentifier == targetPID
    }

    private func clearSessionReferences(keepEngine: Bool = false) {
        display = nil
        selectionPixelRect = nil
        targetWindowFrame = nil
        automaticTarget = nil
        session = nil
        if !keepEngine { engine = nil }
        activityClock = CaptureActivityClock()
        startupWatchdog = CaptureStartupWatchdog()
        automaticTiming = AutomaticScrollTiming()
        stableFrameCount = 0
        noProgressSteps = 0
        cachedEngineHeight = 0
        if controlPanel == nil { cancelRequested = false }
    }
}
