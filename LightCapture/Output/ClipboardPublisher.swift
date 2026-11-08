import AppKit
import Foundation

enum ClipboardPublishError: LocalizedError {
    case pasteboardRejected
    case emptyText

    var errorDescription: String? {
        switch self {
        case .pasteboardRejected: L10n.errorClipboardRejected
        case .emptyText: L10n.ocrEmpty
        }
    }
}

@MainActor
final class ClipboardPublisher {
    private let assetStore: AssetStore
    private let pasteboard: NSPasteboard

    init(assetStore: AssetStore, pasteboard: NSPasteboard = .general) {
        self.assetStore = assetStore
        self.pasteboard = pasteboard
    }

    func publish(text: String) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ClipboardPublishError.emptyText }
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else { throw ClipboardPublishError.pasteboardRejected }
    }

    func publish(pngData: Data, startedAt: Date) throws -> PreparedAsset {
        let asset = try assetStore.prepare(pngData: pngData, startedAt: startedAt)
        return try publish(asset)
    }

    func prepareGIF(_ result: GIFResult, startedAt: Date, isCurrent: @MainActor () -> Bool) async throws -> PreparedAsset {
        try await assetStore.prepareGIF(result, startedAt: startedAt, isCurrent: isCurrent)
    }

    func discard(_ asset: PreparedAsset) {
        assetStore.discard(asset)
    }

    func publish(_ asset: PreparedAsset) throws -> PreparedAsset {
        guard asset.format != .mp4 else { throw AssetStoreError.unsafeAsset }
        let item = NSPasteboardItem()
        item.setData(asset.encodedData, forType: asset.format == .png ? AssetStore.pngPasteboardType : AssetStore.gifPasteboardType)
        item.setString(asset.imageURL.absoluteString, forType: .fileURL)
        item.setString(asset.metadata.assetID.uuidString, forType: AssetStore.privatePasteboardType)

        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else {
            if pasteboard.string(forType: AssetStore.privatePasteboardType) == asset.metadata.assetID.uuidString {
                try? assetStore.markPublished(asset, changeCount: pasteboard.changeCount)
            } else {
                assetStore.discard(asset)
            }
            throw ClipboardPublishError.pasteboardRejected
        }
        do {
            try assetStore.markPublished(asset, changeCount: pasteboard.changeCount)
        } catch {
            // The already-published URL must remain available even if metadata could not be updated.
        }
        return asset
    }
}
