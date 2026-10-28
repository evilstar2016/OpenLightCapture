import CoreGraphics
import Foundation

enum TileStoreError: LocalizedError {
    case invalidGeometry
    case capacityReached
    case insufficientStorage
    case missingBaseImage
    case tileCorrupted
    case unsafeWorkspace
    case fileSystem(Error)

    var errorDescription: String? {
        switch self {
        case .invalidGeometry: L10n.tileInvalidDimensions
        case .capacityReached: L10n.tileCapacity
        case .insufficientStorage: L10n.tileStorage
        case .missingBaseImage: L10n.tileNoFrames
        case .tileCorrupted: L10n.tileUnreadable
        case .unsafeWorkspace: L10n.tileUnsafe
        case let .fileSystem(error): L10n.tileFile(error.localizedDescription)
        }
    }
}

@MainActor
final class TileStore {
    static func cleanupAbandonedWorkspaces(rootURL: URL? = nil) {
        let root = rootURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appending(path: Bundle.main.bundleIdentifier ?? "io.github.evilstar2016.openlightcapture", directoryHint: .isDirectory)
            .appending(path: "Working", directoryHint: .isDirectory)
        guard isOrdinaryDirectory(root),
              let children = try? FileManager.default.contentsOfDirectory(
                  at: root,
                  includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                  options: [.skipsHiddenFiles]
              ) else { return }
        for child in children {
            guard UUID(uuidString: child.lastPathComponent) != nil,
                  let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true
            else { continue }
            try? FileManager.default.removeItem(at: child)
        }
    }

    private struct Tile {
        let filename: String
        let byteCount: Int
        let height: Int
    }

    private let directoryURL: URL
    private let rootURL: URL
    private let width: Int
    private var tiles: [Tile] = []
    private(set) var totalHeight = 0
    private(set) var lastSequence: UInt64?
    private var storedBytes = 0

    init(width: Int, sessionID: UUID, rootURL: URL? = nil) throws {
        guard width > 0 else { throw TileStoreError.invalidGeometry }
        self.width = width
        let root: URL = if let rootURL {
            rootURL
        } else {
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appending(path: Bundle.main.bundleIdentifier ?? "io.github.evilstar2016.openlightcapture", directoryHint: .isDirectory)
                .appending(path: "Working", directoryHint: .isDirectory)
        }
        self.rootURL = root
        directoryURL = root.appending(path: sessionID.uuidString, directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            guard Self.isOrdinaryDirectory(root), chmod(root.path, mode_t(S_IRWXU)) == 0,
                  mkdir(directoryURL.path, mode_t(S_IRWXU)) == 0
            else { throw TileStoreError.unsafeWorkspace }
        } catch let error as TileStoreError {
            throw error
        } catch {
            throw TileStoreError.fileSystem(error)
        }
    }

    func appendFirstFrame(_ frame: RGBAFrame) throws {
        guard tiles.isEmpty, frame.width == width, frame.height > 0 else { throw TileStoreError.invalidGeometry }
        try append(data: Data(frame.bytes), height: frame.height, sequence: 0)
    }

    @discardableResult
    func appendBottomRows(from frame: RGBAFrame, startY: Int, count: Int, sequence: UInt64, replacingBottomRows: Int = 0) throws -> Bool {
        guard frame.width == width, frame.height > 0,
              replacingBottomRows >= 0, replacingBottomRows <= totalHeight, count > replacingBottomRows,
              let bytes = frame.bottomRows(from: startY, count: count)
        else { throw TileStoreError.invalidGeometry }
        if let lastSequence, sequence <= lastSequence { return false }
        try append(data: bytes, height: count, sequence: sequence, replacingBottomRows: replacingBottomRows)
        return true
    }

