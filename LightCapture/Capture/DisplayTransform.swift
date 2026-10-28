import CoreGraphics

struct DisplayTransform: Equatable {
    let screenFrame: CGRect
    let pixelWidth: Int
    let pixelHeight: Int

    init(screenFrame: CGRect, pixelWidth: Int, pixelHeight: Int) throws {
        guard screenFrame.origin.x.isFinite, screenFrame.origin.y.isFinite,
              screenFrame.width.isFinite, screenFrame.height.isFinite,
              screenFrame.width > 0,
              screenFrame.height > 0,
              pixelWidth > 0,
              pixelHeight > 0
        else {
            throw DisplayTransformError.invalidGeometry
        }
        self.screenFrame = screenFrame
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    init(screenFrame: CGRect, capturePointSize: CGSize, pointPixelScale: CGFloat) throws {
        let width = (capturePointSize.width * pointPixelScale).rounded()
        let height = (capturePointSize.height * pointPixelScale).rounded()
        guard pointPixelScale.isFinite, pointPixelScale > 0,
              width.isFinite, height.isFinite,
              width > 0, height > 0, width < CGFloat(Int.max), height < CGFloat(Int.max)
        else { throw DisplayTransformError.invalidGeometry }
        try self.init(screenFrame: screenFrame, pixelWidth: Int(width), pixelHeight: Int(height))
    }

    static func appKitRect(fromQuartzRect rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    var pixelBounds: CGRect {
        CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
    }

    func pixelRect(fromGlobalScreenRect rect: CGRect) -> CGRect? {
        let screenRect = rect.standardized.intersection(screenFrame)
        guard screenRect.width > 0, screenRect.height > 0 else { return nil }

        let scaleX = CGFloat(pixelWidth) / screenFrame.width
        let scaleY = CGFloat(pixelHeight) / screenFrame.height
        let left = floor((screenRect.minX - screenFrame.minX) * scaleX)
        let top = floor((screenFrame.maxY - screenRect.maxY) * scaleY)
        let right = ceil((screenRect.maxX - screenFrame.minX) * scaleX)
        let bottom = ceil((screenFrame.maxY - screenRect.minY) * scaleY)
        let pixels = CGRect(x: left, y: top, width: right - left, height: bottom - top)
            .intersection(pixelBounds)
        guard pixels.width > 0, pixels.height > 0 else { return nil }
        return pixels
    }

    func globalScreenRect(fromPixelRect rect: CGRect) -> CGRect? {
        let pixels = rect.standardized.intersection(pixelBounds)
        guard pixels.width > 0, pixels.height > 0 else { return nil }

        let scaleX = CGFloat(pixelWidth) / screenFrame.width
        let scaleY = CGFloat(pixelHeight) / screenFrame.height
        return CGRect(
            x: screenFrame.minX + pixels.minX / scaleX,
            y: screenFrame.maxY - pixels.maxY / scaleY,
            width: pixels.width / scaleX,
            height: pixels.height / scaleY
        )
    }

    func localTopLeftRect(fromGlobalScreenRect rect: CGRect) -> CGRect? {
        let screenRect = rect.standardized.intersection(screenFrame)
        guard screenRect.width > 0, screenRect.height > 0 else { return nil }
        return CGRect(
            x: screenRect.minX - screenFrame.minX,
            y: screenFrame.maxY - screenRect.maxY,
            width: screenRect.width,
            height: screenRect.height
        )
    }

    func globalScreenRect(fromLocalTopLeftRect rect: CGRect) -> CGRect? {
        let localBounds = CGRect(origin: .zero, size: screenFrame.size)
        let localRect = rect.standardized.intersection(localBounds)
        guard localRect.width > 0, localRect.height > 0 else { return nil }
        return CGRect(
            x: screenFrame.minX + localRect.minX,
            y: screenFrame.maxY - localRect.maxY,
            width: localRect.width,
            height: localRect.height
        )
    }
}

enum DisplayTransformError: Error, Equatable {
    case invalidGeometry
}
