import AppKit

@MainActor
enum AppRelauncher {
    static func restart() {
        do {
            let process = makeProcess(applicationURL: Bundle.main.bundleURL, processID: ProcessInfo.processInfo.processIdentifier)
            try process.run()
            NSApp.terminate(nil)
        } catch {
            let alert = NSAlert()
            alert.messageText = L10n.permissionRestartHeading
            alert.informativeText = L10n.permissionRestartFailed(error.localizedDescription)
            alert.alertStyle = .warning
            alert.addButton(withTitle: L10n.actionOk)
            alert.runModal()
        }
    }

    static func makeProcess(applicationURL: URL, processID: Int32, openExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/open")) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Wait for termination to release the single-instance lock. Pass the
        // app path as an argument so spaces and shell characters stay literal.
        process.arguments = ["-c", """
        relaunch_attempt=0
        while /bin/kill -0 "$1" 2>/dev/null; do
            if [ "$relaunch_attempt" -ge 150 ]; then exit 1; fi
            /bin/sleep 0.2
            relaunch_attempt=$((relaunch_attempt + 1))
        done
        exec "$3" -n "$2"
        """, "OpenLightCapture-relaunch", String(processID), applicationURL.path, openExecutableURL.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return process
    }
}
