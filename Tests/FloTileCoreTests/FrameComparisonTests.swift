import XCTest
import CoreGraphics
@testable import FloTileCore

final class FrameComparisonTests: XCTestCase {
    private let base = CGRect(x: 100, y: 100, width: 400, height: 300)

    func testIdentical() {
        XCTAssertTrue(FrameComparison.approximatelyEqual(base, base))
    }

    func testEachEdgeOffByExactlyTolerance() {
        // minX only
        XCTAssertTrue(FrameComparison.approximatelyEqual(base, CGRect(x: 102, y: 100, width: 398, height: 300)))
        // minY only
        XCTAssertTrue(FrameComparison.approximatelyEqual(base, CGRect(x: 100, y: 102, width: 400, height: 298)))
        // maxX only
        XCTAssertTrue(FrameComparison.approximatelyEqual(base, CGRect(x: 100, y: 100, width: 402, height: 300)))
        // maxY only
        XCTAssertTrue(FrameComparison.approximatelyEqual(base, CGRect(x: 100, y: 100, width: 400, height: 302)))
    }

    func testEdgeOffByMoreThanTolerance() {
        XCTAssertFalse(FrameComparison.approximatelyEqual(base, CGRect(x: 102.5, y: 100, width: 397.5, height: 300)))
        XCTAssertFalse(FrameComparison.approximatelyEqual(base, CGRect(x: 100, y: 102.5, width: 400, height: 297.5)))
        XCTAssertFalse(FrameComparison.approximatelyEqual(base, CGRect(x: 100, y: 100, width: 402.5, height: 300)))
        XCTAssertFalse(FrameComparison.approximatelyEqual(base, CGRect(x: 100, y: 100, width: 400, height: 302.5)))
    }

    func testNegativeCoordinates() {
        let a = CGRect(x: -1500, y: -200, width: 800, height: 600)
        XCTAssertTrue(FrameComparison.approximatelyEqual(a, a.offsetBy(dx: -2, dy: 2)))
        XCTAssertFalse(FrameComparison.approximatelyEqual(a, a.offsetBy(dx: -3, dy: 0)))
    }

    func testSizeOnlyChangeBeyondTolerance() {
        XCTAssertFalse(FrameComparison.approximatelyEqual(base, CGRect(x: 100, y: 100, width: 410, height: 300)))
    }

    func testCustomTolerance() {
        XCTAssertTrue(FrameComparison.approximatelyEqual(base, base.offsetBy(dx: 5, dy: 0), tolerance: 5))
        XCTAssertFalse(FrameComparison.approximatelyEqual(base, base.offsetBy(dx: 5, dy: 0), tolerance: 4))
    }
}
