import Foundation

enum FilenamePolicy {
    static func screenshotName(startedAt: Date, locale: Locale = .current, copyIndex: Int? = nil, context: LocalizationContext = .current, format: CaptureFileFormat = .png) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let suffix = copyIndex.map { " (\($0))" } ?? ""
        let prefix = format == .mp4
            ? context.string("filename.recordingPrefix", defaultValue: "Recording")
            : context.string("filename.prefix", defaultValue: "Screenshot")
        return "\(prefix) \(formatter.string(from: startedAt))\(suffix).\(format.rawValue)"
    }
}
