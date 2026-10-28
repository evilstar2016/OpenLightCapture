import CoreGraphics
import Foundation

enum OverlapMatch: Equatable {
    case unchanged
    case accepted(verticalDisplacement: Int, horizontalDrift: Int, replacingBottomRows: Int = 0)
    case ambiguous(String)
}

enum OverlapMatcher {
    static func match(previous: CGImage, current: CGImage) async -> OverlapMatch {
        await Task.detached(priority: .userInitiated) {
            matchSynchronously(previous: previous, current: current)
        }.value
    }

    private static func matchSynchronously(previous: CGImage, current: CGImage) -> OverlapMatch {
        guard previous.width == current.width, previous.height == current.height else {
            return .ambiguous(L10n.matchSizeChanged)
        }
        let width = previous.width
        let height = previous.height
        let (pixelCount, overflow) = width.multipliedReportingOverflow(by: height)
        guard !overflow, pixelCount <= 60_000_000 else { return .ambiguous(L10n.matchImageLimit) }
        guard let old = RGBAFrame(image: previous), let new = RGBAFrame(image: current) else {
            return .ambiguous(L10n.matchPixelsUnavailable)
        }
        if old.equals(new) { return .unchanged }
        guard height >= 8, width >= 3 else { return .ambiguous(L10n.matchSelectionTooSmall) }

        // A detected narrow scrollbar cannot vote for an offset. Do not blindly
        // ignore the edge: text or a changed join there must still be verified.
        let contentWidth = width - scrollbarWidth(old, new)
        if contentWidth < width, contentIsUnchanged(old, new, contentWidth: contentWidth) { return .unchanged }
        let oldTexture = TextureMap(frame: old, contentWidth: contentWidth)
        let newTexture = TextureMap(frame: new, contentWidth: contentWidth)
        guard oldTexture.supportsAlignment, newTexture.supportsAlignment else {
            return .ambiguous(L10n.matchInsufficientContent)
        }
        var matchedDisplacement: Int?
        var matchedReplacement = 0
        for displacement in 0 ... height * 3 / 4 {
            guard sampleAgrees(old, new, oldTexture: oldTexture, newTexture: newTexture,
                               displacement: displacement, contentWidth: contentWidth),
                let replacement = overlapReplacement(old, new, oldTexture: oldTexture, newTexture: newTexture,
                                                     displacement: displacement, contentWidth: contentWidth)
            else { continue }
            // Do not choose the first plausible offset on repeated/near-repeated text.
            guard matchedDisplacement == nil else {
                return .ambiguous(L10n.matchRepeatedContent)
            }
            matchedDisplacement = displacement
            matchedReplacement = replacement
        }
        guard let matchedDisplacement else {
            return .ambiguous(L10n.matchOverlapLost)
        }
        return matchedDisplacement == 0 ? .unchanged : .accepted(verticalDisplacement: matchedDisplacement, horizontalDrift: 0, replacingBottomRows: matchedReplacement)
    }

    private static func sampleAgrees(_ old: RGBAFrame, _ new: RGBAFrame, oldTexture: TextureMap, newTexture: TextureMap, displacement: Int, contentWidth: Int) -> Bool {
        let overlap = old.height - displacement
        let xStep = max(1, contentWidth / 48)
        let yStep = max(1, overlap / 48)
        var samples = 0
        var differences = 0
        var features = 0
        var featureDifferences = 0
        let sampleCount = ((contentWidth + xStep - 1) / xStep) * ((overlap + yStep - 1) / yStep)
        for y in stride(from: 0, to: overlap, by: yStep) {
            for x in stride(from: 0, to: contentWidth, by: xStep) {
                let different = differs(old.pixel(x: x, y: y + displacement), new.pixel(x: x, y: y))
                samples += 1
                if different {
                    differences += 1
                    if differences * 100 > sampleCount * 8 { return false }
                }
                if oldTexture.pixels[(y + displacement) * old.width + x] || newTexture.pixels[y * old.width + x] {
                    features += 1
                    if different { featureDifferences += 1 }
                }
            }
        }
        // This is only a prefilter. Every surviving offset is checked at full resolution.
        return differences * 100 <= samples * 8 && (features < 8 || featureDifferences * 100 <= features * 10)
    }

