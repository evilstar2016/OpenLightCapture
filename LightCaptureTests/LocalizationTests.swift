import AppKit
import Carbon.HIToolbox
@testable import LightCapture
import XCTest

@MainActor
final class LocalizationTests: XCTestCase {
    private func defaults() throws -> UserDefaults {
        let suite = "io.github.evilstar2016.openlightcapture.localization.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    private func makeStore(_ defaults: UserDefaults, preferences: @escaping () -> [String] = { ["en-US"] }) -> LocalizationStore {
        LocalizationStore(defaults: defaults, configuration: .safeDefault, preferredLanguages: preferences, installContext: { _ in })
    }

    func testSystemLanguageResolutionAndExplicitPreference() {
        let config = LocalizationConfiguration.safeDefault
        XCTAssertEqual(config.resolve(preference: "system", preferredLanguages: ["zh-CN"]), "zh-Hans")
        XCTAssertEqual(config.resolve(preference: "system", preferredLanguages: ["en-GB"]), "en")
        XCTAssertEqual(config.resolve(preference: "system", preferredLanguages: ["fr-FR"]), "en")
        XCTAssertEqual(config.resolve(preference: "system", preferredLanguages: []), "en")
        XCTAssertEqual(config.resolve(preference: "system", preferredLanguages: ["zh-Hant"]), "en")
        XCTAssertEqual(config.resolve(preference: "en", preferredLanguages: ["zh-CN"]), "en")
        XCTAssertEqual(config.resolve(preference: "zh-Hans", preferredLanguages: ["en-US"]), "zh-Hans")
    }

    func testPreferencesPersistAndInvalidSavedLanguageIsRepaired() throws {
        let defaults = try defaults()
        defaults.set("removed-language", forKey: LocalizationStore.preferenceKey)
        let store = makeStore(defaults, preferences: { ["zh-CN"] })
        XCTAssertEqual(store.preference, "system")
        XCTAssertEqual(store.effectiveLanguage, "zh-Hans")
        XCTAssertEqual(defaults.string(forKey: LocalizationStore.preferenceKey), "system")
        store.setPreference("en")
        XCTAssertEqual(makeStore(defaults).effectiveLanguage, "en")
        store.setPreference("invalid")
        XCTAssertEqual(store.preference, "en")
    }

    func testActiveSessionDefersLastChoiceAndCanCancelPendingChange() throws {
        let store = try makeStore(defaults())
        store.setSessionActive(true)
        store.setPreference("zh-Hans")
        XCTAssertEqual(store.preference, "zh-Hans")
        XCTAssertEqual(store.pendingLanguage, "zh-Hans")
        XCTAssertEqual(store.effectiveLanguage, "en")
        store.setPreference("en")
        XCTAssertNil(store.pendingLanguage)
        store.setPreference("zh-Hans")
        store.setSessionActive(false)
        XCTAssertEqual(store.effectiveLanguage, "zh-Hans")
        XCTAssertNil(store.pendingLanguage)
    }

