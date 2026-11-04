import AppKit
import ScreenCaptureKit

@MainActor
protocol RecordingStream: AnyObject {
    var recordingDroppedFrames: Int { get }
    func startRecording(display: CapturedDisplay, sourceRect: CGRect, width: Int, height: Int,
                        options: RecordingOptions, onEvent: @escaping ScreenCaptureEventRelay.Handler,
                        onFailure: @escaping ScreenCaptureStreamService.FailureHandler) async throws
    func probeRecording() async throws -> CGImage
    func stop() async
}

extension ScreenCaptureStreamService: RecordingStream {}

@MainActor
final class RecordingController {
    private enum Phase { case ready, countdown, starting, recording, encoding, preview, output, ending }
    private struct Selection {
        let display: CapturedDisplay
        let sourceRect: CGRect
        let globalRect: CGRect
        let outputSize: CGSize
    }

    private let flow: CaptureFlowController
    private let output: OutputDeliveryService
    private let stream: any RecordingStream
    private let hasScreenPermission: @MainActor () async -> Bool
    private let workingRoot: URL?
    private var session: ActiveCaptureSession?
    private var selection: Selection?
    private var options = RecordingOptions()
    private var phase: Phase = .ready
    private var attemptID = UUID()
    private var cancellation = RecordingCancellation()
    private var store: GIFFrameStore?
    private var videoRecorder: VideoRecorder?
    private var recording: GIFRecording?
    private var result: GIFResult?
    private var videoResult: VideoResult?
    private var savedURL: URL?
    private var panel: RecordingControlPanel?
    private var border: RecordingRegionDimmer?
    private var preview: RecordingPreviewWindowController?
    private var work: Task<Void, Never>?
    private var finishTask: Task<Void, Never>?
    private var encoderTask: Task<GIFResult, Error>?
    private var ticker: Task<Void, Never>?
    private var probe: Task<Void, Never>?
    private var permissionCheck: Task<Void, Never>?
    private var lastPermissionCheckTime = 0.0
    private var outputTask: Task<Void, Never>?
    private var cleanupTask: Task<Void, Never>?
    private var firstFrameTime: TimeInterval?
    private var startingTime = 0.0
    private var lastHealthyTime = 0.0
    private var probeStarted: TimeInterval?
    private var consuming = 0
    private var drain: CheckedContinuation<Void, Never>?
    private var unstable = false
    private var reachedLimit = false

    init(flow: CaptureFlowController, output: OutputDeliveryService, options: RecordingOptions = RecordingOptions(),
         stream: any RecordingStream = ScreenCaptureStreamService(),
         hasScreenPermission: @escaping @MainActor () async -> Bool = { await CapturePermissionAuthorization.shared.hasAccess(to: .screenCapture) },
         workingRoot: URL? = nil)
    {
        self.flow = flow
        self.output = output
        self.options = options
        self.stream = stream
        self.hasScreenPermission = hasScreenPermission
        self.workingRoot = workingRoot
    }

    func begin(display: CapturedDisplay, pixelRect: CGRect, session: ActiveCaptureSession, startsImmediately: Bool = false) {
        guard self.session == nil,
              let global = display.transform.globalScreenRect(fromPixelRect: pixelRect),
              let source = display.transform.localTopLeftRect(fromGlobalScreenRect: global) else { return }
        let kind: RecordingKind = session.mode == .video ? .video : .gif
        if options.kind != kind { options = kind == .video ? .video : RecordingOptions() }
        let size = options.outputSize(width: Int(pixelRect.width), height: Int(pixelRect.height))
        self.session = session
        selection = Selection(display: display, sourceRect: source, globalRect: global, outputSize: size)
        phase = .ready
        showPreparation()
        if startsImmediately { start(showsCursor: options.showsCursor) }
    }

