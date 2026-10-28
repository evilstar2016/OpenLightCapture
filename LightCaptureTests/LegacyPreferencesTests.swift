import Foundation
@testable import LightCapture
import XCTest

@MainActor
final class LegacyPreferencesTests: XCTestCase {
    private func defaults() throws -> UserDefaults {
        let suite = "io.github.evilstar2016.openlightcapture.upgrade.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    func testImportsLanguageAndShortcutWithoutUnrelatedPreferences() throws {
        let defaults = try defaults()
        let shortcut = HotKeyConfiguration(keyCode: 1, carbonModifiers: 256, keyName: "S")
        let data = try JSONEncoder().encode(shortcut)
        LegacyPreferences.importOnce(defaults: defaults, legacyValues: [
            LocalizationStore.preferenceKey: "en",
            HotKeyConfiguration.preferenceKey: data,
            "unrelated": "private value",
        ])
        XCTAssertEqual(defaults.string(forKey: LocalizationStore.preferenceKey), "en")
        XCTAssertEqual(HotKeyConfiguration.load(defaults: defaults), shortcut)
        XCTAssertNil(defaults.object(forKey: "unrelated"))
        XCTAssertTrue(defaults.bool(forKey: LegacyPreferences.migrationKey))
    }

    func testKeepsNewPreferencesAndDoesNotReimportAfterFirstLaunch() throws {
        let defaults = try defaults()
        defaults.set("zh-Hans", forKey: LocalizationStore.preferenceKey)
        LegacyPreferences.importOnce(defaults: defaults, legacyValues: [LocalizationStore.preferenceKey: "en"])
        XCTAssertEqual(defaults.string(forKey: LocalizationStore.preferenceKey), "zh-Hans")
        defaults.removeObject(forKey: LocalizationStore.preferenceKey)
        LegacyPreferences.importOnce(defaults: defaults, legacyValues: [LocalizationStore.preferenceKey: "en"])
        XCTAssertNil(defaults.object(forKey: LocalizationStore.preferenceKey))
    }

    func testFreshInstallWithoutLegacyDomainKeepsDefaults() throws {
        let defaults = try defaults()
        LegacyPreferences.importOnce(defaults: defaults, legacyValues: nil)
        XCTAssertNil(defaults.object(forKey: LocalizationStore.preferenceKey))
        XCTAssertEqual(HotKeyConfiguration.load(defaults: defaults), .default)
        XCTAssertTrue(defaults.bool(forKey: LegacyPreferences.migrationKey))
    }
}