    func testOnlyEffectiveChangesPublishLanguageNotification() throws {
        let store = try makeStore(defaults())
        let changes = expectation(description: "Only effective language changes notify the UI")
        changes.expectedFulfillmentCount = 1
        let observer = NotificationCenter.default.addObserver(forName: LocalizationStore.didChange, object: store, queue: .main) { _ in
            changes.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        store.setSessionActive(true)
        store.setPreference("zh-Hans")
        store.setPreference("zh-Hans")
        store.setSessionActive(false)
        store.setPreference("zh-Hans")
        wait(for: [changes], timeout: 1)
    }

    func testPendingPreferenceSurvivesRestartAndShortcutRecordingBlocksChanges() throws {
        let defaults = try defaults()
        let store = makeStore(defaults)
        store.setSessionActive(true)
        store.setPreference("zh-Hans")
        XCTAssertEqual(makeStore(defaults).effectiveLanguage, "zh-Hans")
        store.setSessionActive(false)
        store.setShortcutRecording(true)
        store.setPreference("en")
        XCTAssertEqual(store.preference, "zh-Hans")
        store.setShortcutRecording(false)
        store.setPreference("en")
        XCTAssertEqual(store.effectiveLanguage, "en")
    }

    func testSystemRefreshHonorsExplicitSelectionAndDefersWhileBusy() throws {
        var preferred = ["en-US"]
        let store = try makeStore(defaults(), preferences: { preferred })
        store.setSessionActive(true)
        preferred = ["zh-CN"]
        store.refreshSystemLanguage()
        XCTAssertEqual(store.effectiveLanguage, "en")
        XCTAssertEqual(store.pendingLanguage, "zh-Hans")
        store.setSessionActive(false)
        XCTAssertEqual(store.effectiveLanguage, "zh-Hans")
        store.setPreference("en")
        store.refreshSystemLanguage()
        XCTAssertEqual(store.effectiveLanguage, "en")
    }

    func testFlowCancellationAppliesLanguageOnlyAfterCleanup() async throws {
        let store = try makeStore(defaults())
        let flow = CaptureFlowController()
        flow.onSessionActivityChange = { store.setSessionActive($0) }
        _ = flow.sessions.begin(mode: .long, targetProcessID: nil)
        store.setSessionActive(true)
        store.setPreference("zh-Hans")
        flow.cancelCurrentSession(restoreFocus: false)
        XCTAssertNil(flow.sessions.activeSession)
        XCTAssertEqual(store.effectiveLanguage, "en", "The caller must finish closing its views before language changes")
        for _ in 0 ..< 10 where store.pendingLanguage != nil {
            await Task.yield()
        }
        XCTAssertEqual(store.effectiveLanguage, "zh-Hans")
    }

    func testPackagedConfigurationResourcesAndPluralTemplates() throws {
        let config = LocalizationConfiguration.load()
        try config.validate()
        XCTAssertEqual(config.languages.map(\.identifier), ["zh-Hans", "en"])
        let english = LocalizationContext(languageIdentifier: "en")
        let chinese = LocalizationContext(languageIdentifier: "zh-Hans")
        XCTAssertEqual(english.string("menu.capture", defaultValue: "MISSING"), "Capture")
        XCTAssertEqual(chinese.string("menu.capture", defaultValue: "MISSING"), "截图")
        XCTAssertEqual(L10n.longRunning("Automatic", 120, 1, in: english), "Automatic scroll · Confirmed 120 px · 1 second")
        XCTAssertEqual(L10n.longRunning("Manual", 240, 2, in: english), "Manual scroll · Confirmed 240 px · 2 seconds")
        XCTAssertEqual(L10n.longRunning("自动", 120, 2, in: chinese), "自动滚动 · 已确认 120 px · 2 秒")
        XCTAssertEqual(L10n.errorSavedCopyDetail("my image.png", "Disk error", in: english), "The file was saved as “my image.png”.\nDisk error")
    }

    func testMissingTranslationFallsBackToEnglishThenReadableDefault() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let english = root.appending(path: "en.lproj")
        let chinese = root.appending(path: "zh-Hans.lproj")
        try FileManager.default.createDirectory(at: english, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: chinese, withIntermediateDirectories: true)
        try "\"fallback.test\" = \"English fallback\";".write(to: english.appending(path: "Localizable.strings"), atomically: true, encoding: .utf8)
        let context = LocalizationContext(languageIdentifier: "zh-Hans", resourceRoot: root)
        XCTAssertEqual(context.string("fallback.test", defaultValue: "Readable default"), "English fallback")
        XCTAssertEqual(context.string("unknown.key", defaultValue: "Readable default"), "Readable default")
    }

