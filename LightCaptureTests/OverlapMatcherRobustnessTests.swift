import CoreGraphics
@testable import LightCapture
import XCTest

final class OverlapMatcherRobustnessTests: XCTestCase {
    func testFindsOffsetDespiteSmallColorRoundingAcrossTheFrame() async throws {
        let page = document(width: 640, height: 1800)
        let first = try crop(page, y: 0)
        let current = try crop(page, y: 97)
        var bytes = try XCTUnwrap(RGBAFrame(image: current)).bytes
        for index in stride(from: 0, to: bytes.count, by: 4) {
            for channel in 0 ..< 3 {
                bytes[index + channel] = UInt8(min(255, Int(bytes[index + channel]) + 2))
            }
        }
        let noisy = image(bytes: bytes, width: current.width, height: current.height)
        let match = await OverlapMatcher.match(previous: first, current: noisy)
        XCTAssertEqual(match, .accepted(verticalDisplacement: 97, horizontalDrift: 0))
    }

    func testIsolatedOverlapChangeDoesNotPauseNormalScrolling() async throws {
        let page = document(width: 640, height: 1800)
        let first = try crop(page, y: 0)
        let current = try crop(page, y: 97)
        let changed = try painting(current, rect: CGRect(x: 17, y: 81, width: 1, height: 1), value: 0)
        let match = await OverlapMatcher.match(previous: first, current: changed)
        XCTAssertEqual(match, .accepted(verticalDisplacement: 97, horizontalDrift: 0))
    }

    func testSmallHoverHighlightUsesContentToConfirmTheOffset() async throws {
        let page = document(width: 640, height: 1800)
        let first = try crop(page, y: 0)
        let current = try crop(page, y: 97)
        let highlighted = try painting(current, rect: CGRect(x: 180, y: 120, width: 20, height: 10), value: 180)
        let match = await OverlapMatcher.match(previous: first, current: highlighted)
        XCTAssertEqual(match, .accepted(verticalDisplacement: 97, horizontalDrift: 0))
    }

    func testStationaryHoverIsNotMistakenForNewRows() async throws {
        let first = try crop(document(width: 640, height: 1800), y: 0)
        let highlighted = try painting(first, rect: CGRect(x: 180, y: 120, width: 20, height: 10), value: 180)
        let match = await OverlapMatcher.match(previous: first, current: highlighted)
        XCTAssertEqual(match, .unchanged)
    }

    func testSeparatedNativeSpellcheckAndHoverChangesDoNotLoseTheAlignment() async throws {
        let page = document(width: 640, height: 1800)
        let first = try crop(page, y: 0)
        var current = try painting(crop(page, y: 97), rect: CGRect(x: 500, y: 20, width: 24, height: 24), value: 180)
        for y in [350, 406, 462] {
            current = try painting(current, rect: CGRect(x: 300, y: y, width: 60, height: 2), value: 180)
        }
        let match = await OverlapMatcher.match(previous: first, current: current)
        XCTAssertEqual(match, .accepted(verticalDisplacement: 97, horizontalDrift: 0))
    }

    func testDistributedChangesCannotUseSmallComponentsToHideARepaint() async throws {
        let page = document(width: 640, height: 1800)
        let first = try crop(page, y: 0)
        var current = try crop(page, y: 97)
        for y in stride(from: 24, to: 470, by: 16) {
            for x in stride(from: 300, to: 624, by: 16) {
                current = try painting(current, rect: CGRect(x: x, y: y, width: 1, height: 1), value: 180)
            }
        }
        let match = await OverlapMatcher.match(previous: first, current: current)
        guard case .ambiguous = match else { return XCTFail("分散重绘仍须受变化面积约束") }
    }

    func testChangingNarrowScrollbarCannotVetoAlignedDocumentContent() async throws {
        let page = document(width: 640, height: 1800)
        let first = try scrollbar(crop(page, y: 0), thumbY: 40)
        let current = try scrollbar(crop(page, y: 97), thumbY: 120)
        let match = await OverlapMatcher.match(previous: first, current: current)
        XCTAssertEqual(match, .accepted(verticalDisplacement: 97, horizontalDrift: 0))
    }

    func testScrollbarChangeAloneCannotCreateProgressEvenWithoutText() async throws {
        let blank = image(bytes: [UInt8](repeating: 255, count: 640 * 600 * 4), width: 640, height: 600)
        for (oldY, newY) in [(100, 200), (200, 100)] {
            let first = try scrollbar(blank, thumbY: oldY)
            let current = try scrollbar(blank, thumbY: newY)
            let match = await OverlapMatcher.match(previous: first, current: current)
            XCTAssertEqual(match, .unchanged)
        }
    }

