import XCTest
@testable import FloTileCore

/// Spec: right -> showMenu (any modifiers); left + (option or control) -> showMenu;
/// left otherwise -> tile; other -> ignore (any modifiers).
final class ClickActionTests: XCTestCase {
    private func act(_ b: ClickButton, _ m: ClickModifiers = []) -> ClickAction {
        ClickAction.action(for: b, modifiers: m)
    }

    func testExhaustiveTable() {
        var checked = 0
        for button in ClickButton.allCases {
            for raw in UInt8(0)...15 {
                let hasOption = raw & 1 != 0
                let hasControl = raw & 2 != 0
                let expected: ClickAction
                switch button {
                case .right: expected = .showMenu
                case .left: expected = (hasOption || hasControl) ? .showMenu : .tile
                case .other: expected = .ignore
                }
                XCTAssertEqual(act(button, ClickModifiers(rawValue: raw)), expected,
                               "button \(button) mods \(raw)")
                checked += 1
            }
        }
        XCTAssertEqual(checked, 48)
    }

    func testPlainLeftTiles() { XCTAssertEqual(act(.left), .tile) }
    func testLeftOptionMenu() { XCTAssertEqual(act(.left, .option), .showMenu) }
    func testLeftControlMenu() { XCTAssertEqual(act(.left, .control), .showMenu) }
    func testLeftShiftTiles() { XCTAssertEqual(act(.left, .shift), .tile) }
    func testLeftCommandTiles() { XCTAssertEqual(act(.left, .command), .tile) }
    func testLeftShiftCommandTiles() { XCTAssertEqual(act(.left, [.shift, .command]), .tile) }
    func testLeftOptionShiftMenu() { XCTAssertEqual(act(.left, [.option, .shift]), .showMenu) }
    func testRightMenu() { XCTAssertEqual(act(.right), .showMenu) }
    func testRightCommandMenu() { XCTAssertEqual(act(.right, .command), .showMenu) }
    func testOtherIgnored() { XCTAssertEqual(act(.other), .ignore) }
    func testOtherOptionIgnored() { XCTAssertEqual(act(.other, .option), .ignore) }

    func testOptionSetBehaviour() {
        XCTAssertEqual(ClickModifiers([]).rawValue, 0)
        let u = ClickModifiers.option.union(.shift)
        XCTAssertTrue(u.contains(.option))
        XCTAssertTrue(u.contains(.shift))
        XCTAssertFalse(u.contains(.control))
        XCTAssertEqual(u.rawValue, 5)
    }
}
