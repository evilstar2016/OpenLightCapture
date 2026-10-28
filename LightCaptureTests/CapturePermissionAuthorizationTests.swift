import AppKit
@testable import LightCapture
import XCTest

@MainActor
final class CapturePermissionAuthorizationTests: XCTestCase {
    func testGrantedPermissionDoesNotPromptRequestOrOpenSettings() async {
        let authorization = CapturePermissionAuthorization(
            preflight: { _ in true },
            request: { _ in XCTFail("已有权限不应再次申请") },
            confirm: { _ in XCTFail("已有权限不应弹窗"); return false },
            openSettings: { _ in XCTFail("已有权限不应打开设置") }
        )
        await assertAccess(true, to: .screenCapture, using: authorization)
        await assertAccess(true, to: .automaticScroll, using: authorization)
    }

    func testScreenCaptureRequestsOnlyScreenPermissionAndOpensItsExactPane() async {
        var checks: [CapturePermissionKind] = []
        var requests: [CapturePermissionKind] = []
        var prompts: [CapturePermissionKind] = []
        var opened: [URL] = []
        let authorization = CapturePermissionAuthorization(
            preflight: { checks.append($0); return false },
            request: { requests.append($0) },
            confirm: { prompts.append($0); return true },
            openSettings: { opened.append($0) }
        )
        await assertAccess(false, to: .screenCapture, using: authorization)
        XCTAssertEqual(checks, [.screenCapture])
        XCTAssertEqual(prompts, [.screenCapture])
        XCTAssertEqual(requests, [.screenCapture])
        XCTAssertEqual(opened.map(\.absoluteString), ["x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"])
    }

    func testAutomaticCaptureRequestsControlAndOpensItsExactPane() async {
        var requests: [CapturePermissionKind] = []
        var prompts: [CapturePermissionKind] = []
        var opened: [URL] = []
        let authorization = CapturePermissionAuthorization(
            preflight: { _ in false },
            request: { requests.append($0) },
            confirm: { prompts.append($0); return true },
            openSettings: { opened.append($0) }
        )
        await assertAccess(false, to: .automaticScroll, using: authorization)
        XCTAssertEqual(prompts, [.automaticScroll])
        XCTAssertEqual(requests, [.automaticScroll])
        XCTAssertEqual(opened.map(\.absoluteString), ["x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"])
    }

    func testCancellingThePromptDoesNotRequestAccessOrOpenSettings() async {
        let authorization = CapturePermissionAuthorization(
            preflight: { _ in false },
            request: { _ in XCTFail("取消后不应申请权限") },
            confirm: { _ in false },
            openSettings: { _ in XCTFail("取消后不应打开设置") }
        )
        await assertAccess(false, to: .screenCapture, using: authorization)
        await assertAccess(false, to: .automaticScroll, using: authorization)
    }

    func testRepeatedUserAttemptsCanOpenSettingsWithoutRepeatingNativeRequests() async {
        var requests: [CapturePermissionKind] = []
        var opened: [URL] = []
        let authorization = CapturePermissionAuthorization(
            preflight: { _ in false },
            request: { requests.append($0) },
            confirm: { _ in true },
            openSettings: { opened.append($0) }
        )
        for _ in 0 ..< 10 {
            await assertAccess(false, to: .screenCapture, using: authorization)
            await assertAccess(false, to: .automaticScroll, using: authorization)
        }
        XCTAssertEqual(requests, [.screenCapture, .automaticScroll])
        XCTAssertEqual(opened.count, 20)
    }

    func testANewGrantDoesNotResumeCaptureInsideTheAuthorizationFlow() async {
        var granted = false
        var opened: [URL] = []
        let authorization = CapturePermissionAuthorization(
            preflight: { _ in granted },
            request: { _ in granted = true },
            confirm: { _ in true },
            openSettings: { opened.append($0) }
        )
        await assertAccess(false, to: .automaticScroll, using: authorization)
        XCTAssertTrue(granted)
        XCTAssertEqual(opened, [CapturePermissionKind.automaticScroll.settingsURL])
    }

