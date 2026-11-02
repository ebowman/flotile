import XCTest
@testable import FloTileCore

@MainActor
final class SettingsModelTests: XCTestCase {
    func testInitReadsServiceState() {
        XCTAssertTrue(SettingsModel(loginItems: FakeLoginItemService(enabled: true)).openAtLogin)
        XCTAssertFalse(SettingsModel(loginItems: FakeLoginItemService(enabled: false)).openAtLogin)
    }

    func testEnableSuccess() {
        let f = FakeLoginItemService()
        let m = SettingsModel(loginItems: f)
        m.setOpenAtLogin(true)
        XCTAssertTrue(m.openAtLogin)
        XCTAssertNil(m.errorMessage)
        XCTAssertEqual(f.setCalls, [true])
    }

    func testDisableSuccess() {
        let f = FakeLoginItemService(enabled: true)
        let m = SettingsModel(loginItems: f)
        m.setOpenAtLogin(false)
        XCTAssertFalse(m.openAtLogin)
        XCTAssertNil(m.errorMessage)
        XCTAssertEqual(f.setCalls, [false])
    }

    func testLoginItemErrorFailure() {
        let f = FakeLoginItemService(enabled: false)
        f.errorToThrow = LoginItemError(message: "nope")
        let m = SettingsModel(loginItems: f)
        m.setOpenAtLogin(true)
        XCTAssertEqual(m.errorMessage, "nope")
        XCTAssertFalse(m.openAtLogin)
    }

    func testNSErrorDenied() {
        let f = FakeLoginItemService()
        f.errorToThrow = NSError(domain: "SMAppServiceErrorDomain", code: 11)
        let m = SettingsModel(loginItems: f, appName: "App")
        m.setOpenAtLogin(true)
        XCTAssertEqual(m.errorMessage, "Open at Login was denied. Enable it for App in System Settings > General > Login Items.")
        XCTAssertFalse(m.openAtLogin)
    }

    func testSuccessClearsError() {
        let f = FakeLoginItemService()
        f.errorToThrow = LoginItemError(message: "bad")
        let m = SettingsModel(loginItems: f)
        m.setOpenAtLogin(true)
        XCTAssertNotNil(m.errorMessage)
        f.errorToThrow = nil
        m.setOpenAtLogin(true)
        XCTAssertNil(m.errorMessage)
        XCTAssertTrue(m.openAtLogin)
    }

    func testRefreshPicksUpExternalChange() {
        let f = FakeLoginItemService()
        let m = SettingsModel(loginItems: f)
        f.enabled = true
        m.refresh()
        XCTAssertTrue(m.openAtLogin)
    }
}
