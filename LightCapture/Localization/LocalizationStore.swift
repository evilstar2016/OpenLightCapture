import Combine
import Foundation

@MainActor
final class LocalizationStore: ObservableObject {
    static let shared = LocalizationStore()
    static let preferenceKey = "appLanguage"
    static let didChange = Notification.Name("OpenLightCapture.languageDidChange")

    let configuration: LocalizationConfiguration
    @Published private(set) var preference: String
    @Published private(set) var effectiveLanguage: String
    @Published private(set) var pendingLanguage: String?
    @Published private(set) var isRecordingShortcut = false
    private let defaults: UserDefaults
    private let preferredLanguages: () -> [String]
    private let installContext: (LocalizationContext) -> Void
    private var sessionIsActive = false

    init(
        defaults: UserDefaults = .standard,
        configuration: LocalizationConfiguration = .load(),
        preferredLanguages: @escaping () -> [String] = { Locale.preferredLanguages },
        installContext: @escaping (LocalizationContext) -> Void = { LocalizationRuntime.shared.install($0) }
    ) {
        self.defaults = defaults
        self.configuration = configuration
        self.preferredLanguages = preferredLanguages
        self.installContext = installContext
        let saved = defaults.string(forKey: Self.preferenceKey)
        let preference = saved.flatMap { value in
            value == "system" || configuration.languages.contains(where: { $0.identifier == value }) ? value : nil
        } ?? configuration.defaultSelection
        self.preference = preference
        effectiveLanguage = configuration.resolve(preference: preference, preferredLanguages: preferredLanguages())
        if saved != nil, saved != preference { defaults.set(preference, forKey: Self.preferenceKey) }
        installContext(LocalizationContext(languageIdentifier: effectiveLanguage, fallbackLanguage: configuration.fallbackLanguage))
    }

    func setPreference(_ value: String) {
        guard !isRecordingShortcut,
              value == "system" || configuration.languages.contains(where: { $0.identifier == value })
        else { return }
        preference = value
        defaults.set(value, forKey: Self.preferenceKey)
        resolveAndApply()
    }

    func setSessionActive(_ active: Bool) {
        sessionIsActive = active
        if !active { resolveAndApply() }
    }

    func setShortcutRecording(_ recording: Bool) {
        isRecordingShortcut = recording
        if !recording { resolveAndApply() }
    }

    func refreshSystemLanguage() {
        guard preference == "system" else { return }
        resolveAndApply()
    }

    private func resolveAndApply() {
        let language = configuration.resolve(preference: preference, preferredLanguages: preferredLanguages())
        guard language != effectiveLanguage else {
            pendingLanguage = nil
            return
        }
        guard !sessionIsActive, !isRecordingShortcut else {
            pendingLanguage = language
            return
        }
        installContext(LocalizationContext(languageIdentifier: language, fallbackLanguage: configuration.fallbackLanguage))
        effectiveLanguage = language
        pendingLanguage = nil
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}
