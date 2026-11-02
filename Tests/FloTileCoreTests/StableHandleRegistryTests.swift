import XCTest
@testable import FloTileCore

private final class Node { }

final class StableHandleRegistryTests: XCTestCase {
    private func make() -> StableHandleRegistry<Node> {
        StableHandleRegistry<Node> { $0 === $1 }
    }

    func testSameElementsTwiceYieldIdenticalIDs() {
        let r = make()
        let n = [Node(), Node(), Node()]
        let a = r.handles(for: n, in: 1).map(\.id)
        let b = r.handles(for: n, in: 1).map(\.id)
        XCTAssertEqual(a, b)
        XCTAssertEqual(Set(a).count, 3)
    }

    func testNewElementGetsNewIDOldUnchanged() {
        let r = make()
        let n = [Node(), Node()]
        let a = r.handles(for: n, in: 1).map(\.id)
        let extra = Node()
        let b = r.handles(for: n + [extra], in: 1).map(\.id)
        XCTAssertEqual(Array(b.prefix(2)), a)
        XCTAssertFalse(a.contains(b[2]))
    }

    func testDroppedElementIDNoLongerResolves() {
        let r = make()
        let n = [Node(), Node(), Node()]
        let a = r.handles(for: n, in: 1).map(\.id)
        let b = r.handles(for: [n[0], n[2]], in: 1).map(\.id)
        XCTAssertEqual(b, [a[0], a[2]])
        XCTAssertNil(r.element(for: a[1]))
        XCTAssertTrue(r.element(for: a[0]) === n[0])
        XCTAssertEqual(r.count, 2)
    }

    func testIDsMonotonicAndNeverReused() {
        let r = make()
        let n = [Node(), Node()]
        let a = r.handles(for: n, in: 1).map(\.id.rawValue)
        _ = r.handles(for: [], in: 1)
        let c = r.handles(for: [Node()], in: 1).map(\.id.rawValue)
        XCTAssertGreaterThan(c[0], a.max()!)
    }

    func testGroupsAreIndependent() {
        let r = make()
        let g1 = Node(), g2 = Node()
        let i1 = r.handles(for: [g1], in: 1)[0].id
        let i2 = r.handles(for: [g2], in: 2)[0].id
        XCTAssertNotEqual(i1, i2)
        _ = r.handles(for: [], in: 1)
        XCTAssertNil(r.element(for: i1))
        XCTAssertTrue(r.element(for: i2) === g2)
        XCTAssertEqual(r.handles(for: [g2], in: 2)[0].id, i2)
    }

    func testRemoveGroupClearsOnlyThatGroup() {
        let r = make()
        _ = r.handles(for: [Node(), Node()], in: 1)
        let keep = Node()
        let k = r.handles(for: [keep], in: 2)[0].id
        XCTAssertEqual(r.count, 3)
        r.removeGroup(1)
        XCTAssertEqual(r.count, 1)
        XCTAssertTrue(r.element(for: k) === keep)
        r.removeGroup(99)
        XCTAssertEqual(r.count, 1)
    }

    func testDuplicateInputsShareID() {
        let r = make()
        let n = Node()
        let h = r.handles(for: [n, n], in: 1)
        XCTAssertEqual(h[0].id, h[1].id)
        XCTAssertEqual(r.count, 1)
    }

    func testElementForReturnsLatestReference() {
        let r = make()
        var calls = 0
        let same = StableHandleRegistry<(key: Int, tag: Node)> { calls += 1; return $0.key == $1.key }
        let first = Node(), second = Node()
        let id = same.handles(for: [(1, first)], in: 1)[0].id
        _ = same.handles(for: [(1, second)], in: 1)
        XCTAssertTrue(same.element(for: id)?.tag === second)
        XCTAssertGreaterThan(calls, 0)
        XCTAssertNil(r.element(for: id))
    }
}
