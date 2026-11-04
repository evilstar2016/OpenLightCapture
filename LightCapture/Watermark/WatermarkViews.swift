import AppKit
import Combine
import SwiftUI

private extension WatermarkAnchor {
    var title: String {
        [L10n.watermarkTopLeft, L10n.watermarkTop, L10n.watermarkTopRight,
         L10n.watermarkLeft, L10n.watermarkCenter, L10n.watermarkRight,
         L10n.watermarkBottomLeft, L10n.watermarkBottom, L10n.watermarkBottomRight][rawValue]
    }
}

struct WatermarkEditorFields: View {
    @Binding var text: String
    @Binding var style: WatermarkStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(L10n.watermarkText, text: $text, axis: .vertical)
                .lineLimit(1 ... 3)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("watermark.text")
            Picker(L10n.watermarkMode, selection: $style.mode) {
                Text(verbatim: L10n.watermarkSingle).tag(WatermarkMode.single)
                Text(verbatim: L10n.watermarkTiled).tag(WatermarkMode.tiled)
            }
            .accessibilityIdentifier("watermark.mode")
            if style.mode == .single {
                Picker(L10n.watermarkAnchor, selection: $style.anchor) {
                    ForEach(WatermarkAnchor.allCases, id: \.self) { anchor in
                        Text(verbatim: anchor.title).tag(anchor)
                    }
                }
                .accessibilityIdentifier("watermark.anchor")
                percentSlider(L10n.watermarkMargin, value: $style.marginRatio, range: 0 ... 20)
            } else {
                percentSlider(L10n.watermarkHorizontalGap, value: $style.horizontalGapRatio, range: 5 ... 100)
                percentSlider(L10n.watermarkVerticalGap, value: $style.verticalGapRatio, range: 5 ... 100)
            }
            percentSlider(L10n.watermarkFont, value: $style.fontRatio, range: 1 ... 20)
            percentSlider(L10n.watermarkOpacity, value: $style.opacity, range: 5 ... 100)
            HStack {
                Text(verbatim: L10n.watermarkAngle)
                Slider(value: $style.angle, in: -90 ... 90, step: 1)
                Text(verbatim: "\(Int(style.angle))").monospacedDigit().frame(width: 36)
            }
            ColorPicker(L10n.watermarkColor, selection: Binding(
                get: { Color(.sRGB, red: style.color.red, green: style.color.green, blue: style.color.blue, opacity: 1) },
                set: { color in
                    guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                    style.color = WatermarkColor(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
                }
            ), supportsOpacity: false)
        }
        .controlSize(.small)
    }

    private func percentSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(verbatim: title).frame(minWidth: 108, alignment: .leading)
            Slider(value: Binding(get: { value.wrappedValue * 100 }, set: { value.wrappedValue = $0 / 100 }), in: range, step: 1)
                .accessibilityLabel(Text(verbatim: title))
            Text(verbatim: "\(Int((value.wrappedValue * 100).rounded()))").monospacedDigit().frame(width: 30)
        }
    }
}

struct WatermarkSample: NSViewRepresentable {
    var selection: WatermarkSelection?

    func makeNSView(context _: Context) -> WatermarkSampleView {
        WatermarkSampleView()
    }

    func updateNSView(_ view: WatermarkSampleView, context _: Context) {
        view.selection = selection
        view.needsDisplay = true
    }
}

final class WatermarkSampleView: NSView {
    var selection: WatermarkSelection?
    private let cache = WatermarkPreviewCache()

    override func draw(_: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        let title = L10n.watermarkSample as NSString
        title.draw(at: CGPoint(x: 18, y: bounds.height - 32), withAttributes: [.font: NSFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: NSColor.darkGray])
        NSColor(white: 0.89, alpha: 1).setFill()
        for row in 0 ..< 3 {
            NSBezierPath(roundedRect: CGRect(x: 18, y: bounds.height - 54 - CGFloat(row) * 18, width: max(20, bounds.width * (row == 2 ? 0.5 : 0.78)), height: 7), xRadius: 3, yRadius: 3).fill()
        }
        guard let selection, let context = NSGraphicsContext.current?.cgContext else { return }
        do {
            // A fixed synthetic image size makes sample font sizes predictable.
            let size = CGSize(width: 800, height: max(1, 800 * bounds.height / max(1, bounds.width)))
            let layout = try cache.resolve(selection, size: size)
            context.saveGState()
            context.scaleBy(x: bounds.width / size.width, y: bounds.height / size.height)
            WatermarkRenderer.draw(layout, in: context)
            context.restoreGState()
        } catch {
            (error.localizedDescription as NSString).draw(in: bounds.insetBy(dx: 12, dy: 12), withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.systemOrange])
        }
    }
}

