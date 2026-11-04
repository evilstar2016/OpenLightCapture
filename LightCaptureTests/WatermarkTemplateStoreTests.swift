import Foundation
@testable import LightCapture
import XCTest

@MainActor
final class WatermarkTemplateStoreTests: XCTestCase {
    func testNewInstallHasBuiltinsWithoutWritingOrEnablingWatermarks() throws {
        try withStore { store, _ in
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
            XCTAssertEqual(store.snapshot().templates.count, 3)
            XCTAssertNil(store.snapshot().defaultSelection)
            XCTAssertTrue(store.snapshot().templates.allSatisfy(\.isBuiltin))
        }
    }

    func testCRUDAndDefaultPersistAcrossRestartAndDeletionClearsDefault() throws {
        try withStore { store, root in
            var template = WatermarkTemplate(name: "署名", text: "@sample")
            try store.save(template)
            try store.setDefault(id: template.id)
            let frozen = store.snapshot()
            template.text = "仅供内部审阅"
            try store.save(template)
            let restarted = WatermarkTemplateStore(directory: root)
            XCTAssertEqual(restarted.library.templates, [template])
            XCTAssertEqual(restarted.snapshot().defaultSelection?.text, template.text)
            XCTAssertEqual(frozen.defaultSelection?.text, "@sample")
            try restarted.delete(id: template.id)
            XCTAssertNil(restarted.library.defaultTemplateID)
            XCTAssertTrue(WatermarkTemplateStore(directory: root).library.templates.isEmpty)
        }
    }

    func testBuiltinDefaultAndStableIDsSurviveLanguageChanges() throws {
        try withStore { store, _ in
            let english = store.snapshot(in: LocalizationContext(languageIdentifier: "en"))
            let chinese = store.snapshot(in: LocalizationContext(languageIdentifier: "zh-Hans"))
            XCTAssertEqual(english.templates.map(\.id), chinese.templates.map(\.id))
            XCTAssertNotEqual(english.templates[0].text, chinese.templates[0].text)
            try store.setDefault(id: english.templates[0].id)
            XCTAssertEqual(store.snapshot(in: LocalizationContext(languageIdentifier: "en")).defaultSelection?.text, english.templates[0].text)
            XCTAssertThrowsError(try store.save(english.templates[0]))
            XCTAssertThrowsError(try store.delete(id: english.templates[0].id))
        }
    }

    func testFailedAtomicWriteKeepsPublishedStateAndOriginalFile() throws {
        try withStore { store, root in
            let template = WatermarkTemplate(name: "署名", text: "Alice")
            try store.save(template)
            let original = try Data(contentsOf: store.fileURL)
            let failing = WatermarkTemplateStore(directory: root, writer: { _, _ in throw CocoaError(.fileWriteNoPermission) })
            XCTAssertThrowsError(try failing.setDefault(id: template.id))
            XCTAssertEqual(failing.library, store.library)
            XCTAssertEqual(try Data(contentsOf: store.fileURL), original)
        }
    }

