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

    func testMaximizeOnSecondClickDefaultsTrueAndPersistsFalse() {
        let name = "FloTileTests-" + UUID().uuidString
        defer { UserDefaults().removePersistentDomain(forName: name) }
        let defaults = UserDefaults(suiteName: name)!
        let model = SettingsModel(loginItems: FakeLoginItemService(), defaults: defaults)
        XCTAssertTrue(model.maximizeOnSecondClick)
        model.setMaximizeOnSecondClick(false)
        XCTAssertFalse(model.maximizeOnSecondClick)
        XCTAssertFalse(defaults.bool(forKey: SettingsModel.maximizeOnSecondClickKey))
        XCTAssertNotNil(defaults.object(forKey: SettingsModel.maximizeOnSecondClickKey))
    }
}
