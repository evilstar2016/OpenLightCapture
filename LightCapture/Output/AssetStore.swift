import AppKit
import Foundation
import UniformTypeIdentifiers

enum AssetPhase: String, Codable {
    case working
    case staging
    case published
    case retired
}

struct AssetMetadata: Codable {
    let schemaVersion: Int
    let assetID: UUID
    let relativeFilename: String
    let createdAt: Date
    var phase: AssetPhase
    var retiredAt: Date?
    var publicationChangeCount: Int?
}

struct PreparedAsset {
    let metadata: AssetMetadata
    let directoryURL: URL
    let imageURL: URL
    let pngData: Data
}

enum AssetStoreError: LocalizedError {
    case invalidPNG
    case invalidDimensions
    case insufficientStorage
    case unsafeAsset
    case fileSystem(Error)

    var errorDescription: String? {
        switch self {
        case .invalidPNG: L10n.errorInvalidPNG
        case .invalidDimensions: L10n.errorInvalidDimensions
        case .insufficientStorage: L10n.errorAssetStorage
        case .unsafeAsset: L10n.errorAssetUnsafe
        case let .fileSystem(error): L10n.errorAssetFile(error.localizedDescription)
        }
    }
}

@MainActor
final class AssetStore {
    static let privatePasteboardType = NSPasteboard.PasteboardType("io.github.evilstar2016.openlightcapture.asset-id")
    static let pngPasteboardType = NSPasteboard.PasteboardType(UTType.png.identifier)

    private let fileManager: FileManager
    private let rootURL: URL
    private let metadataFilename = "asset.json"
    private var currentAssetID: UUID?
    private var observedPasteboardChangeCount: Int?
    private var maintenancePasteboard: NSPasteboard?
    private var maintenanceTimer: Timer?
    private var reaperTimer: Timer?

