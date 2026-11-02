import XCTest

final class AppBundleTests: XCTestCase {
    func testBundleIdentifier() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "ie.boboco.FloTile")
    }

    func testIsAgentApp() {
        XCTAssertEqual(Bundle.main.infoDictionary?["LSUIElement"] as? Bool, true)
    }

    func testDisplayName() {
        XCTAssertEqual(Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String, "FlöTile")
    }
}
