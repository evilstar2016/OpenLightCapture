import AppKit

enum CaptureSessionState: String {
    case preparing
    case selecting
    case scrollReady
    case capturing
    case paused
    case reviewing
    case partialReview
    case editing
    case preparingOutput
    case publishing
    case cancelling
}

struct ActiveCaptureSession: Equatable {
    let id: UUID
    let generation: UInt64
    let startedAt: Date
    let mode: CaptureMode
    var targetProcessID: Int32?
    var targetWindowID: CGWindowID?
    var state: CaptureSessionState
}

@MainActor
final class CaptureSessionCoordinator {
    private(set) var activeSession: ActiveCaptureSession?
    private var nextGeneration: UInt64 = 0

    @discardableResult
    func begin(mode: CaptureMode, targetProcessID: Int32?) -> ActiveCaptureSession? {
        guard activeSession == nil else { return activeSession }
        nextGeneration &+= 1
        let session = ActiveCaptureSession(
            id: UUID(),
            generation: nextGeneration,
            startedAt: Date(),
            mode: mode,
            targetProcessID: targetProcessID,
            targetWindowID: nil,
            state: .preparing
        )
        activeSession = session
        return session
    }

    @discardableResult
    func transition(sessionID: UUID, generation: UInt64, to state: CaptureSessionState) -> Bool {
        guard var session = activeSession,
              session.id == sessionID,
              session.generation == generation,
              session.state != .cancelling
        else {
            return false
        }
        session.state = state
        activeSession = session
        return true
    }

    func isCurrent(sessionID: UUID, generation: UInt64) -> Bool {
        activeSession?.id == sessionID
            && activeSession?.generation == generation
            && activeSession?.state != .cancelling
    }

    func setTarget(sessionID: UUID, generation: UInt64, processID: Int32?, windowID: CGWindowID?) {
        guard var session = activeSession,
              session.id == sessionID,
              session.generation == generation
        else {
            return
        }
        session.targetProcessID = processID
        session.targetWindowID = windowID
        activeSession = session
    }

    func cancel(sessionID: UUID, generation: UInt64) -> Bool {
        guard transition(sessionID: sessionID, generation: generation, to: .cancelling) else { return false }
        activeSession = nil
        return true
    }

    func finish(sessionID: UUID, generation: UInt64) -> Bool {
        guard isCurrent(sessionID: sessionID, generation: generation) else { return false }
        activeSession = nil
        return true
    }
}

struct FocusContext {
    let processIdentifier: Int32?

    @MainActor
    static func capture(fallbackProcessID: Int32? = nil) -> FocusContext {
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return FocusContext(processIdentifier: frontmost == ProcessInfo.processInfo.processIdentifier ? fallbackProcessID : frontmost)
    }

    @MainActor
    func restore() {
        guard let processIdentifier,
              let application = NSRunningApplication(processIdentifier: processIdentifier),
              !application.isTerminated
        else {
            return
        }
        application.activate(options: [.activateAllWindows])
    }
}

struct CaptureActivityClock {
    private var startedAt: TimeInterval?
    private var pausedAt: TimeInterval?
    private var accumulatedPause: TimeInterval = 0

    mutating func start(at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        startedAt = time
        pausedAt = nil
        accumulatedPause = 0
    }

    mutating func pause(at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard startedAt != nil, pausedAt == nil else { return }
        pausedAt = time
    }

    mutating func resume(at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard let pausedAt else { return }
        accumulatedPause += max(0, time - pausedAt)
        self.pausedAt = nil
    }

    func elapsed(at time: TimeInterval = ProcessInfo.processInfo.systemUptime) -> TimeInterval {
        guard let startedAt else { return 0 }
        return max(0, (pausedAt ?? time) - startedAt - accumulatedPause)
    }
}

/// Scroll settling and a stopped frame stream are separate conditions. Idle
/// frames still prove that delivery is healthy while the target is stationary.
struct AutomaticScrollTiming {
    private var stepSentAt: TimeInterval?
    private var lastFrameReceivedAt: TimeInterval?
    private(set) var isStepPending = false

    mutating func requestStep() {
        isStepPending = true
    }

    mutating func sentStep(at time: TimeInterval) {
        isStepPending = false
        stepSentAt = time
        lastFrameReceivedAt = nil
    }

    mutating func receivedFrame(at time: TimeInterval) {
        lastFrameReceivedAt = time
    }

    func canConsumeFrame(at time: TimeInterval) -> Bool {
        guard !isStepPending else { return false }
        guard let stepSentAt else { return true }
        return time - stepSentAt >= 0.5
    }

    func canCheckNoProgress(at time: TimeInterval) -> Bool {
        guard !isStepPending else { return false }
        guard let stepSentAt else { return false }
        return time - stepSentAt >= 2
    }

    func frameDeliveryTimedOut(at time: TimeInterval) -> Bool {
        guard let stepSentAt else { return false }
        return time - max(stepSentAt, lastFrameReceivedAt ?? stepSentAt) >= 5
    }
}

struct CaptureStartupWatchdog {
    private var attemptStartedAtActiveTime: TimeInterval = 0

    mutating func beginAttempt(activeElapsed: TimeInterval) {
        attemptStartedAtActiveTime = activeElapsed
    }

    func shouldPause(confirmedHeight: Int, activeElapsed: TimeInterval) -> Bool {
        confirmedHeight == 0 && activeElapsed - attemptStartedAtActiveTime >= 5
    }
}