    func testAnOpenPromptDoesNotStackAnotherPrompt() async {
        var prompts = 0
        var authorization: CapturePermissionAuthorization!
        authorization = CapturePermissionAuthorization(
            preflight: { _ in false },
            request: { _ in XCTFail("本测试未确认授权") },
            confirm: { permission in
                prompts += 1
                await self.assertAccess(false, to: permission, using: authorization)
                return false
            },
            openSettings: { _ in XCTFail("本测试不应打开设置") }
        )
        await assertAccess(false, to: .screenCapture, using: authorization)
        XCTAssertEqual(prompts, 1)
    }

    func testNewPermissionGrantPromptsOnceAndRestartsOnlyWhenConfirmed() async {
        for permission in [CapturePermissionKind.screenCapture, .automaticScroll] {
            for acceptRestart in [false, true] {
                var granted = false
                var prompts = 0
                var restarts = 0
                let authorization = CapturePermissionAuthorization(
                    preflight: { _ in granted },
                    request: { _ in },
                    confirm: { _ in true },
                    openSettings: { _ in },
                    confirmRestart: { prompts += 1; return acceptRestart },
                    restartApplication: { restarts += 1 }
                )
                await assertAccess(false, to: permission, using: authorization)
                await authorization.checkForPermissionChanges()
                XCTAssertEqual(prompts, 0, "未授权时不能提前提示重启")
                granted = true
                await authorization.checkForPermissionChanges()
                await authorization.checkForPermissionChanges(returnedFromSettings: true)
                XCTAssertEqual(prompts, 1)
                XCTAssertEqual(restarts, acceptRestart ? 1 : 0)
                await assertAccess(false, to: permission, using: authorization, "新的权限需要重启后再开始，不能继续旧会话")
                XCTAssertEqual(prompts, 1)
            }
        }
    }

    func testCancellingAuthorizationNeverSchedulesARestartPrompt() async {
        let authorization = CapturePermissionAuthorization(
            preflight: { _ in false },
            request: { _ in XCTFail("取消后不能申请权限") },
            confirm: { _ in false },
            openSettings: { _ in XCTFail("取消后不能打开设置") },
            confirmRestart: { XCTFail("取消授权后不能提示重启"); return false },
            restartApplication: { XCTFail("不能自动重启") }
        )
        await assertAccess(false, to: .automaticScroll, using: authorization)
        await authorization.checkForPermissionChanges(returnedFromSettings: true)
    }

    func testReturningFromSettingsRemindsEvenWhenPermissionPreflightIsStale() async {
        var prompts = 0
        let authorization = CapturePermissionAuthorization(
            preflight: { _ in false },
            request: { _ in },
            confirm: { _ in true },
            openSettings: { _ in },
            confirmRestart: { prompts += 1; return false },
            restartApplication: { XCTFail("选择稍后不能重启") }
        )
        authorization.startMonitoring(workspaceNotificationCenter: NotificationCenter(), applicationNotificationCenter: NotificationCenter())
        defer { authorization.stopMonitoring() }
        await assertAccess(false, to: .automaticScroll, using: authorization)
        await authorization.applicationDidActivate(bundleIdentifier: "com.apple.systempreferences")
        XCTAssertEqual(prompts, 0, "进入设置时不能抢先弹窗")
        await authorization.applicationDidActivate(bundleIdentifier: "io.github.evilstar2016.openlightcapture")
        XCTAssertEqual(prompts, 1)
        let hasControlAccess = await authorization.hasAccess(to: .automaticScroll)
        XCTAssertFalse(hasControlAccess, "返回设置不能被当作已授权")
        await authorization.applicationDidActivate(bundleIdentifier: "io.github.evilstar2016.openlightcapture")
        XCTAssertEqual(prompts, 1)
    }

    func testLaterKeepsScreenCaptureAvailableWhenOnlyControlNeedsRestart() async {
        var controlGranted = false
        let authorization = CapturePermissionAuthorization(
            preflight: { $0 == .screenCapture || controlGranted },
            request: { _ in },
            confirm: { _ in true },
            openSettings: { _ in },
            confirmRestart: { false },
            restartApplication: { XCTFail("选择稍后不能重启") }
        )
        await assertAccess(false, to: .automaticScroll, using: authorization)
        controlGranted = true
        await authorization.checkForPermissionChanges()
        await assertAccess(false, to: .automaticScroll, using: authorization)
        await assertAccess(true, to: .screenCapture, using: authorization, "自动控制的重启要求不能阻止普通截图或手动长图")
    }

