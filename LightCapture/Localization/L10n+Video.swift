import Foundation

extension L10n {
    static var videoTitle: String {
        LocalizationContext.current.string("video.title", defaultValue: "Record video")
    }

    static var videoParameters: String {
        LocalizationContext.current.string("video.parameters", defaultValue: "MP4 / H.264 · up to 30 fps · 10 minutes · 1920 px maximum edge")
    }

    static var videoPrepareHint: String {
        LocalizationContext.current.string("video.prepareHint", defaultValue: "Records a fixed screen region without sound. Covering windows and notifications may appear.")
    }

    static var videoPreview: String {
        LocalizationContext.current.string("video.preview", defaultValue: "Video Preview")
    }

    static var videoSave: String {
        LocalizationContext.current.string("video.save", defaultValue: "Save video")
    }

    static var videoSaving: String {
        LocalizationContext.current.string("video.saving", defaultValue: "Saving video…")
    }

    static var videoFinishing: String {
        LocalizationContext.current.string("video.finishing", defaultValue: "Finishing video…")
    }

    static var videoLimitReached: String {
        LocalizationContext.current.string("video.limitReached", defaultValue: "The 10-minute recording limit was reached.")
    }

    static var videoDiscardPrompt: String {
        LocalizationContext.current.string("video.discardPrompt", defaultValue: "Discard this video? Unsaved content will be lost.")
    }

    static var videoRerecordPrompt: String {
        LocalizationContext.current.string("video.rerecordPrompt", defaultValue: "Discard this video and record again?")
    }

    static var videoHelp: String {
        LocalizationContext.current.string("video.help", defaultValue: "Preview the recording, then save an MP4 file. Video saving does not change your clipboard.")
    }

    static var videoInvalidMaterial: String {
        LocalizationContext.current.string("error.video.material", defaultValue: "The video is invalid or unavailable. Please record again.")
    }

    static var videoEncodingFailed: String {
        LocalizationContext.current.string("error.video.encoding", defaultValue: "Could not encode or finish the video. Please record again.")
    }

    static var videoTooLarge: String {
        LocalizationContext.current.string("error.video.tooLarge", defaultValue: "The video exceeds the 1 GiB limit. Record a shorter clip or a smaller region.")
    }

    static var videoBackpressure: String {
        LocalizationContext.current.string("error.video.backpressure", defaultValue: "The video encoder stopped accepting frames. Recording has ended.")
    }

    static var videoSmallRegion: String {
        LocalizationContext.current.string("error.video.smallRegion", defaultValue: "Select a video region at least 2 × 2 pixels in size.")
    }

    static func videoRunning(_ seconds: Int) -> String {
        let time = String(format: "%02d:%02d", seconds / 60, seconds % 60)
        return LocalizationContext.current.format("video.running", defaultValue: "Recording · %@ / 10:00", arguments: [time])
    }

    static func videoSummary(_ result: VideoResult) -> String {
        let size = ByteCountFormatter.string(fromByteCount: Int64(result.byteCount), countStyle: .binary)
        return LocalizationContext.current.format("video.summary", defaultValue: "%@ s · %ld × %ld px · %@ · MP4", arguments: [String(format: "%.1f", result.duration), result.width, result.height, size])
    }
}
