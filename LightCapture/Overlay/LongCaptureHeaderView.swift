import AppKit
import Carbon.HIToolbox

@MainActor
final class LongCaptureHeaderView: NSView {
    private(set) var headerHeight: CGFloat = 64
    private var isDragging = false
    var onUnhandledKeyDown: ((NSEvent) -> Void)?

    static func canConfigure(in size: CGSize) -> Bool {
        size.width >= 48 && size.height >= 80
    }

    override var isFlipped: Bool {
        true
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = NSUserInterfaceItemIdentifier("capture.long.headerBoundary")
        toolTip = L10n.longHeaderHelp
        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
        setAccessibilityLabel(L10n.longKeepHeader)
        setAccessibilityHelp(L10n.longHeaderHelp)
    }

    required init?(coder _: NSCoder) {
        nil
    }

    func setHeaderHeight(_ height: CGFloat) {
        guard height.isFinite else { return }
        headerHeight = min(max(8, height), max(8, bounds.height - 64))
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        if !isHidden {
            addCursorRect(boundaryRect, cursor: .resizeUpDown)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, let parent = superview else { return nil }
        return boundaryRect.contains(convert(point, from: parent)) ? self : nil
    }

    override func draw(_: NSRect) {
        NSColor.controlAccentColor.withAlphaComponent(0.16).setFill()
        NSBezierPath(rect: CGRect(x: 0, y: 0, width: bounds.width, height: headerHeight)).fill()
        NSColor.controlAccentColor.setStroke()
        let line = NSBezierPath()
        line.move(to: CGPoint(x: 0, y: headerHeight))
        line.line(to: CGPoint(x: bounds.width, y: headerHeight))
        line.lineWidth = 2
        line.stroke()

        let handle = NSBezierPath(roundedRect: CGRect(x: bounds.midX - 18, y: headerHeight - 4, width: 36, height: 8), xRadius: 4, yRadius: 4)
        NSColor.white.setFill()
        handle.fill()
        handle.lineWidth = 2
        handle.stroke()

        let labelRect = CGRect(x: 4, y: max(1, headerHeight - 28), width: max(1, bounds.width - 8), height: 20)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let text = L10n.longHeaderBoundary as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
        ]
        let width = min(labelRect.width, text.size(withAttributes: attributes).width + 16)
        let background = CGRect(x: labelRect.midX - width / 2, y: labelRect.minY, width: width, height: labelRect.height)
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: background, xRadius: 4, yRadius: 4).fill()
        text.draw(in: background.insetBy(dx: 6, dy: 2), withAttributes: attributes)
    }

    override func mouseDown(with _: NSEvent) {
        guard !isHidden else { return }
        window?.makeFirstResponder(self)
        isDragging = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        setHeaderHeight(convert(event.locationInWindow, from: nil).y)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        isDragging = false
    }

    override func keyDown(with event: NSEvent) {
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        switch Int(event.keyCode) {
        case kVK_UpArrow: setHeaderHeight(headerHeight - step)
        case kVK_DownArrow: setHeaderHeight(headerHeight + step)
        default: onUnhandledKeyDown?(event)
        }
    }

    override func accessibilityValue() -> Any? {
        headerHeight
    }

    override func accessibilityMinValue() -> Any? {
        CGFloat(8)
    }

    override func accessibilityMaxValue() -> Any? {
        max(8, bounds.height - 64)
    }

    override func accessibilityPerformIncrement() -> Bool {
        setHeaderHeight(headerHeight + 1)
        return true
    }

    override func accessibilityPerformDecrement() -> Bool {
        setHeaderHeight(headerHeight - 1)
        return true
    }

    private var boundaryRect: CGRect {
        CGRect(x: 0, y: headerHeight - 10, width: bounds.width, height: 20).intersection(bounds)
    }
}
