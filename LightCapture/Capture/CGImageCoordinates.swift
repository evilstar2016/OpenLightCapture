import CoreGraphics

enum CaptureImageLimits {
    static let maximumPixels = 60_000_000
    static let maximumHeight = 50000

    static func contains(width: Int, height: Int) -> Bool {
        width > 0 && height > 0 && height <= maximumHeight && width <= maximumPixels / height
    }
}

extension CGImage {
    /// Crops using the app's canonical top-left pixel coordinates.
    func cropping(topLeftRect rect: CGRect) -> CGImage? {
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let clipped = rect.standardized.intersection(bounds)
        guard clipped.width > 0, clipped.height > 0 else { return nil }
        // CGImage cropping uses image pixels from the top left. Only drawing
        // into an unflipped CGContext needs the Quartz bottom-left transform.
        return cropping(to: clipped.integral.intersection(bounds))
    }

    func thumbnail(maxPixelSize: CGSize) -> CGImage? {
        guard maxPixelSize.width > 0, maxPixelSize.height > 0 else { return nil }
        let scale = min(maxPixelSize.width / CGFloat(width), maxPixelSize.height / CGFloat(height), 1)
        let thumbnailWidth = max(1, Int((CGFloat(width) * scale).rounded(.down)))
        let thumbnailHeight = max(1, Int((CGFloat(height) * scale).rounded(.down)))
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: thumbnailWidth,
            height: thumbnailHeight,
            bitsPerComponent: 8,
            bytesPerRow: thumbnailWidth * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .low
        context.draw(self, in: CGRect(x: 0, y: 0, width: thumbnailWidth, height: thumbnailHeight))
        return context.makeImage()
    }
}
