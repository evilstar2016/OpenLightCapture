import AppKit

@MainActor
enum AnnotationToolbarStyle {
    static let tools: [AnnotationTool] = [.crop, .select, .rectangle, .ellipse, .arrow, .brush, .mosaic, .text]

    static func button(_ symbol: String, title: String, target: AnyObject, action: Selector, width: CGFloat = 30) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: title) ?? NSImage(), target: target, action: action)
        button.title = title
        button.identifier = NSUserInterfaceItemIdentifier("capture.action.\(symbol)")
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.isBordered = false
        button.toolTip = title
        button.setAccessibilityLabel(title)
        button.widthAnchor.constraint(equalToConstant: width).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        button.contentTintColor = .labelColor
        return button
    }

    static func toolButton(_ tool: AnnotationTool, target: AnyObject, action: Selector) -> NSButton {
        let title: String = switch tool {
        case .crop: L10n.toolAdjustSelection
        case .select: L10n.toolSelectAnnotation
        default: tool.title
        }
        let button = Self.button(tool.symbolName, title: title, target: target, action: action, width: tool == .text ? max(44, (title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium)]).width + 16) : 30)
        if tool == .text {
            button.image = nil
            button.imagePosition = .noImage
            button.font = .systemFont(ofSize: 12, weight: .medium)
            button.toolTip = L10n.toolTextHelp
        }
        button.tag = tool.rawValue
        button.identifier = NSUserInterfaceItemIdentifier("capture.annotation.tool.\(tool.rawValue)")
        button.setButtonType(.toggle)
        return button
    }

    static func update(_ button: NSButton, selected: Bool, enabled: Bool) {
        button.state = selected ? .on : .off
        button.contentTintColor = selected ? .controlAccentColor : .labelColor
        button.isEnabled = enabled
    }

    static func separator() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        line.widthAnchor.constraint(equalToConstant: 1).isActive = true
        line.heightAnchor.constraint(equalToConstant: 18).isActive = true
        return line
    }
}
