import CoreGraphics
@testable import LightCapture
import XCTest

final class LongCaptureEngineTests: XCTestCase {
    func testNormalizedPixelsRoundTripThroughCGImageProvider() throws {
        let source = patternedImage(width: 24, height: 40)
        let bytes = try XCTUnwrap(RGBAFrame(image: source)).bytes
        let image = makeImage(bytes: bytes, width: 24, height: 40)
        let roundTrip = pixelBytes(image)
        let expected = Data(bytes)
        XCTAssertEqual(roundTrip, expected)
    }

    func testNormalizedPixelsStartWithTheKnownTopLeftPixel() throws {
        let frame = try XCTUnwrap(RGBAFrame(image: patternedImage(width: 24, height: 40)))
        XCTAssertEqual(frame.pixel(x: 0, y: 0), 0x0000_00FF)
        XCTAssertEqual(frame.pixel(x: 1, y: 0), 0x0B17_1FFF)
    }

    func testMatcherFindsDisplacementsBetweenTheOldCoarseSteps() async throws {
        let page = patternedImage(width: 32, height: 900)
        let previous = try XCTUnwrap(page.cropping(topLeftRect: CGRect(x: 0, y: 0, width: 32, height: 600)))
        for offset in [74, 128, 210] {
            let current = try XCTUnwrap(page.cropping(topLeftRect: CGRect(x: 0, y: offset, width: 32, height: 600)))
            let match = await OverlapMatcher.match(previous: previous, current: current)
            XCTAssertEqual(match, .accepted(verticalDisplacement: offset, horizontalDrift: 0))
        }
    }

    func testMatcherRejectsOnePixelHorizontalDriftToPreserveFullWidth() async throws {
        let page = patternedImage(width: 32, height: 64)
        let previous = try XCTUnwrap(page.cropping(topLeftRect: CGRect(x: 0, y: 0, width: 24, height: 32)))
        let current = try XCTUnwrap(page.cropping(topLeftRect: CGRect(x: 1, y: 8, width: 24, height: 32)))
        guard case .ambiguous = await OverlapMatcher.match(previous: previous, current: current) else {
            return XCTFail("未经对齐的横向漂移不能写入全宽长图")
        }
    }

    func testMatcherFindsUniqueDownwardDisplacement() async throws {
        let page = patternedImage(width: 24, height: 48)
        let previous = try XCTUnwrap(page.cropping(topLeftRect: CGRect(x: 0, y: 0, width: 24, height: 32)))
        let current = try XCTUnwrap(page.cropping(topLeftRect: CGRect(x: 0, y: 8, width: 24, height: 32)))
        let previousPixels = try XCTUnwrap(RGBAFrame(image: previous))
        let currentPixels = try XCTUnwrap(RGBAFrame(image: current))
        XCTAssertEqual(previousPixels.pixel(x: 3, y: 8), currentPixels.pixel(x: 3, y: 0), "相同的页面行必须在两帧中具有相同像素")

        let match = await OverlapMatcher.match(previous: previous, current: current)
        XCTAssertEqual(match, .accepted(verticalDisplacement: 8, horizontalDrift: 0))
    }

    func testMatcherRejectsRepeatedRowsAsAmbiguous() async throws {
        let page = patternedImage(width: 16, height: 64, rowPeriod: 4)
        let previous = try XCTUnwrap(page.cropping(topLeftRect: CGRect(x: 0, y: 0, width: 16, height: 32)))
        let current = try XCTUnwrap(page.cropping(topLeftRect: CGRect(x: 0, y: 6, width: 16, height: 32)))

        guard case .ambiguous = await OverlapMatcher.match(previous: previous, current: current) else {
            XCTFail("重复行的拼接位置必须被拒绝")
            return
        }
    }

