import XCTest
import FloTileCore
@testable import FloTile

@MainActor
final class SettingsViewModelIntegrationTests: XCTestCase {
    func testFailedEnableLeavesToggleOffAndShowsMessage() {
        let fake = FakeLoginItemService()
        fake.errorToThrow = LoginItemError(message: "boom")
        let model = SettingsModel(loginItems: fake)
        model.setOpenAtLogin(true)
        XCTAssertFalse(model.openAtLogin)
        XCTAssertEqual(model.errorMessage, "boom")
        XCTAssertEqual(fake.setCalls, [true])
    }
}