    private static func overlapReplacement(_ old: RGBAFrame, _ new: RGBAFrame, oldTexture: TextureMap, newTexture: TextureMap, displacement: Int, contentWidth: Int) -> Int? {
        let overlap = old.height - displacement
        let pixelCount = contentWidth * overlap
        var differences = 0
        var features = 0
        var featureDifferences = 0
        var matchedFeatures = 0
        var supportedBands: UInt8 = 0
        var minFeatureX = contentWidth
        var maxFeatureX = 0
        var minFeatureY = overlap
        var maxFeatureY = 0
        let changeCellSize = 8
        let changeColumns = (contentWidth + changeCellSize - 1) / changeCellSize
        var changedCells: Set<Int> = []
        var changedRows: Set<Int> = []
        let seamHeight = min(24, max(4, overlap / 10))
        for y in 0 ..< overlap {
            for x in 0 ..< contentWidth {
                let isFeature = oldTexture.pixels[(y + displacement) * old.width + x] || newTexture.pixels[y * old.width + x]
                if isFeature { features += 1 }
                if differs(old.pixel(x: x, y: y + displacement), new.pixel(x: x, y: y)) {
                    differences += 1
                    if isFeature { featureDifferences += 1 }
                    if differences > max(1, pixelCount / 100) { return nil }
                    changedCells.insert((y / changeCellSize) * changeColumns + x / changeCellSize)
                    changedRows.insert(y)
                } else if isFeature {
                    matchedFeatures += 1
                    supportedBands |= 1 << min(3, y * 4 / overlap)
                    minFeatureX = min(minFeatureX, x)
                    maxFeatureX = max(maxFeatureX, x)
                    minFeatureY = min(minFeatureY, y)
                    maxFeatureY = max(maxFeatureY, y)
                }
            }
        }
        // White margins cannot outvote misaligned sparse text: check the union
        // of edges in BOTH frames, not just the proportion of matching background.
        guard matchedFeatures >= 32, featureDifferences * 100 <= features * 3,
              supportedBands.nonzeroBitCount >= 2,
              maxFeatureY - minFeatureY >= overlap / 3,
              maxFeatureX - minFeatureX >= min(48, contentWidth / 6)
        else { return nil }
        if differences > max(1, pixelCount / 1000) {
            // Spellcheck marks and hover/caret changes can be far apart. Their
            // combined bounding box may span the document even though each
            // change is small. Bound the SUM of connected regions instead;
            // sparse changes throughout the text still exhaust this budget.
            guard changesAreLocalized(changedCells, columns: changeColumns,
                                      cellSize: changeCellSize, areaLimit: pixelCount / 20)
            else { return nil }
        }
        if displacement == 0 { return 0 }
        // Keep a fully matching band before the join. If a native decoration
        // changed there, move the join upward and replace that short stored
        // tail with aligned rows from this frame, preserving the exact height.
        for replacement in 0 ... min(96, overlap / 4) {
            let join = overlap - replacement
            if (max(0, join - seamHeight) ..< join).allSatisfy({ !changedRows.contains($0) }) {
                return replacement
            }
        }
        return nil
    }

    private static func changesAreLocalized(_ changedCells: Set<Int>, columns: Int, cellSize: Int, areaLimit: Int) -> Bool {
        var remaining = changedCells
        var totalArea = 0
        while let start = remaining.popFirst() {
            var pending = [start]
            var head = 0
            var minX = start % columns
            var maxX = minX
            var minY = start / columns
            var maxY = minY
            while head < pending.count {
                let cell = pending[head]
                head += 1
                let x = cell % columns
                let y = cell / columns
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
                for nextY in max(0, y - 1) ... y + 1 {
                    for nextX in max(0, x - 1) ... min(columns - 1, x + 1) {
                        let neighbor = nextY * columns + nextX
                        if remaining.remove(neighbor) != nil { pending.append(neighbor) }
                    }
                }
            }
            totalArea += (maxX - minX + 1) * (maxY - minY + 1) * cellSize * cellSize
            if totalArea > areaLimit { return false }
        }
        return true
    }

    private static func contentIsUnchanged(_ old: RGBAFrame, _ new: RGBAFrame, contentWidth: Int) -> Bool {
        old.bytes.withUnsafeBytes { lhs in
            new.bytes.withUnsafeBytes { rhs in
                for y in 0 ..< old.height {
                    let offset = y * old.width * 4
                    if memcmp(lhs.baseAddress!.advanced(by: offset), rhs.baseAddress!.advanced(by: offset), contentWidth * 4) != 0 { return false }
                }
                return true
            }
        }
    }

