import AppKit
import XCTest
import FloTileCore
@testable import FloTile

@MainActor
final class SettingsWindowControllerTests: XCTestCase {
    func testShowSharedReusesSingleWindowWithExpectedConfiguration() throws {
        let model = SettingsModel(loginItems: FakeLoginItemService())
        SettingsWindowController.showShared(model: model)
        let first = try XCTUnwrap(SettingsWindowController.sharedWindowForTesting)
        SettingsWindowController.showShared(model: model)
        let second = try XCTUnwrap(SettingsWindowController.sharedWindowForTesting)
        XCTAssertTrue(first === second)
        XCTAssertEqual(first.title, "FlöTile Settings")
        XCTAssertTrue(first.styleMask.contains(.titled))
        XCTAssertTrue(first.styleMask.contains(.closable))
        XCTAssertFalse(first.styleMask.contains(.resizable))
        XCTAssertFalse(first.isReleasedWhenClosed)
        first.close()
    }
}