    func testFilenameContextAndDuplicateIndexDoNotChangeTimestamp() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let english = FilenamePolicy.screenshotName(startedAt: date, copyIndex: 2, context: LocalizationContext(languageIdentifier: "en"))
        let chinese = FilenamePolicy.screenshotName(startedAt: date, copyIndex: 2, context: LocalizationContext(languageIdentifier: "zh-Hans"))
        XCTAssertTrue(english.hasPrefix("Screenshot "))
        XCTAssertTrue(chinese.hasPrefix("截图 "))
        XCTAssertEqual(english.replacingOccurrences(of: "Screenshot ", with: ""), chinese.replacingOccurrences(of: "截图 ", with: ""))
        XCTAssertTrue(english.hasSuffix(" (2).png"))
    }

    func testInvalidConfigurationIsRejected() {
        let english = LocalizationConfiguration.Language(identifier: "en", nativeName: "English")
        XCTAssertThrowsError(try LocalizationConfiguration(defaultSelection: "system", fallbackLanguage: "en", languages: [english, english]).validate())
        XCTAssertThrowsError(try LocalizationConfiguration(defaultSelection: "missing", fallbackLanguage: "en", languages: [english]).validate())
        XCTAssertThrowsError(try LocalizationConfiguration(defaultSelection: "system", fallbackLanguage: "missing", languages: [english]).validate())
    }

    func testToolTextAndAccessibilityFollowBothLanguages() throws {
        let original = LocalizationContext.current
        defer { LocalizationRuntime.shared.install(original) }
        for (language, title) in [("en", "Text"), ("zh-Hans", "文字")] {
            LocalizationRuntime.shared.install(LocalizationContext(languageIdentifier: language))
            let target = NSObject()
            let button = AnnotationToolbarStyle.toolButton(.text, target: target, action: Selector("unused:"))
            XCTAssertEqual(button.title, title)
            XCTAssertEqual(button.accessibilityLabel(), title)
            XCTAssertEqual(button.identifier?.rawValue, "capture.annotation.tool.6")
            XCTAssertGreaterThanOrEqual(button.fittingSize.width, 44)
            XCTAssertEqual(button.imagePosition, .noImage)
            XCTAssertFalse(try XCTUnwrap(button.toolTip).isEmpty)
        }
    }

    func testEnglishSettingsAndLongPanelFitAndProducePreviews() async throws {
        let original = LocalizationContext.current
        defer { LocalizationRuntime.shared.install(original) }
        // Keep hosted tests independent of Documents folder authorization for the app identity.
        let previewRoot = FileManager.default.temporaryDirectory.appending(path: "OpenLightCapture-i18n-previews-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: previewRoot, withIntermediateDirectories: true)
        for language in ["en", "zh-Hans"] {
            let defaults = try defaults()
            defaults.set(language, forKey: LocalizationStore.preferenceKey)
            let store = LocalizationStore(defaults: defaults, configuration: .safeDefault)
            let settings = SettingsWindowController(hotKeyService: HotKeyService(), localization: store)
            let window = try XCTUnwrap(settings.window)
            defer { settings.close() }
            let view = try XCTUnwrap(window.contentView)
            view.layoutSubtreeIfNeeded()
            await Task.yield()
            view.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(view.fittingSize.height, 0)
            XCTAssertGreaterThanOrEqual(view.bounds.height + 1, view.fittingSize.height)
            try savePreview(view, to: previewRoot.appending(path: "settings-\(language).png"))

            let panel = LongCaptureControlPanel(screenFrame: CGRect(x: 0, y: 0, width: 1000, height: 800), selectedGlobalRect: CGRect(x: 100, y: 300, width: 500, height: 300))
            defer { panel.close() }
            panel.showRunning(mode: .automatic, height: 1200, elapsed: 2)
            let root = try XCTUnwrap(panel.contentView)
            root.layoutSubtreeIfNeeded()
            for button in descendants(root).compactMap({ $0 as? NSButton }) where !button.isHidden {
                XCTAssertTrue(root.bounds.contains(root.convert(button.bounds, from: button)), button.title)
                XCTAssertGreaterThanOrEqual(button.bounds.width + 1, button.intrinsicContentSize.width, button.title)
            }
            try savePreview(root, to: previewRoot.appending(path: "long-\(language).png"))
        }
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private func savePreview(_ view: NSView, to url: URL) throws {
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: url)
    }
}
