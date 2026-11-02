import XCTest
@testable import FloTileCore

final class FloTileCoreTests: XCTestCase {
    func testVersion() {
        XCTAssertEqual(FloTileCore.version, "0.1.0")
    }
}
