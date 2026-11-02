import XCTest
import CoreGraphics
@testable import FloTileCore

final class WindowInfoTests: XCTestCase {
    func testWindowIDEqualityAndHash() {
        XCTAssertEqual(WindowID(1), WindowID(1))
        XCTAssertNotEqual(WindowID(1), WindowID(2))
        XCTAssertEqual(WindowID(7).rawValue, 7)
        XCTAssertEqual(Set([WindowID(1), WindowID(1), WindowID(2)]).count, 2)
        let d: [WindowID: String] = [WindowID(1): "a", WindowID(2): "b"]
        XCTAssertEqual(d[WindowID(2)], "b")
    }

    func testWindowInfoValueSemantics() {
        let f = CGRect(x: 1, y: 2, width: 3, height: 4)
        let a = WindowInfo(id: WindowID(1), frame: f, isMinimized: true, isStandard: false, discoveryIndex: 5)
        XCTAssertEqual(a.id, WindowID(1))
        XCTAssertEqual(a.frame, f)
        XCTAssertTrue(a.isMinimized)
        XCTAssertFalse(a.isStandard)
        XCTAssertEqual(a.discoveryIndex, 5)
        XCTAssertEqual(a, WindowInfo(id: WindowID(1), frame: f, isMinimized: true, isStandard: false, discoveryIndex: 5))
        XCTAssertNotEqual(a, WindowInfo(id: WindowID(1), frame: f, isMinimized: true, isStandard: false, discoveryIndex: 6))
    }

    func testScreenInfoValueSemantics() {
        let f = CGRect(x: 0, y: 0, width: 100, height: 100)
        let v = CGRect(x: 0, y: 0, width: 100, height: 80)
        let a = ScreenInfo(id: ScreenID(3), frame: f, visibleFrame: v)
        XCTAssertEqual(a.id, ScreenID(3))
        XCTAssertEqual(a.frame, f)
        XCTAssertEqual(a.visibleFrame, v)
        XCTAssertEqual(a, ScreenInfo(id: ScreenID(3), frame: f, visibleFrame: v))
        XCTAssertNotEqual(a, ScreenInfo(id: ScreenID(4), frame: f, visibleFrame: v))
    }
}
