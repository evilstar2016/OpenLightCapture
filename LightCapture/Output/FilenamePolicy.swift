import Foundation

enum FilenamePolicy {
    static func screenshotName(startedAt: Date, locale: Locale = .current, copyIndex: Int? = nil, context: LocalizationContext = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let suffix = copyIndex.map { " (\($0))" } ?? ""
        let prefix = context.string("filename.prefix", defaultValue: "Screenshot")
        return "\(prefix) \(formatter.string(from: startedAt))\(suffix).png"
    }
}
