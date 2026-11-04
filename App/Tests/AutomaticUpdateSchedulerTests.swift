import XCTest
import FloTileCore
@testable import FloTile

@MainActor
final class AutomaticUpdateSchedulerTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var store: UpdateCheckStore!
    private var calendar: Calendar!
    private var enabled = true
    private var current = Date()
    private var calls = 0

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "AutomaticUpdateSchedulerTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = UpdateCheckStore(defaults: defaults)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        calendar = cal
        enabled = true
        calls = 0
        current = date(2026, 11, 4, 12, 0)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        store = nil
        try await super.tearDown()
    }

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    private func makeScheduler(
        failureBackoff: TimeInterval = 3_600,
        check: (() async -> Void)? = nil
    ) -> AutomaticUpdateScheduler {
        AutomaticUpdateScheduler(
            isEnabled: { [unowned self] in enabled },
            minuteOfDay: { 600 },
            store: store,
            now: { [unowned self] in current },
            calendar: calendar,
            check: check ?? { [unowned self] in calls += 1 },
            failureBackoff: failureBackoff
        )
    }

    func testDisabledDoesNotCheck() async {
        enabled = false
        await makeScheduler().tick()
        XCTAssertEqual(calls, 0)
    }

    func testEnabledWithEmptyStoreChecksOnce() async {
        await makeScheduler().tick()
        XCTAssertEqual(calls, 1)
    }

    func testLastCheckAfterScheduledInstantNotDue() async {
        // Most recent scheduled instant is 2026-11-04 10:00 UTC.
        store.recordLastCheck(date(2026, 11, 4, 10, 30))
        await makeScheduler().tick()
        XCTAssertEqual(calls, 0)
    }

    func testLastCheckBeforeScheduledInstantIsDue() async {
        store.recordLastCheck(date(2026, 11, 4, 9, 30))
        await makeScheduler().tick()
        XCTAssertEqual(calls, 1)
    }

    func testReentrantTickIsSkippedThenLaterTickRuns() async {
        var continuation: CheckedContinuation<Void, Never>?
        var entered = false
        let scheduler = makeScheduler(check: { [unowned self] in
            calls += 1
            await withCheckedContinuation { c in
                continuation = c
                entered = true
            }
        })
        let first = Task { @MainActor in await scheduler.tick() }
        while !entered { await Task.yield() }
        await scheduler.tick()
        XCTAssertEqual(calls, 1)
        continuation?.resume()
        await first.value
        // Next day, still due (store is never written by the scheduler).
        current = date(2026, 11, 5, 12, 0)
        let second = Task { @MainActor in await scheduler.tick() }
        while continuation == nil || calls < 2 { await Task.yield() }
        continuation?.resume()
        await second.value
        XCTAssertEqual(calls, 2)
    }

    func testFailedCheckBacksOffThenRetriesAfterBackoff() async {
        let scheduler = makeScheduler()
        await scheduler.tick()
        XCTAssertEqual(calls, 1)
        current = current.addingTimeInterval(300)
        await scheduler.tick()
        XCTAssertEqual(calls, 1)
        current = date(2026, 11, 4, 13, 0)
        await scheduler.tick()
        XCTAssertEqual(calls, 2)
    }

    func testSuccessfulCheckDoesNotBackOff() async {
        let scheduler = makeScheduler(check: { [unowned self] in
            calls += 1
            store.recordLastCheck(current)
        })
        await scheduler.tick()
        XCTAssertEqual(calls, 1)
        current = date(2026, 11, 5, 10, 0)
        await scheduler.tick()
        XCTAssertEqual(calls, 2)
    }

    func testBackoffClearsAfterSubsequentSuccess() async {
        var succeed = false
        let scheduler = makeScheduler(check: { [unowned self] in
            calls += 1
            if succeed { store.recordLastCheck(current) }
        })
        await scheduler.tick()
        XCTAssertEqual(calls, 1)
        succeed = true
        current = date(2026, 11, 4, 13, 0)
        await scheduler.tick()
        XCTAssertEqual(calls, 2)
        // Success recorded; next day's scheduled time is due and not blocked.
        current = date(2026, 11, 5, 10, 0)
        await scheduler.tick()
        XCTAssertEqual(calls, 3)
    }

    func testFailureBackoffIsInjectable() async {
        let scheduler = makeScheduler(failureBackoff: 600)
        await scheduler.tick()
        current = current.addingTimeInterval(599)
        await scheduler.tick()
        XCTAssertEqual(calls, 1)
        current = current.addingTimeInterval(1)
        await scheduler.tick()
        XCTAssertEqual(calls, 2)
    }

    func testShouldRunAutomatically() {
        XCTAssertFalse(AutomaticUpdateScheduler.shouldRunAutomatically(
            arguments: ["FloTile"], environment: ["XCTestConfigurationFilePath": "/x"]))
        XCTAssertFalse(AutomaticUpdateScheduler.shouldRunAutomatically(
            arguments: ["FloTile", "--self-test-tile-cycle"], environment: [:]))
        XCTAssertTrue(AutomaticUpdateScheduler.shouldRunAutomatically(arguments: ["FloTile"], environment: [:]))
    }

    func testStartTwiceThenStopDoesNotCrash() {
        let scheduler = makeScheduler()
        scheduler.start()
        scheduler.start()
        scheduler.stop()
        scheduler.stop()
    }
}