    func testRestartPromptDoesNotReenterWhenActivationArrivesDuringTheModal() async {
        var granted = false
        var prompts = 0
        var authorization: CapturePermissionAuthorization!
        defer { authorization = nil }
        authorization = CapturePermissionAuthorization(
            preflight: { _ in granted },
            request: { _ in },
            confirm: { _ in true },
            openSettings: { _ in },
            confirmRestart: {
                prompts += 1
                await authorization.checkForPermissionChanges(returnedFromSettings: true)
                await self.assertAccess(false, to: .automaticScroll, using: authorization)
                return false
            },
            restartApplication: { XCTFail("选择稍后不能重启") }
        )
        await assertAccess(false, to: .automaticScroll, using: authorization)
        granted = true
        await authorization.checkForPermissionChanges()
        XCTAssertEqual(prompts, 1)
    }

    func testMonitoringDetectsAGrantWithoutWaitingForAppActivation() async {
        var granted = false
        let prompt = expectation(description: "设置中授权后提示重启")
        let authorization = CapturePermissionAuthorization(
            preflight: { _ in granted },
            request: { _ in },
            confirm: { _ in true },
            openSettings: { _ in granted = true },
            confirmRestart: { prompt.fulfill(); return false },
            restartApplication: { XCTFail("选择稍后不能重启") }
        )
        authorization.startMonitoring(workspaceNotificationCenter: NotificationCenter(), applicationNotificationCenter: NotificationCenter())
        defer { authorization.stopMonitoring() }
        await assertAccess(false, to: .automaticScroll, using: authorization)
        await fulfillment(of: [prompt], timeout: 5)
    }

    func testApplicationActivationChecksPendingPermissionsAndStopRemovesObservers() async {
        var granted = false
        let prompt = expectation(description: "返回应用时提示重启")
        let center = NotificationCenter()
        let authorization = CapturePermissionAuthorization(
            preflight: { _ in granted },
            request: { _ in },
            confirm: { _ in true },
            openSettings: { _ in },
            confirmRestart: { prompt.fulfill(); return false },
            restartApplication: { XCTFail("选择稍后不能重启") }
        )
        authorization.startMonitoring(workspaceNotificationCenter: NotificationCenter(), applicationNotificationCenter: center)
        await assertAccess(false, to: .automaticScroll, using: authorization)
        granted = true
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        await fulfillment(of: [prompt], timeout: 2)
        authorization.stopMonitoring()
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        await authorization.checkForPermissionChanges(returnedFromSettings: true)
    }

    func testRestartPromptHasBothActionsInChineseAndEnglish() {
        let original = LocalizationContext.current
        defer { LocalizationRuntime.shared.install(original) }
        for (language, titles) in [("zh-Hans", ["立即重启", "稍后"]), ("en", ["Restart Now", "Later"])] {
            LocalizationRuntime.shared.install(LocalizationContext(languageIdentifier: language))
            let alert = CapturePermissionAuthorization.makeRestartAlert()
            XCTAssertEqual(alert.buttons.map(\.title), titles)
            XCTAssertEqual(alert.informativeText, L10n.permissionRestartPrompt)
            XCTAssertTrue(alert.informativeText.contains(language == "zh-Hans" ? "结束当前截图" : "ends the current screenshot"))
            XCTAssertGreaterThan(alert.window.level.rawValue, NSWindow.Level.floating.rawValue, "重启提示必须显示在长截图面板上方")
        }
    }

    func testStoppingBeforeTheGrantCancelsPendingRecovery() async {
        var granted = false
        let authorization = CapturePermissionAuthorization(
            preflight: { _ in granted },
            request: { _ in },
            confirm: { _ in true },
            openSettings: { _ in },
            confirmRestart: { XCTFail("停止监听后不能弹出重启提示"); return false },
            restartApplication: { XCTFail("不能重启") }
        )
        authorization.startMonitoring(workspaceNotificationCenter: NotificationCenter(), applicationNotificationCenter: NotificationCenter())
        await assertAccess(false, to: .automaticScroll, using: authorization)
        authorization.stopMonitoring()
        granted = true
        await authorization.checkForPermissionChanges(returnedFromSettings: true)
        await authorization.applicationDidActivate(bundleIdentifier: "io.github.evilstar2016.openlightcapture")
    }