    private func showPreparation() {
        guard let selection else { return }
        panel?.dismiss()
        let panel = RecordingControlPanel(screenFrame: selection.display.screenFrame, selection: selection.globalRect,
                                          outputSize: selection.outputSize, showsCursor: options.showsCursor, kind: options.kind)
        panel.onStart = { [weak self] cursor in self?.start(showsCursor: cursor) }
        panel.onStop = { [weak self] in self?.stop() }
        panel.onDiscard = { [weak self] in self?.cancel() }
        panel.onChangeRegion = { [weak self] in self?.changeRegion() }
        panel.onCancelCountdown = { [weak self] in self?.resetAttempt() }
        self.panel = panel
        panel.showReady()
        setState(.recordingReady)
    }

    func present() {
        if phase == .encoding || phase == .preview || phase == .output { preview?.present() }
        else { panel?.orderFrontRegardless() }
    }

    /// Already captured content needs no screen permission and survives display changes.
    func environmentChanged() -> Bool {
        guard session != nil else { return false }
        if phase == .encoding || phase == .preview || phase == .output {
            preview?.pauseForSleep()
            preview?.reposition()
            return false
        }
        cancel(restoreFocus: false)
        return true
    }

    func start(showsCursor: Bool) {
        guard phase == .ready, let selection, session != nil else { return }
        options.showsCursor = showsCursor
        phase = .countdown
        setState(.countingDown)
        let id = attemptID
        let cancellation = cancellation
        let options = options
        let workingRoot = workingRoot
        // Mark the recorded region from the first countdown tick on, so the
        // selection keeps its own outline once the frozen overlay is gone.
        let border = RecordingRegionDimmer(screenFrame: selection.display.screenFrame, region: selection.globalRect)
        self.border = border
        border.orderFrontRegardless()
        border.startPulsing()
        flow.restoreTargetFocus()
        work = Task { [weak self] in
            guard let self else { return }
            do {
                for seconds in stride(from: options.countdownSeconds, to: 0, by: -1) {
                    try cancellation.check()
                    guard isCurrent(id) else { return }
                    panel?.showCountdown(seconds)
                    try await Task.sleep(for: .seconds(1))
                }
                try cancellation.check()
                phase = .starting
                setState(.startingRecording)
                startingTime = Self.now
                panel?.showCountdown(0)
                startTicker(id)
                if options.kind == .video {
                    let recorder = try await Task.detached(priority: .userInitiated) {
                        try VideoRecorder(width: Int(selection.outputSize.width), height: Int(selection.outputSize.height), options: options, root: workingRoot ?? VideoRecorder.defaultRoot)
                    }.value
                    guard isCurrent(id) else { await recorder.cleanup(); return }
                    videoRecorder = recorder
                } else {
                    let store = try await Task.detached(priority: .userInitiated) {
                        try GIFFrameStore(width: Int(selection.outputSize.width), height: Int(selection.outputSize.height), options: options, root: workingRoot ?? GIFFrameStore.defaultRoot)
                    }.value
                    guard isCurrent(id) else { await store.cleanup(); return }
                    self.store = store
                }
                try await stream.startRecording(display: selection.display, sourceRect: selection.sourceRect,
                                                width: Int(selection.outputSize.width), height: Int(selection.outputSize.height), options: options,
                                                onEvent: { [weak self] event in await self?.consume(event, attempt: id) },
                                                onFailure: { [weak self] message in self?.fail(message, attempt: id) })
                guard isCurrent(id), phase == .starting || phase == .recording else { await stream.stop(); return }
                border.stopPulsing()
            } catch is CancellationError {
                // The owner of cancellation waits for this task before removing material.
            } catch {
                fail(error.localizedDescription, attempt: id)
            }
        }
    }

    private func consume(_ event: CaptureFrameEvent, attempt id: UUID) async {
        guard isCurrent(id), phase == .starting || phase == .recording else { return }
        switch event.status {
        case .complete, .started:
            guard let image = event.image else { return }
            if let firstFrameTime, event.hostTime > firstFrameTime + options.maxDuration { return }
            lastHealthyTime = Self.now
            consuming += 1
            defer {
                consuming -= 1
                if consuming == 0 { drain?.resume(); drain = nil }
            }
            do {
                let accepted: Bool
                if let videoRecorder {
                    accepted = try await videoRecorder.append(image, at: event.hostTime, cancellation: cancellation)
                } else if let store {
                    accepted = try await store.append(image, at: event.hostTime, cancellation: cancellation)
                } else { return }
                guard isCurrent(id) else { return }
                if accepted, firstFrameTime == nil {
                    firstFrameTime = event.hostTime
                    phase = .recording
                    setState(.recording)
                    panel?.showRecording(0)
                }
            } catch is CancellationError {} catch { fail(error.localizedDescription, attempt: id) }
        case .idle:
            if firstFrameTime != nil { lastHealthyTime = Self.now }
        case .blank, .suspended, .stopped:
            fail(L10n.gifStreamStopped, attempt: id)
        @unknown default:
            fail(L10n.gifStreamStopped, attempt: id)
        }
    }

