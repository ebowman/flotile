import AppKit
import XCTest
import FloTileCore
@testable import FloTile

@MainActor
final class AppKitScreenProviderTests: XCTestCase {
    func testScreensMatchNSScreens() {
        let screens = AppKitScreenProvider().screens()
        XCTAssertEqual(screens.count, NSScreen.screens.count)
        for (info, screen) in zip(screens, NSScreen.screens) {
            XCTAssertEqual(info.frame, screen.frame)
            XCTAssertEqual(info.visibleFrame, screen.visibleFrame)
        }
        if screens.count > 1 {
            XCTAssertEqual(Set(screens.map(\.id)).count, screens.count)
        }
    }

    func testTargetScreenWithoutButton() throws {
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("no screens") }
        let info = try XCTUnwrap(AppKitScreenProvider.targetScreen(forStatusButton: nil))
        XCTAssertTrue(NSScreen.screens.contains { $0.frame == info.frame })
    }
}