    func testRightEdgeContentMovesTheJoinInsteadOfBeingIgnoredAsAScrollbar() async throws {
        let page = document(width: 640, height: 1800)
        let first = try crop(page, y: 0)
        let current = try painting(crop(page, y: 97), rect: CGRect(x: 635, y: 501, width: 1, height: 1), value: 0)
        let match = await OverlapMatcher.match(previous: first, current: current)
        XCTAssertEqual(match, .accepted(verticalDisplacement: 97, horizontalDrift: 0, replacingBottomRows: 2), "右侧正文的变化必须参与接缝选择")
    }

    func testLowTextureBlinkCannotInventScrolling() async throws {
        let blank = image(bytes: [UInt8](repeating: 255, count: 640 * 600 * 4), width: 640, height: 600)
        let caret = try painting(blank, rect: CGRect(x: 200, y: 100, width: 2, height: 16), value: 0)
        let match = await OverlapMatcher.match(previous: blank, current: caret)
        guard case .ambiguous = match else { return XCTFail("单个光标不能作为滚动位移的证据") }
    }

    func testWhiteMarginsCannotHideOnePixelHorizontalMovementOfSparseText() async throws {
        let page = document(width: 1024, height: 1800, glyphCount: 5)
        let first = try XCTUnwrap(page.cropping(topLeftRect: CGRect(x: 0, y: 0, width: 1000, height: 600)))
        let current = try XCTUnwrap(page.cropping(topLeftRect: CGRect(x: 1, y: 97, width: 1000, height: 600)))
        let match = await OverlapMatcher.match(previous: first, current: current)
        guard case .ambiguous = match else { return XCTFail("空白不能掩盖正文横向错位") }
    }

    func testLargeRepaintCannotBeAcceptedAsSmallRenderingNoise() async throws {
        let page = document(width: 640, height: 1800)
        let first = try crop(page, y: 0)
        let current = try painting(crop(page, y: 97), rect: CGRect(x: 100, y: 100, width: 300, height: 200), value: 40)
        let match = await OverlapMatcher.match(previous: first, current: current)
        guard case .ambiguous = match else { return XCTFail("大面积内容变化不能写入") }
    }

    func testNearRepeatedContentStillRequiresAUniquePosition() async throws {
        var bytes = [UInt8](repeating: 255, count: 128 * 1200 * 4)
        for y in 0 ..< 1200 {
            for x in 0 ..< 128 {
                let offset = (y * 128 + x) * 4
                bytes[offset] = UInt8(((y % 80) * 37 + x * 11) % 251)
                bytes[offset + 1] = UInt8(((y % 80) * 67 + x * 23) % 253)
                bytes[offset + 2] = UInt8(((y % 80) * 97 + x * 31) % 255)
            }
        }
        let page = image(bytes: bytes, width: 128, height: 1200)
        let first = try crop(page, y: 0)
        let current = try painting(crop(page, y: 37), rect: CGRect(x: 17, y: 81, width: 1, height: 1), value: 0)
        let match = await OverlapMatcher.match(previous: first, current: current)
        guard case .ambiguous = match else { return XCTFail("近似重复纹理也不能随便挑选一个偏移") }
    }

    func testChangedSeamMovesToAnIntactBandButFixedFooterStillCannotBeHidden() async throws {
        let page = document(width: 640, height: 1800)
        let first = try crop(page, y: 0)
        let current = try crop(page, y: 97)
        let changedSeam = try painting(current, rect: CGRect(x: 17, y: 501, width: 1, height: 1), value: 0)
        let seamMatch = await OverlapMatcher.match(previous: first, current: changedSeam)
        XCTAssertEqual(seamMatch, .accepted(verticalDisplacement: 97, horizontalDrift: 0, replacingBottomRows: 2))
        let footer = CGRect(x: 0, y: 590, width: 640, height: 10)
        let withFooter = try painting(first, rect: footer, value: 60)
        let nextWithFooter = try painting(current, rect: footer, value: 60)
        let footerMatch = await OverlapMatcher.match(previous: withFooter, current: nextWithFooter)
        guard case .ambiguous = footerMatch else { return XCTFail("固定底栏不能反复追加到正文") }
    }

