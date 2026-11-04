import CoreGraphics
import CoreText
import Foundation

/// All geometry is in final image pixels, in an unflipped Quartz context.
struct WatermarkLayout {
    let selection: WatermarkSelection
    let outputSize: CGSize
    let fontSize: CGFloat
    let unitSize: CGSize
    let rotatedSize: CGSize
    let lines: [CTLine]
    let lineWidths: [CGFloat]
    let ascent: CGFloat
    let lineHeight: CGFloat

    init(selection: WatermarkSelection, outputSize: CGSize) throws {
        try selection.validate()
        guard outputSize.width.isFinite, outputSize.height.isFinite,
              outputSize.width > 0, outputSize.height > 0,
              outputSize.width <= 60_000_000, outputSize.height <= 50000
        else { throw WatermarkError.tooSmall }
        let shortSide = min(outputSize.width, outputSize.height)
        var size = max(6, shortSide * selection.style.fontRatio)
        var measured = Self.measure(selection, fontSize: size)
        let radians = selection.style.angle * .pi / 180
        func rotated(_ unit: CGSize) -> CGSize {
            CGSize(width: abs(cos(radians)) * unit.width + abs(sin(radians)) * unit.height,
                   height: abs(sin(radians)) * unit.width + abs(cos(radians)) * unit.height)
        }
        if selection.style.mode == .single {
            let margin = shortSide * selection.style.marginRatio
            let bounds = rotated(measured.size)
            let factor = min(1, (outputSize.width - margin * 2) / bounds.width, (outputSize.height - margin * 2) / bounds.height)
            size *= factor
            guard size >= 6 - 0.0001 else { throw WatermarkError.tooSmall }
            measured = Self.measure(selection, fontSize: size)
        }
        self.selection = selection
        self.outputSize = outputSize
        fontSize = size
        unitSize = measured.size
        rotatedSize = rotated(measured.size)
        lines = measured.lines
        lineWidths = measured.widths
        ascent = measured.ascent
        lineHeight = size * 1.3
    }

    private static func measure(_ selection: WatermarkSelection, fontSize: CGFloat) -> (size: CGSize, lines: [CTLine], widths: [CGFloat], ascent: CGFloat) {
        let font = CTFontCreateWithName("PingFangSC-Regular" as CFString, fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): selection.style.color.cgColor(opacity: 1),
        ]
        let lines = selection.lines.map {
            CTLineCreateWithAttributedString(NSAttributedString(string: $0, attributes: attributes))
        }
        let widths = lines.map { CGFloat(CTLineGetTypographicBounds($0, nil, nil, nil)) }
        return (CGSize(width: max(1, widths.max() ?? 1), height: fontSize * 1.3 * CGFloat(lines.count)), lines, widths, CTFontGetAscent(font))
    }
}

enum WatermarkRenderer {
    static func draw(_ layout: WatermarkLayout, in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        context.clip(to: CGRect(origin: .zero, size: layout.outputSize))
        context.setAlpha(layout.selection.style.opacity)
        context.textMatrix = .identity
        let style = layout.selection.style
        let shortSide = min(layout.outputSize.width, layout.outputSize.height)
        if style.mode == .single {
            let margin = shortSide * style.marginRatio
            let xs = [margin + layout.rotatedSize.width / 2, layout.outputSize.width / 2, layout.outputSize.width - margin - layout.rotatedSize.width / 2]
            let ys = [layout.outputSize.height - margin - layout.rotatedSize.height / 2, layout.outputSize.height / 2, margin + layout.rotatedSize.height / 2]
            drawUnit(layout, center: CGPoint(x: xs[style.anchor.column], y: ys[style.anchor.row]), in: context)
        } else {
            let stepX = layout.rotatedSize.width + shortSide * style.horizontalGapRatio
            let stepY = layout.rotatedSize.height + shortSide * style.verticalGapRatio
            let visible = context.boundingBoxOfClipPath.intersection(CGRect(origin: .zero, size: layout.outputSize))
            guard !visible.isNull else { return }
            // Iterate only visible cells; never allocate a full-image pattern bitmap.
            let firstColumn = Int(floor((visible.minX - layout.rotatedSize.width) / stepX))
            let lastColumn = Int(ceil((visible.maxX + layout.rotatedSize.width) / stepX))
            let firstRow = Int(floor((layout.outputSize.height - visible.maxY - layout.rotatedSize.height) / stepY))
            let lastRow = Int(ceil((layout.outputSize.height - visible.minY + layout.rotatedSize.height) / stepY))
            for row in firstRow ... lastRow {
                for column in firstColumn ... lastColumn {
                    drawUnit(layout, center: CGPoint(x: CGFloat(column) * stepX + layout.rotatedSize.width / 2,
                                                     y: layout.outputSize.height - CGFloat(row) * stepY - layout.rotatedSize.height / 2), in: context)
                }
            }
        }
    }

    private static func drawUnit(_ layout: WatermarkLayout, center: CGPoint, in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: layout.selection.style.angle * .pi / 180)
        for (index, line) in layout.lines.enumerated() {
            context.textPosition = CGPoint(x: -layout.lineWidths[index] / 2,
                                           y: layout.unitSize.height / 2 - layout.ascent - CGFloat(index) * layout.lineHeight)
            CTLineDraw(line, context)
        }
    }
}

/// A canvas owns its cache; background output rendering constructs its own layout.
@MainActor
final class WatermarkPreviewCache {
    private var selection: WatermarkSelection?
    private var size = CGSize.zero
    private var layout: WatermarkLayout?

    func resolve(_ selection: WatermarkSelection, size: CGSize) throws -> WatermarkLayout {
        if self.selection == selection, self.size == size, let layout { return layout }
        let layout = try WatermarkLayout(selection: selection, outputSize: size)
        self.selection = selection
        self.size = size
        self.layout = layout
        return layout
    }
}
