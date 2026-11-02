import AppKit
import XCTest
import FloTileCore
@testable import FloTile

@MainActor
final class StatusItemControllerTests: XCTestCase {
    private final class Counts {
        var tiles: [ScreenInfo] = []
        var undos = 0
        var canUndo = true
        var settings = 0
        var updates = 0
        var quits = 0
    }

    private func make() -> (StatusItemController, Counts) {
        let c = Counts()
        let controller = StatusItemController(
            onTile: { c.tiles.append($0) },
            canUndo: { c.canUndo },
            onUndo: { c.undos += 1 },
            onOpenSettings: { c.settings += 1 },
            onCheckForUpdates: { c.updates += 1 },
            onQuit: { c.quits += 1 }
        )
        return (controller, c)
    }

    func testMenuStructure() {
        let (controller, _) = make()
        let menu = controller.buildMenu()
        XCTAssertEqual(menu.items.count, 6)
        XCTAssertFalse(menu.autoenablesItems)
        XCTAssertEqual(menu.items.map(\.title), ["Undo Tiling", "", "Settings…", "Check for Updates…", "", "Quit FlöTile"])
        XCTAssertTrue(menu.items[1].isSeparatorItem)
        XCTAssertTrue(menu.items[4].isSeparatorItem)
        XCTAssertEqual(menu.items[0].keyEquivalent, "")
        XCTAssertEqual(menu.items[2].keyEquivalent, ",")
        XCTAssertTrue(menu.items[2].keyEquivalentModifierMask.contains(.command))
        XCTAssertEqual(menu.items[3].keyEquivalent, "")
        XCTAssertEqual(menu.items[5].keyEquivalent, "q")
    }

    func testUndoEnabledFollowsCanUndo() {
        let (controller, c) = make()
        c.canUndo = true
        XCTAssertTrue(controller.buildMenu().items[0].isEnabled)
        c.canUndo = false
        XCTAssertFalse(controller.buildMenu().items[0].isEnabled)
    }

    func testUndoActionInvokesOnUndo() throws {
        let (controller, c) = make()
        let item = controller.buildMenu().items[0]
        let target = try XCTUnwrap(item.target)
        _ = target.perform(try XCTUnwrap(item.action), with: item)
        XCTAssertEqual(c.undos, 1)
        XCTAssertEqual(c.settings, 0)
    }

    func testDispatchTile() throws {
        let (controller, c) = make()
        controller.dispatch(.tile)
        XCTAssertEqual(c.tiles.count, 1)
        let frame = try XCTUnwrap(c.tiles.first).frame
        XCTAssertTrue(NSScreen.screens.contains { $0.frame == frame })
    }

    func testDispatchShowMenuWithoutItem() {
        let (controller, c) = make()
        controller.dispatch(.showMenu)
        XCTAssertTrue(c.tiles.isEmpty)
        XCTAssertEqual(c.settings, 0)
        XCTAssertEqual(c.quits, 0)
    }

    func testDispatchIgnore() {
        let (controller, c) = make()
        controller.dispatch(.ignore)
        XCTAssertTrue(c.tiles.isEmpty)
        XCTAssertEqual(c.settings, 0)
        XCTAssertEqual(c.quits, 0)
    }

    func testMenuItemsInvokeClosures() throws {
        let (controller, c) = make()
        let menu = controller.buildMenu()
        let settings = menu.items[2]
        let updates = menu.items[3]
        let quit = menu.items[5]
        let target = try XCTUnwrap(settings.target)
        _ = target.perform(try XCTUnwrap(settings.action), with: settings)
        XCTAssertEqual(c.settings, 1)
        XCTAssertEqual(c.quits, 0)
        let uTarget = try XCTUnwrap(updates.target)
        _ = uTarget.perform(try XCTUnwrap(updates.action), with: updates)
        XCTAssertEqual(c.updates, 1)
        XCTAssertEqual(c.quits, 0)
        let qTarget = try XCTUnwrap(quit.target)
        _ = qTarget.perform(try XCTUnwrap(quit.action), with: quit)
        XCTAssertEqual(c.quits, 1)
        XCTAssertEqual(c.settings, 1)
    }
}
