import AppKit

struct SelectionToolbarLayout {
    let toolbar: CGRect
    let palette: CGRect
    let sizeBadge: CGRect

    init(bounds: CGRect, selection: CGRect, toolbarSize: CGSize, paletteSize: CGSize, badgeSize: CGSize) {
        let margin: CGFloat = 8
        let gap: CGFloat = 8
        let width = min(toolbarSize.width, max(1, bounds.width - margin * 2))
        let totalHeight = toolbarSize.height + (paletteSize.height > 0 ? paletteSize.height + 6 : 0)
        let x = min(max(selection.maxX - width, bounds.minX + margin), max(bounds.minX + margin, bounds.maxX - width - margin))
        let below = selection.maxY + gap
        let above = selection.minY - totalHeight - gap
        let y: CGFloat = if below + totalHeight <= bounds.maxY - margin {
            below
        } else if above >= bounds.minY + margin {
            above
        } else {
            max(bounds.minY + margin, bounds.maxY - totalHeight - margin)
        }
        toolbar = CGRect(x: x, y: y, width: width, height: toolbarSize.height)
        palette = CGRect(x: x, y: toolbar.maxY + 6, width: min(paletteSize.width, max(1, bounds.width - margin * 2)), height: paletteSize.height)
        let badgeY = selection.minY - badgeSize.height - 6
        sizeBadge = CGRect(
            x: min(max(selection.minX, bounds.minX + margin), max(bounds.minX + margin, bounds.maxX - badgeSize.width - margin)),
            y: max(bounds.minY + margin, badgeY), width: badgeSize.width, height: badgeSize.height
        )
    }
}

@MainActor
class CaptureToolbarPlate: NSStackView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // The overlay positions these floating stacks manually. A required
        // autoresizing width would fight their changing intrinsic content size
        // when contextual controls are shown or hidden.
        translatesAutoresizingMaskIntoConstraints = false
        orientation = .horizontal
        alignment = .centerY
        distribution = .fill
        detachesHiddenViews = true
        spacing = 4
        edgeInsets = NSEdgeInsets(top: 5, left: 7, bottom: 5, right: 7)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.16
        layer?.shadowRadius = 7
        layer?.shadowOffset = CGSize(width: 0, height: -2)
    }

    required init?(coder _: NSCoder) {
        nil
    }

    func updateColors(appearance: NSAppearance) {
        appearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.98).cgColor
            layer?.borderColor = NSColor.separatorColor.cgColor
        }
    }
}

@MainActor
final class AnnotationColorButton: NSButton {
    let annotationColor: AnnotationColor

    init(color: AnnotationColor, name: String) {
        annotationColor = color
        super.init(frame: CGRect(x: 0, y: 0, width: 24, height: 26))
        title = ""
        isBordered = false
        setButtonType(.toggle)
        toolTip = name
        setAccessibilityLabel(name)
        widthAnchor.constraint(equalToConstant: 24).isActive = true
        heightAnchor.constraint(equalToConstant: 26).isActive = true
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override func draw(_: NSRect) {
        let face = NSBezierPath(ovalIn: bounds.insetBy(dx: 5, dy: 6))
        annotationColor.nsColor.setFill()
        face.fill()
        NSColor.separatorColor.setStroke()
        face.lineWidth = 1
        face.stroke()
        if state == .on {
            NSColor.controlAccentColor.setStroke()
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 2, dy: 3))
            ring.lineWidth = 2
            ring.stroke()
        }
    }
}