    private static func scrollbarWidth(_ old: RGBAFrame, _ new: RGBAFrame) -> Int {
        guard old.width >= 200, old.height >= 100 else { return 0 }
        let edgeWidth = min(24, old.width / 50)
        var thumbColumns = 0
        for x in old.width - edgeWidth ..< old.width {
            for frame in [old, new] {
                var minimum = 255
                var maximum = 0
                for y in 0 ..< frame.height {
                    let pixel = frame.pixel(x: x, y: y)
                    let red = Int(pixel >> 24)
                    let green = Int((pixel >> 16) & 255)
                    let blue = Int((pixel >> 8) & 255)
                    guard max(red, green, blue) - min(red, green, blue) <= 8 else { return 0 }
                    minimum = min(minimum, red)
                    maximum = max(maximum, red)
                }
                if maximum - minimum <= 12 { continue }
                let midpoint = (minimum + maximum) / 2
                var transitions = 0
                var lastClass: Bool?
                var runLength = 0
                var shortestRun = frame.height
                for y in 0 ..< frame.height {
                    let isLight = Int(frame.pixel(x: x, y: y) >> 24) > midpoint
                    if let lastClass, lastClass != isLight {
                        transitions += 1
                        shortestRun = min(shortestRun, runLength)
                        runLength = 0
                    }
                    lastClass = isLight
                    runLength += 1
                }
                shortestRun = min(shortestRun, runLength)
                // A thumb is one long vertical run, not the many short strokes
                // of document text. Uniform neighbouring track columns are allowed.
                guard transitions <= 2, shortestRun >= min(20, frame.height / 10) else { return 0 }
                thumbColumns += 1
            }
        }
        return thumbColumns >= min(4, edgeWidth) ? edgeWidth : 0
    }

    private static func differs(_ lhs: UInt32, _ rhs: UInt32, tolerance: Int = 3) -> Bool {
        abs(Int(lhs >> 24) - Int(rhs >> 24)) > tolerance
            || abs(Int((lhs >> 16) & 255) - Int((rhs >> 16) & 255)) > tolerance
            || abs(Int((lhs >> 8) & 255) - Int((rhs >> 8) & 255)) > tolerance
            || abs(Int(lhs & 255) - Int(rhs & 255)) > tolerance
    }

    private struct TextureMap {
        let pixels: [Bool]
        let supportsAlignment: Bool

        init(frame: RGBAFrame, contentWidth: Int) {
            var pixels = [Bool](repeating: false, count: frame.width * frame.height)
            var count = 0
            var minX = contentWidth
            var maxX = 0
            var minY = frame.height
            var maxY = 0
            for y in 0 ..< frame.height {
                for x in 0 ..< contentWidth {
                    let pixel = frame.pixel(x: x, y: y)
                    let textured = differs(pixel, frame.pixel(x: min(x + 1, contentWidth - 1), y: y), tolerance: 12)
                        || differs(pixel, frame.pixel(x: x, y: min(y + 1, frame.height - 1)), tolerance: 12)
                    pixels[y * frame.width + x] = textured
                    if textured {
                        count += 1
                        minX = min(minX, x)
                        maxX = max(maxX, x)
                        minY = min(minY, y)
                        maxY = max(maxY, y)
                    }
                }
            }
            self.pixels = pixels
            // Necessary support even at the smallest allowed overlap. Besides
            // rejecting unreliable blank captures, this avoids scanning every
            // full-resolution offset for a blinking caret on an empty page.
            supportsAlignment = count >= 32 && maxX - minX >= min(48, contentWidth / 6)
                && maxY - minY >= frame.height / 12
        }
    }
}

struct RGBAFrame {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init?(image: CGImage) {
        width = image.width
        height = image.height
        let (bytesPerRow, rowOverflow) = image.width.multipliedReportingOverflow(by: 4)
        let (byteCount, overflow) = bytesPerRow.multipliedReportingOverflow(by: image.height)
        guard !rowOverflow, !overflow else { return nil }
        var pixels = [UInt8](repeating: 0, count: byteCount)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue))
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress,
                  let context = CGContext(
                      data: baseAddress,
                      width: image.width,
                      height: image.height,
                      bitsPerComponent: 8,
                      bytesPerRow: bytesPerRow,
                      space: colorSpace,
                      bitmapInfo: bitmapInfo.rawValue
                  )
            else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard rendered else { return nil }
        bytes = pixels
    }

    static func make(image: CGImage) async -> RGBAFrame? {
        await Task.detached(priority: .userInitiated) { RGBAFrame(image: image) }.value
    }

    func pixel(x: Int, y: Int) -> UInt32 {
        let offset = (y * width + x) * 4
        return UInt32(bytes[offset]) << 24
            | UInt32(bytes[offset + 1]) << 16
            | UInt32(bytes[offset + 2]) << 8
            | UInt32(bytes[offset + 3])
    }

    func equals(_ other: RGBAFrame) -> Bool {
        width == other.width && height == other.height && bytes == other.bytes
    }

    func bottomRows(from startY: Int, count rowCount: Int) -> Data? {
        guard startY >= 0, rowCount > 0, startY + rowCount <= height else { return nil }
        let start = startY * width * 4
        let end = (startY + rowCount) * width * 4
        return Data(bytes[start ..< end])
    }
}
