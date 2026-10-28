import AppKit
import ImageIO
import UniformTypeIdentifiers

@MainActor
final class OutputDeliveryService {
    typealias PNGEncoder = @Sendable (CGImage) async throws -> Data
    private let publisher: ClipboardPublisher
    private let encoder: PNGEncoder
    var onPublished: (() -> Void)?

    init(assetStore: AssetStore, pasteboard: NSPasteboard = .general, encoder: @escaping PNGEncoder = OutputDeliveryService.encodePNG) {
        publisher = ClipboardPublisher(assetStore: assetStore, pasteboard: pasteboard)
        self.encoder = encoder
    }

    func copy(_ image: CGImage, startedAt: Date, isCurrent: @MainActor () -> Bool = { true }) async -> Bool {
        guard isCurrent(), !Task.isCancelled else { return false }
        do {
            let data = try await encoder(image)
            guard isCurrent(), !Task.isCancelled else { return false }
            _ = try publisher.publish(pngData: data, startedAt: startedAt)
            onPublished?()
            return true
        } catch {
            guard isCurrent(), !Task.isCancelled else { return false }
            showError(L10n.errorCopyTitle, detail: error.localizedDescription)
            return false
        }
    }

    func saveAndCopy(_ image: CGImage, startedAt: Date, parentWindow: NSWindow?, isCurrent: @MainActor () -> Bool = { true }) async -> Bool {
        guard isCurrent(), !Task.isCancelled else { return false }
        let data: Data
        do {
            data = try await encoder(image)
        } catch {
            guard isCurrent(), !Task.isCancelled else { return false }
            showError(L10n.errorPngTitle, detail: error.localizedDescription)
            return false
        }

        guard isCurrent(), !Task.isCancelled,
              let destination = await chooseSaveDestination(startedAt: startedAt, parentWindow: parentWindow),
              isCurrent(), !Task.isCancelled
        else { return false }
        do {
            try data.write(to: destination, options: .atomic)
        } catch {
            showError(L10n.errorSaveTitle, detail: error.localizedDescription)
            return false
        }

        do {
            _ = try publisher.publish(pngData: data, startedAt: startedAt)
            onPublished?()
            return true
        } catch {
            showError(L10n.errorSavedCopyTitle, detail: L10n.errorSavedCopyDetail(destination.lastPathComponent, error.localizedDescription))
            return false
        }
    }

    nonisolated static func encodePNG(_ image: CGImage) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            try encodePNGSynchronously(image)
        }.value
    }

    nonisolated static func encodePNGSynchronously(_ image: CGImage) throws -> Data {
        try autoreleasepool {
            let source = removingRedundantAlpha(from: image)
            let properties: CFDictionary? = switch source.alphaInfo {
            case .none, .noneSkipFirst, .noneSkipLast:
                [kCGImagePropertyPNGDictionary: [kCGImagePropertyPNGCompressionFilter: IMAGEIO_PNG_FILTER_NONE]] as CFDictionary
            default: nil
            }
            // Repeated growth of ImageIO's output buffer retains substantial
            // VM memory on the current system. Reserve a bounded raw-pixel
            // budget up front; compressed output can still grow if needed.
            let capacity = CaptureImageLimits.contains(width: source.width, height: source.height)
                ? source.width * source.height * 4 + source.height + 65536 : 0
            guard let data = NSMutableData(capacity: capacity) else { throw PNGEncodingError.destinationUnavailable }
            guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
                throw PNGEncodingError.destinationUnavailable
            }
            CGImageDestinationAddImage(destination, source, properties)
            guard CGImageDestinationFinalize(destination) else { throw PNGEncodingError.encodingFailed }
            return data as Data
        }
    }

    private nonisolated static func removingRedundantAlpha(from image: CGImage) -> CGImage {
        // The renderer emits RGBA; native captures can use little-endian
        // BGRA. Both layouts store alpha in byte 3. Other layouts retain the
        // original ImageIO path, including genuine transparency.
        guard image.bitsPerComponent == 8, image.bitsPerPixel == 32,
              let space = image.colorSpace, space.model == .rgb,
              let provider = image.dataProvider, let data = provider.data,
              let bytes = CFDataGetBytePtr(data)
        else { return image }
        let order = image.bitmapInfo.intersection(.byteOrderMask)
        let opaqueAlpha: CGImageAlphaInfo
        if order == .byteOrder32Big, image.alphaInfo == .premultipliedLast || image.alphaInfo == .last {
            opaqueAlpha = .noneSkipLast
        } else if order == .byteOrder32Little, image.alphaInfo == .premultipliedFirst || image.alphaInfo == .first {
            opaqueAlpha = .noneSkipFirst
        } else {
            return image
        }
        let (byteCount, overflow) = image.bytesPerRow.multipliedReportingOverflow(by: image.height)
        guard !overflow, CFDataGetLength(data) >= byteCount else { return image }
        for y in 0 ..< image.height {
            let row = bytes.advanced(by: y * image.bytesPerRow)
            for x in 0 ..< image.width where row[x * 4 + 3] != 255 {
                return image
            }
        }
        let bitmapInfo = CGBitmapInfo(rawValue: (image.bitmapInfo.rawValue & ~CGBitmapInfo.alphaInfoMask.rawValue) | opaqueAlpha.rawValue)
        return CGImage(width: image.width, height: image.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: image.bytesPerRow,
                       space: space, bitmapInfo: bitmapInfo, provider: provider, decode: image.decode,
                       shouldInterpolate: image.shouldInterpolate, intent: image.renderingIntent) ?? image
    }

    private func chooseSaveDestination(startedAt: Date, parentWindow: NSWindow?) async -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = FilenamePolicy.screenshotName(startedAt: startedAt)

        if let parentWindow {
            return await withCheckedContinuation { continuation in
                panel.beginSheetModal(for: parentWindow) { response in
                    continuation.resume(returning: response == .OK ? panel.url : nil)
                }
            }
        }
        return await withCheckedContinuation { continuation in
            panel.begin { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
        }
    }

    private func showError(_ title: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.actionOk)
        alert.runModal()
    }
}

private enum PNGEncodingError: LocalizedError {
    case destinationUnavailable
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .destinationUnavailable: L10n.errorPngDestination
        case .encodingFailed: L10n.errorPngEncoding
        }
    }
}
