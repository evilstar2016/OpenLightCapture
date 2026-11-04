import Foundation

extension L10n {
    static var watermarkTitle: String {
        LocalizationContext.current.string("watermark.title", defaultValue: "Watermark")
    }

    static var watermarkNone: String {
        LocalizationContext.current.string("watermark.none", defaultValue: "No Watermark")
    }

    static var watermarkManage: String {
        LocalizationContext.current.string("watermark.manage", defaultValue: "Manage Templates…")
    }

    static var watermarkManagerTitle: String {
        LocalizationContext.current.string("watermark.managerTitle", defaultValue: "Watermark Templates")
    }

    static var watermarkDefault: String {
        LocalizationContext.current.string("watermark.default", defaultValue: "Default watermark")
    }

    static var watermarkNextCapture: String {
        LocalizationContext.current.string("watermark.nextCapture", defaultValue: "Changes apply to new screenshots.")
    }

    static var watermarkNew: String {
        LocalizationContext.current.string("watermark.new", defaultValue: "New")
    }

    static var watermarkDuplicate: String {
        LocalizationContext.current.string("watermark.duplicate", defaultValue: "Duplicate")
    }

    static var watermarkDelete: String {
        LocalizationContext.current.string("watermark.delete", defaultValue: "Delete")
    }

    static var watermarkSave: String {
        LocalizationContext.current.string("watermark.save", defaultValue: "Save Template")
    }

    static var watermarkName: String {
        LocalizationContext.current.string("watermark.name", defaultValue: "Template name")
    }

    static var watermarkText: String {
        LocalizationContext.current.string("watermark.text", defaultValue: "Watermark text")
    }

    static var watermarkMode: String {
        LocalizationContext.current.string("watermark.mode", defaultValue: "Layout")
    }

    static var watermarkSingle: String {
        LocalizationContext.current.string("watermark.single", defaultValue: "Single")
    }

    static var watermarkTiled: String {
        LocalizationContext.current.string("watermark.tiled", defaultValue: "Tiled")
    }

    static var watermarkAnchor: String {
        LocalizationContext.current.string("watermark.anchor", defaultValue: "Position")
    }

    static var watermarkFont: String {
        LocalizationContext.current.string("watermark.font", defaultValue: "Text size (%)")
    }

    static var watermarkOpacity: String {
        LocalizationContext.current.string("watermark.opacity", defaultValue: "Opacity (%)")
    }

    static var watermarkAngle: String {
        LocalizationContext.current.string("watermark.angle", defaultValue: "Angle (°)")
    }

    static var watermarkMargin: String {
        LocalizationContext.current.string("watermark.margin", defaultValue: "Margin (%)")
    }

    static var watermarkHorizontalGap: String {
        LocalizationContext.current.string("watermark.horizontalGap", defaultValue: "Horizontal gap (%)")
    }

    static var watermarkVerticalGap: String {
        LocalizationContext.current.string("watermark.verticalGap", defaultValue: "Vertical gap (%)")
    }

    static var watermarkColor: String {
        LocalizationContext.current.string("watermark.color", defaultValue: "Color")
    }

    static var watermarkAdjust: String {
        LocalizationContext.current.string("watermark.adjust", defaultValue: "Adjust This Screenshot")
    }

    static var watermarkCustom: String {
        LocalizationContext.current.string("watermark.custom", defaultValue: "Custom")
    }

    static var watermarkApply: String {
        LocalizationContext.current.string("watermark.apply", defaultValue: "Apply")
    }

    static var watermarkCancel: String {
        LocalizationContext.current.string("watermark.cancel", defaultValue: "Cancel")
    }

    static var watermarkBuiltinHint: String {
        LocalizationContext.current.string("watermark.builtinHint", defaultValue: "Built-in template. Duplicate it to edit.")
    }

    static var watermarkDraftHint: String {
        LocalizationContext.current.string("watermark.draftHint", defaultValue: "Changes are not saved until you save the template.")
    }

    static var watermarkSessionHint: String {
        LocalizationContext.current.string("watermark.sessionHint", defaultValue: "Changes affect only this screenshot.")
    }

    static var watermarkReset: String {
        LocalizationContext.current.string("watermark.reset", defaultValue: "Back Up and Reset Library")
    }