    func testNoIntactJoinWithinTheBoundedTailStillPauses() async throws {
        let page = document(width: 640, height: 1800)
        let first = try crop(page, y: 0)
        let changed = try painting(crop(page, y: 97), rect: CGRect(x: 500, y: 400, width: 1, height: 103), value: 180)
        let match = await OverlapMatcher.match(previous: first, current: changed)
        guard case .ambiguous = match else { return XCTFail("不能跨过大段不稳定尾部寻找接缝") }
    }

    @MainActor
    func testNativeDecorationAtTheJoinReplacesTheOldTailWithoutMissingOrDuplicatingRows() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let page = document(width: 640, height: 1800)
        let first = try painting(crop(page, y: 0), rect: CGRect(x: 500, y: 590, width: 60, height: 2), value: 180)
        let engine = LongCaptureEngine(sessionID: UUID(), workspaceRootURL: root)
        _ = await engine.consume(first)
        _ = await engine.consume(first)
        let update = try await engine.consume(crop(page, y: 97))
        XCTAssertEqual(update, .appended(height: 697, addedPixels: 97))
        let result = try engine.finish()
        let expected = try XCTUnwrap(page.cropping(topLeftRect: CGRect(x: 0, y: 0, width: 640, height: 697)))
        XCTAssertEqual(try XCTUnwrap(RGBAFrame(image: result)).bytes, try XCTUnwrap(RGBAFrame(image: expected)).bytes)
    }

    @MainActor
    func testLongSequenceWithOverlapChangesReconstructsEverySourceRowExactly() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let page = document(width: 640, height: 2400)
        let engine = LongCaptureEngine(sessionID: UUID(), workspaceRootURL: root)
        let first = try crop(page, y: 0)
        _ = await engine.consume(first)
        _ = await engine.consume(first)
        var lastOffset = 0
        for offset in [97, 190, 305, 440, 579, 720, 890, 1041] {
            var frame = try painting(crop(page, y: offset), rect: CGRect(x: 180, y: 120, width: 20, height: 10), value: 180)
            frame = try painting(frame, rect: CGRect(x: 500, y: 350, width: 60, height: 2), value: 180)
            let update = await engine.consume(frame)
            XCTAssertEqual(update, .appended(height: offset + 600, addedPixels: offset - lastOffset))
            lastOffset = offset
        }
        let result = try engine.finish()
        let expected = try XCTUnwrap(page.cropping(topLeftRect: CGRect(x: 0, y: 0, width: 640, height: lastOffset + 600)))
        XCTAssertEqual(try XCTUnwrap(RGBAFrame(image: result)).bytes, try XCTUnwrap(RGBAFrame(image: expected)).bytes)
    }

    private func document(width: Int, height: Int, glyphCount: Int? = nil) -> CGImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        var random: UInt64 = 0xC0FFEE
        for row in stride(from: 16, to: height - 16, by: 28) {
            let count = glyphCount ?? min((width - 80) / 9, 24 + row / 28 % 24)
            for glyph in 0 ..< count {
                random = random &* 6_364_136_223_846_793_005 &+ 1
                for y in 0 ..< 12 {
                    for x in 0 ..< 6 where (random >> ((x + y * 7) % 61)) & 1 != 0 {
                        let index = ((row + y) * width + 40 + glyph * 9 + x) * 4
                        bytes[index] = 24
                        bytes[index + 1] = 24
                        bytes[index + 2] = 24
                    }
                }
            }
        }
        return image(bytes: bytes, width: width, height: height)
    }

    private func crop(_ page: CGImage, y: Int) throws -> CGImage {
        try XCTUnwrap(page.cropping(topLeftRect: CGRect(x: 0, y: y, width: page.width, height: 600)))
    }

    private func scrollbar(_ frame: CGImage, thumbY: Int) throws -> CGImage {
        let track = try painting(frame, rect: CGRect(x: frame.width - 10, y: 0, width: 10, height: frame.height), value: 240)
        return try painting(track, rect: CGRect(x: frame.width - 8, y: thumbY, width: 6, height: 70), value: 100)
    }

    private func painting(_ frame: CGImage, rect: CGRect, value: UInt8) throws -> CGImage {
        var bytes = try XCTUnwrap(RGBAFrame(image: frame)).bytes
        for y in Int(rect.minY) ..< Int(rect.maxY) {
            for x in Int(rect.minX) ..< Int(rect.maxX) {
                let offset = (y * frame.width + x) * 4
                for channel in 0 ..< 3 {
                    bytes[offset + channel] = value
                }
            }
        }
        return image(bytes: bytes, width: frame.width, height: frame.height)
    }

    private func image(bytes: [UInt8], width: Int, height: Int) -> CGImage {
        CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)),
                provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }
}
