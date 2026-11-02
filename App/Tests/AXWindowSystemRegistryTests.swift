import ApplicationServices
import FloTileCore
import XCTest
@testable import FloTile

@MainActor
final class AXWindowSystemRegistryTests: XCTestCase {
    private func makeRegistry() -> StableHandleRegistry<AXUIElement> {
        StableHandleRegistry<AXUIElement>(isSame: { CFEqual($0, $1) })
    }

    func testSameElementCreatedTwiceKeepsItsID() {
        let registry = makeRegistry()
        let first = registry.handles(for: [AXUIElementCreateApplication(getpid())], in: 1)
        let second = registry.handles(for: [AXUIElementCreateApplication(getpid())], in: 1)
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first.map(\.id), second.map(\.id))
    }

    func testDistinctElementsGetDistinctIDs() {
        let registry = makeRegistry()
        let handles = registry.handles(
            for: [AXUIElementCreateApplication(getpid()), AXUIElementCreateSystemWide()], in: 1)
        XCTAssertEqual(handles.count, 2)
        XCTAssertNotEqual(handles[0].id, handles[1].id)
    }

    func testVanishedElementIsPruned() {
        let registry = makeRegistry()
        let both = registry.handles(
            for: [AXUIElementCreateApplication(getpid()), AXUIElementCreateSystemWide()], in: 1)
        _ = registry.handles(for: [AXUIElementCreateApplication(getpid())], in: 1)
        XCTAssertNotNil(registry.element(for: both[0].id))
        XCTAssertNil(registry.element(for: both[1].id))
    }

    func testRemoveGroupClearsHandles() {
        let registry = makeRegistry()
        let handles = registry.handles(for: [AXUIElementCreateApplication(getpid())], in: 1)
        registry.removeGroup(1)
        XCTAssertNil(registry.element(for: handles[0].id))
    }

    func testForgetApplicationOnUnknownPIDDoesNotCrash() {
        AXWindowSystem().forgetApplication(pid: 12345)
    }
}
