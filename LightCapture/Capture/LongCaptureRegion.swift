import CoreGraphics

/// The header is retained in the first output tile, but excluded from alignment.
/// All dimensions here are native capture pixels, independent of display scale.
struct LongCaptureRegion: Equatable {
    let fixedHeaderHeight: Int

    init(fixedHeaderHeight: Int = 0) {
        self.fixedHeaderHeight = fixedHeaderHeight
    }

    func bodyRect(width: Int, height: Int) -> CGRect? {
        guard width > 0, height > 0,
              fixedHeaderHeight >= 0, fixedHeaderHeight < height,
              fixedHeaderHeight == 0 || height - fixedHeaderHeight >= 8
        else { return nil }
        return CGRect(x: 0, y: fixedHeaderHeight, width: width, height: height - fixedHeaderHeight)
    }

    func bodyScreenRect(selectionPixelRect: CGRect, transform: DisplayTransform) -> CGRect? {
        guard selectionPixelRect.minX.isFinite, selectionPixelRect.minY.isFinite,
              selectionPixelRect.width.isFinite, selectionPixelRect.height.isFinite,
              selectionPixelRect.width > 0, selectionPixelRect.width <= CGFloat(CaptureImageLimits.maximumPixels),
              selectionPixelRect.height > 0, selectionPixelRect.height <= CGFloat(CaptureImageLimits.maximumHeight),
              let body = bodyRect(width: Int(selectionPixelRect.width), height: Int(selectionPixelRect.height))
        else { return nil }
        return transform.globalScreenRect(fromPixelRect: body.offsetBy(dx: selectionPixelRect.minX, dy: selectionPixelRect.minY))
    }
}
