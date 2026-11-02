import AppKit
import XCTest
import FloTileCore
@testable import FloTile

final class EventMappingTests: XCTestCase {
    func testButtonMapping() {
        XCTAssertEqual(EventMapping.clickButton(for: .leftMouseUp), .left)
        XCTAssertEqual(EventMapping.clickButton(for: .leftMouseDown), .left)
        XCTAssertEqual(EventMapping.clickButton(for: .rightMouseUp), .right)
        XCTAssertEqual(EventMapping.clickButton(for: .rightMouseDown), .right)
        XCTAssertEqual(EventMapping.clickButton(for: .otherMouseUp), .other)
        XCTAssertEqual(EventMapping.clickButton(for: .keyDown), .other)
    }

    func testModifierMapping() {
        XCTAssertEqual(EventMapping.clickModifiers(from: []), [])
        XCTAssertEqual(EventMapping.clickModifiers(from: .option), .option)
        XCTAssertEqual(EventMapping.clickModifiers(from: .control), .control)
        XCTAssertEqual(EventMapping.clickModifiers(from: .shift), .shift)
        XCTAssertEqual(EventMapping.clickModifiers(from: .command), .command)
    }

    func testCombinedAndIgnoredModifiers() {
        XCTAssertEqual(EventMapping.clickModifiers(from: [.option, .shift, .command]), [.option, .shift, .command])
        XCTAssertEqual(EventMapping.clickModifiers(from: [.option, .control, .shift, .command]),
                       [.option, .control, .shift, .command])
        XCTAssertEqual(EventMapping.clickModifiers(from: .capsLock), [])
        XCTAssertEqual(EventMapping.clickModifiers(from: [.function, .numericPad, .capsLock]), [])
        XCTAssertEqual(EventMapping.clickModifiers(from: [.capsLock, .option]), .option)
    }
}
