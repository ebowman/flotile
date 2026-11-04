import XCTest
@testable import FloTileCore

@MainActor
final class SettingsModelAutoUpdateTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        suite = "FloTileTests-" + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        try await super.tearDown()
    }

    private func model() -> SettingsModel {
        SettingsModel(loginItems: FakeLoginItemService(), defaults: defaults)
    }

    func testToggleUnsetDefaultsToTrue() {
        XCTAssertTrue(model().automaticUpdateChecks)
    }

    func testToggleStoredFalse() {
        defaults.set(false, forKey: SettingsModel.automaticUpdateChecksKey)
        XCTAssertFalse(model().automaticUpdateChecks)
    }

    func testSetToggleFalsePersistsAndPublishes() {
        let m = model()
        m.setAutomaticUpdateChecks(false)
        XCTAssertFalse(m.automaticUpdateChecks)
        XCTAssertNotNil(defaults.object(forKey: SettingsModel.automaticUpdateChecksKey))
        XCTAssertFalse(defaults.bool(forKey: SettingsModel.automaticUpdateChecksKey))
        XCTAssertFalse(model().automaticUpdateChecks)
    }

    func testSetToggleTrueAfterFalse() {
        let m = model()
        m.setAutomaticUpdateChecks(false)
        m.setAutomaticUpdateChecks(true)
        XCTAssertTrue(m.automaticUpdateChecks)
        XCTAssertTrue(model().automaticUpdateChecks)
    }

    func testRefreshPicksUpExternalToggleWrite() {
        let m = model()
        XCTAssertTrue(m.automaticUpdateChecks)
        defaults.set(false, forKey: SettingsModel.automaticUpdateChecksKey)
        m.refresh()
        XCTAssertFalse(m.automaticUpdateChecks)
    }

    func testRefreshPicksUpExternalMinuteWrite() {
        let m = model()
        defaults.set(61, forKey: SettingsModel.automaticUpdateCheckMinuteKey)
        m.refresh()
        XCTAssertEqual(m.automaticUpdateCheckMinute, 61)
    }

    func testMinuteUnsetIsDefault() {
        XCTAssertEqual(model().automaticUpdateCheckMinute, 600)
    }

    func testMinuteStored() {
        defaults.set(480, forKey: SettingsModel.automaticUpdateCheckMinuteKey)
        XCTAssertEqual(model().automaticUpdateCheckMinute, 480)
    }

    func testMinuteOutOfRangeFallsBack() {
        defaults.set(5000, forKey: SettingsModel.automaticUpdateCheckMinuteKey)
        XCTAssertEqual(model().automaticUpdateCheckMinute, 600)
        defaults.set(-1, forKey: SettingsModel.automaticUpdateCheckMinuteKey)
        XCTAssertEqual(model().automaticUpdateCheckMinute, 600)
    }

    func testMinuteNonIntFallsBack() {
        defaults.set("noon", forKey: SettingsModel.automaticUpdateCheckMinuteKey)
        XCTAssertEqual(model().automaticUpdateCheckMinute, 600)
    }

    func testSetMinuteClampsHigh() {
        let m = model()
        m.setAutomaticUpdateCheckMinute(1500)
        XCTAssertEqual(m.automaticUpdateCheckMinute, 1439)
        XCTAssertEqual(defaults.integer(forKey: SettingsModel.automaticUpdateCheckMinuteKey), 1439)
    }

    func testSetMinuteClampsLow() {
        let m = model()
        m.setAutomaticUpdateCheckMinute(-5)
        XCTAssertEqual(m.automaticUpdateCheckMinute, 0)
    }

    func testSetMinuteZeroPersists() {
        let m = model()
        m.setAutomaticUpdateCheckMinute(0)
        XCTAssertEqual(m.automaticUpdateCheckMinute, 0)
        XCTAssertNotNil(defaults.object(forKey: SettingsModel.automaticUpdateCheckMinuteKey))
        XCTAssertEqual(model().automaticUpdateCheckMinute, 0)
    }

    func testNewSettingsLeaveMaximizeUnchanged() {
        let m = model()
        m.setMaximizeOnSecondClick(false)
        m.setAutomaticUpdateChecks(false)
        m.setAutomaticUpdateCheckMinute(100)
        XCTAssertFalse(m.maximizeOnSecondClick)
        m.setMaximizeOnSecondClick(true)
        m.setAutomaticUpdateChecks(true)
        m.setAutomaticUpdateCheckMinute(200)
        XCTAssertTrue(m.maximizeOnSecondClick)
    }
}