@MainActor
final class WatermarkPopoverController: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private weak var parentWindow: NSWindow?
    private weak var previousResponder: NSResponder?

    var isShown: Bool {
        popover.isShown
    }

    func show(relativeTo button: NSButton, selection: WatermarkSelection?, library: WatermarkLibrarySnapshot, onApply: @escaping (WatermarkSelection?) -> Void) {
        close()
        parentWindow = button.window
        previousResponder = button.window?.firstResponder
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: WatermarkSelectionView(selection: selection, library: library, onApply: { [weak self] result in
            onApply(result)
            self?.close()
        }, onCancel: { [weak self] in self?.close() }))
        popover.contentViewController?.view.identifier = NSUserInterfaceItemIdentifier("watermark.popover")
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        if let level = button.window?.level { popover.contentViewController?.view.window?.level = level }
    }

    func close() {
        popover.close()
    }

    func popoverDidClose(_: Notification) {
        if let responder = previousResponder { parentWindow?.makeFirstResponder(responder) }
        popover.contentViewController = nil
        previousResponder = nil
        parentWindow = nil
    }
}

struct WatermarkSelectionView: View {
    @State var selection: WatermarkSelection?
    let library: WatermarkLibrarySnapshot
    let onApply: (WatermarkSelection?) -> Void
    let onCancel: () -> Void
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: L10n.watermarkTitle).font(.headline)
            Picker(L10n.watermarkTitle, selection: Binding(
                get: { selection?.sourceID ?? (selection == nil ? "none" : "custom") },
                set: { id in
                    selection = library.templates.first { $0.id == id }?.selection
                    error = nil
                }
            )) {
                Text(verbatim: L10n.watermarkNone).tag("none")
                ForEach(library.templates) { template in Text(verbatim: template.name).tag(template.id) }
                if selection != nil, selection?.sourceID == nil {
                    Text(verbatim: L10n.watermarkCustom).tag("custom")
                }
            }
            .accessibilityIdentifier("watermark.selection")
            WatermarkSample(selection: selection).frame(height: 120).clipShape(RoundedRectangle(cornerRadius: 6))
            if selection != nil {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(verbatim: L10n.watermarkAdjust).font(.subheadline.weight(.semibold))
                        WatermarkEditorFields(text: Binding(get: { selection?.text ?? "" }, set: { selection?.text = $0; markCustom() }), style: Binding(get: { selection?.style ?? WatermarkStyle() }, set: { selection?.style = $0; markCustom() }))
                    }
                }
                .frame(height: 280)
            }
            Text(verbatim: error ?? L10n.watermarkSessionHint).font(.caption).foregroundStyle(error == nil ? Color.secondary : Color.red)
            HStack {
                Spacer()
                Button(L10n.watermarkCancel, action: onCancel).keyboardShortcut(.cancelAction)
                Button(L10n.watermarkApply) {
                    do { try selection?.validate(); onApply(selection) }
                    catch { self.error = error.localizedDescription }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .accessibilityIdentifier("watermark.apply")
            }
        }
        .padding(16)
        .frame(width: 420)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func markCustom() {
        selection?.sourceID = nil
        selection?.sourceName = nil
    }
}

@MainActor
final class WatermarkManagerModel: ObservableObject {
    let store: WatermarkTemplateStore
    @Published var draft: WatermarkTemplate?
    @Published var error: String?
    private var original: WatermarkTemplate?

    var hasChanges: Bool {
        draft != original
    }

    init(store: WatermarkTemplateStore) {
        self.store = store
    }

    func confirmDiscard() -> Bool {
        guard hasChanges else { return true }
        let alert = NSAlert()
        alert.messageText = L10n.watermarkDiscard
        alert.addButton(withTitle: L10n.watermarkKeepEditing)
        alert.addButton(withTitle: L10n.watermarkDiscardAction)
        return alert.runModal() == .alertSecondButtonReturn
    }

    func select(_ template: WatermarkTemplate?) {
        guard confirmDiscard() else { return }
        draft = template
        original = template
        error = nil
    }

    func newTemplate() {
        guard confirmDiscard() else { return }
        draft = WatermarkTemplate(name: L10n.watermarkCustom, text: "")
        original = nil
        error = nil
    }

    func duplicate() {
        guard let current = draft, confirmDiscard() else { return }
        let name = String(current.name.prefix(30)) + " · " + L10n.watermarkDuplicate
        draft = WatermarkTemplate(name: String(name.prefix(40)), text: current.text, style: current.style)
        original = nil
        error = nil
    }

