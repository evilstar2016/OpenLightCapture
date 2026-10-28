import CoreGraphics
import CoreImage
import CoreText

enum AnnotationRenderError: LocalizedError {
    case invalidCrop
    case allocationFailed
    case mosaicFailed

    var errorDescription: String? {
        switch self {
        case .invalidCrop: L10n.errorInvalidCrop
        case .allocationFailed: L10n.errorRenderMemory
        case .mosaicFailed: L10n.errorMosaic
        }
    }
}

enum AnnotationRenderer {
    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    static func render(_ snapshot: AnnotationRenderSnapshot) async throws -> CGImage {
        try await Task.detached(priority: .userInitiated) {
            try autoreleasepool { try renderSynchronously(snapshot) }
        }.value
    }

    static func renderSynchronously(_ snapshot: AnnotationRenderSnapshot) throws -> CGImage {
        let crop = snapshot.cropRect.integral.intersection(CGRect(x: 0, y: 0, width: snapshot.image.width, height: snapshot.image.height))
        guard crop.width > 0, crop.height > 0,
              let base = snapshot.image.cropping(topLeftRect: crop)
        else {
            throw AnnotationRenderError.invalidCrop
        }

        let width = base.width
        let height = base.height
        let (pixelCount, overflow) = width.multipliedReportingOverflow(by: height)
        guard !overflow, pixelCount <= CaptureImageLimits.maximumPixels,
              CaptureImageLimits.contains(width: width, height: height)
        else { throw AnnotationRenderError.allocationFailed }
        // Cropping alone needs no new full-sized bitmap or color conversion.
        // Preserve the native profile and transparency when there are no marks.
        if snapshot.annotations.isEmpty { return base }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            throw AnnotationRenderError.allocationFailed
        }
        context.interpolationQuality = .none
        context.draw(base, in: CGRect(x: 0, y: 0, width: width, height: height))

        let relativeAnnotations = snapshot.annotations.map { $0.translated(dx: -crop.minX, dy: -crop.minY) }
        for annotation in relativeAnnotations {
            switch annotation.content {
            case let .rectangle(rect, color, lineWidth):
                context.setStrokeColor(color.cgColor)
                context.setLineWidth(lineWidth)
                context.stroke(quartzRect(rect, imageHeight: height).insetBy(dx: lineWidth / 2, dy: lineWidth / 2))
            case let .ellipse(rect, color, lineWidth):
                let width = min(lineWidth, min(rect.width, rect.height) / 2)
                context.setStrokeColor(color.cgColor)
                context.setLineWidth(width)
                context.strokeEllipse(in: quartzRect(rect, imageHeight: height).insetBy(dx: width / 2, dy: width / 2))
            case let .arrow(start, end, color, lineWidth):
                drawArrow(start: start, end: end, color: color, lineWidth: lineWidth, in: context, imageHeight: height)
            case let .brush(points, color, lineWidth):
                guard let first = points.first else { continue }
                context.saveGState()
                context.setStrokeColor(color.cgColor)
                context.setFillColor(color.cgColor)
                context.setLineWidth(lineWidth)
                context.setLineCap(.round)
                context.setLineJoin(.round)
                if points.count == 1 {
                    let point = quartzPoint(first, imageHeight: height)
                    context.fillEllipse(in: CGRect(x: point.x - lineWidth / 2, y: point.y - lineWidth / 2, width: lineWidth, height: lineWidth))
                } else {
                    context.beginPath()
                    context.addLines(between: points.map { quartzPoint($0, imageHeight: height) })
                    context.strokePath()
                }
                context.restoreGState()
            case let .text(rect, value, fontSize, color):
                drawText(value, in: quartzRect(rect, imageHeight: height), fontSize: fontSize, color: color, in: context)
            case let .mosaic(rect, blockSize):
                let sourceRect = rect.offsetBy(dx: crop.minX, dy: crop.minY).standardized
                    .intersection(CGRect(x: 0, y: 0, width: snapshot.image.width, height: snapshot.image.height))
                let imageRect = sourceRect.offsetBy(dx: -crop.minX, dy: -crop.minY)
                guard !imageRect.intersection(CGRect(x: 0, y: 0, width: width, height: height)).isEmpty else { continue }
                // Keep the filter anchored in original image coordinates. A
                // crop must not change the mosaic pattern seen in the editor.
                guard let mosaic = pixelatedRegion(snapshot.image, topLeftRect: sourceRect, blockSize: blockSize) else {
                    throw AnnotationRenderError.mosaicFailed
                }
                context.saveGState()
                context.interpolationQuality = .none
                context.draw(mosaic, in: quartzRect(imageRect, imageHeight: height))
                context.restoreGState()
            }
        }

