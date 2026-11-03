import XCTest
@testable import FloTileCore

@MainActor
final class SettingsModelMaximizeTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suite = "FloTileTests-" + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    private func model() -> SettingsModel {
        SettingsModel(loginItems: FakeLoginItemService(), defaults: defaults)
    }

    func testUnsetDefaultsToTrue() {
        XCTAssertTrue(model().maximizeOnSecondClick)
    }

    func testStoredFalse() {
        defaults.set(false, forKey: SettingsModel.maximizeOnSecondClickKey)
        XCTAssertFalse(model().maximizeOnSecondClick)
    }

    func testStoredTrue() {
        defaults.set(true, forKey: SettingsModel.maximizeOnSecondClickKey)
        XCTAssertTrue(model().maximizeOnSecondClick)
    }

    func testSetPersistsAndPublishes() {
        let m = model()
        m.setMaximizeOnSecondClick(false)
        XCTAssertFalse(m.maximizeOnSecondClick)
        XCTAssertFalse(defaults.bool(forKey: SettingsModel.maximizeOnSecondClickKey))
        XCTAssertFalse(model().maximizeOnSecondClick)
        m.setMaximizeOnSecondClick(true)
        XCTAssertTrue(m.maximizeOnSecondClick)
        XCTAssertTrue(model().maximizeOnSecondClick)
    }

    func testRefreshPicksUpExternalChange() {
        let m = model()
        defaults.set(false, forKey: SettingsModel.maximizeOnSecondClickKey)
        XCTAssertTrue(m.maximizeOnSecondClick)
        m.refresh()
        XCTAssertFalse(m.maximizeOnSecondClick)
    }
}
