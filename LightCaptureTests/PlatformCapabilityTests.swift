import AppKit
import Carbon.HIToolbox
@testable import LightCapture
import XCTest

final class PlatformCapabilityTests: XCTestCase {
    @MainActor
    func testOpenSourceAppUsesIndependentPackagedIdentityInBothLanguages() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "io.github.evilstar2016.openlightcapture")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String, "OpenLightCapture")
        XCTAssertEqual(Bundle.main.bundleURL.lastPathComponent, "OpenLightCapture.app")
        XCTAssertEqual(AssetStore.privatePasteboardType.rawValue, "io.github.evilstar2016.openlightcapture.asset-id")
        for language in ["en", "zh-Hans"] {
            let context = LocalizationContext(languageIdentifier: language)
            XCTAssertEqual(context.string("app.name", defaultValue: "MISSING"), "OpenLightCapture")
        }
    }

    func testSinglePasteboardItemCanAdvertiseImageFileAndPrivateIdentity() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let fileURL = root.appending(path: "Screenshot.png")
        try Data([137, 80, 78, 71, 13, 10, 26, 10]).write(to: fileURL)
        let item = NSPasteboardItem()
        item.setData(Data([137, 80, 78, 71]), forType: .png)
        item.setString(fileURL.absoluteString, forType: .fileURL)
        item.setString(UUID().uuidString, forType: NSPasteboard.PasteboardType("io.github.evilstar2016.openlightcapture.asset-id"))

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("io.github.evilstar2016.openlightcapture.tests.\(UUID().uuidString)"))
        XCTAssertTrue(pasteboard.writeObjects([item]))

        let types = try XCTUnwrap(pasteboard.pasteboardItems?.first?.types)
        XCTAssertTrue(types.contains(.png))
        XCTAssertTrue(types.contains(.fileURL))
        XCTAssertTrue(types.contains(NSPasteboard.PasteboardType("io.github.evilstar2016.openlightcapture.asset-id")))
    }

    func testDefaultHotKeyIsShiftCommandA() {
        XCTAssertEqual(HotKeyConfiguration.default.keyCode, UInt16(kVK_ANSI_A))
        XCTAssertEqual(HotKeyConfiguration.default.carbonModifiers, UInt32(cmdKey | shiftKey))
        XCTAssertEqual(HotKeyConfiguration.default.displayName, "⇧⌘A")
    }

    func testHotKeyConfigurationPersistsInIsolatedDefaults() throws {
        let suiteName = "io.github.evilstar2016.openlightcapture.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let shortcut = HotKeyConfiguration(keyCode: 0x24, carbonModifiers: UInt32(cmdKey | optionKey), keyName: "↩")
        shortcut.save(defaults: defaults)

        XCTAssertEqual(HotKeyConfiguration.load(defaults: defaults), shortcut)
    }
}
