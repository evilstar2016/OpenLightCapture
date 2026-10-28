import AppKit
import Carbon.HIToolbox
import os

private let hotKeyLogger = Logger(subsystem: "io.github.evilstar2016.openlightcapture", category: "HotKey")

@MainActor
final class HotKeyService {
    private let logger = hotKeyLogger
    private(set) var configuration = HotKeyConfiguration.load()
    var onConfigurationChange: ((HotKeyConfiguration) -> Void)?

    private var handler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private var callback: (() -> Void)?
    private var isSuspended = false

    func register(onPressed: @escaping () -> Void) throws {
        callback = onPressed
        isSuspended = false
        try install(configuration)
    }

    func update(_ newConfiguration: HotKeyConfiguration) throws {
        let previous = configuration
        let wasSuspended = isSuspended
        uninstall()
        do {
            guard newConfiguration.carbonModifiers & UInt32(cmdKey | shiftKey | optionKey | controlKey) != 0 else {
                throw HotKeyError.modifierRequired
            }
            try install(newConfiguration)
            if wasSuspended {
                uninstall()
                isSuspended = true
            }
            configuration = newConfiguration
            configuration.save()
            onConfigurationChange?(newConfiguration)
        } catch {
            if !wasSuspended { try? install(previous) }
            isSuspended = wasSuspended
            throw error
        }
    }

    func suspend() {
        isSuspended = true
        uninstall()
    }

    func resume() throws {
        guard isSuspended else { return }
        try install(configuration)
        isSuspended = false
    }

    func unregister() {
        uninstall()
        callback = nil
        isSuspended = true
    }

    private func install(_ shortcut: HotKeyConfiguration) throws {
        logger.info("Registering global screenshot hotkey \(shortcut.displayName, privacy: .public)")
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                var pressedID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &pressedID
                )
                hotKeyLogger.info("Carbon hotkey event delivered: status \(status, privacy: .public), signature \(pressedID.signature, privacy: .public), id \(pressedID.id, privacy: .public)")
                guard status == noErr, pressedID.id == 1 else { return noErr }
                let service = Unmanaged<HotKeyService>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in
                    service.logger.info("Global screenshot hotkey received")
                    service.callback?()
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            &handler
        )
        guard installStatus == noErr else {
            logger.error("InstallEventHandler failed with status \(installStatus, privacy: .public)")
            throw HotKeyError.registrationFailed(installStatus, shortcut.displayName)
        }

        var identifier = EventHotKeyID()
        identifier.signature = OSType(0x4350_494D)
        identifier.id = 1
        let registerStatus = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.carbonModifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        guard registerStatus == noErr else {
            RemoveEventHandler(handler)
            handler = nil
            logger.error("RegisterEventHotKey failed for \(shortcut.displayName, privacy: .public) with status \(registerStatus, privacy: .public)")
            throw HotKeyError.registrationFailed(registerStatus, shortcut.displayName)
        }
        logger.info("Global screenshot hotkey registered: \(shortcut.displayName, privacy: .public)")
    }

    private func uninstall() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        if let handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
    }
}

struct HotKeyConfiguration: Codable, Equatable {
    let keyCode: UInt16
    let carbonModifiers: UInt32
    let keyName: String

    static let preferenceKey = "globalScreenshotHotKey"
    static let `default` = HotKeyConfiguration(keyCode: UInt16(kVK_ANSI_A), carbonModifiers: UInt32(cmdKey | shiftKey), keyName: "A")

    var displayName: String {
        var result = ""
        if carbonModifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result + (keyName.isEmpty ? L10n.settingsKeyCode(Int(keyCode)) : keyName)
    }

    static func load(defaults: UserDefaults = .standard) -> HotKeyConfiguration {
        guard let data = defaults.data(forKey: preferenceKey),
              let value = try? JSONDecoder().decode(HotKeyConfiguration.self, from: data),
              value.carbonModifiers & UInt32(cmdKey | shiftKey | optionKey | controlKey) != 0
        else {
            return .default
        }
        return value
    }

    func save(defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.preferenceKey)
    }
}

enum HotKeyError: LocalizedError {
    case registrationFailed(OSStatus, String)
    case modifierRequired

    var errorDescription: String? {
        switch self {
        case let .registrationFailed(status, shortcut):
            L10n.errorHotKeyRejected(shortcut, Int(status))
        case .modifierRequired:
            L10n.errorHotKeyModifier
        }
    }
}
