import XCTest
@testable import FloTileCore

final class UpdateCheckStoreTests: XCTestCase {
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

    func testEmptyReturnsNil() {
        let store = UpdateCheckStore(defaults: defaults)
        XCTAssertNil(store.loadLastCheck())
        XCTAssertNil(store.loadSkippedVersion())
    }

    func testLastCheckRoundTrip() throws {
        let store = UpdateCheckStore(defaults: defaults)
        let date = Date(timeIntervalSince1970: 1_800_000_000.5)
        store.recordLastCheck(date)
        let loaded = try XCTUnwrap(store.loadLastCheck())
        XCTAssertEqual(loaded.timeIntervalSince1970, date.timeIntervalSince1970, accuracy: 0.001)
    }

    func testSkippedVersionRoundTripAndReplace() {
        let store = UpdateCheckStore(defaults: defaults)
        store.recordSkippedVersion("1.2.3")
        XCTAssertEqual(store.loadSkippedVersion(), "1.2.3")
        store.recordSkippedVersion("1.3.0")
        XCTAssertEqual(store.loadSkippedVersion(), "1.3.0")
    }

    func testNonDateLastCheckIsNil() {
        defaults.set("yesterday", forKey: UpdateCheckStore.lastCheckKey)
        XCTAssertNil(UpdateCheckStore(defaults: defaults).loadLastCheck())
    }

    func testEmptySkippedVersionIsNil() {
        defaults.set("", forKey: UpdateCheckStore.skippedVersionKey)
        XCTAssertNil(UpdateCheckStore(defaults: defaults).loadSkippedVersion())
    }

    func testNonStringSkippedVersionIsNil() {
        defaults.set(42, forKey: UpdateCheckStore.skippedVersionKey)
        XCTAssertNil(UpdateCheckStore(defaults: defaults).loadSkippedVersion())
    }
}
