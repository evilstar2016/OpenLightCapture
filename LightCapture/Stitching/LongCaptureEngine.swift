import CoreGraphics
import Foundation

enum LongCaptureEngineUpdate: Equatable {
    case waitingForStableFrame
    case initialized(height: Int)
    case unchanged(height: Int)
    case appended(height: Int, addedPixels: Int)
    case paused(reason: String, height: Int)
    case capacityReached(height: Int)
}

@MainActor
final class LongCaptureEngine {
    typealias Matcher = @Sendable (CGImage, CGImage) async -> OverlapMatch
    private let sessionID: UUID
    private let matcher: Matcher
    private let now: () -> TimeInterval
    private var store: TileStore?
    private var baseline: CGImage?
    private var startupCandidate: CGImage?
    private var nextSequence: UInt64 = 1
    private var operationGeneration: UInt64 = 0
    private var mismatchStartedAt: TimeInterval?
    private var mismatchFrames = 0
    private(set) var isPaused = false
    private(set) var isComplete = false
    private(set) var pauseReason: String?

    init(sessionID: UUID, workspaceRootURL: URL? = nil, matcher: @escaping Matcher = OverlapMatcher.match, now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.sessionID = sessionID
        self.workspaceRootURL = workspaceRootURL
        self.matcher = matcher
        self.now = now
    }

    private let workspaceRootURL: URL?

    func consume(_ image: CGImage) async -> LongCaptureEngineUpdate {
        guard !isPaused, !isComplete else {
            return .paused(reason: pauseReason ?? L10n.stitchIntakeStopped, height: store?.totalHeight ?? 0)
        }
        operationGeneration &+= 1
        let generation = operationGeneration
        guard CaptureImageLimits.contains(width: image.width, height: image.height)
        else {
            return pause(L10n.stitchInvalidImage)
        }

        guard let baseline else {
            guard let startupCandidate else {
                startupCandidate = image
                return .waitingForStableFrame
            }
            let match = await matcher(startupCandidate, image)
            guard isCurrentOperation(generation) else { return pausedUpdate() }
            switch match {
            case .unchanged:
                await initialize(with: image, generation: generation)
                guard isCurrentOperation(generation) else { return pausedUpdate() }
                return store.map { .initialized(height: $0.totalHeight) } ?? pause(L10n.stitchWorkspaceFailed)
            case let .accepted(displacement, drift, replacement):
                guard drift == 0, displacement > 0, displacement <= image.height * 3 / 4,
                      replacement >= 0, replacement <= min(96, (image.height - displacement) / 4)
                else {
                    return pause(L10n.stitchInitialAlignment)
                }
                guard let currentPixels = await RGBAFrame.make(image: image) else {
                    guard isCurrentOperation(generation) else { return pausedUpdate() }
                    self.startupCandidate = image
                    return .waitingForStableFrame
                }
                guard isCurrentOperation(generation) else { return pausedUpdate() }
                await initialize(with: startupCandidate, generation: generation)
                guard isCurrentOperation(generation) else { return pausedUpdate() }
                do {
                    let appended = try store?.appendBottomRows(
                        from: currentPixels,
                        startY: currentPixels.height - displacement - replacement,
                        count: displacement + replacement,
                        sequence: 1,
                        replacingBottomRows: replacement
                    ) ?? false
                    guard appended else { return pause(L10n.stitchInitialTile) }
                    baseline = image
                    self.startupCandidate = nil
                    nextSequence = 2
                    return .appended(height: store?.totalHeight ?? image.height, addedPixels: displacement)
                } catch let error as TileStoreError {
                    return capacityOrPause(error)
                } catch {
                    return pause(error.localizedDescription)
                }
            case .ambiguous:
                self.startupCandidate = image
                return .waitingForStableFrame
            }
        }

        guard image.width == baseline.width, image.height == baseline.height else {
            return pause(L10n.stitchSizeChanged)
        }
        switch await matcher(baseline, image) {
        case .unchanged:
            guard isCurrentOperation(generation) else { return pausedUpdate() }
            resetMismatch()
            return .unchanged(height: store?.totalHeight ?? 0)
        case let .accepted(displacement, drift, replacement):
            guard isCurrentOperation(generation) else { return pausedUpdate() }
            guard drift == 0, displacement > 0, displacement <= image.height * 3 / 4,
                  replacement >= 0, replacement <= min(96, (image.height - displacement) / 4)
            else {
                return pause(L10n.stitchAlignmentLost)
            }
            resetMismatch()
            guard let currentPixels = await RGBAFrame.make(image: image) else {
                guard isCurrentOperation(generation) else { return pausedUpdate() }
                return pause(L10n.stitchProcessingFailed)
            }
            guard isCurrentOperation(generation) else { return pausedUpdate() }
            do {
                let appended = try store?.appendBottomRows(
                    from: currentPixels,
                    startY: currentPixels.height - displacement - replacement,
                    count: displacement + replacement,
                    sequence: nextSequence,
                    replacingBottomRows: replacement
                ) ?? false
                guard appended else { return pause(L10n.stitchDuplicateFrame) }
                self.baseline = image
                nextSequence &+= 1
                return .appended(height: store?.totalHeight ?? 0, addedPixels: displacement)
            } catch let error as TileStoreError {
                return capacityOrPause(error)
            } catch {
                return pause(error.localizedDescription)
            }
        case let .ambiguous(reason):
            guard isCurrentOperation(generation) else { return pausedUpdate() }
            let time = now()
            if mismatchStartedAt == nil { mismatchStartedAt = time }
            mismatchFrames += 1
            // Keep the committed baseline and stop automatic wheel steps while
            // smooth scrolling/hover/loading settles. Never store an unmatched frame.
            if mismatchFrames < 4 || time - (mismatchStartedAt ?? time) < 1.25 {
                return .waitingForStableFrame
            }
            return pause(reason)
        }
    }