    func testAutomaticLongCaptureSchedulesTheGrantReminderThroughItsActualStartAction() async throws {
        let flow = CaptureFlowController()
        let session = try XCTUnwrap(flow.sessions.begin(mode: .long, targetProcessID: nil))
        XCTAssertTrue(flow.sessions.transition(sessionID: session.id, generation: session.generation, to: .scrollReady))
        var granted = false
        let request = expectation(description: "自动长图申请控制权限")
        let restartPrompt = expectation(description: "自动长图授权后提示重启")
        let authorization = CapturePermissionAuthorization(
            preflight: { _ in granted },
            request: { _ in request.fulfill() },
            confirm: { permission in XCTAssertEqual(permission, .automaticScroll); return true },
            openSettings: { _ in },
            confirmRestart: { restartPrompt.fulfill(); return false },
            restartApplication: { XCTFail("选择稍后不能重启") }
        )
        let controller = LongCaptureController(captureFlowController: flow, permissionAuthorization: authorization)
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let context = try XCTUnwrap(CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 400, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let screen = try FrozenScreen(displayID: 0, screenFrame: rect, image: XCTUnwrap(context.makeImage()), transform: DisplayTransform(screenFrame: rect, pixelWidth: 100, pixelHeight: 100), windows: [])
        controller.begin(screen: screen, pixelRect: rect, session: session)
        defer {
            controller.cancel()
            flow.cancelCurrentSession(restoreFocus: false)
        }
        let panel = try XCTUnwrap(NSApp.windows.compactMap { $0 as? LongCaptureControlPanel }.first { $0.isVisible })
        panel.onStartAutomatic?()
        await fulfillment(of: [request], timeout: 2)
        granted = true
        await authorization.checkForPermissionChanges()
        await fulfillment(of: [restartPrompt], timeout: 2)
        XCTAssertEqual(flow.sessions.activeSession?.state, .scrollReady)
        XCTAssertTrue(panel.isVisible, "稍后重启应保留手动模式入口")
        await assertAccess(false, to: .automaticScroll, using: authorization)
    }

    func testRelaunchWaitsForTheOldProcessAndPreservesTheLiteralAppPath() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let stub = root.appending(path: "open stub")
        try "#!/bin/sh\nprintf '%s\\n' \"$@\" > \"${0%/*}/called.txt\"\n".write(to: stub, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: stub.path)
        let app = root.appending(path: "轻截图 $(touch unexpected).app")
        let output = root.appending(path: "called.txt")
        let parent = Process()
        parent.executableURL = URL(fileURLWithPath: "/bin/cat")
        parent.standardInput = Pipe()
        parent.standardOutput = FileHandle.nullDevice
        try parent.run()
        defer { if parent.isRunning { parent.terminate() } }
        let process = AppRelauncher.makeProcess(applicationURL: app, processID: parent.processIdentifier, openExecutableURL: stub)
        let relaunched = expectation(description: "旧进程退出后启动同一路径的应用")
        process.terminationHandler = { _ in relaunched.fulfill() }
        try process.run()
        defer { if process.isRunning { process.terminate() } }
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path), "旧进程退出前不能启动新实例")
        parent.terminate()
        parent.waitUntilExit()
        await fulfillment(of: [relaunched], timeout: 3)
        guard !process.isRunning else { return XCTFail("重启辅助进程未按时退出") }
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(try String(contentsOf: output, encoding: .utf8), "-n\n\(app.path)\n")
    }

    func testSlowSystemPermissionCallLeavesTheMainQueueResponsive() async {
        let entered = expectation(description: "后台权限检查已进入等待")
        let release = DispatchSemaphore(value: 0)
        let operation = Task {
            await CapturePermissionSystemAccess.perform {
                XCTAssertFalse(Thread.isMainThread)
                entered.fulfill()
                return release.wait(timeout: .now() + 3) == .success
            }
        }
        defer { release.signal() }
        await fulfillment(of: [entered], timeout: 1)
        let heartbeat = expectation(description: "权限服务未返回时主线程仍能处理事件")
        DispatchQueue.main.async { heartbeat.fulfill() }
        await fulfillment(of: [heartbeat], timeout: 0.5)
        release.signal()
        let completed = await operation.value
        XCTAssertTrue(completed)
    }

    func testReturningFromSettingsDoesNotWaitForASlowPermissionRecheck() async {
        var shouldWait = false
        var release: CheckedContinuation<Bool, Never>?
        let entered = expectation(description: "权限状态检查尚未返回")
        let reminder = expectation(description: "返回设置无需等待权限服务即可显示提醒")
        var prompts = 0
        let authorization = CapturePermissionAuthorization(
            preflight: { _ in
                guard shouldWait else { return false }
                return await withCheckedContinuation {
                    release = $0
                    entered.fulfill()
                }
            },
            request: { _ in },
            confirm: { _ in true },
            openSettings: { _ in },
            confirmRestart: { prompts += 1; reminder.fulfill(); return false },
            restartApplication: { XCTFail("选择稍后不能重启") }
        )
        await assertAccess(false, to: .automaticScroll, using: authorization)
        shouldWait = true
        let checking = Task { await authorization.checkForPermissionChanges() }
        await fulfillment(of: [entered], timeout: 1)
        await authorization.checkForPermissionChanges(returnedFromSettings: true)
        await fulfillment(of: [reminder], timeout: 0.5)
        release?.resume(returning: true)
        await checking.value
        XCTAssertEqual(prompts, 1, "迟到的状态不能再次弹窗")
    }

    func testRealRestartWindowAllowsMainActorWorkAndBothButtons() async {
        for accept in [false, true] {
            let presenter = PermissionAlertPresenter()
            let alert = CapturePermissionAuthorization.makeRestartAlert()
            let presenting = Task { await presenter.present(alert) }
            defer { presenting.cancel() }
            for _ in 0 ..< 20 where !alert.window.isVisible {
                await Task.yield()
            }
            XCTAssertTrue(alert.window.isVisible)
            let heartbeat = expectation(description: "真实重启窗口保持打开时主线程仍可运行")
            Task { @MainActor in heartbeat.fulfill() }
            await fulfillment(of: [heartbeat], timeout: 0.5)
            XCTAssertTrue(alert.window.isVisible, "响应性检查必须发生在窗口关闭之前")
            alert.buttons[accept ? 0 : 1].performClick(nil)
            let accepted = await presenting.value
            XCTAssertEqual(accepted, accept)
            XCTAssertFalse(alert.window.isVisible)
        }
    }

    func testCancellingThePresentationClosesTheRealWindowAndAllowsAnotherPrompt() async {
        let presenter = PermissionAlertPresenter()
        let alert = CapturePermissionAuthorization.makeRestartAlert()
        let presenting = Task { await presenter.present(alert) }
        for _ in 0 ..< 20 where !alert.window.isVisible {
            await Task.yield()
        }
        XCTAssertTrue(alert.window.isVisible)
        presenting.cancel()
        let accepted = await presenting.value
        XCTAssertFalse(accepted)
        XCTAssertFalse(alert.window.isVisible)
        let next = CapturePermissionAuthorization.makeRestartAlert()
        let nextPresentation = Task { await presenter.present(next) }
        for _ in 0 ..< 20 where !next.window.isVisible {
            await Task.yield()
        }
        XCTAssertTrue(next.window.isVisible)
        next.buttons[1].performClick(nil)
        let nextAccepted = await nextPresentation.value
        XCTAssertFalse(nextAccepted)
    }

    func testStoppingDuringASlowNativeRequestDoesNotOpenSettingsAfterItCompletes() async {
        let entered = expectation(description: "系统授权请求尚未返回")
        var release: CheckedContinuation<Void, Never>?
        let authorization = CapturePermissionAuthorization(
            preflight: { _ in false },
            request: { _ in
                await withCheckedContinuation {
                    release = $0
                    entered.fulfill()
                }
            },
            confirm: { _ in true },
            openSettings: { _ in XCTFail("结束授权后不能由迟到的请求再次打开设置") }
        )
        let authorizing = Task { await authorization.ensureAccess(to: .automaticScroll) }
        await fulfillment(of: [entered], timeout: 1)
        authorizing.cancel()
        authorization.stopMonitoring()
        release?.resume()
        let allowed = await authorizing.value
        XCTAssertFalse(allowed)
    }

    private func assertAccess(_ expected: Bool, to permission: CapturePermissionKind, using authorization: CapturePermissionAuthorization, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) async {
        let allowed = await authorization.ensureAccess(to: permission)
        XCTAssertEqual(allowed, expected, message, file: file, line: line)
    }
}
