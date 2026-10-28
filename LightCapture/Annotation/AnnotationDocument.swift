import AppKit
import CoreGraphics

struct AnnotationColor: Equatable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat

    static let red = AnnotationColor(red: 0.94, green: 0.18, blue: 0.20, alpha: 1)
    static let black = AnnotationColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1)
    static let white = AnnotationColor(red: 1, green: 1, blue: 1, alpha: 1)

    var cgColor: CGColor {
        CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [red, green, blue, alpha])!
    }

    var nsColor: NSColor {
        NSColor(cgColor: cgColor) ?? .labelColor
    }
}

enum AnnotationContent: Equatable {
    case rectangle(rect: CGRect, color: AnnotationColor, lineWidth: CGFloat)
    case ellipse(rect: CGRect, color: AnnotationColor, lineWidth: CGFloat)
    case arrow(start: CGPoint, end: CGPoint, color: AnnotationColor, lineWidth: CGFloat)
    case brush(points: [CGPoint], color: AnnotationColor, lineWidth: CGFloat)
    case text(rect: CGRect, value: String, fontSize: CGFloat, color: AnnotationColor)
    case mosaic(rect: CGRect, blockSize: CGFloat)
}

struct Annotation: Equatable, Identifiable {
    let id: UUID
    var content: AnnotationContent

    init(id: UUID = UUID(), content: AnnotationContent) {
        self.id = id
        self.content = content
    }

    var bounds: CGRect {
        switch content {
        case let .rectangle(rect, _, _), let .ellipse(rect, _, _), let .text(rect, _, _, _), let .mosaic(rect, _):
            rect.standardized
        case let .arrow(start, end, _, _):
            CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
        case let .brush(points, _, lineWidth):
            if let first = points.first {
                points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { bounds, point in
                    CGRect(x: min(bounds.minX, point.x), y: min(bounds.minY, point.y),
                           width: max(bounds.maxX, point.x) - min(bounds.minX, point.x),
                           height: max(bounds.maxY, point.y) - min(bounds.minY, point.y))
                }.insetBy(dx: -lineWidth / 2, dy: -lineWidth / 2)
            } else {
                .zero
            }
        }
    }

    func contains(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        switch content {
        case .rectangle, .text, .mosaic:
            return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        case .ellipse:
            return CGPath(ellipseIn: bounds.insetBy(dx: -tolerance, dy: -tolerance), transform: nil).contains(point)
        case let .arrow(start, end, _, lineWidth):
            let angle = atan2(end.y - start.y, end.x - start.x)
            let head = max(lineWidth * 4, 8)
            let wing = CGFloat.pi / 7
            let path = CGMutablePath()
            path.move(to: start)
            path.addLine(to: end)
            path.move(to: CGPoint(x: end.x - head * cos(angle - wing), y: end.y - head * sin(angle - wing)))
            path.addLine(to: end)
            path.addLine(to: CGPoint(x: end.x - head * cos(angle + wing), y: end.y - head * sin(angle + wing)))
            return path.copy(strokingWithWidth: lineWidth + tolerance * 2, lineCap: .round, lineJoin: .round, miterLimit: 1).contains(point)
        case let .brush(points, _, lineWidth):
            guard let first = points.first else { return false }
            let radius = lineWidth / 2 + tolerance
            if points.count == 1 { return hypot(point.x - first.x, point.y - first.y) <= radius }
            let path = CGMutablePath()
            path.addLines(between: points)
            return path.copy(strokingWithWidth: radius * 2, lineCap: .round, lineJoin: .round, miterLimit: 1).contains(point)
        }
    }

    func translated(dx: CGFloat, dy: CGFloat) -> Annotation {
        let content: AnnotationContent = switch self.content {
        case let .rectangle(rect, color, lineWidth):
            .rectangle(rect: rect.offsetBy(dx: dx, dy: dy), color: color, lineWidth: lineWidth)
        case let .ellipse(rect, color, lineWidth):
            .ellipse(rect: rect.offsetBy(dx: dx, dy: dy), color: color, lineWidth: lineWidth)
        case let .arrow(start, end, color, lineWidth):
            .arrow(
                start: CGPoint(x: start.x + dx, y: start.y + dy),
                end: CGPoint(x: end.x + dx, y: end.y + dy),
                color: color,
                lineWidth: lineWidth
            )
        case let .brush(points, color, lineWidth):
            .brush(points: points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }, color: color, lineWidth: lineWidth)
        case let .text(rect, value, fontSize, color):
            .text(rect: rect.offsetBy(dx: dx, dy: dy), value: value, fontSize: fontSize, color: color)
        case let .mosaic(rect, blockSize):
            .mosaic(rect: rect.offsetBy(dx: dx, dy: dy), blockSize: blockSize)
        }
        return Annotation(id: id, content: content)
    }
}

