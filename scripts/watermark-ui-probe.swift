import AppKit
import Foundation

/// Native popover lifecycle smoke check in a standalone process, without XCTest diagnostics injection.
/// Only synthetic content and the probe's own views are used. No screen or clipboard access.
@main
struct WatermarkUIProbe {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = ProbeDelegate()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
private final class ProbeDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var button: NSButton!
    private var responder: FocusView!
    private let controller = WatermarkPopoverController()
    private var applied = false
    private var results: [String: Any] = [:]

    func applicationDidFinishLaunching(_: Notification) {
        window = NSWindow(contentRect: CGRect(x: 200, y: 100, width: 520, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = .screenSaver
        button = NSButton(title: "Watermark", target: nil, action: nil)
        button.frame = CGRect(x: 220, y: 480, width: 100, height: 28)
        responder = FocusView(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
        window.contentView?.addSubview(button)
        window.contentView?.addSubview(responder)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.show() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { self.finish(success: false) }
    }

    private func show() {
        window.makeFirstResponder(responder)
        let templates = WatermarkTemplate.builtins(in: LocalizationContext(languageIdentifier: "en"))
        let library = WatermarkLibrarySnapshot(templates: templates, defaultTemplateID: templates[0].id)
        controller.show(relativeTo: button, selection: library.defaultSelection, library: library) { _ in self.applied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            let popup = NSApp.windows.first { window in
                guard let content = window.contentView else { return false }
                return self.views(content).contains { $0.identifier?.rawValue == "watermark.popover" }
            }
            self.results["shown"] = self.controller.isShown
            self.results["overlay_level_matches"] = popup?.level == self.window.level
            if let content = popup?.contentView.flatMap({ self.views($0).first { $0.identifier?.rawValue == "watermark.popover" } }) {
                self.results["content_height"] = content.frame.height
                self.results["style_controls_visible"] = content.frame.height > 500 && content.frame.height < 700
            }
            self.controller.close()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self.results["closed"] = !self.controller.isShown
                self.results["cancel_did_not_apply"] = !self.applied
                self.results["focus_restored"] = self.window.firstResponder === self.responder
                let keys = ["shown", "overlay_level_matches", "style_controls_visible", "closed", "cancel_did_not_apply", "focus_restored"]
                self.finish(success: keys.allSatisfy { self.results[$0] as? Bool == true })
            }
        }
    }

    private func views(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(views)
    }

    private func finish(success: Bool) {
        results["passed"] = success
        let data = (try? JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
        controller.close()
        window?.close()
        exit(success ? 0 : 1)
    }
}

@MainActor
private final class FocusView: NSView {
    override var acceptsFirstResponder: Bool {
        true
    }
}
