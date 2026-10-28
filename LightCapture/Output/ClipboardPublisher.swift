import AppKit
import Foundation

enum ClipboardPublishError: LocalizedError {
    case pasteboardRejected

    var errorDescription: String? {
        L10n.errorClipboardRejected
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

    func publish(pngData: Data, startedAt: Date) throws -> PreparedAsset {
        let asset = try assetStore.prepare(pngData: pngData, startedAt: startedAt)
        let item = NSPasteboardItem()
        item.setData(asset.pngData, forType: AssetStore.pngPasteboardType)
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