@MainActor
final class AnnotationDocument {
    let image: CGImage
    private(set) var cropRect: CGRect
    private(set) var annotations: [Annotation] = []
    private(set) var revision: UInt64 = 0
    private var undoStack: [AnnotationCommand] = []
    private var redoStack: [AnnotationCommand] = []

    init(image: CGImage, cropRect: CGRect? = nil) {
        self.image = image
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let initialCrop = cropRect?.standardized.integral.intersection(bounds) ?? bounds
        self.cropRect = initialCrop.width > 0 && initialCrop.height > 0 ? initialCrop : bounds
    }

    var canUndo: Bool {
        !undoStack.isEmpty
    }

    var canRedo: Bool {
        !redoStack.isEmpty
    }

    var hasUncommittedChanges: Bool {
        !annotations.isEmpty || cropRect != CGRect(x: 0, y: 0, width: image.width, height: image.height)
    }

    func add(_ annotation: Annotation) {
        record(.insert(annotation: annotation, index: annotations.count))
    }

    func remove(id: UUID) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        record(.remove(annotation: annotations[index], index: index))
    }

    func replace(_ annotation: Annotation) {
        guard let index = annotations.firstIndex(where: { $0.id == annotation.id }), annotations[index] != annotation else { return }
        record(.replace(old: annotations[index], new: annotation, index: index))
    }

    func setCropRect(_ rect: CGRect) {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let clipped = rect.standardized.intersection(bounds)
        guard clipped.width > 0, clipped.height > 0 else { return }
        let integral = CGRect(
            x: floor(clipped.minX),
            y: floor(clipped.minY),
            width: ceil(clipped.maxX) - floor(clipped.minX),
            height: ceil(clipped.maxY) - floor(clipped.minY)
        )
        guard integral != cropRect else { return }
        record(.crop(old: cropRect, new: integral))
    }

    @discardableResult
    func undo() -> Bool {
        guard let command = undoStack.popLast() else { return false }
        apply(command, forward: false)
        redoStack.append(command)
        return true
    }

    @discardableResult
    func redo() -> Bool {
        guard let command = redoStack.popLast() else { return false }
        apply(command, forward: true)
        undoStack.append(command)
        return true
    }

    func renderSnapshot() -> AnnotationRenderSnapshot {
        AnnotationRenderSnapshot(image: image, cropRect: cropRect, annotations: annotations, revision: revision)
    }

    private func record(_ command: AnnotationCommand) {
        apply(command, forward: true)
        undoStack.append(command)
        redoStack.removeAll(keepingCapacity: true)
    }

    private func apply(_ command: AnnotationCommand, forward: Bool) {
        switch command {
        case let .insert(annotation, index):
            if forward {
                annotations.insert(annotation, at: min(index, annotations.count))
            } else {
                annotations.removeAll { $0.id == annotation.id }
            }
        case let .remove(annotation, index):
            if forward {
                annotations.removeAll { $0.id == annotation.id }
            } else {
                annotations.insert(annotation, at: min(index, annotations.count))
            }
        case let .replace(old, new, index):
            let replacement = forward ? new : old
            if let current = annotations.firstIndex(where: { $0.id == replacement.id }) {
                annotations[current] = replacement
            } else {
                annotations.insert(replacement, at: min(index, annotations.count))
            }
        case let .crop(old, new):
            cropRect = forward ? new : old
        }
        revision &+= 1
    }
}

private enum AnnotationCommand {
    case insert(annotation: Annotation, index: Int)
    case remove(annotation: Annotation, index: Int)
    case replace(old: Annotation, new: Annotation, index: Int)
    case crop(old: CGRect, new: CGRect)
}

struct AnnotationRenderSnapshot: @unchecked Sendable {
    let image: CGImage
    let cropRect: CGRect
    let annotations: [Annotation]
    let revision: UInt64
}