    static var watermarkResetHint: String {
        LocalizationContext.current.string("watermark.resetHint", defaultValue: "The original library will be backed up before resetting.")
    }

    static var watermarkInvalidName: String {
        LocalizationContext.current.string("watermark.invalidName", defaultValue: "Enter a template name of 1–40 characters.")
    }

    static var watermarkInvalidText: String {
        LocalizationContext.current.string("watermark.invalidText", defaultValue: "Enter watermark text of up to 120 characters and 3 lines.")
    }

    static var watermarkInvalidStyle: String {
        LocalizationContext.current.string("watermark.invalidStyle", defaultValue: "The watermark style contains invalid values.")
    }

    static var watermarkTemplateLimit: String {
        LocalizationContext.current.string("watermark.templateLimit", defaultValue: "You can save up to 50 custom templates.")
    }

    static var watermarkReadOnly: String {
        LocalizationContext.current.string("watermark.readOnly", defaultValue: "The template library cannot be read. The original file is retained. Back it up and reset to save templates again.")
    }

    static var watermarkInvalidLibrary: String {
        LocalizationContext.current.string("watermark.invalidLibrary", defaultValue: "The template library or default selection is invalid.")
    }

    static var watermarkTooSmall: String {
        LocalizationContext.current.string("watermark.tooSmall", defaultValue: "The watermark does not fit. Enlarge the selection, shorten the text, or turn off the watermark.")
    }

    static var watermarkMissingDefault: String {
        LocalizationContext.current.string("watermark.missingDefault", defaultValue: "The default template is missing. New screenshots will have no watermark.")
    }

    static var watermarkDiscard: String {
        LocalizationContext.current.string("watermark.discard", defaultValue: "Discard unsaved template changes?")
    }

    static var watermarkKeepEditing: String {
        LocalizationContext.current.string("watermark.keepEditing", defaultValue: "Keep Editing")
    }

    static var watermarkDiscardAction: String {
        LocalizationContext.current.string("watermark.discardAction", defaultValue: "Discard Changes")
    }

    static var watermarkSample: String {
        LocalizationContext.current.string("watermark.sample", defaultValue: "Screenshot preview")
    }

    static var watermarkTopLeft: String {
        LocalizationContext.current.string("watermark.topLeft", defaultValue: "Top Left")
    }

    static var watermarkTop: String {
        LocalizationContext.current.string("watermark.top", defaultValue: "Top")
    }

    static var watermarkTopRight: String {
        LocalizationContext.current.string("watermark.topRight", defaultValue: "Top Right")
    }

    static var watermarkLeft: String {
        LocalizationContext.current.string("watermark.left", defaultValue: "Left")
    }

    static var watermarkCenter: String {
        LocalizationContext.current.string("watermark.center", defaultValue: "Center")
    }

    static var watermarkRight: String {
        LocalizationContext.current.string("watermark.right", defaultValue: "Right")
    }

    static var watermarkBottomLeft: String {
        LocalizationContext.current.string("watermark.bottomLeft", defaultValue: "Bottom Left")
    }

    static var watermarkBottom: String {
        LocalizationContext.current.string("watermark.bottom", defaultValue: "Bottom")
    }

    static var watermarkBottomRight: String {
        LocalizationContext.current.string("watermark.bottomRight", defaultValue: "Bottom Right")
    }

    static func watermarkReferenceName(in context: LocalizationContext = .current) -> String {
        context.string("watermark.referenceName", defaultValue: "Corner Reference")
    }

    static func watermarkReferenceText(in context: LocalizationContext = .current) -> String {
        context.string("watermark.referenceText", defaultValue: "For reference only")
    }

    static func watermarkInternalName(in context: LocalizationContext = .current) -> String {
        context.string("watermark.internalName", defaultValue: "Centered Internal Notice")
    }

    static func watermarkInternalText(in context: LocalizationContext = .current) -> String {
        context.string("watermark.internalText", defaultValue: "Internal use only")
    }

    static func watermarkProtectedName(in context: LocalizationContext = .current) -> String {
        context.string("watermark.protectedName", defaultValue: "Tiled Protection")
    }

    static func watermarkProtectedText(in context: LocalizationContext = .current) -> String {
        context.string("watermark.protectedText", defaultValue: "Do not reproduce without permission")
    }
}
