import AppKit
import Carbon.HIToolbox

enum AnnotationTool: Int, CaseIterable {
    case select
    case rectangle
    case ellipse
    case arrow
    case brush
    case mosaic
    case text
    case crop

    var title: String {
        switch self {
        case .select: L10n.toolSelect
        case .rectangle: L10n.toolRectangle
        case .ellipse: L10n.toolEllipse
        case .arrow: L10n.toolArrow
        case .brush: L10n.toolBrush
        case .text: L10n.toolText
        case .mosaic: L10n.toolMosaic
        case .crop: L10n.toolCrop
        }
    }

    var symbolName: String {
        switch self {
        case .select: "cursorarrow"
        case .rectangle: "rectangle"
        case .ellipse: "oval"
        case .arrow: "arrow.up.right"
        case .brush: "pencil.tip.crop.circle"
        case .text: "text.cursor"
        case .mosaic: "square.grid.3x3.fill"
        case .crop: "crop"
        }
    }
}

struct AnnotationStyle {
    var color: AnnotationColor = .red
    var lineWidth: CGFloat = 3
    var fontSize: CGFloat = 22
    var mosaicBlockSize: CGFloat = 12
}

@MainActor
final class AnnotationCanvasView: NSView {
    let document: AnnotationDocument
    var isInteractionEnabled = true
    var displayScale: CGFloat?
    var fillsBounds = false
    var passesMouseEventsThrough = false
    var style = AnnotationStyle()
    var tool: AnnotationTool = .select {
        didSet {
            if tool != oldValue {
                creationStart = nil
                creationEnd = nil
                brushPoints.removeAll(keepingCapacity: true)
                dragOriginal = nil
                dragPreview = nil
                selectedAnnotationID = nil
            }
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }

    var onTextRequest: ((CGRect, Annotation?) -> Void)?
    var onFinishTextEditing: (() -> Void)?
    var onDocumentChange: (() -> Void)?
    var onCancel: (() -> Void)?
    var onComplete: (() -> Void)?
    var onSaveRequested: (() -> Void)?

    private let baseImage: NSImage
    private var selectedAnnotationID: UUID?
    private var creationStart: CGPoint?
    private var creationEnd: CGPoint?
    private var brushPoints: [CGPoint] = []
    private var dragOriginal: Annotation?
    private var dragPreview: Annotation?
    private var dragStart = CGPoint.zero
    private var mosaicCache: [UUID: (content: AnnotationContent, image: CGImage)] = [:]

    override var isFlipped: Bool {
        true
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        passesMouseEventsThrough ? nil : super.hitTest(point)
    }

    override func resetCursorRects() {
        guard isInteractionEnabled, !passesMouseEventsThrough else { return }
        if dragOriginal != nil {
            addCursorRect(bounds, cursor: .closedHand)
            return
        }
        addCursorRect(bounds, cursor: tool == .text ? .iBeam : (tool == .select ? .arrow : .crosshair))
        guard tool != .crop else { return }
        let imageRect = aspectFitRect(size: document.cropRect.size)
        for annotation in document.annotations {
            let rect = viewRect(forPixelRect: annotation.bounds).insetBy(dx: -6, dy: -6).intersection(imageRect).intersection(bounds)
            if !rect.isEmpty { addCursorRect(rect, cursor: .openHand) }
        }
    }

    override func layout() {
        super.layout()
        if let editingRect = currentTextEditingRect, let textEditor = currentTextEditor {
            textEditor.frame = viewRect(forPixelRect: editingRect).insetBy(dx: -2, dy: -2)
            (textEditor as? AnnotationInputTextView)?.updateDisplayScale(aspectFitRect(size: document.cropRect.size).width / document.cropRect.width)
        }
    }

    private var currentTextEditor: NSView? {
        subviews.first { $0 is AnnotationInputTextView }
    }

    private var currentTextEditingRect: CGRect? {
        (currentTextEditor as? AnnotationInputTextView)?.pixelEditingRect
    }

    init(document: AnnotationDocument) {
        self.document = document
        baseImage = NSImage(cgImage: document.image, size: CGSize(width: document.image.width, height: document.image.height))
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override func draw(_: CGRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()

        let crop = document.cropRect
        let fittedImageRect = aspectFitRect(size: crop.size)
        if crop.origin == .zero, crop.size == CGSize(width: document.image.width, height: document.image.height) {
            baseImage.draw(in: fittedImageRect)
        } else if let cropped = document.image.cropping(topLeftRect: crop.integral) {
            NSImage(cgImage: cropped, size: CGSize(width: cropped.width, height: cropped.height)).draw(in: fittedImageRect)
        }

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: fittedImageRect).addClip()
        var items = document.annotations
        if let dragPreview, let index = items.firstIndex(where: { $0.id == dragPreview.id }) {
            items[index] = dragPreview
        }
        for annotation in items {
            draw(annotation)
        }
        drawCurrentPreview()
        if let selected = items.first(where: { $0.id == selectedAnnotationID }) {
            NSColor.controlAccentColor.setStroke()
            let outline = NSBezierPath(rect: viewRect(forPixelRect: selected.bounds).insetBy(dx: -4, dy: -4))
            outline.lineWidth = 1
            outline.setLineDash([4, 3], count: 2, phase: 0)
            outline.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    override func mouseDown(with event: NSEvent) {
        guard isInteractionEnabled else { return }
        onFinishTextEditing?()
        window?.makeFirstResponder(self)
        creationStart = nil
        creationEnd = nil
        brushPoints.removeAll(keepingCapacity: true)
        selectedAnnotationID = nil
        dragOriginal = nil
        dragPreview = nil
        needsDisplay = true
        let viewPoint = convert(event.locationInWindow, from: nil)
        guard aspectFitRect(size: document.cropRect.size).contains(viewPoint) else { return }
        let point = pixelPoint(from: viewPoint)
        // Option lets a drawing gesture start on an existing annotation.
        if tool != .crop, tool == .select || !event.modifierFlags.contains(.option),
           let hit = annotation(at: point)
        {
            selectedAnnotationID = hit.id
            if event.clickCount >= 2, case .text = hit.content {
                onTextRequest?(hit.bounds, hit)
                return
            }
            dragOriginal = hit
            dragStart = point
            NSCursor.closedHand.set()
            window?.invalidateCursorRects(for: self)
            return
        }
        switch tool {
        case .select:
            break
        case .brush:
            brushPoints = [point]
        case .rectangle, .ellipse, .arrow, .mosaic, .text, .crop:
            creationStart = point
            creationEnd = point
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isInteractionEnabled else { return }
        let point = pixelPoint(from: convert(event.locationInWindow, from: nil))
        if dragOriginal != nil {
            updateDragPreview(at: point)
        } else if tool == .brush, let last = brushPoints.last {
            // Keep the sampled gesture, including turns and retraced segments.
            // Mouse-up commits the whole stroke as a single history command.
            if hypot(point.x - last.x, point.y - last.y) >= 0.5 { brushPoints.append(point) }
        } else if creationStart != nil {
            creationEnd = point
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isInteractionEnabled else { return }
        let point = pixelPoint(from: convert(event.locationInWindow, from: nil))
        if tool == .select || dragOriginal != nil {
            updateDragPreview(at: point)
            if let dragPreview, let dragOriginal, dragPreview != dragOriginal {
                document.replace(dragPreview)
                onDocumentChange?()
            }
            dragOriginal = nil
            dragPreview = nil
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
            return
        }

        if tool == .brush {
            guard !brushPoints.isEmpty else { return }
            if brushPoints.last != point { brushPoints.append(point) }
            document.add(Annotation(content: .brush(points: brushPoints, color: style.color, lineWidth: style.lineWidth)))
            brushPoints.removeAll(keepingCapacity: true)
            onDocumentChange?()
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
            return
        }

        guard let start = creationStart else { return }
        let end = point
        creationStart = nil
        creationEnd = nil
        let rect = rect(from: start, to: end)
        if tool == .text, rect.width < 2, rect.height < 2 {
            let crop = document.cropRect
            let size = CGSize(width: min(style.fontSize * 12, crop.width), height: min(style.fontSize * 2.2, crop.height))
            onTextRequest?(CGRect(
                x: min(start.x, crop.maxX - size.width), y: min(start.y, crop.maxY - size.height),
                width: size.width, height: size.height
            ), nil)
            needsDisplay = true
            return
        }
        guard tool == .arrow ? hypot(end.x - start.x, end.y - start.y) >= 3 : (rect.width >= 2 && rect.height >= 2) else {
            needsDisplay = true
            return
        }

        switch tool {
        case .rectangle:
            document.add(Annotation(content: .rectangle(rect: rect, color: style.color, lineWidth: style.lineWidth)))
        case .ellipse:
            document.add(Annotation(content: .ellipse(rect: rect, color: style.color, lineWidth: style.lineWidth)))
        case .arrow:
            document.add(Annotation(content: .arrow(start: start, end: end, color: style.color, lineWidth: style.lineWidth)))
        case .text:
            onTextRequest?(rect, nil)
        case .mosaic:
            document.add(Annotation(content: .mosaic(rect: rect, blockSize: style.mosaicBlockSize)))
        case .crop:
            document.setCropRect(rect)
        case .select, .brush:
            break
        }
        onDocumentChange?()
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            onCancel?()
            return
        }
        guard isInteractionEnabled else { return }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "z" {
            if event.modifierFlags.contains(.shift) { _ = document.redo() } else { _ = document.undo() }
            onDocumentChange?()
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
            return
        }
        if event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete) {
            if let selectedAnnotationID {
                document.remove(id: selectedAnnotationID)
                self.selectedAnnotationID = nil
                onDocumentChange?()
                needsDisplay = true
                window?.invalidateCursorRects(for: self)
            }
            return
        }
        if event.keyCode == UInt16(kVK_Return)
            || (event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers?.lowercased() == "c")
        {
            onComplete?()
            return
        }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "s" {
            onSaveRequested?()
            return
        }
        super.keyDown(with: event)
    }

    func refresh() {
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
        onDocumentChange?()
    }

    func viewRect(forPixelRect rect: CGRect) -> CGRect {
        let crop = document.cropRect
        let imageRect = aspectFitRect(size: crop.size)
        let scale = imageRect.width / crop.width
        let scaleY = imageRect.height / crop.height
        return CGRect(
            x: imageRect.minX + (rect.minX - crop.minX) * scale,
            y: imageRect.minY + (rect.minY - crop.minY) * scaleY,
            width: rect.width * scale,
            height: rect.height * scaleY
        )
    }

    private func annotation(at point: CGPoint) -> Annotation? {
        let imageRect = aspectFitRect(size: document.cropRect.size)
        let scale = min(imageRect.width / document.cropRect.width, imageRect.height / document.cropRect.height)
        guard scale > 0 else { return nil }
        return document.annotations.reversed().first { annotation in
            if case .text = annotation.content { return annotation.bounds.contains(point) }
            return annotation.contains(point, tolerance: 6 / scale)
        }
    }

    private func updateDragPreview(at point: CGPoint) {
        guard let dragOriginal else { return }
        let bounds = dragOriginal.bounds
        let crop = document.cropRect
        let requestedX = point.x - dragStart.x
        let requestedY = point.y - dragStart.y
        // Include zero so selecting a partially cropped annotation never snaps it.
        // An annotation larger than the crop can pan between its two edges.
        let dx = min(max(requestedX, min(0, crop.minX - bounds.minX, crop.maxX - bounds.maxX)), max(0, crop.minX - bounds.minX, crop.maxX - bounds.maxX))
        let dy = min(max(requestedY, min(0, crop.minY - bounds.minY, crop.maxY - bounds.maxY)), max(0, crop.minY - bounds.minY, crop.maxY - bounds.maxY))
        dragPreview = dragOriginal.translated(dx: dx, dy: dy)
    }

    private func draw(_ annotation: Annotation) {
        let scale = aspectFitRect(size: document.cropRect.size).width / document.cropRect.width
        switch annotation.content {
        case let .rectangle(rect, color, lineWidth):
            let path = NSBezierPath(rect: viewRect(forPixelRect: rect).insetBy(dx: lineWidth * scale / 2, dy: lineWidth * scale / 2))
            path.lineWidth = max(lineWidth * scale, 1)
            color.nsColor.setStroke()
            path.stroke()
        case let .ellipse(rect, color, lineWidth):
            let width = min(lineWidth, min(rect.width, rect.height) / 2)
            let path = NSBezierPath(ovalIn: viewRect(forPixelRect: rect).insetBy(dx: width * scale / 2, dy: width * scale / 2))
            path.lineWidth = max(width * scale, 1)
            color.nsColor.setStroke()
            path.stroke()
        case let .arrow(start, end, color, lineWidth):
            let a = viewPoint(fromPixelPoint: start)
            let b = viewPoint(fromPixelPoint: end)
            drawArrow(from: a, to: b, color: color.nsColor, width: max(lineWidth * scale, 1))
        case let .brush(points, color, lineWidth):
            drawBrush(points: points, color: color.nsColor, width: max(lineWidth * scale, 1))
        case let .text(rect, value, fontSize, color):
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont(name: "PingFangSC-Regular", size: fontSize * scale) ?? NSFont.systemFont(ofSize: fontSize * scale),
                .foregroundColor: color.nsColor,
            ]
            (value as NSString).draw(in: viewRect(forPixelRect: rect).insetBy(dx: 3 * scale, dy: 3 * scale), withAttributes: attributes)
        case let .mosaic(rect, blockSize):
            let mosaic: CGImage
            if let cached = mosaicCache[annotation.id], cached.content == annotation.content {
                mosaic = cached.image
            } else if let generated = AnnotationRenderer.pixelatedRegion(document.image, topLeftRect: rect, blockSize: blockSize) {
                mosaicCache[annotation.id] = (annotation.content, generated)
                mosaic = generated
            } else {
                return
            }
            NSImage(cgImage: mosaic, size: CGSize(width: mosaic.width, height: mosaic.height)).draw(in: viewRect(forPixelRect: rect))
        }
    }

    private func drawCurrentPreview() {
        if tool == .brush {
            let scale = aspectFitRect(size: document.cropRect.size).width / document.cropRect.width
            drawBrush(points: brushPoints, color: style.color.nsColor, width: max(style.lineWidth * scale, 1))
            return
        }
        guard let creationStart, let creationEnd else { return }
        let rect = rect(from: creationStart, to: creationEnd)
        if tool == .ellipse {
            if rect.width >= 2, rect.height >= 2 {
                draw(Annotation(content: .ellipse(rect: rect, color: style.color, lineWidth: style.lineWidth)))
            }
            return
        }
        NSColor.systemBlue.setStroke()
        let outline = NSBezierPath(rect: viewRect(forPixelRect: rect))
        outline.lineWidth = 1
        outline.setLineDash([4, 3], count: 2, phase: 0)
        outline.stroke()
        if tool == .arrow {
            drawArrow(
                from: viewPoint(fromPixelPoint: creationStart),
                to: viewPoint(fromPixelPoint: creationEnd),
                color: .systemBlue,
                width: 2
            )
        }
    }

    private func drawBrush(points: [CGPoint], color: NSColor, width: CGFloat) {
        guard let first = points.first else { return }
        let start = viewPoint(fromPixelPoint: first)
        if points.count == 1 {
            color.setFill()
            NSBezierPath(ovalIn: CGRect(x: start.x - width / 2, y: start.y - width / 2, width: width, height: width)).fill()
            return
        }
        let path = NSBezierPath()
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: start)
        for point in points.dropFirst() {
            path.line(to: viewPoint(fromPixelPoint: point))
        }
        color.setStroke()
        path.stroke()
    }

    private func drawArrow(from start: CGPoint, to end: CGPoint, color: NSColor, width: CGFloat) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 0.1 else { return }
        let angle = atan2(dy, dx)
        let head = max(width * 4, 8)
        let wing = CGFloat.pi / 7
        let left = CGPoint(x: end.x - head * cos(angle - wing), y: end.y - head * sin(angle - wing))
        let right = CGPoint(x: end.x - head * cos(angle + wing), y: end.y - head * sin(angle + wing))
        let path = NSBezierPath()
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: start)
        path.line(to: end)
        path.move(to: left)
        path.line(to: end)
        path.line(to: right)
        color.setStroke()
        path.stroke()
    }

    private func aspectFitRect(size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        if fillsBounds { return bounds }
        let scale = displayScale ?? min(bounds.width / size.width, bounds.height / size.height)
        let width = size.width * scale
        let height = size.height * scale
        return CGRect(x: (bounds.width - width) / 2, y: (bounds.height - height) / 2, width: width, height: height)
    }

    private func pixelPoint(from viewPoint: CGPoint) -> CGPoint {
        let imageRect = aspectFitRect(size: document.cropRect.size)
        let scale = imageRect.width / document.cropRect.width
        let scaleY = imageRect.height / document.cropRect.height
        let x = min(max(document.cropRect.minX + (viewPoint.x - imageRect.minX) / scale, document.cropRect.minX), document.cropRect.maxX)
        let y = min(max(document.cropRect.minY + (viewPoint.y - imageRect.minY) / scaleY, document.cropRect.minY), document.cropRect.maxY)
        return CGPoint(x: x, y: y)
    }

    private func viewPoint(fromPixelPoint point: CGPoint) -> CGPoint {
        let crop = document.cropRect
        let imageRect = aspectFitRect(size: crop.size)
        let scale = imageRect.width / crop.width
        let scaleY = imageRect.height / crop.height
        return CGPoint(x: imageRect.minX + (point.x - crop.minX) * scale, y: imageRect.minY + (point.y - crop.minY) * scaleY)
    }

    private func rect(from first: CGPoint, to second: CGPoint) -> CGRect {
        CGRect(x: min(first.x, second.x), y: min(first.y, second.y), width: abs(second.x - first.x), height: abs(second.y - first.y))
    }
}

@MainActor
final class AnnotationInputTextView: NSTextView {
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?
    var pixelEditingRect: CGRect?
    var pixelFontSize: CGFloat = 22

    func updateDisplayScale(_ scale: CGFloat) {
        let size = max(pixelFontSize * scale, 0.1)
        font = NSFont(name: "PingFangSC-Regular", size: size) ?? NSFont.systemFont(ofSize: size)
        textContainerInset = CGSize(width: 3 * scale, height: 3 * scale)
        textContainer?.lineFragmentPadding = 0
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            onCancel?()
            return
        }
        if event.keyCode == UInt16(kVK_Return), !hasMarkedText() {
            if event.modifierFlags.contains(.shift) {
                super.keyDown(with: event)
            } else {
                onCommit?()
            }
            return
        }
        super.keyDown(with: event)
    }

    override func cancelOperation(_: Any?) {
        onCancel?()
    }
}
