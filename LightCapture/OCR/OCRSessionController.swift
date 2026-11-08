import AppKit

@MainActor
final class OCRSessionController {
    typealias Recognizer = @Sendable (AnnotationRenderSnapshot) async throws -> OCRResult

    enum State: Equatable {
        case idle, recognizing, ready, empty, failed, dismissed
    }

    let windowController = OCRResultWindowController()
    private(set) var state: State = .idle
    private let snapshot: AnnotationRenderSnapshot
    private let recognize: Recognizer
    private let isCurrent: () -> Bool
    private let onReturn: () -> Void
    private let onCopy: (String) throws -> Void
    private var task: Task<Void, Never>?
    private var requestID = UUID()

    init(snapshot: AnnotationRenderSnapshot,
         recognize: @escaping Recognizer = TextRecognitionService.recognize,
         isCurrent: @escaping () -> Bool,
         onReturn: @escaping () -> Void,
         onCopy: @escaping (String) throws -> Void)
    {
        self.snapshot = snapshot
        self.recognize = recognize
        self.isCurrent = isCurrent
        self.onReturn = onReturn
        self.onCopy = onCopy
        windowController.onReturn = { [weak self] in self?.returnToImage() }
        windowController.onRetry = { [weak self] in self?.retry() }
        windowController.onCopy = { [weak self] in self?.copyAndFinish() }
    }

    func present(on screen: NSScreen?) {
        windowController.showRecognizing()
        windowController.present(on: screen)
        start()
    }

    func start() {
        guard state != .dismissed, state != .recognizing, isCurrent() else { return }
        task?.cancel()
        requestID = UUID()
        let id = requestID
        let recognize = recognize
        let snapshot = snapshot
        state = .recognizing
        windowController.showRecognizing()
        task = Task { @MainActor [weak self] in
            do {
                let result = try await recognize(snapshot)
                guard let self, accepts(id) else { return }
                state = result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .empty : .ready
                windowController.showResult(result.text)
            } catch {
                guard let self, accepts(id), !(error is CancellationError) else { return }
                state = .failed
                let message = (error as? TextRecognitionError)?.errorDescription
                    ?? (error as? AnnotationRenderError)?.errorDescription ?? L10n.ocrFailed
                windowController.showError(message)
            }
        }
    }

    func dismiss() {
        guard state != .dismissed else { return }
        state = .dismissed
        requestID = UUID()
        task?.cancel()
        task = nil
        windowController.dismiss()
    }

    func returnToImage() {
        guard state != .dismissed else { return }
        dismiss()
        // The owner must always clear the child, even if the source revision
        // changed. It decides whether the capture session can be restored.
        onReturn()
    }

    func retry() {
        guard state == .empty || state == .failed else { return }
        start()
    }

    func copyAndFinish() {
        guard state == .ready, isCurrent(), !windowController.textView.hasMarkedText() else { return }
        let text = windowController.textView.string
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            try onCopy(text)
            dismiss()
        } catch {
            windowController.showCopyError()
        }
    }

    private func accepts(_ id: UUID) -> Bool {
        state == .recognizing && id == requestID && isCurrent() && !Task.isCancelled
    }
}
