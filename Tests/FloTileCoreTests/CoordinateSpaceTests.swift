import XCTest
import CoreGraphics
@testable import FloTileCore

final class CoordinateSpaceTests: XCTestCase {
    let cs = CoordinateSpace(primaryScreenHeight: 900)

    func testBelowMenuBar() {
        let r = cs.appKitRect(fromAXOrigin: CGPoint(x: 0, y: 25), size: CGSize(width: 100, height: 100))
        XCTAssertEqual(r, CGRect(x: 0, y: 775, width: 100, height: 100))
    }

    func testMenuBar() {
        let r = cs.appKitRect(fromAXOrigin: .zero, size: CGSize(width: 1440, height: 25))
        XCTAssertEqual(r.minY, 875)
        XCTAssertEqual(r.maxY, 900)
    }

    func testLeftDisplayKeepsX() {
        let r = cs.appKitRect(fromAXOrigin: CGPoint(x: -1000, y: 0), size: CGSize(width: 100, height: 100))
        XCTAssertEqual(r.minX, -1000)
    }

    func testDisplayAbove() {
        let r = cs.appKitRect(fromAXOrigin: CGPoint(x: 0, y: -500), size: CGSize(width: 200, height: 200))
        XCTAssertEqual(r.minY, 1200)
    }

    func testRoundTrips() {
        let sizes = [CGSize(width: 1, height: 1), CGSize(width: 100, height: 50), CGSize(width: 1512, height: 944)]
        for x in stride(from: -2560.0, through: 2560.0, by: 640.0) {
            for y in stride(from: -1000.0, through: 2000.0, by: 250.0) {
                for s in sizes {
                    let o = CGPoint(x: x, y: y)
                    let r = cs.appKitRect(fromAXOrigin: o, size: s)
                    XCTAssertEqual(cs.axOrigin(fromAppKit: r), o)
                    // Reverse direction: AppKit rect -> AX origin -> AppKit rect.
                    let back = cs.appKitRect(fromAXOrigin: cs.axOrigin(fromAppKit: r), size: r.size)
                    XCTAssertEqual(back, r)
                    let ak = CGRect(origin: o, size: s)
                    XCTAssertEqual(cs.appKitRect(fromAXOrigin: cs.axOrigin(fromAppKit: ak), size: ak.size), ak)
                }
            }
        }
    }
}
