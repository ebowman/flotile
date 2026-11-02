import XCTest
@testable import FloTileCore

final class TileOutcomeSelfTestLabelTests: XCTestCase {
    func testAccessibilityNotGranted() {
        XCTAssertEqual(TileOutcome.accessibilityNotGranted.selfTestLabel, "accessibilityNotGranted")
    }

    func testNoFrontmostApp() {
        XCTAssertEqual(TileOutcome.noFrontmostApp.selfTestLabel, "noFrontmostApp")
    }

    func testNoWindows() {
        XCTAssertEqual(TileOutcome.noWindows.selfTestLabel, "noWindows")
    }

    func testTiled() {
        XCTAssertEqual(TileOutcome.tiled(count: 2).selfTestLabel, "tiled:2")
    }

    func testPartial() {
        XCTAssertEqual(TileOutcome.partial(succeeded: 1, failed: 3).selfTestLabel, "partial:1/3")
    }

    func testRestored() {
        XCTAssertEqual(TileOutcome.restored(count: 4).selfTestLabel, "restored:4")
    }

    func testFailed() {
        XCTAssertEqual(TileOutcome.failed(reason: "boom").selfTestLabel, "failed:boom")
    }
}
