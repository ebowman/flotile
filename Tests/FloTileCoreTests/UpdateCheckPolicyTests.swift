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

    // MARK: - Europe/Dublin DST

    private var dublin: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Dublin")!
        return c
    }()

    private func dub(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        dublin.date(
            from: DateComponents(
                year: 2026, month: month, day: day, hour: hour, minute: minute, second: 0))!
    }

    private func dubDue(_ last: Date?, _ now: Date, _ minuteOfDay: Int) -> Bool {
        UpdateCheckPolicy.isDue(
            lastCheck: last, now: now, minuteOfDay: minuteOfDay, calendar: dublin)
    }

    func testSpringForwardGapIsDueOncePerDay() {
        XCTAssertTrue(dubDue(dub(3, 28, 1, 30), dub(3, 29, 2, 35), 90))
        XCTAssertFalse(dubDue(dub(3, 29, 2, 35), dub(3, 29, 12, 0), 90))
        XCTAssertTrue(dubDue(dub(3, 29, 2, 35), dub(3, 30, 1, 31), 90))

        let now = dub(3, 29, 12, 0)
        let instant = UpdateCheckPolicy.mostRecentScheduledInstant(
            before: now, minuteOfDay: 90, calendar: dublin)
        XCTAssertTrue(
            dublin.isDate(instant, inSameDayAs: now), "instant was \(instant)")
        XCTAssertLessThan(instant, now, "instant was \(instant)")
        XCTAssertGreaterThan(instant, dub(3, 29, 0, 59), "instant was \(instant)")
    }

    func testFallBackDayIsDueOncePerDay() {
        XCTAssertTrue(dubDue(dub(10, 24, 1, 30), dub(10, 25, 3, 0), 90))
        XCTAssertFalse(dubDue(dub(10, 25, 3, 0), dub(10, 25, 23, 0), 90))
    }

    func testRegularDublinDay() {
        XCTAssertTrue(dubDue(dub(6, 9, 9, 0), dub(6, 10, 10, 30), 600))
        XCTAssertFalse(dubDue(dub(6, 10, 10, 5), dub(6, 10, 11, 0), 600))
    }
}
