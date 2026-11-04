import Foundation

extension L10n {
    static var gifAfterMarks: String {
        LocalizationContext.current.string("gif.afterMarks", defaultValue: "Undo all annotations and turn off the watermark before recording.")
    }

    static var recordingClearsEdits: String {
        LocalizationContext.current.string("recording.clearsEdits", defaultValue: "Click to clear the watermark and annotations, then record.")
    }

    static var recordingClearTitle: String {
        LocalizationContext.current.string("recording.clearTitle", defaultValue: "Clear watermark and annotations to record?")
    }

    static var recordingClearDetail: String {
        LocalizationContext.current.string("recording.clearDetail", defaultValue: "GIF and video capture the raw region only, without the screenshot editing layers. Choose \"Clear and record\" to remove the watermark and all annotations of this capture.")
    }

    static var recordingClearConfirm: String {
        LocalizationContext.current.string("recording.clearConfirm", defaultValue: "Clear and record")
    }

    static var gifTitle: String {
        LocalizationContext.current.string("gif.title", defaultValue: "Record GIF")
    }

    static var gifStart: String {
        LocalizationContext.current.string("gif.start", defaultValue: "Start recording")
    }

    static var gifStop: String {
        LocalizationContext.current.string("gif.stop", defaultValue: "Stop and preview")
    }

    static var gifAbandon: String {
        LocalizationContext.current.string("gif.abandon", defaultValue: "Discard")
    }

    static var gifRerecord: String {
        LocalizationContext.current.string("gif.rerecord", defaultValue: "Record again")
    }

    static var gifSelectAgain: String {
        LocalizationContext.current.string("gif.selectAgain", defaultValue: "Change region")
    }

    static var gifCursor: String {
        LocalizationContext.current.string("gif.cursor", defaultValue: "Show mouse pointer")
    }

    static var gifParameters: String {
        LocalizationContext.current.string("gif.parameters", defaultValue: "10 fps maximum · 30 seconds · 1280 px maximum edge")
    }

    static var gifPrepareHint: String {
        LocalizationContext.current.string("gif.prepareHint", defaultValue: "Records a fixed screen region without sound. Other windows and notifications covering this region may appear.")
    }

    static var gifStarting: String {
        LocalizationContext.current.string("gif.starting", defaultValue: "Starting recording…")
    }

    static var gifEncoding: String {
        LocalizationContext.current.string("gif.encoding", defaultValue: "Creating GIF…")
    }

    static var gifEnding: String {
        LocalizationContext.current.string("gif.ending", defaultValue: "Finishing…")
    }

    static var gifPreview: String {
        LocalizationContext.current.string("gif.preview", defaultValue: "GIF Preview")
    }

    static var gifRawPreview: String {
        LocalizationContext.current.string("gif.rawPreview", defaultValue: "Original recording preview — GIF is not ready")
    }

    static var gifCopy: String {
        LocalizationContext.current.string("gif.copy", defaultValue: "Copy GIF")
    }

    static var gifSaveCopy: String {
        LocalizationContext.current.string("gif.saveCopy", defaultValue: "Save and copy")
    }

    static var gifRetryEncoding: String {
        LocalizationContext.current.string("gif.retryEncoding", defaultValue: "Retry creating GIF")
    }

    static var gifDiscardPrompt: String {
        LocalizationContext.current.string("gif.discardPrompt", defaultValue: "Discard this recording? Unsaved content will be lost.")
    }

    static var gifRerecordPrompt: String {
        LocalizationContext.current.string("gif.rerecordPrompt", defaultValue: "Discard this recording and record again?")
    }

    static var gifLimitReached: String {
        LocalizationContext.current.string("gif.limitReached", defaultValue: "The 30-second recording limit was reached.")
    }

    static var gifUnstable: String {
        LocalizationContext.current.string("gif.unstable", defaultValue: "Capture was unstable; some moments may be missing. Playback timing is preserved.")
    }

    static var gifPasteHelp: String {
        LocalizationContext.current.string("gif.pasteHelp", defaultValue: "Apps choose how to paste GIFs. If animation is not accepted, save the GIF and send it as a file.")
    }

    static var gifInvalidMaterial: String {
        LocalizationContext.current.string("error.gif.material", defaultValue: "The recording material is invalid or unavailable. Please record again.")
    }

    static var gifStorage: String {
        LocalizationContext.current.string("error.gif.storage", defaultValue: "Not enough space for recording. Select a smaller region or free disk space.")
    }

    static var gifNoFrames: String {
        LocalizationContext.current.string("error.gif.noFrames", defaultValue: "No screen image was received. Check screen recording permission and try again.")
    }

    static var gifEncodingFailed: String {
        LocalizationContext.current.string("error.gif.encoding", defaultValue: "Could not create the GIF. Retry or record again.")
    }

    static var gifStreamStopped: String {
        LocalizationContext.current.string("error.gif.stream", defaultValue: "Screen capture was interrupted. Please start a new recording.")
    }

    static var gifTooLarge: String {
        LocalizationContext.current.string("error.gif.tooLarge", defaultValue: "The GIF exceeds 50 MiB. Record a shorter clip or a smaller region.")
    }

    static func gifCountdown(_ seconds: Int) -> String {
        LocalizationContext.current.format("gif.countdown", defaultValue: "Recording starts in %ld…", arguments: [seconds])
    }

    static func gifRunning(_ seconds: Int) -> String {
        LocalizationContext.current.format("gif.running", defaultValue: "Recording · %ld / 30 s", arguments: [seconds])
    }

    static func gifSummary(duration: Double, width: Int, height: Int, bytes: Int?) -> String {
        let size = bytes.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .binary) } ?? "—"
        return LocalizationContext.current.format("gif.summary", defaultValue: "%@ s · %ld × %ld px · %@", arguments: [String(format: "%.1f", duration), width, height, size])
    }

    static func gifSavedCopyFailed(_ name: String, reason: String) -> String {
        LocalizationContext.current.format("gif.savedCopyFailed", defaultValue: "Saved to %@, but copying failed: %@", arguments: [name, reason])
    }
}