    func renderImage() throws -> CGImage {
        guard hasSafeWorkspace else { throw TileStoreError.unsafeWorkspace }
        guard !tiles.isEmpty, totalHeight > 0 else { throw TileStoreError.missingBaseImage }
        let (pixelCount, overflow) = width.multipliedReportingOverflow(by: totalHeight)
        guard !overflow, CaptureImageLimits.contains(width: width, height: totalHeight), pixelCount <= CaptureImageLimits.maximumPixels else { throw TileStoreError.capacityReached }
        let (bytesPerRow, rowOverflow) = width.multipliedReportingOverflow(by: 4)
        let (byteCount, byteOverflow) = bytesPerRow.multipliedReportingOverflow(by: totalHeight)
        guard !rowOverflow, !byteOverflow else { throw TileStoreError.capacityReached }

        var fullImageData = Data(count: byteCount)
        var cursor = 0
        do {
            for tile in tiles {
                let data = try Data(contentsOf: directoryURL.appending(path: tile.filename), options: .mappedIfSafe)
                let visibleBytes = width * tile.height * 4
                guard data.count == tile.byteCount, visibleBytes <= data.count else { throw TileStoreError.tileCorrupted }
                fullImageData.replaceSubrange(cursor ..< cursor + visibleBytes, with: data.prefix(visibleBytes))
                cursor += visibleBytes
            }
        } catch let error as TileStoreError {
            throw error
        } catch {
            throw TileStoreError.fileSystem(error)
        }
        guard cursor == fullImageData.count else { throw TileStoreError.tileCorrupted }
        let provider = CGDataProvider(data: fullImageData as CFData)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue))
        guard let provider,
              let image = CGImage(
                  width: width,
                  height: totalHeight,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: bytesPerRow,
                  space: colorSpace,
                  bitmapInfo: bitmapInfo,
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              )
        else { throw TileStoreError.tileCorrupted }
        try? FileManager.default.removeItem(at: directoryURL)
        return image
    }

    func cancel() {
        if hasSafeWorkspace { try? FileManager.default.removeItem(at: directoryURL) }
        tiles.removeAll(keepingCapacity: false)
        storedBytes = 0
        totalHeight = 0
        lastSequence = nil
    }

    private func append(data: Data, height: Int, sequence: UInt64, replacingBottomRows: Int = 0) throws {
        guard hasSafeWorkspace else { throw TileStoreError.unsafeWorkspace }
        guard height > 0 else { throw TileStoreError.invalidGeometry }
        let (nextHeight, heightOverflow) = (totalHeight - replacingBottomRows).addingReportingOverflow(height)
        let (pixelCount, pixelOverflow) = width.multipliedReportingOverflow(by: nextHeight)
        guard !heightOverflow, !pixelOverflow, CaptureImageLimits.contains(width: width, height: nextHeight), pixelCount <= CaptureImageLimits.maximumPixels else {
            throw TileStoreError.capacityReached
        }
        let (nextStoredBytes, bytesOverflow) = storedBytes.addingReportingOverflow(data.count)
        guard !bytesOverflow, nextStoredBytes <= 2 * 1024 * 1024 * 1024 else { throw TileStoreError.insufficientStorage }
        if let values = try? directoryURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let available = values.volumeAvailableCapacityForImportantUsage,
           available < Int64(data.count)
        {
            throw TileStoreError.insufficientStorage
        }

        guard data.count == width * height * 4 else { throw TileStoreError.invalidGeometry }
        let filename = String(format: "%08llu.rgba", sequence)
        let fileURL = directoryURL.appending(path: filename)
        do {
            try writeTile(data, to: fileURL)
        } catch {
            throw TileStoreError.fileSystem(error)
        }
        // Commit metadata only after the new tile is durable. Old files remain
        // immutable and counted in storedBytes until session cleanup, so a failed
        // write cannot discard confirmed rows and temporary disk use stays bounded.
        var remaining = replacingBottomRows
        while remaining > 0, let tail = tiles.popLast() {
            if tail.height > remaining {
                tiles.append(Tile(filename: tail.filename, byteCount: tail.byteCount, height: tail.height - remaining))
                remaining = 0
            } else {
                remaining -= tail.height
            }
        }
        tiles.append(Tile(filename: filename, byteCount: data.count, height: height))
        totalHeight = nextHeight
        storedBytes = nextStoredBytes
        lastSequence = sequence
    }

    private var hasSafeWorkspace: Bool {
        Self.isOrdinaryDirectory(rootURL) && Self.isOrdinaryDirectory(directoryURL)
    }

    private static func isOrdinaryDirectory(_ url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return false }
        return attributes[.type] as? FileAttributeType == .typeDirectory
    }

    private func writeTile(_ topDownData: Data, to destination: URL) throws {
        let temporary = directoryURL.appending(path: ".\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        do {
            let handle = try FileHandle(forWritingTo: temporary)
            defer { try? handle.close() }
            try handle.write(contentsOf: topDownData)
            try handle.synchronize()
            try handle.close()
            try FileManager.default.moveItem(at: temporary, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }
}