    private func startTicker(_ id: UUID) {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                guard let self, isCurrent(id) else { return }
                if phase == .starting {
                    if Self.now - startingTime >= 5 { fail(L10n.gifNoFrames, attempt: id); return }
                } else if phase == .recording, let start = firstFrameTime {
                    let elapsed = max(0, Self.now - start)
                    panel?.showRecording(min(Int(options.maxDuration), Int(elapsed)))
                    if elapsed >= options.maxDuration { reachedLimit = true; stop(); return }
                    if permissionCheck == nil, Self.now - lastPermissionCheckTime >= 1 {
                        lastPermissionCheckTime = Self.now
                        permissionCheck = Task { [weak self] in
                            guard let self else { return }
                            defer { permissionCheck = nil }
                            let allowed = await hasScreenPermission()
                            if isCurrent(id), !Task.isCancelled, !allowed { fail(L10n.gifStreamStopped, attempt: id) }
                        }
                    }
                    if let probeStarted, Self.now - probeStarted >= 1 {
                        fail(L10n.gifStreamStopped, attempt: id)
                        return
                    }
                    if probe == nil, Self.now - lastHealthyTime >= 5 { startProbe(id) }
                } else { return }
            }
        }
    }

    private func startProbe(_ id: UUID) {
        probeStarted = Self.now
        probe = Task { [weak self] in
            guard let self else { return }
            defer { self.probe = nil; self.probeStarted = nil }
            do {
                let image = try await stream.probeRecording()
                guard isCurrent(id), !Task.isCancelled else { return }
                unstable = true
                await self.consume(CaptureFrameEvent(image: image, status: .complete, hostTime: Self.now), attempt: id)
            } catch {
                if isCurrent(id), !Task.isCancelled { fail(error.localizedDescription, attempt: id) }
            }
        }
    }

    func stop() {
        guard phase == .recording, store != nil || videoRecorder != nil else { return }
        let stopTime = Self.now
        let id = attemptID
        phase = .encoding
        setState(.encoding)
        ticker?.cancel()
        probe?.cancel()
        panel?.showEnding()
        border?.close()
        border = nil
        finishTask = Task { [weak self] in
            guard let self else { return }
            await work?.value
            await stream.stop()
            await waitForFrames()
            guard isCurrent(id) else { return }
            unstable = unstable || stream.recordingDroppedFrames > 0
            do {
                panel?.dismiss()
                panel = nil
                if let videoRecorder {
                    let dropped = await videoRecorder.droppedFrames
                    unstable = unstable || dropped > 0
                    let preview = makePreview()
                    preview.showFinishingVideo()
                    let result = try await videoRecorder.finish(at: stopTime, cancellation: cancellation)
                    guard isCurrent(id) else { return }
                    videoResult = result
                    phase = .preview
                    setState(.recordingPreviewing)
                    let text = [reachedLimit ? L10n.videoLimitReached : nil, unstable ? L10n.gifUnstable : nil].compactMap(\.self).joined(separator: "\n")
                    preview.showVideo(result, text: text)
                } else if let store {
                    let recording = try await store.seal(at: stopTime)
                    guard isCurrent(id) else { return }
                    self.recording = recording
                    await generate(recording, attempt: id)
                }
            } catch is CancellationError {} catch { fail(error.localizedDescription, attempt: id) }
        }
    }

    private func makePreview() -> RecordingPreviewWindowController {
        if let preview { return preview }
        let preview = RecordingPreviewWindowController()
        preview.onDiscard = { [weak self] in self?.cancel() }
        preview.onRerecord = { [weak self] in self?.resetAttempt() }
        preview.onCopy = { [weak self] save in self?.deliver(save: save) }
        preview.onRetry = { [weak self] in self?.retryEncoding() }
        self.preview = preview
        return preview
    }

    private func generate(_ recording: GIFRecording, attempt id: UUID) async {
        let preview = makePreview()
        preview.show(source: .raw(recording), text: L10n.gifRawPreview, canPublish: false)
        preview.setBusy(true, text: L10n.gifEncoding, allowDiscard: true)
        let cancellation = cancellation
        let task = Task.detached(priority: .userInitiated) { try GIFEncoder.encode(recording, cancellation: cancellation) }
        encoderTask = task
        do {
            let result = try await task.value
            guard isCurrent(id) else { return }
            self.result = result
            await preview.stopPlaybackAndWait()
            await store?.removeRawFrames()
            self.recording = nil
            phase = .preview
            setState(.recordingPreviewing)
            let text = [reachedLimit ? L10n.gifLimitReached : nil, unstable ? L10n.gifUnstable : nil].compactMap(\.self).joined(separator: "\n")
            preview.show(source: .gif(result), text: text, canPublish: result.canPublish)
        } catch is CancellationError {} catch {
            guard isCurrent(id) else { return }
            phase = .preview
            setState(.recordingPreviewing)
            let canRetry = (error as? GIFError) != .tooLarge
            preview.show(source: .raw(recording), text: "\(L10n.gifRawPreview)\n\(error.localizedDescription)", canPublish: false, canRetry: canRetry)
        }
    }

    private func retryEncoding() {
        guard phase == .preview, let recording, result == nil else { return }
        phase = .encoding
        setState(.encoding)
        let id = attemptID
        finishTask = Task { [weak self] in await self?.generate(recording, attempt: id) }
    }

    private func deliver(save: Bool) {
        if options.kind == .video { saveVideo(); return }
        guard phase == .preview, let result, let session else { return }
        let id = attemptID
        phase = .output
        setState(.preparingOutput)
        preview?.setBusy(true, text: save ? L10n.gifSaveCopy : L10n.gifCopy)
        outputTask = Task { [weak self] in
            guard let self else { return }
            let outcome = await output.deliverGIF(result, startedAt: session.startedAt, save: save,
                                                  previouslySavedURL: savedURL, parentWindow: preview?.window,
                                                  isCurrent: { self.isCurrent(id) && self.phase == .output })
            guard isCurrent(id) else { return }
            switch outcome {
            case .completed:
                phase = .ending
                await retireAttempt()
                clear()
                flow.finishRecordingSession(session)
            case .cancelled:
                phase = .preview
                setState(.recordingPreviewing)
                preview?.showFailure("", canPublish: result.canPublish)
            case let .failed(savedURL, message):
                self.savedURL = savedURL
                phase = .preview
                setState(.recordingPreviewing)
                preview?.showFailure(message, canPublish: result.canPublish)
            }
        }
    }

    private func saveVideo() {
        guard phase == .preview, let result = videoResult, let session else { return }
        let id = attemptID
        phase = .output
        setState(.preparingOutput)
        preview?.setBusy(true, text: L10n.videoSaving)
        outputTask = Task { [weak self] in
            guard let self else { return }
            let outcome = await output.saveVideo(result, startedAt: session.startedAt, parentWindow: preview?.window,
                                                 isCurrent: { self.isCurrent(id) && self.phase == .output })
            guard isCurrent(id) else { return }
            switch outcome {
            case .saved:
                phase = .ending
                await retireAttempt()
                clear()
                flow.finishRecordingSession(session)
            case .cancelled:
                phase = .preview
                setState(.recordingPreviewing)
                preview?.showFailure("", canPublish: true)
            case let .failed(message):
                phase = .preview
                setState(.recordingPreviewing)
                preview?.showFailure(message, canPublish: true)
            }
        }
    }

    func resetAttempt() {
        guard phase == .preview || phase == .countdown || phase == .starting else { return }
        phase = .ending
        panel?.showEnding()
        cleanupTask = Task { [weak self] in
            guard let self else { return }
            await retireAttempt()
            guard let session, flow.isCurrent(sessionID: session.id, generation: session.generation) else { return }
            newAttempt()
            phase = .ready
            showPreparation()
        }
    }

    private func changeRegion() {
        guard phase == .ready, let session else { return }
        phase = .ending
        cleanupTask = Task { [weak self] in
            guard let self else { return }
            await retireAttempt()
            clear()
            await flow.reselectRecording(session)
        }
    }

    func cancel(restoreFocus: Bool = true) {
        guard let session else { return }
        if phase == .ending {
            guard flow.sessions.activeSession?.state != .cancelling else { return }
            setState(.cancelling)
            let previous = cleanupTask
            cleanupTask = Task { [weak self] in
                await previous?.value
                guard let self, self.session?.id == session.id else { return }
                await retireAttempt()
                clear()
                flow.finishRecordingSession(session, restoreFocus: restoreFocus)
            }
            return
        }
        phase = .ending
        setState(.cancelling)
        cancellation.cancel()
        panel?.showEnding()
        preview?.setBusy(true, text: L10n.gifEnding)
        cleanupTask = Task { [weak self] in
            guard let self else { return }
            await retireAttempt()
            clear()
            flow.finishRecordingSession(session, restoreFocus: restoreFocus)
        }
    }

    private func fail(_ message: String, attempt id: UUID) {
        guard isCurrent(id), phase != .ending else { return }
        let errorTitle = options.kind.title
        cancel(restoreFocus: false)
        let cleanup = cleanupTask
        Task { @MainActor [weak self] in
            await cleanup?.value
            guard let self else { return }
            if await !hasScreenPermission() { flow.onScreenPermissionRevocation() }
            else {
                let alert = NSAlert()
                alert.messageText = errorTitle
                alert.informativeText = message
                alert.addButton(withTitle: L10n.actionOk)
                _ = await PermissionAlertPresenter.shared.present(alert)
            }
        }
    }

    private func retireAttempt() async {
        cancellation.cancel()
        work?.cancel()
        ticker?.cancel()
        probe?.cancel()
        permissionCheck?.cancel()
        await preview?.stopPlaybackAndWait()
        preview?.setBusy(true, text: L10n.gifEnding)
        panel?.showEnding()
        border?.close()
        border = nil
        await videoRecorder?.cancelWriting()
        await work?.value
        await stream.stop()
        await waitForFrames()
        await finishTask?.value
        if let encoderTask { _ = await encoderTask.result }
        // A screenshot probe cannot be force-cancelled; its late callback is guarded by the token.
        await probe?.value
        await permissionCheck?.value
        await store?.cleanup()
        store = nil
        await videoRecorder?.cleanup()
        videoRecorder = nil
        preview?.dismiss()
        preview = nil
        panel?.dismiss()
        panel = nil
    }

    private func newAttempt() {
        attemptID = UUID()
        cancellation = RecordingCancellation()
        work = nil
        finishTask = nil
        encoderTask = nil
        ticker = nil
        probe = nil
        permissionCheck = nil
        lastPermissionCheckTime = 0
        firstFrameTime = nil
        probeStarted = nil
        recording = nil
        result = nil
        videoResult = nil
        savedURL = nil
        unstable = false
        reachedLimit = false
    }

    private func clear() {
        session = nil
        selection = nil
        newAttempt()
    }

    private func waitForFrames() async {
        if consuming > 0 { await withCheckedContinuation { drain = $0 } }
    }

    private func isCurrent(_ id: UUID) -> Bool {
        guard let session else { return false }
        return id == attemptID && !cancellation.isCancelled && flow.isCurrent(sessionID: session.id, generation: session.generation)
    }

    private func setState(_ state: CaptureSessionState) {
        guard let session else { return }
        _ = flow.sessions.transition(sessionID: session.id, generation: session.generation, to: state)
    }

    private static var now: Double {
        CMClockGetTime(CMClockGetHostTimeClock()).seconds
    }
}
