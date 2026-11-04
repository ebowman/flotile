import XCTest
@testable import FloTile

final class CheckTimeBindingTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private let reference = Date(timeIntervalSince1970: 1_800_000_000)

    private func check(_ minute: Int, hour: Int, min: Int, file: StaticString = #filePath, line: UInt = #line) {
        let d = CheckTimeBinding.date(fromMinute: minute, calendar: calendar, reference: reference)
        let c = calendar.dateComponents([.hour, .minute], from: d)
        XCTAssertEqual(c.hour, hour, file: file, line: line)
        XCTAssertEqual(c.minute, min, file: file, line: line)
        XCTAssertEqual(CheckTimeBinding.minute(from: d, calendar: calendar), minute, file: file, line: line)
    }

    func testTenAM() { check(600, hour: 10, min: 0) }
    func testMidnight() { check(0, hour: 0, min: 0) }
    func testLastMinute() { check(1439, hour: 23, min: 59) }
}