    init(rootURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.rootURL = support.appending(path: Bundle.main.bundleIdentifier ?? "io.github.evilstar2016.openlightcapture", directoryHint: .isDirectory)
                .appending(path: "Assets", directoryHint: .isDirectory)
        }
    }

    func prepare(pngData: Data, startedAt: Date) throws -> PreparedAsset {
        guard isPNG(pngData) else { throw AssetStoreError.invalidPNG }
        guard validDimensions(pngData) else { throw AssetStoreError.invalidDimensions }
        do {
            try ensureRoot()
            let currentBytes = try directorySize(at: rootURL)
            let maxBytes: UInt64 = 2 * 1024 * 1024 * 1024
            let newFileBytes = UInt64(pngData.count)
            guard newFileBytes <= maxBytes, currentBytes <= maxBytes - newFileBytes else { throw AssetStoreError.insufficientStorage }
            if let values = try? rootURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
               let available = values.volumeAvailableCapacityForImportantUsage,
               available < Int64(pngData.count)
            {
                throw AssetStoreError.insufficientStorage
            }
            let id = UUID()
            let directory = rootURL.appending(path: id.uuidString, directoryHint: .isDirectory)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let filename = uniqueFilename(startedAt: startedAt)
            let imageURL = directory.appending(path: filename)
            var metadata = AssetMetadata(
                schemaVersion: 1,
                assetID: id,
                relativeFilename: filename,
                createdAt: startedAt,
                phase: .staging,
                retiredAt: nil,
                publicationChangeCount: nil
            )
            try writeMetadata(metadata, to: directory)
            try pngData.write(to: imageURL, options: .atomic)
            guard chmod(imageURL.path, mode_t(S_IRUSR | S_IWUSR)) == 0 else {
                try? fileManager.removeItem(at: directory)
                throw AssetStoreError.unsafeAsset
            }
            let imageValues = try imageURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard imageValues.isRegularFile == true, imageValues.isSymbolicLink != true, imageValues.fileSize == pngData.count else {
                try? fileManager.removeItem(at: directory)
                throw AssetStoreError.unsafeAsset
            }
            metadata.phase = .staging
            return PreparedAsset(metadata: metadata, directoryURL: directory, imageURL: imageURL, pngData: pngData)
        } catch let error as AssetStoreError {
            throw error
        } catch {
            throw AssetStoreError.fileSystem(error)
        }
    }

    func markPublished(_ asset: PreparedAsset, changeCount: Int) throws {
        guard isManagedAsset(asset), var metadata = try readMetadata(in: asset.directoryURL), metadata.assetID == asset.metadata.assetID else {
            throw AssetStoreError.unsafeAsset
        }
        if let oldID = currentAssetID, oldID != metadata.assetID {
            retire(assetID: oldID, at: Date())
        }
        metadata.phase = .published
        metadata.publicationChangeCount = changeCount
        metadata.retiredAt = nil
        try writeMetadata(metadata, to: asset.directoryURL)
        currentAssetID = metadata.assetID
        observedPasteboardChangeCount = changeCount
    }

    func discard(_ asset: PreparedAsset) {
        guard isManagedAsset(asset), asset.metadata.assetID != currentAssetID else { return }
        guard let metadata = readMetadataIfValid(in: asset.directoryURL), metadata.assetID == asset.metadata.assetID,
              metadata.phase == .staging
        else { return }
        try? fileManager.removeItem(at: asset.directoryURL)
    }

    func startMaintenance(pasteboard: NSPasteboard = .general) {
        guard maintenanceTimer == nil else { return }
        try? ensureRoot()
        maintenancePasteboard = pasteboard
        reconcileAtLaunch(pasteboard: pasteboard)
        observedPasteboardChangeCount = pasteboard.changeCount
        maintenanceTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let maintenancePasteboard else { return }
                observePasteboard(maintenancePasteboard)
            }
        }
        maintenanceTimer?.tolerance = 0.5
        reaperTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reapRetiredAssets(now: Date()) }
        }
        reaperTimer?.tolerance = 10
        reapRetiredAssets(now: Date())
    }

    func stopMaintenance() {
        maintenanceTimer?.invalidate()
        maintenanceTimer = nil
        reaperTimer?.invalidate()
        reaperTimer = nil
        maintenancePasteboard = nil
    }

    func reapRetiredAssets(now: Date) {
        guard let children = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        for directory in children {
            guard isDirectChild(directory), isOrdinaryDirectory(directory),
                  let metadata = readMetadataIfValid(in: directory),
                  metadata.phase == .retired,
                  metadata.assetID != currentAssetID,
                  let retiredAt = metadata.retiredAt,
                  now.timeIntervalSince(retiredAt) >= 15 * 60,
                  isSafeImageName(metadata.relativeFilename)
            else { continue }
            try? fileManager.removeItem(at: directory)
        }
    }

    private func reconcileAtLaunch(pasteboard: NSPasteboard) {
        guard let children = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        var published: [(URL, AssetMetadata)] = []
        let pastedID = pasteboard.string(forType: Self.privatePasteboardType).flatMap(UUID.init(uuidString:))
        let pasteboardHasTypes = pasteboard.types != nil
        for directory in children where isDirectChild(directory) && isOrdinaryDirectory(directory) {
            do {
                guard var metadata = try readMetadata(in: directory) else { continue }
                switch metadata.phase {
                case .working:
                    try? fileManager.removeItem(at: directory)
                case .staging:
                    if pastedID == metadata.assetID {
                        metadata.phase = .published
                        metadata.publicationChangeCount = pasteboard.changeCount
                        try? writeMetadata(metadata, to: directory)
                        published.append((directory, metadata))
                    } else if pasteboardHasTypes {
                        metadata.phase = .retired
                        metadata.retiredAt = Date()
                        try? writeMetadata(metadata, to: directory)
                    }
                case .published:
                    published.append((directory, metadata))
                case .retired:
                    break
                }
            } catch {
                continue
            }
        }
        if let current = published.first(where: { $0.1.assetID == pastedID }) {
            currentAssetID = current.1.assetID
            for (directory, var metadata) in published where metadata.assetID != current.1.assetID {
                metadata.phase = .retired
                metadata.retiredAt = metadata.retiredAt ?? Date()
                try? writeMetadata(metadata, to: directory)
            }
        } else if pasteboardHasTypes {
            for (directory, var metadata) in published {
                metadata.phase = .retired
                metadata.retiredAt = metadata.retiredAt ?? Date()
                try? writeMetadata(metadata, to: directory)
            }
        } else if let latest = published.max(by: { $0.1.createdAt < $1.1.createdAt }) {
            currentAssetID = latest.1.assetID
        }
    }

    private func observePasteboard(_ pasteboard: NSPasteboard) {
        guard let observedPasteboardChangeCount, pasteboard.changeCount != observedPasteboardChangeCount else { return }
        guard pasteboard.types != nil else { return }
        let newID = pasteboard.string(forType: Self.privatePasteboardType).flatMap(UUID.init(uuidString:))
        if let currentAssetID, newID != currentAssetID {
            retire(assetID: currentAssetID, at: Date())
            self.currentAssetID = nil
        }
        if let newID, assetDirectory(for: newID) != nil {
            currentAssetID = newID
        }
        self.observedPasteboardChangeCount = pasteboard.changeCount
    }

    private func retire(assetID: UUID, at date: Date) {
        guard let directory = assetDirectory(for: assetID), var metadata = readMetadataIfValid(in: directory), metadata.assetID == assetID else { return }
        metadata.phase = .retired
        metadata.retiredAt = date
        try? writeMetadata(metadata, to: directory)
    }

    private func assetDirectory(for id: UUID) -> URL? {
        let directory = rootURL.appending(path: id.uuidString, directoryHint: .isDirectory)
        guard isDirectChild(directory), isOrdinaryDirectory(directory),
              let metadata = readMetadataIfValid(in: directory), metadata.assetID == id
        else { return nil }
        return directory
    }

    private func isManagedAsset(_ asset: PreparedAsset) -> Bool {
        isDirectChild(asset.directoryURL) && isOrdinaryDirectory(asset.directoryURL)
            && asset.directoryURL.lastPathComponent == asset.metadata.assetID.uuidString
            && asset.imageURL.deletingLastPathComponent().standardizedFileURL == asset.directoryURL.standardizedFileURL
    }

    private func ensureRoot() throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard isOrdinaryDirectory(rootURL), chmod(rootURL.path, mode_t(S_IRWXU)) == 0 else { throw AssetStoreError.unsafeAsset }
    }

    private func writeMetadata(_ metadata: AssetMetadata, to directory: URL) throws {
        guard isDirectChild(directory), isOrdinaryDirectory(directory) else { throw AssetStoreError.unsafeAsset }
        let data = try JSONEncoder.assetEncoder.encode(metadata)
        let metadataURL = directory.appending(path: metadataFilename)
        try data.write(to: metadataURL, options: .atomic)
        guard chmod(metadataURL.path, mode_t(S_IRUSR | S_IWUSR)) == 0 else { throw AssetStoreError.unsafeAsset }
    }

    private func readMetadata(in directory: URL) throws -> AssetMetadata? {
        guard isDirectChild(directory), isOrdinaryDirectory(directory) else { return nil }
        let url = directory.appending(path: metadataFilename)
        guard fileManager.fileExists(atPath: url.path), try isOrdinaryFile(url) else { return nil }
        let metadata = try JSONDecoder.assetDecoder.decode(AssetMetadata.self, from: Data(contentsOf: url))
        guard metadata.schemaVersion == 1, metadata.assetID.uuidString == directory.lastPathComponent,
              isSafeImageName(metadata.relativeFilename)
        else { throw AssetStoreError.unsafeAsset }
        let imageURL = directory.appending(path: metadata.relativeFilename)
        if fileManager.fileExists(atPath: imageURL.path), try !isOrdinaryFile(imageURL) { throw AssetStoreError.unsafeAsset }
        return metadata
    }

    private func readMetadataIfValid(in directory: URL) -> AssetMetadata? {
        do {
            return try readMetadata(in: directory)
        } catch {
            return nil
        }
    }

    private func isDirectChild(_ url: URL) -> Bool {
        url.deletingLastPathComponent().standardizedFileURL == rootURL.standardizedFileURL
    }

    private func isOrdinaryDirectory(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return false }
        return values.isDirectory == true && values.isSymbolicLink != true
    }

    private func isOrdinaryFile(_ url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        return values.isRegularFile == true && values.isSymbolicLink != true
    }

    private func isSafeImageName(_ value: String?) -> Bool {
        guard let value, !value.isEmpty, value != ".", value != "..",
              !value.contains("/"), !value.contains("\\"), value.hasSuffix(".png")
        else { return false }
        return true
    }

    private func isPNG(_ data: Data) -> Bool {
        guard data.count >= 8, Array(data.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10],
              let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { return false }
        return CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
    }

    private func validDimensions(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0
        else { return false }
        return CaptureImageLimits.contains(width: width, height: height)
    }

    private func directorySize(at url: URL) throws -> UInt64 {
        let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey], options: [.skipsPackageDescendants])
        var total: UInt64 = 0
        while let item = enumerator?.nextObject() as? URL {
            let values = try item.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { enumerator?.skipDescendants() }
            if values.isRegularFile == true { total &+= UInt64(values.fileSize ?? 0) }
        }
        return total
    }

    private func uniqueFilename(startedAt: Date) -> String {
        let existingNames = Set((try? fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil))?.compactMap { directory in
            readMetadataIfValid(in: directory)?.relativeFilename
        } ?? [])
        var index = 1
        while existingNames.contains(FilenamePolicy.screenshotName(startedAt: startedAt, copyIndex: index == 1 ? nil : index)) {
            index += 1
        }
        return FilenamePolicy.screenshotName(startedAt: startedAt, copyIndex: index == 1 ? nil : index)
    }
}

private extension JSONEncoder {
    static var assetEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var assetDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
