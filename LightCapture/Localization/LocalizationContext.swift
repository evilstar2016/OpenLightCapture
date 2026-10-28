import Foundation

/// A value snapshot that can be passed to background work without UI isolation.
struct LocalizationContext: Equatable {
    let languageIdentifier: String
    let fallbackLanguage: String
    let resourceRoot: URL

    init(languageIdentifier: String, fallbackLanguage: String = "en", resourceRoot: URL = Bundle.main.bundleURL) {
        self.languageIdentifier = languageIdentifier
        self.fallbackLanguage = fallbackLanguage
        self.resourceRoot = resourceRoot
    }

    static var current: LocalizationContext {
        LocalizationRuntime.shared.context
    }

    func string(_ key: String, defaultValue: String) -> String {
        let missing = "\u{1F}missing:\(key)"
        for language in [languageIdentifier, fallbackLanguage] {
            if let bundle = LocalizationResources.shared.bundle(language: language, root: resourceRoot) {
                let value = bundle.localizedString(forKey: key, value: missing, table: "Localizable")
                if value != missing { return value }
            }
        }
        return defaultValue
    }

    func format(_ key: String, defaultValue: String, arguments: [CVarArg]) -> String {
        String(format: string(key, defaultValue: defaultValue), locale: Locale(identifier: languageIdentifier), arguments: arguments)
    }
}

/// All mutations are made by LocalizationStore. Readers take an immutable snapshot.
final class LocalizationRuntime: @unchecked Sendable {
    static let shared = LocalizationRuntime()
    private let lock = NSLock()
    private var value = LocalizationContext(languageIdentifier: "en")

    var context: LocalizationContext {
        lock.withLock { value }
    }

    func install(_ context: LocalizationContext) {
        lock.withLock { value = context }
    }
}

private final class LocalizationResources: @unchecked Sendable {
    static let shared = LocalizationResources()
    private let lock = NSLock()
    private var bundles: [String: Bundle] = [:]

    func bundle(language: String, root: URL) -> Bundle? {
        let url = root.appending(path: "Contents/Resources/\(language).lproj")
        let key = url.path
        return lock.withLock {
            if let cached = bundles[key] { return cached }
            // macOS app bundles have Contents/Resources; test resource bundles may be flat.
            let candidates = [url, root.appending(path: "\(language).lproj")]
            guard let bundle = candidates.lazy.compactMap({ Bundle(url: $0) }).first else { return nil }
            bundles[key] = bundle
            return bundle
        }
    }
}
