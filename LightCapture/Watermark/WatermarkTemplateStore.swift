import Combine
import Foundation

@MainActor
final class WatermarkTemplateStore: ObservableObject {
    static let shared = WatermarkTemplateStore()

    @Published private(set) var library = WatermarkLibrary()
    @Published private(set) var issue: String?
    @Published private(set) var isReadOnly = false

    let fileURL: URL
    private let writer: (Data, URL) throws -> Void

    init(directory: URL? = nil, writer: @escaping (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) {
        let root = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: Bundle.main.bundleIdentifier ?? "io.github.evilstar2016.openlightcapture", directoryHint: .isDirectory)
            .appending(path: "Watermarks", directoryHint: .isDirectory)
        fileURL = root.appending(path: "templates.json")
        self.writer = writer
        load()
    }

    func snapshot(in context: LocalizationContext = .current) -> WatermarkLibrarySnapshot {
        WatermarkLibrarySnapshot(templates: WatermarkTemplate.builtins(in: context) + library.templates, defaultTemplateID: library.defaultTemplateID)
    }

    func save(_ template: WatermarkTemplate) throws {
        guard !template.isBuiltin, UUID(uuidString: template.id) != nil else { throw WatermarkError.readOnly }
        try template.validate()
        var next = library
        if let index = next.templates.firstIndex(where: { $0.id == template.id }) {
            next.templates[index] = template
        } else {
            guard next.templates.count < 50 else { throw WatermarkError.templateLimit }
            next.templates.append(template)
        }
        try persist(next)
    }

    func delete(id: String) throws {
        guard library.templates.contains(where: { $0.id == id }) else { throw WatermarkError.readOnly }
        var next = library
        next.templates.removeAll { $0.id == id }
        if next.defaultTemplateID == id { next.defaultTemplateID = nil }
        try persist(next)
    }

    func setDefault(id: String?) throws {
        guard id == nil || snapshot().templates.contains(where: { $0.id == id }) else { throw WatermarkError.invalidLibrary }
        var next = library
        next.defaultTemplateID = id
        try persist(next)
    }

    /// Explicit recovery preserves the original file before enabling writes.
    func reset() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let backup = fileURL.deletingLastPathComponent().appending(path: "templates-\(UUID().uuidString).backup.json")
            try FileManager.default.copyItem(at: fileURL, to: backup)
        }
        try write(WatermarkLibrary())
        library = WatermarkLibrary()
        isReadOnly = false
        issue = nil
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            guard ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= 262_144 else { throw WatermarkError.invalidLibrary }
            let decoded = try JSONDecoder().decode(WatermarkLibrary.self, from: Data(contentsOf: fileURL))
            guard decoded.schemaVersion == 1, decoded.templates.count <= 50,
                  Set(decoded.templates.map(\.id)).count == decoded.templates.count
            else { throw WatermarkError.invalidLibrary }
            for template in decoded.templates {
                guard !template.isBuiltin, UUID(uuidString: template.id) != nil else { throw WatermarkError.invalidLibrary }
                try template.validate()
            }
            library = decoded
            if let id = decoded.defaultTemplateID, !snapshot().templates.contains(where: { $0.id == id }) {
                library.defaultTemplateID = nil
                issue = L10n.watermarkMissingDefault
            }
        } catch {
            isReadOnly = true
            issue = L10n.watermarkReadOnly
        }
    }

    private func persist(_ next: WatermarkLibrary) throws {
        guard !isReadOnly else { throw WatermarkError.readOnly }
        try write(next)
        library = next
        issue = nil
    }

    private func write(_ next: WatermarkLibrary) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try writer(encoder.encode(next), fileURL)
    }
}