    func pauseIntake(reason: String) {
        guard !isComplete else { return }
        operationGeneration &+= 1
        isPaused = true
        pauseReason = reason
    }

    func resume(discardUnconfirmedCandidate: Bool = false) {
        guard !isComplete else { return }
        operationGeneration &+= 1
        resetMismatch()
        if discardUnconfirmedCandidate, baseline == nil {
            startupCandidate = nil
        }
        isPaused = false
        pauseReason = nil
    }

    func finish() throws -> CGImage {
        guard let store else { throw TileStoreError.missingBaseImage }
        isComplete = true
        isPaused = true
        let image = try store.renderImage()
        self.store = nil
        baseline = nil
        startupCandidate = nil
        return image
    }

    func cancel() {
        operationGeneration &+= 1
        store?.cancel()
        store = nil
        startupCandidate = nil
        baseline = nil
        resetMismatch()
        isPaused = true
        isComplete = true
    }

    private func initialize(with image: CGImage, generation: UInt64) async {
        guard let pixels = await RGBAFrame.make(image: image) else {
            guard isCurrentOperation(generation) else { return }
            _ = pause(L10n.stitchFirstPixels)
            return
        }
        guard isCurrentOperation(generation) else { return }
        do {
            let store = try TileStore(width: image.width, sessionID: sessionID, rootURL: workspaceRootURL)
            do {
                try store.appendFirstFrame(pixels)
            } catch {
                store.cancel()
                throw error
            }
            self.store = store
            baseline = image
            startupCandidate = nil
        } catch {
            _ = pause(error.localizedDescription)
        }
    }

    private func capacityOrPause(_ error: TileStoreError) -> LongCaptureEngineUpdate {
        if case .capacityReached = error {
            isPaused = true
            isComplete = true
            pauseReason = error.localizedDescription
            return .capacityReached(height: store?.totalHeight ?? 0)
        }
        return pause(error.localizedDescription)
    }

    private func pause(_ reason: String) -> LongCaptureEngineUpdate {
        operationGeneration &+= 1
        isPaused = true
        pauseReason = reason
        return .paused(reason: reason, height: store?.totalHeight ?? 0)
    }

    private func isCurrentOperation(_ generation: UInt64) -> Bool {
        !isPaused && !isComplete && operationGeneration == generation
    }

    private func resetMismatch() {
        mismatchStartedAt = nil
        mismatchFrames = 0
    }

    private func pausedUpdate() -> LongCaptureEngineUpdate {
        .paused(reason: pauseReason ?? L10n.stitchPaused, height: store?.totalHeight ?? 0)
    }
}
