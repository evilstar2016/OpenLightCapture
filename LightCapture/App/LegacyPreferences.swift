import Foundation

@MainActor
enum LegacyPreferences {
    static let migrationKey = "openlightcapture.importedLegacyPreferences"

    /// Imports only explicitly supplied preferences; no other preference domains are read automatically.
    static func importOnce(
        defaults: UserDefaults = .standard,
        legacyValues: [String: Any]? = nil
    ) {
        guard !defaults.bool(forKey: migrationKey) else { return }
        // Import only app preferences; keep newer choices and the old domain intact.
        for key in [LocalizationStore.preferenceKey, HotKeyConfiguration.preferenceKey] where defaults.object(forKey: key) == nil {
            if let value = legacyValues?[key] { defaults.set(value, forKey: key) }
        }
        defaults.set(true, forKey: migrationKey)
    }
}