    func testCorruptAndFutureLibrariesStayReadOnlyUntilExplicitBackupAndReset() throws {
        for data in try [Data("broken".utf8), JSONEncoder().encode(WatermarkLibrary(schemaVersion: 2))] {
            try withStore { store, root in
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                try data.write(to: store.fileURL)
                let recovered = WatermarkTemplateStore(directory: root)
                XCTAssertTrue(recovered.isReadOnly)
                XCTAssertNotNil(recovered.issue)
                XCTAssertNil(recovered.snapshot().defaultSelection)
                XCTAssertThrowsError(try recovered.save(WatermarkTemplate(name: "test", text: "test")))
                XCTAssertEqual(try Data(contentsOf: store.fileURL), data)
                try recovered.reset()
                XCTAssertFalse(recovered.isReadOnly)
                let backup = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first { $0.lastPathComponent.contains("backup") })
                XCTAssertEqual(try Data(contentsOf: backup), data)
                XCTAssertEqual(WatermarkTemplateStore(directory: root).library, WatermarkLibrary())
            }
        }
    }

    func testMissingDefaultFallsBackWithoutChangingFile() throws {
        try withStore { store, root in
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(WatermarkLibrary(defaultTemplateID: "missing"))
            try data.write(to: store.fileURL)
            let restarted = WatermarkTemplateStore(directory: root)
            XCTAssertFalse(restarted.isReadOnly)
            XCTAssertNil(restarted.snapshot().defaultSelection)
            XCTAssertNotNil(restarted.issue)
            XCTAssertEqual(try Data(contentsOf: store.fileURL), data)
            XCTAssertThrowsError(try restarted.setDefault(id: "missing"))
        }
    }

    func testValidationRejectsInvalidTextStyleAndTemplateLimit() throws {
        try withStore { store, _ in
            for text in ["", "  \n ", String(repeating: "文", count: 121), "a\nb\nc\nd"] {
                XCTAssertThrowsError(try store.save(WatermarkTemplate(name: "test", text: text)))
            }
            XCTAssertThrowsError(try store.save(WatermarkTemplate(name: "", text: "test")))
            var invalid = WatermarkTemplate(name: "test", text: "test")
            invalid.style.fontRatio = .nan
            XCTAssertThrowsError(try store.save(invalid))
            invalid.style.fontRatio = 0.04
            invalid.style.horizontalGapRatio = 0
            XCTAssertThrowsError(try store.save(invalid))
            try store.save(WatermarkTemplate(name: "多行", text: "A\r\nB\r\nC"))
            for index in 1 ..< 50 {
                try store.save(WatermarkTemplate(name: "\(index)", text: "test"))
            }
            XCTAssertThrowsError(try store.save(WatermarkTemplate(name: "extra", text: "test")))
            var existing = store.library.templates[0]
            existing.text = "updated"
            XCTAssertNoThrow(try store.save(existing))
        }
    }

    func testDuplicateIDsAndOversizedFileAreRejected() throws {
        let template = WatermarkTemplate(name: "A", text: "B")
        for data in try [JSONEncoder().encode(WatermarkLibrary(templates: [template, template])), Data(repeating: 32, count: 262_145)] {
            try withStore { store, root in
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                try data.write(to: store.fileURL)
                XCTAssertTrue(WatermarkTemplateStore(directory: root).isReadOnly)
            }
        }
    }

    func testSessionFreezesTemplatesAndDefaultsUntilNextCapture() throws {
        try withStore { store, _ in
            var template = WatermarkTemplate(name: "署名", text: "Alice")
            try store.save(template)
            try store.setDefault(id: template.id)
            let flow = CaptureFlowController(watermarkStore: store)
            let session = try XCTUnwrap(flow.sessions.begin(mode: .normal, targetProcessID: nil))
            flow.prepareWatermarks(for: session)
            template.text = "Bob"
            try store.save(template)
            try store.delete(id: template.id)
            XCTAssertEqual(flow.watermarkContext?.selection?.text, "Alice")
            XCTAssertTrue(flow.watermarkContext?.library.templates.contains { $0.text == "Alice" } == true)
            _ = flow.sessions.cancel(sessionID: session.id, generation: session.generation)
            let next = try XCTUnwrap(flow.sessions.begin(mode: .long, targetProcessID: nil))
            flow.prepareWatermarks(for: session) // stale generation cannot replace it
            flow.prepareWatermarks(for: next)
            XCTAssertNil(flow.watermarkContext?.selection)
            XCTAssertEqual(flow.watermarkContext?.sessionID, next.id)
            flow.cancelCurrentSession(restoreFocus: false)
            XCTAssertNil(flow.watermarkContext)
        }
    }

    private func withStore(_ body: (WatermarkTemplateStore, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "watermarks-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try body(WatermarkTemplateStore(directory: root), root)
    }
}
