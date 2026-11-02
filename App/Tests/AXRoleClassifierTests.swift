import XCTest
@testable import FloTile

final class AXRoleClassifierTests: XCTestCase {
    func testStandardWindow() {
        XCTAssertTrue(AXRoleClassifier.isStandardWindow(role: "AXWindow", subrole: "AXStandardWindow"))
    }

    func testNonStandardWindows() {
        XCTAssertFalse(AXRoleClassifier.isStandardWindow(role: "AXWindow", subrole: "AXDialog"))
        XCTAssertFalse(AXRoleClassifier.isStandardWindow(role: "AXWindow", subrole: nil))
        XCTAssertFalse(AXRoleClassifier.isStandardWindow(role: "AXSheet", subrole: "AXStandardWindow"))
        XCTAssertFalse(AXRoleClassifier.isStandardWindow(role: nil, subrole: nil))
        XCTAssertFalse(AXRoleClassifier.isStandardWindow(role: "AXWindow", subrole: "AXFloatingWindow"))
    }

    func testDescribe() {
        XCTAssertEqual(AXRoleClassifier.describe(axErrorCode: 0), "success")
        XCTAssertEqual(AXRoleClassifier.describe(axErrorCode: -25204), "cannotComplete")
        XCTAssertEqual(AXRoleClassifier.describe(axErrorCode: -25211), "apiDisabled")
        XCTAssertEqual(AXRoleClassifier.describe(axErrorCode: -25202), "invalidUIElement")
        XCTAssertEqual(AXRoleClassifier.describe(axErrorCode: 12345), "AXError(12345)")
    }

    func testErrorDescriptions() {
        let failed = AXWindowSystemError.attributeFailed(attribute: "AXSize", code: -25204).description
        XCTAssertTrue(failed.contains("AXSize"))
        XCTAssertTrue(failed.contains("cannotComplete"))
        XCTAssertTrue(AXWindowSystemError.unexpectedValue(attribute: "AXWindows").description.contains("AXWindows"))
        XCTAssertTrue(AXWindowSystemError.unknownWindow(42).description.contains("42"))
    }
}