    func testEngineStoresOnlyNewBottomRowsAndRebuildsOriginalOrder() async throws {
        let workspace = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let page = patternedImage(width: 24, height: 48)
        let previous = try XCTUnwrap(page.cropping(topLeftRect: CGRect(x: 0, y: 0, width: 24, height: 32)))
        let current = try XCTUnwrap(page.cropping(topLeftRect: CGRect(x: 0, y: 8, width: 24, height: 32)))
        let engine = await MainActor.run { LongCaptureEngine(sessionID: UUID(), workspaceRootURL: workspace) }

        let first = await engine.consume(previous)
        let second = await engine.consume(current)
        XCTAssertEqual(first, .waitingForStableFrame)
        XCTAssertEqual(second, .appended(height: 40, addedPixels: 8))

        let stitched = try await engine.finish()
        let expected = try XCTUnwrap(page.cropping(topLeftRect: CGRect(x: 0, y: 0, width: 24, height: 40)))
        XCTAssertEqual(stitched.width, expected.width)
        XCTAssertEqual(stitched.height, expected.height)
        let stitchedBytes = pixelBytes(stitched)
        let expectedBytes = pixelBytes(expected)
        XCTAssertEqual(stitchedBytes, expectedBytes)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: workspace.path).isEmpty)
    }

    func testExternalPauseKeepsOnlyPreviouslyConfirmedTiles() async throws {
        let workspace = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let page = patternedImage(width: 24, height: 64)
        let firstFrame = try XCTUnwrap(page.cropping(topLeftRect: CGRect(x: 0, y: 0, width: 24, height: 32)))
        let secondFrame = try XCTUnwrap(page.cropping(topLeftRect: CGRect(x: 0, y: 8, width: 24, height: 32)))
        let thirdFrame = try XCTUnwrap(page.cropping(topLeftRect: CGRect(x: 0, y: 16, width: 24, height: 32)))
        let engine = await MainActor.run { LongCaptureEngine(sessionID: UUID(), workspaceRootURL: workspace) }

        _ = await engine.consume(firstFrame)
        let appended = await engine.consume(secondFrame)
        XCTAssertEqual(appended, .appended(height: 40, addedPixels: 8))
        await engine.pauseIntake(reason: "目标已切换")
        let rejected = await engine.consume(thirdFrame)
        XCTAssertEqual(rejected, .paused(reason: "目标已切换", height: 40))

        let partial = try await engine.finish()
        XCTAssertEqual(partial.height, 40)
        let expected = try XCTUnwrap(page.cropping(topLeftRect: CGRect(x: 0, y: 0, width: 24, height: 40)))
        XCTAssertEqual(pixelBytes(partial), pixelBytes(expected))
    }

    func testSwitchingToManualDropsUnconfirmedStartupFrame() async throws {
        let workspace = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let page = patternedImage(width: 24, height: 64)
        let firstFrame = try XCTUnwrap(page.cropping(topLeftRect: CGRect(x: 0, y: 0, width: 24, height: 32)))
        let scrolledFrame = try XCTUnwrap(page.cropping(topLeftRect: CGRect(x: 0, y: 16, width: 24, height: 32)))
        let engine = await MainActor.run { LongCaptureEngine(sessionID: UUID(), workspaceRootURL: workspace) }

        let first = await engine.consume(firstFrame)
        XCTAssertEqual(first, .waitingForStableFrame)
        await engine.pauseIntake(reason: "自动模式已暂停")
        await engine.resume(discardUnconfirmedCandidate: true)

        let firstManualFrame = await engine.consume(scrolledFrame)
        let stableManualFrame = await engine.consume(scrolledFrame)
        XCTAssertEqual(firstManualFrame, .waitingForStableFrame)
        XCTAssertEqual(stableManualFrame, .initialized(height: 32))
        let result = try await engine.finish()
        XCTAssertEqual(pixelBytes(result), pixelBytes(scrolledFrame))
    }

    func testMatcherPausesOnHorizontalDriftBeyondTolerance() async throws {
        let page = patternedImage(width: 32, height: 64)
        let previous = try XCTUnwrap(page.cropping(topLeftRect: CGRect(x: 0, y: 0, width: 24, height: 32)))
        let current = try XCTUnwrap(page.cropping(topLeftRect: CGRect(x: 3, y: 8, width: 24, height: 32)))

        guard case .ambiguous = await OverlapMatcher.match(previous: previous, current: current) else {
            XCTFail("横向漂移超过容差时不能拼接")
            return
        }
    }

    @MainActor
    func testHeightLimitPreservesExactlyThePreviouslyConfirmedRows() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let page = patternedImage(width: 1, height: 50000)
        let pixels = try XCTUnwrap(RGBAFrame(image: page))
        let store = try TileStore(width: 1, sessionID: UUID(), rootURL: root)
        try store.appendFirstFrame(pixels)
        XCTAssertThrowsError(try store.appendBottomRows(from: pixels, startY: 49999, count: 1, sequence: 1)) { error in
            guard case TileStoreError.capacityReached = error else { return XCTFail("应触发高度上限") }
        }
        XCTAssertEqual(store.totalHeight, 50000)
        XCTAssertEqual(try store.renderImage().dataProvider?.data as Data?, page.dataProvider?.data as Data?)
    }

    @MainActor
    func testTileStoreRejectsLinkedWorkspaceRootAndCleanupPreservesItsDestination() throws {
        let fixture = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let external = fixture.appending(path: "external", directoryHint: .isDirectory)
        let unrelated = external.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
        let sentinel = unrelated.appending(path: "keep.txt")
        try Data("用户文件".utf8).write(to: sentinel)
        let root = fixture.appending(path: "Working", directoryHint: .isDirectory)
        try FileManager.default.createSymbolicLink(at: root, withDestinationURL: external)

        XCTAssertThrowsError(try TileStore(width: 4, sessionID: UUID(), rootURL: root))
        TileStore.cleanupAbandonedWorkspaces(rootURL: root)
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("用户文件".utf8))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: external.path), [unrelated.lastPathComponent])
    }

    @MainActor
    func testTileStoreRejectsAnExistingSessionSymlinkWithoutWritingToItsDestination() throws {
        let fixture = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let root = fixture.appending(path: "Working", directoryHint: .isDirectory)
        let external = fixture.appending(path: "external", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        let sessionID = UUID()
        try FileManager.default.createSymbolicLink(at: root.appending(path: sessionID.uuidString), withDestinationURL: external)

        XCTAssertThrowsError(try TileStore(width: 4, sessionID: sessionID, rootURL: root))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: external.path).isEmpty)
    }

    @MainActor
    func testTileStoreRejectsReusingAnExistingSessionDirectory() throws {
        let fixture = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let sessionID = UUID()
        let directory = fixture.appending(path: sessionID.uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sentinel = directory.appending(path: "keep.txt")
        try Data("已有内容".utf8).write(to: sentinel)
        XCTAssertThrowsError(try TileStore(width: 4, sessionID: sessionID, rootURL: fixture))
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("已有内容".utf8))
    }

    @MainActor
    func testTileStoreStopsWhenItsRootIsReplacedByASymlink() throws {
        let fixture = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let root = fixture.appending(path: "Working", directoryHint: .isDirectory)
        let sessionID = UUID()
        let store = try TileStore(width: 4, sessionID: sessionID, rootURL: root)
        let pixels = try XCTUnwrap(RGBAFrame(image: patternedImage(width: 4, height: 4)))
        try store.appendFirstFrame(pixels)
        let external = fixture.appending(path: "external", directoryHint: .isDirectory)
        let unrelated = external.appending(path: sessionID.uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
        let sentinel = unrelated.appending(path: "keep.txt")
        try Data("用户文件".utf8).write(to: sentinel)
        try FileManager.default.moveItem(at: root, to: fixture.appending(path: "original"))
        try FileManager.default.createSymbolicLink(at: root, withDestinationURL: external)

        XCTAssertThrowsError(try store.appendBottomRows(from: pixels, startY: 3, count: 1, sequence: 1))
        XCTAssertThrowsError(try store.renderImage())
        store.cancel()
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("用户文件".utf8))
    }

    @MainActor
    func testOversizedStartupDoesNotCreateAWorkingDirectory() async {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let image = patternedImage(width: 1, height: 50001)
        let engine = LongCaptureEngine(sessionID: UUID(), workspaceRootURL: root)
        guard case .paused = await engine.consume(image) else { return XCTFail("首帧超限应暂停") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testMatcherRejectsReverseScrollingAndInsufficientOverlap() async throws {
        let page = patternedImage(width: 32, height: 1400)
        let previous = try XCTUnwrap(page.cropping(topLeftRect: CGRect(x: 0, y: 100, width: 32, height: 600)))
        for offset in [20, 580] {
            let current = try XCTUnwrap(page.cropping(topLeftRect: CGRect(x: 0, y: offset, width: 32, height: 600)))
            guard case .ambiguous = await OverlapMatcher.match(previous: previous, current: current) else { return XCTFail("反向或超过 75% 视口的滚动不能写入") }
        }
    }

    func testFullWidthVerificationMovesTheJoinPastAChangeBetweenSampledPixels() async throws {
        let page = patternedImage(width: 128, height: 900)
        let previous = try XCTUnwrap(page.cropping(topLeftRect: CGRect(x: 0, y: 0, width: 128, height: 600)))
        let current = try XCTUnwrap(page.cropping(topLeftRect: CGRect(x: 0, y: 74, width: 128, height: 600)))
        var bytes = try XCTUnwrap(RGBAFrame(image: current)).bytes
        bytes[(525 * 128 + 1) * 4] ^= 255
        let changed = makeImage(bytes: bytes, width: 128, height: 600)
        let match = await OverlapMatcher.match(previous: previous, current: changed)
        XCTAssertEqual(match, .accepted(verticalDisplacement: 74, horizontalDrift: 0, replacingBottomRows: 1))
    }

    @MainActor
    func testTailReplacementCanSpanTilesAndPreservesExactSourceRows() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let page = patternedImage(width: 24, height: 100)
        let first = try XCTUnwrap(page.cropping(topLeftRect: CGRect(x: 0, y: 0, width: 24, height: 32)))
        let store = try TileStore(width: 24, sessionID: UUID(), rootURL: root)
        try store.appendFirstFrame(XCTUnwrap(RGBAFrame(image: first)))
        let pixels = try XCTUnwrap(RGBAFrame(image: page))
        XCTAssertTrue(try store.appendBottomRows(from: pixels, startY: 32, count: 2, sequence: 1))
        XCTAssertTrue(try store.appendBottomRows(from: pixels, startY: 31, count: 7, sequence: 2, replacingBottomRows: 3))
        XCTAssertFalse(try store.appendBottomRows(from: pixels, startY: 31, count: 7, sequence: 2, replacingBottomRows: 3))
        XCTAssertEqual(store.totalHeight, 38)
        let expected = try XCTUnwrap(page.cropping(topLeftRect: CGRect(x: 0, y: 0, width: 24, height: 38)))
        XCTAssertEqual(try pixelBytes(store.renderImage()), pixelBytes(expected))
    }

    @MainActor
    func testFailedReplacementWritePreservesAllConfirmedRows() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let sessionID = UUID()
        let page = patternedImage(width: 24, height: 32)
        let pixels = try XCTUnwrap(RGBAFrame(image: page))
        let store = try TileStore(width: 24, sessionID: sessionID, rootURL: root)
        try store.appendFirstFrame(pixels)
        try Data([0]).write(to: root.appending(path: sessionID.uuidString).appending(path: "00000001.rgba"))
        XCTAssertThrowsError(try store.appendBottomRows(from: pixels, startY: 20, count: 12, sequence: 1, replacingBottomRows: 3))
        XCTAssertEqual(store.totalHeight, 32)
        XCTAssertEqual(store.lastSequence, 0)
        XCTAssertEqual(try pixelBytes(store.renderImage()), pixelBytes(page))
    }

    @MainActor
    func testTransientMismatchRecoversWithoutSkippingOrDuplicatingRows() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let page = patternedImage(width: 128, height: 1000)
        let first = try XCTUnwrap(page.cropping(topLeftRect: CGRect(x: 0, y: 0, width: 128, height: 600)))
        let current = try XCTUnwrap(page.cropping(topLeftRect: CGRect(x: 0, y: 74, width: 128, height: 600)))
        let next = try XCTUnwrap(page.cropping(topLeftRect: CGRect(x: 0, y: 158, width: 128, height: 600)))
        var bytes = try XCTUnwrap(RGBAFrame(image: current)).bytes
        // Simulate a transient repaint across the join, which must never be committed.
        for index in (500 * 128 * 4) ..< (530 * 128 * 4) {
            bytes[index] ^= 127
        }
        let unstable = makeImage(bytes: bytes, width: 128, height: 600)
        var time = 0.0
        let engine = LongCaptureEngine(sessionID: UUID(), workspaceRootURL: root, now: { time })
        _ = await engine.consume(first)
        let initialized = await engine.consume(first)
        XCTAssertEqual(initialized, .initialized(height: 600))
        for _ in 0 ..< 3 {
            time += 0.2
            let waiting = await engine.consume(unstable)
            XCTAssertEqual(waiting, .waitingForStableFrame)
            XCTAssertFalse(engine.isPaused)
        }
        let recovered = await engine.consume(current)
        XCTAssertEqual(recovered, .appended(height: 674, addedPixels: 74))
        let appended = await engine.consume(next)
        XCTAssertEqual(appended, .appended(height: 758, addedPixels: 84))
        let duplicate = await engine.consume(next)
        XCTAssertEqual(duplicate, .unchanged(height: 758))
        let result = try engine.finish()
        let expected = try XCTUnwrap(page.cropping(topLeftRect: CGRect(x: 0, y: 0, width: 128, height: 758)))
        XCTAssertEqual(pixelBytes(result), pixelBytes(expected))
    }

    @MainActor
    func testPersistentMismatchPausesAndPreservesTheLastConfirmedImage() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let page = patternedImage(width: 128, height: 1400)
        let first = try XCTUnwrap(page.cropping(topLeftRect: CGRect(x: 0, y: 0, width: 128, height: 600)))
        let tooFar = try XCTUnwrap(page.cropping(topLeftRect: CGRect(x: 0, y: 600, width: 128, height: 600)))
        var time = 0.0
        let engine = LongCaptureEngine(sessionID: UUID(), workspaceRootURL: root, now: { time })
        _ = await engine.consume(first)
        _ = await engine.consume(first)
        for step in 0 ..< 3 {
            time = Double(step) * 0.7
            let update = await engine.consume(tooFar)
            XCTAssertEqual(update, .waitingForStableFrame)
        }
        time = 2
        let rejected = await engine.consume(tooFar)
        guard case .paused(_, height: 600) = rejected else { return XCTFail("持续无法匹配时必须暂停") }
        XCTAssertTrue(engine.isPaused)
        XCTAssertEqual(try pixelBytes(engine.finish()), pixelBytes(first))
    }

    @MainActor
    func testResumingMismatchStartsANewGracePeriod() async {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = patternedImage(width: 24, height: 32)
        let gate = TestOverlapMatchSequence(results: [.unchanged, .ambiguous("变化"), .ambiguous("变化")])
        var time = 0.0
        let engine = LongCaptureEngine(sessionID: UUID(), workspaceRootURL: root, matcher: { _, _ in await gate.next() }, now: { time })
        _ = await engine.consume(first)
        _ = await engine.consume(first)
        _ = await engine.consume(first)
        engine.pauseIntake(reason: "用户暂停")
        time = 100
        engine.resume()
        let update = await engine.consume(first)
        XCTAssertEqual(update, .waitingForStableFrame)
        XCTAssertFalse(engine.isPaused)
        engine.cancel()
    }

    @MainActor
    func testEngineRejectsInvalidMatcherGeometryBeforeWriting() async {
        let frame = patternedImage(width: 24, height: 32)
        for match in [OverlapMatch.accepted(verticalDisplacement: 0, horizontalDrift: 0), .accepted(verticalDisplacement: 8, horizontalDrift: 1), .accepted(verticalDisplacement: 25, horizontalDrift: 0)] {
            let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: root) }
            let engine = LongCaptureEngine(sessionID: UUID(), workspaceRootURL: root, matcher: { _, _ in match })
            _ = await engine.consume(frame)
            guard case .paused = await engine.consume(frame) else { return XCTFail("错误位移不能进入图块存储") }
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        }
    }

    @MainActor
    func testSwitchingToManualInvalidatesAnInFlightStartupMatch() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = TestOverlapMatchGate()
        let engine = LongCaptureEngine(sessionID: UUID(), workspaceRootURL: root, matcher: { _, _ in await gate.match() })
        let page = patternedImage(width: 24, height: 64)
        let first = try XCTUnwrap(page.cropping(topLeftRect: CGRect(x: 0, y: 0, width: 24, height: 32)))
        let scrolled = try XCTUnwrap(page.cropping(topLeftRect: CGRect(x: 0, y: 8, width: 24, height: 32)))
        _ = await engine.consume(first)
        let pending = Task { @MainActor in await engine.consume(scrolled) }
        await gate.waitUntilStarted()
        engine.resume(discardUnconfirmedCandidate: true)
        await gate.finish()
        _ = await pending.value
        let newManualFrame = await engine.consume(scrolled)
        XCTAssertEqual(newManualFrame, .waitingForStableFrame)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        engine.cancel()
    }

    private func patternedImage(width: Int, height: Int, rowPeriod: Int = 0) -> CGImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0 ..< height {
            let encodedRow = rowPeriod > 0 ? y % rowPeriod : y
            for x in 0 ..< width {
                let offset = (y * width + x) * 4
                bytes[offset] = UInt8((encodedRow * 37 + x * 11) % 251)
                bytes[offset + 1] = UInt8((encodedRow * 67 + x * 23) % 253)
                bytes[offset + 2] = UInt8((encodedRow * 97 + x * 31) % 255)
                bytes[offset + 3] = 255
            }
        }
        let data = Data(bytes) as CFData
        let provider = CGDataProvider(data: data)!
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue))
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }

    private func pixelBytes(_ image: CGImage) -> Data {
        let frame = RGBAFrame(image: image)!
        return Data(frame.bytes)
    }

    private func makeImage(bytes: [UInt8], width: Int, height: Int) -> CGImage {
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue))
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }
}

private actor TestOverlapMatchSequence {
    private var results: [OverlapMatch]

    init(results: [OverlapMatch]) {
        self.results = results
    }

    func next() -> OverlapMatch {
        results.removeFirst()
    }
}

private actor TestOverlapMatchGate {
    private var didStart = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var resultWaiter: CheckedContinuation<OverlapMatch, Never>?

    func match() async -> OverlapMatch {
        await withCheckedContinuation { continuation in
            resultWaiter = continuation
            didStart = true
            startWaiter?.resume()
            startWaiter = nil
        }
    }

    func waitUntilStarted() async {
        if didStart { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func finish() {
        resultWaiter?.resume(returning: .accepted(verticalDisplacement: 8, horizontalDrift: 0))
        resultWaiter = nil
    }
}
