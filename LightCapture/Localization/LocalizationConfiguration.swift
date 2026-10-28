import Foundation
import OSLog

struct LocalizationConfiguration: Decodable, Equatable {
    struct Language: Decodable, Equatable, Identifiable {
        let identifier: String
        let nativeName: String
        var id: String {
            identifier
        }
    }

    let defaultSelection: String
    let fallbackLanguage: String
    let languages: [Language]

    static let safeDefault = LocalizationConfiguration(
        defaultSelection: "system", fallbackLanguage: "en",
        languages: [Language(identifier: "zh-Hans", nativeName: "简体中文"), Language(identifier: "en", nativeName: "English")]
    )

    func validate() throws {
        let identifiers = languages.map(\.identifier)
        guard !identifiers.isEmpty, Set(identifiers).count == identifiers.count,
              identifiers.contains(fallbackLanguage),
              defaultSelection == "system" || identifiers.contains(defaultSelection),
              languages.allSatisfy({ !$0.nativeName.isEmpty && $0.identifier != "system" && !$0.identifier.contains("/") && !$0.identifier.contains(".") })
        else { throw ConfigurationError.invalid }
    }

    static func load(bundle: Bundle = .main) -> LocalizationConfiguration {
        do {
            guard let url = bundle.url(forResource: "LocalizationConfig", withExtension: "json") else {
                throw ConfigurationError.invalid
            }
            let configuration = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
            try configuration.validate()
            return configuration
        } catch {
            Logger(subsystem: "io.github.evilstar2016.openlightcapture", category: "localization").error("Invalid localization configuration; using safe defaults")
            return .safeDefault
        }
    }

    func resolve(preference: String, preferredLanguages: [String]) -> String {
        let identifiers = languages.map(\.identifier)
        if preference != "system", identifiers.contains(preference) { return preference }
        // The explicit last candidate makes unsupported system languages fall back predictably.
        return Bundle.preferredLocalizations(from: identifiers, forPreferences: preferredLanguages + [fallbackLanguage]).first ?? fallbackLanguage
    }

    private enum ConfigurationError: Error { case invalid }
}
