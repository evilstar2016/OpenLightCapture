import AppKit

enum AnnotationStyleChange: Equatable {
    case color
    case lineWidth
    case fontSize
    case mosaicBlockSize
}

@MainActor
final class AnnotationStyleControls: CaptureToolbarPlate {
    private let styleLabel = NSTextField(labelWithString: L10n.styleWidth)
    private let widthControl = NSSegmentedControl(labels: [L10n.styleThin, L10n.styleMedium, L10n.styleThick], trackingMode: .selectOne, target: nil, action: nil)
    private let fontControl = NSSegmentedControl(labels: ["14", "18", "24", "32"], trackingMode: .selectOne, target: nil, action: nil)
    private let mosaicControl = NSSegmentedControl(labels: [L10n.styleSmall, L10n.styleMedium, L10n.styleLarge], trackingMode: .selectOne, target: nil, action: nil)
    private let colors = NSStackView()
    private var colorButtons: [AnnotationColorButton] = []
    private(set) var selectedColor: AnnotationColor = .red
    var onChange: ((AnnotationStyleChange) -> Void)?

    override init(frame frameRect: NSRect = .zero) {
        super.init(frame: frameRect)
        identifier = NSUserInterfaceItemIdentifier("capture.annotation.style")
        styleLabel.font = .systemFont(ofSize: 11)
        styleLabel.textColor = .secondaryLabelColor
        addArrangedSubview(styleLabel)
        for (control, width, id) in [(widthControl, CGFloat(160), "width"), (fontControl, 128, "font"), (mosaicControl, 160, "mosaic")] {
            control.controlSize = .small
            control.selectedSegment = 1
            control.target = self
            control.action = #selector(changeSize(_:))
            control.identifier = NSUserInterfaceItemIdentifier("capture.annotation.\(id)")
            control.widthAnchor.constraint(equalToConstant: width).isActive = true
            addArrangedSubview(control)
        }
        colors.orientation = .horizontal
        colors.spacing = 2
        let choices: [(AnnotationColor, String)] = [
            (.red, L10n.colorRed), (AnnotationColor(red: 1, green: 0.55, blue: 0.08, alpha: 1), L10n.colorOrange),
            (AnnotationColor(red: 1, green: 0.82, blue: 0.08, alpha: 1), L10n.colorYellow),
            (AnnotationColor(red: 0.16, green: 0.68, blue: 0.35, alpha: 1), L10n.colorGreen),
            (AnnotationColor(red: 0.12, green: 0.48, blue: 0.96, alpha: 1), L10n.colorBlue), (.black, L10n.colorBlack), (.white, L10n.colorWhite),
        ]
        for (index, choice) in choices.enumerated() {
            let (color, name) = choice
            let button = AnnotationColorButton(color: color, name: name)
            button.identifier = NSUserInterfaceItemIdentifier("capture.annotation.color.\(index)")
            button.target = self
            button.action = #selector(changeColor(_:))
            colorButtons.append(button)
            colors.addArrangedSubview(button)
        }
        addArrangedSubview(colors)
        update(for: .select, enabled: true)
    }

    required init?(coder _: NSCoder) {
        nil
    }

    func style(pixelScale: CGFloat) -> AnnotationStyle {
        AnnotationStyle(
            color: selectedColor,
            lineWidth: value([2, 3, 5], for: widthControl) * pixelScale,
            fontSize: value([14, 18, 24, 32], for: fontControl) * pixelScale,
            mosaicBlockSize: value([8, 12, 20], for: mosaicControl) * pixelScale
        )
    }

    func selectTextStyle(fontSize: CGFloat, color: AnnotationColor, pixelScale: CGFloat) {
        selectedColor = color
        let sizes: [CGFloat] = [14, 18, 24, 32]
        fontControl.selectedSegment = sizes.indices.min { abs(sizes[$0] * pixelScale - fontSize) < abs(sizes[$1] * pixelScale - fontSize) } ?? 1
        updateColorSelection()
    }

    func update(for tool: AnnotationTool, enabled: Bool) {
        isHidden = ![AnnotationTool.rectangle, .ellipse, .arrow, .brush, .text, .mosaic].contains(tool)
        widthControl.isHidden = ![AnnotationTool.rectangle, .ellipse, .arrow, .brush].contains(tool)
        fontControl.isHidden = tool != .text
        mosaicControl.isHidden = tool != .mosaic
        colors.isHidden = tool == .mosaic
        styleLabel.stringValue = tool == .text ? L10n.styleFontSize : (tool == .mosaic ? L10n.styleMosaicSize : L10n.styleWidth)
        for control in [widthControl, fontControl, mosaicControl] {
            control.isEnabled = enabled
        }
        for button in colorButtons {
            button.isEnabled = enabled
        }
        updateColorSelection()
    }

    private func value(_ values: [CGFloat], for control: NSSegmentedControl) -> CGFloat {
        values[min(max(control.selectedSegment, 0), values.count - 1)]
    }

    private func updateColorSelection() {
        for button in colorButtons {
            button.state = button.annotationColor == selectedColor ? .on : .off
            button.needsDisplay = true
        }
    }

    @objc private func changeColor(_ sender: AnnotationColorButton) {
        selectedColor = sender.annotationColor
        updateColorSelection()
        onChange?(.color)
    }

    @objc private func changeSize(_ sender: NSSegmentedControl) {
        onChange?(sender === fontControl ? .fontSize : (sender === widthControl ? .lineWidth : .mosaicBlockSize))
    }
}