    func save() {
        guard let draft else { return }
        do {
            try store.save(draft)
            original = draft
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    func delete() {
        guard let draft, confirmDiscard() else { return }
        do {
            try store.delete(id: draft.id)
            self.draft = nil
            original = nil
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    func reset() {
        guard confirmDiscard() else { return }
        do {
            try store.reset()
            draft = nil
            original = nil
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

@MainActor
final class WatermarkManagerWindowController: NSWindowController, NSWindowDelegate {
    static let shared = WatermarkManagerWindowController(store: .shared)
    let model: WatermarkManagerModel
    private var languageObserver: AnyCancellable?

    init(store: WatermarkTemplateStore) {
        model = WatermarkManagerModel(store: store)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 880, height: 650), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.minSize = CGSize(width: 820, height: 600)
        window.identifier = NSUserInterfaceItemIdentifier("watermark.manager")
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: WatermarkManagerView(model: model, store: store))
        languageObserver = NotificationCenter.default.publisher(for: LocalizationStore.didChange).sink { [weak self] _ in
            self?.window?.title = L10n.watermarkManagerTitle
        }
    }

    required init?(coder _: NSCoder) {
        nil
    }

    func show() {
        window?.title = L10n.watermarkManagerTitle
        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowShouldClose(_: NSWindow) -> Bool {
        model.confirmDiscard()
    }
}

struct SettingsWatermarkSection: View {
    @ObservedObject var store = WatermarkTemplateStore.shared
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: L10n.watermarkManagerTitle).font(.headline)
            HStack {
                Picker(L10n.watermarkDefault, selection: Binding(get: { store.library.defaultTemplateID ?? "none" }, set: { id in
                    do { try store.setDefault(id: id == "none" ? nil : id); error = nil }
                    catch { self.error = error.localizedDescription }
                })) {
                    Text(verbatim: L10n.watermarkNone).tag("none")
                    ForEach(store.snapshot().templates) { template in Text(verbatim: template.name).tag(template.id) }
                }
                .disabled(store.isReadOnly)
                .accessibilityIdentifier("settings.watermark.default")
                Button(L10n.watermarkManage) { WatermarkManagerWindowController.shared.show() }
                    .accessibilityIdentifier("settings.watermark.manage")
            }
            Text(verbatim: error ?? store.issue ?? L10n.watermarkNextCapture)
                .font(.caption).foregroundStyle(error == nil && store.issue == nil ? Color.secondary : Color.orange)
        }
    }
}

private struct WatermarkManagerView: View {
    @ObservedObject var model: WatermarkManagerModel
    @ObservedObject var store: WatermarkTemplateStore
    @ObservedObject private var localization = LocalizationStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let issue = store.issue {
                Text(verbatim: issue).foregroundStyle(.orange).font(.callout)
                if store.isReadOnly {
                    HStack {
                        Button(L10n.watermarkReset) {
                            model.reset()
                        }
                        Text(verbatim: L10n.watermarkResetHint).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            HStack {
                Picker(L10n.watermarkDefault, selection: Binding(get: { store.library.defaultTemplateID ?? "none" }, set: { id in
                    do { try store.setDefault(id: id == "none" ? nil : id) }
                    catch { model.error = error.localizedDescription }
                })) {
                    Text(verbatim: L10n.watermarkNone).tag("none")
                    ForEach(store.snapshot().templates) { template in Text(verbatim: template.name).tag(template.id) }
                }
                .disabled(store.isReadOnly)
                Text(verbatim: L10n.watermarkNextCapture).font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading) {
                    List(store.snapshot().templates) { template in
                        Button { model.select(template) } label: {
                            HStack {
                                Text(verbatim: template.name)
                                Spacer()
                                if template.id == model.draft?.id { Image(systemName: "checkmark") }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 5)
                    }
                    HStack {
                        Button(L10n.watermarkNew) { model.newTemplate() }.disabled(store.isReadOnly)
                        Button(L10n.watermarkDuplicate) { model.duplicate() }.disabled(model.draft == nil || store.isReadOnly)
                    }
                }
                .frame(width: 240)
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    if let draft = model.draft {
                        TextField(L10n.watermarkName, text: Binding(get: { model.draft?.name ?? "" }, set: { model.draft?.name = $0 }))
                            .textFieldStyle(.roundedBorder)
                            .disabled(draft.isBuiltin || store.isReadOnly)
                            .accessibilityIdentifier("watermark.name")
                        WatermarkSample(selection: draft.selection).frame(height: 140).clipShape(RoundedRectangle(cornerRadius: 6))
                        ScrollView {
                            WatermarkEditorFields(text: Binding(get: { model.draft?.text ?? "" }, set: { model.draft?.text = $0 }), style: Binding(get: { model.draft?.style ?? WatermarkStyle() }, set: { model.draft?.style = $0 }))
                                .disabled(draft.isBuiltin || store.isReadOnly)
                        }
                        Text(verbatim: draft.isBuiltin ? L10n.watermarkBuiltinHint : L10n.watermarkDraftHint).font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button(L10n.watermarkDelete) { model.delete() }
                                .disabled(draft.isBuiltin || store.isReadOnly || !store.library.templates.contains(where: { $0.id == draft.id }))
                            Spacer()
                            Button(L10n.watermarkSave) { model.save() }
                                .disabled(draft.isBuiltin || store.isReadOnly || !model.hasChanges)
                                .accessibilityIdentifier("watermark.save")
                        }
                    } else {
                        Text(verbatim: L10n.watermarkManagerTitle).font(.title2)
                        Text(verbatim: L10n.watermarkBuiltinHint).foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity)
            }
            if let error = model.error { Text(verbatim: error).foregroundStyle(.red).font(.callout) }
        }
        .padding(20)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.locale, Locale(identifier: localization.effectiveLanguage))
        .onChange(of: localization.effectiveLanguage) { _ in
            if let draft = model.draft, draft.isBuiltin {
                model.select(store.snapshot().templates.first { $0.id == draft.id })
            }
        }
    }
}