        guard let output = context.makeImage() else { throw AnnotationRenderError.allocationFailed }
        return output
    }

    static func pixelatedRegion(_ image: CGImage, topLeftRect: CGRect, blockSize: CGFloat) -> CGImage? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let clipped = topLeftRect.standardized.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard clipped.width > 0, clipped.height > 0 else { return nil }
        let filterRect = quartzRect(clipped, imageHeight: Int(image.height)).integral
        let source = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIPixellate") else { return nil }
        filter.setValue(source, forKey: kCIInputImageKey)
        filter.setValue(max(blockSize, 2), forKey: kCIInputScaleKey)
        filter.setValue(CIVector(x: filterRect.midX, y: filterRect.midY), forKey: kCIInputCenterKey)
        guard let output = filter.outputImage?.cropped(to: filterRect) else { return nil }
        return ciContext.createCGImage(output, from: filterRect)
    }

    private static func drawArrow(
        start: CGPoint,
        end: CGPoint,
        color: AnnotationColor,
        lineWidth: CGFloat,
        in context: CGContext,
        imageHeight: Int
    ) {
        let startPoint = quartzPoint(start, imageHeight: imageHeight)
        let endPoint = quartzPoint(end, imageHeight: imageHeight)
        let dx = endPoint.x - startPoint.x
        let dy = endPoint.y - startPoint.y
        let length = hypot(dx, dy)
        guard length > 0.01 else { return }

        let angle = atan2(dy, dx)
        let headLength = max(lineWidth * 4, 8)
        let wing = CGFloat.pi / 7
        let left = CGPoint(x: endPoint.x - headLength * cos(angle - wing), y: endPoint.y - headLength * sin(angle - wing))
        let right = CGPoint(x: endPoint.x - headLength * cos(angle + wing), y: endPoint.y - headLength * sin(angle + wing))

        context.setStrokeColor(color.cgColor)
        context.setFillColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.beginPath()
        context.move(to: startPoint)
        context.addLine(to: endPoint)
        context.move(to: left)
        context.addLine(to: endPoint)
        context.addLine(to: right)
        context.strokePath()
    }

    private static func drawText(_ value: String, in rect: CGRect, fontSize: CGFloat, color: AnnotationColor, in context: CGContext) {
        let font = CTFontCreateWithName("PingFangSC-Regular" as CFString, fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor,
        ]
        let attributedString = NSAttributedString(string: value, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        let path = CGPath(rect: rect.insetBy(dx: 3, dy: 3), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        context.saveGState()
        context.textMatrix = .identity
        CTFrameDraw(frame, context)
        context.restoreGState()
    }

    private static func quartzRect(_ topLeftRect: CGRect, imageHeight: Int) -> CGRect {
        CGRect(
            x: topLeftRect.minX,
            y: CGFloat(imageHeight) - topLeftRect.maxY,
            width: topLeftRect.width,
            height: topLeftRect.height
        )
    }

    private static func quartzPoint(_ topLeftPoint: CGPoint, imageHeight: Int) -> CGPoint {
        CGPoint(x: topLeftPoint.x, y: CGFloat(imageHeight) - topLeftPoint.y)
    }
}
