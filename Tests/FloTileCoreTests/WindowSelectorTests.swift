import XCTest
import CoreGraphics
@testable import FloTileCore

final class WindowSelectorTests: XCTestCase {
    private func screen(_ id: Int, x: CGFloat, y: CGFloat = 0, w: CGFloat = 1000, h: CGFloat = 800) -> ScreenInfo {
        let r = CGRect(x: x, y: y, width: w, height: h)
        return ScreenInfo(id: ScreenID(id), frame: r, visibleFrame: r)
    }

    private func win(_ id: Int, _ frame: CGRect, minimized: Bool = false, standard: Bool = true, index: Int? = nil) -> WindowInfo {
        WindowInfo(id: WindowID(id), frame: frame, isMinimized: minimized, isStandard: standard, discoveryIndex: index ?? id)
    }

    private func ids(_ ws: [WindowInfo]) -> [Int] { ws.map { $0.id.rawValue } }

    private var main: ScreenInfo { screen(1, x: 0) }
    private var right: ScreenInfo { screen(2, x: 1000) }
    private let ok = CGRect(x: 100, y: 100, width: 200, height: 200)

    func testStandardNonMinimizedIncluded() {
        XCTAssertEqual(ids(WindowSelector.eligibleWindows([win(1, ok)], on: main)), [1])
    }

    func testMinimizedExcluded() {
        XCTAssertTrue(WindowSelector.eligibleWindows([win(1, ok, minimized: true)], on: main).isEmpty)
    }

    func testNonStandardExcluded() {
        XCTAssertTrue(WindowSelector.eligibleWindows([win(1, ok, standard: false)], on: main).isEmpty)
    }

    func testCenterOnOtherDisplayExcludedEvenIfOverlapping() {
        // x 900..1300, center 1100 -> on right screen, but overlaps main.
        let w = win(1, CGRect(x: 900, y: 100, width: 400, height: 200))
        XCTAssertTrue(WindowSelector.eligibleWindows([w], on: main).isEmpty)
        XCTAssertEqual(ids(WindowSelector.eligibleWindows([w], on: right)), [1])
    }

    func testStraddlingWindowIncludedOnlyWhereCenterIs() {
        let onMain = win(1, CGRect(x: 800, y: 100, width: 399, height: 200)) // center 999.5
        let pastBoundary = win(2, CGRect(x: 800, y: 100, width: 401, height: 200)) // center 1000.5
        XCTAssertEqual(ids(WindowSelector.eligibleWindows([onMain, pastBoundary], on: main)), [1])
        XCTAssertEqual(ids(WindowSelector.eligibleWindows([onMain, pastBoundary], on: right)), [2])
    }

    func testCenterOnMaxXEdgeExcluded() {
        let w = win(1, CGRect(x: 900, y: 100, width: 200, height: 200)) // center x = 1000
        XCTAssertTrue(WindowSelector.eligibleWindows([w], on: main).isEmpty)
    }

    func testCenterOnMaxYEdgeExcluded() {
        let w = win(1, CGRect(x: 100, y: 700, width: 200, height: 200)) // center y = 800
        XCTAssertTrue(WindowSelector.eligibleWindows([w], on: main).isEmpty)
    }

    func testCenterAtOriginIncluded() {
        let w = win(1, CGRect(x: -100, y: -100, width: 200, height: 200)) // center (0,0)
        XCTAssertEqual(ids(WindowSelector.eligibleWindows([w], on: main)), [1])
    }

    func testZeroWidthExcluded() {
        XCTAssertTrue(WindowSelector.eligibleWindows([win(1, CGRect(x: 100, y: 100, width: 0, height: 200))], on: main).isEmpty)
    }

    func testZeroHeightExcluded() {
        XCTAssertTrue(WindowSelector.eligibleWindows([win(1, CGRect(x: 100, y: 100, width: 200, height: 0))], on: main).isEmpty)
    }

    func testEligibleKeepsInputOrder() {
        let ws = [win(3, ok), win(1, ok), win(2, ok)]
        XCTAssertEqual(ids(WindowSelector.eligibleWindows(ws, on: main)), [3, 1, 2])
    }

    func testEmptyInput() {
        XCTAssertTrue(WindowSelector.eligibleWindows([], on: main).isEmpty)
        XCTAssertTrue(WindowSelector.readingOrder([]).isEmpty)
    }

    func testReadingOrderHigherMaxYFirst() {
        let low = win(1, CGRect(x: 0, y: 0, width: 100, height: 100))
        let high = win(2, CGRect(x: 500, y: 300, width: 100, height: 100))
        XCTAssertEqual(ids(WindowSelector.readingOrder([low, high])), [2, 1])
    }

    func testReadingOrderEqualMaxYSmallerMinXFirst() {
        let a = win(1, CGRect(x: 300, y: 0, width: 100, height: 100))
        let b = win(2, CGRect(x: 100, y: 0, width: 100, height: 100))
        XCTAssertEqual(ids(WindowSelector.readingOrder([a, b])), [2, 1])
    }

    func testReadingOrderFullTieSmallerDiscoveryIndexFirst() {
        let a = win(1, ok, index: 7)
        let b = win(2, ok, index: 3)
        XCTAssertEqual(ids(WindowSelector.readingOrder([a, b])), [2, 1])
    }

    func testReadingOrderIdenticalKeysKeepInputOrder() {
        let a = win(1, ok, index: 5)
        let b = win(2, ok, index: 5)
        XCTAssertEqual(ids(WindowSelector.readingOrder([a, b])), [1, 2])
        XCTAssertEqual(ids(WindowSelector.readingOrder([b, a])), [2, 1])
    }

    func testCombinedPipeline() {
        let ws = [
            win(1, CGRect(x: 600, y: 100, width: 200, height: 200), index: 0), // eligible, bottom right
            win(2, CGRect(x: 100, y: 500, width: 200, height: 200), minimized: true, index: 1),
            win(3, CGRect(x: 100, y: 100, width: 200, height: 200), index: 2), // eligible, bottom left
            win(4, CGRect(x: 1200, y: 500, width: 200, height: 200), index: 3), // other screen
            win(5, CGRect(x: 300, y: 500, width: 200, height: 200), standard: false, index: 4),
            win(6, CGRect(x: 400, y: 400, width: 200, height: 300), index: 5), // eligible, top (maxY 700)
        ]
        let result = WindowSelector.readingOrder(WindowSelector.eligibleWindows(ws, on: main))
        XCTAssertEqual(ids(result), [6, 3, 1])
    }
}
