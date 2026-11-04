import CoreGraphics
import Foundation

enum WatermarkMode: String, Codable, CaseIterable {
    case single, tiled
}

enum WatermarkAnchor: Int, Codable, CaseIterable {
    case topLeft, top, topRight, left, center, right, bottomLeft, bottom, bottomRight

    var column: Int {
        rawValue % 3
    }

    var row: Int {
        rawValue / 3
    }
}

struct WatermarkColor: Codable, Equatable {
    var red = 0.35
    var green = 0.35
    var blue = 0.35

    func cgColor(opacity: Double) -> CGColor {
        CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [red, green, blue, opacity])!
    }
}

struct WatermarkStyle: Codable, Equatable {
    var mode: WatermarkMode = .single
    var anchor: WatermarkAnchor = .bottomRight
    var fontRatio = 0.04
    var color = WatermarkColor()
    var opacity = 0.5
    var angle = 0.0
    var marginRatio = 0.03
    var horizontalGapRatio = 0.20
    var verticalGapRatio = 0.15

    func validate() throws {
        let ranges: [(Double, ClosedRange<Double>)] = [
            (fontRatio, 0.01 ... 0.20), (opacity, 0.05 ... 1), (angle, -90 ... 90),
            (marginRatio, 0 ... 0.20), (horizontalGapRatio, 0.05 ... 1), (verticalGapRatio, 0.05 ... 1),
            (color.red, 0 ... 1), (color.green, 0 ... 1), (color.blue, 0 ... 1),
        ]
        guard ranges.allSatisfy({ $0.0.isFinite && $0.1.contains($0.0) }) else { throw WatermarkError.invalidStyle }
    }
}

struct WatermarkSelection: Codable, Equatable {
    var sourceID: String?
    var sourceName: String?
    var text: String
    var style: WatermarkStyle

    var lines: [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: .newlines)
    }

    func validate() throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.count <= 120, text.utf8.count <= 2048, lines.count <= 3
        else { throw WatermarkError.invalidText }
        try style.validate()
    }
}

struct WatermarkTemplate: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var name: String
    var text: String
    var style = WatermarkStyle()

    var isBuiltin: Bool {
        id.hasPrefix("builtin.")
    }

    var selection: WatermarkSelection {
        WatermarkSelection(sourceID: id, sourceName: name, text: text, style: style)
    }

    func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 40, name.utf8.count <= 512 else {
            throw WatermarkError.invalidName
        }
        try selection.validate()
    }

    static func builtins(in context: LocalizationContext = .current) -> [WatermarkTemplate] {
        var centered = WatermarkStyle()
        centered.anchor = .center
        var tiled = WatermarkStyle()
        tiled.mode = .tiled
        tiled.opacity = 0.15
        tiled.angle = -30
        return [
            WatermarkTemplate(id: "builtin.reference", name: L10n.watermarkReferenceName(in: context), text: L10n.watermarkReferenceText(in: context)),
            WatermarkTemplate(id: "builtin.internal", name: L10n.watermarkInternalName(in: context), text: L10n.watermarkInternalText(in: context), style: centered),
            WatermarkTemplate(id: "builtin.protected", name: L10n.watermarkProtectedName(in: context), text: L10n.watermarkProtectedText(in: context), style: tiled),
        ]
    }
}

struct WatermarkLibrary: Codable, Equatable {
    var schemaVersion = 1
    var templates: [WatermarkTemplate] = []
    var defaultTemplateID: String?
}

struct WatermarkLibrarySnapshot: Equatable {
    var templates: [WatermarkTemplate] = []
    var defaultTemplateID: String?

    static let empty = WatermarkLibrarySnapshot()

    var defaultSelection: WatermarkSelection? {
        templates.first { $0.id == defaultTemplateID }?.selection
    }
}

struct CaptureWatermarkContext: Equatable {
    let sessionID: UUID
    let generation: UInt64
    let library: WatermarkLibrarySnapshot
    var selection: WatermarkSelection?
}

enum WatermarkError: LocalizedError {
    case invalidName, invalidText, invalidStyle, templateLimit, readOnly, invalidLibrary, tooSmall

    var errorDescription: String? {
        switch self {
        case .invalidName: L10n.watermarkInvalidName
        case .invalidText: L10n.watermarkInvalidText
        case .invalidStyle: L10n.watermarkInvalidStyle
        case .templateLimit: L10n.watermarkTemplateLimit
        case .readOnly: L10n.watermarkReadOnly
        case .invalidLibrary: L10n.watermarkInvalidLibrary
        case .tooSmall: L10n.watermarkTooSmall
        }
    }
}
