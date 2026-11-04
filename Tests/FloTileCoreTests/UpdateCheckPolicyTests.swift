import XCTest
@testable import FloTileCore

final class UpdateCheckPolicyTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(
            from: DateComponents(
                year: 2026, month: 11, day: day, hour: hour, minute: minute, second: 0))!
    }

    private func due(_ last: Date?, _ now: Date, _ minuteOfDay: Int = 600) -> Bool {
        UpdateCheckPolicy.isDue(
            lastCheck: last, now: now, minuteOfDay: minuteOfDay, calendar: calendar)
    }

    func testDefaultMinute() {
        XCTAssertEqual(UpdateCheckPolicy.defaultMinuteOfDay, 600)
    }

    func testNilIsDue() {
        XCTAssertTrue(due(nil, date(4, 10, 30)))
    }

    func testYesterdayMissedIsDue() {
        XCTAssertTrue(due(date(3, 9, 0), date(4, 10, 30)))
    }

    func testCheckedAfterScheduledIsNotDue() {
        XCTAssertFalse(due(date(4, 10, 5), date(4, 11, 0)))
    }

    func testBeforeScheduledTimeIsNotDue() {
        XCTAssertFalse(due(date(4, 9, 0), date(4, 9, 59)))
    }

    func testExactlyAtScheduledTimeIsDue() {
        XCTAssertTrue(due(date(4, 9, 0), date(4, 10, 0)))
    }

    func testFutureLastCheckIsDue() {
        XCTAssertTrue(due(date(5, 12, 0), date(4, 10, 30)))
    }

    func testMidnightEdge() {
        XCTAssertTrue(due(date(3, 23, 0), date(4, 0, 0), 0))
        XCTAssertFalse(due(date(4, 0, 0), date(4, 0, 30), 0))
    }

    func testLastMinuteEdge() {
        XCTAssertFalse(due(date(3, 23, 59), date(4, 23, 58), 1439))
        XCTAssertTrue(due(date(3, 23, 59), date(4, 23, 59), 1439))
    }

    func testOutOfRangeClamps() {
        let now = date(4, 12, 0)
        XCTAssertEqual(
            UpdateCheckPolicy.mostRecentScheduledInstant(
                before: now, minuteOfDay: 5000, calendar: calendar),
            date(3, 23, 59))
        XCTAssertEqual(
            UpdateCheckPolicy.mostRecentScheduledInstant(
                before: now, minuteOfDay: -5, calendar: calendar),
            date(4, 0, 0))
    }

    func testMostRecentInstantTodayWhenPassed() {
        XCTAssertEqual(
            UpdateCheckPolicy.mostRecentScheduledInstant(
                before: date(4, 10, 30), minuteOfDay: 600, calendar: calendar),
            date(4, 10, 0))
    }

    func testMostRecentInstantYesterdayWhenBeforeToday() {
        XCTAssertEqual(
            UpdateCheckPolicy.mostRecentScheduledInstant(
                before: date(4, 9, 0), minuteOfDay: 600, calendar: calendar),
            date(3, 10, 0))
    }
}
