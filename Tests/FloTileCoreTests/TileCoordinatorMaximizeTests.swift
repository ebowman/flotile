import XCTest
import CoreGraphics
@testable import FloTileCore

final class TileCoordinatorMaximizeTests: XCTestCase {
    private let screen = ScreenInfo(
        id: ScreenID(1),
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875))
    private let pid: pid_t = 100
    private let clock = Date(timeIntervalSince1970: 5678)
    private var fill: CGRect { TilingLayout.insetIntegral(screen.visibleFrame) }

    private func tiledFrame(_ id: Int) -> CGRect { CGRect(x: 10 * id, y: 0, width: 100, height: 100) }
    private func beforeFrame(_ id: Int) -> CGRect { CGRect(x: 500 + id, y: 300, width: 200, height: 150) }

    /// Fake whose windows sit at their tiled frames; setFrame reflects into windowsByPID.
    private func make(_ ids: [Int]) -> (TileCoordinator, FakeWindowSystem, TileSnapshot) {
        let ws = FakeWindowSystem()
        ws.windowsByPID[pid] = ids.map {
            WindowInfo(id: WindowID($0), frame: tiledFrame($0), isMinimized: false, isStandard: true, discoveryIndex: $0)
        }
        ws.onSetFrame = { id, frame in
            ws.windowsByPID[100] = (ws.windowsByPID[100] ?? []).map {
                $0.id == id
                    ? WindowInfo(id: id, frame: frame, isMinimized: false, isStandard: true, discoveryIndex: id.rawValue)
                    : $0
            }
        }
        let date = clock
        let c = TileCoordinator(windowSystem: ws, now: { date })
        let snap = TileSnapshot(
            pid: pid, screenID: screen.id,
            before: Dictionary(uniqueKeysWithValues: ids.map { (WindowID($0), beforeFrame($0)) }),
            after: Dictionary(uniqueKeysWithValues: ids.map { (WindowID($0), tiledFrame($0)) }),
            takenAt: Date(timeIntervalSince1970: 1))
        return (c, ws, snap)
    }

    func testAllSuccess() throws {
        let (c, ws, snap) = make([2, 1])
        let r = c.maximizeAndSnapshot(snap, on: screen)
        XCTAssertEqual(r.outcome, .maximized(count: 2))
        let new = try XCTUnwrap(r.snapshot)
        XCTAssertEqual(new.phase, .maximized)
        XCTAssertEqual(snap.phase, .tiled)
        XCTAssertEqual(new.before, snap.before)
        XCTAssertEqual(new.takenAt, clock)
        XCTAssertEqual(new.pid, pid)
        XCTAssertEqual(new.screenID, screen.id)
        XCTAssertEqual(new.after, [WindowID(1): fill, WindowID(2): fill])
        XCTAssertEqual(ws.setFrameCalls.map { $0.0.rawValue }, [1, 2])
        XCTAssertTrue(ws.setFrameCalls.allSatisfy { $0.1 == fill })
    }

    func testPartialFailureKeepsFailedWindowForRestore() throws {
        let (c, ws, snap) = make([1, 2, 3])
        ws.failingWindowIDs = [WindowID(2)]
        let r = c.maximizeAndSnapshot(snap, on: screen)
        XCTAssertEqual(r.outcome, .partial(succeeded: 2, failed: 1))
        let new = try XCTUnwrap(r.snapshot)
        XCTAssertEqual(new.after[WindowID(2)], tiledFrame(2))
        XCTAssertEqual(new.after[WindowID(1)], fill)
        XCTAssertEqual(new.after[WindowID(3)], fill)

        ws.failingWindowIDs = []
        XCTAssertEqual(c.restore(new), .restored(count: 3))
        let restored = Dictionary(ws.setFrameCalls.suffix(3).map { ($0.0, $0.1) }, uniquingKeysWith: { _, l in l })
        XCTAssertEqual(restored, snap.before)
    }

    func testAllFailGivesNoSnapshot() {
        let (c, ws, snap) = make([1, 2])
        ws.failingWindowIDs = [WindowID(1), WindowID(2)]
        let r = c.maximizeAndSnapshot(snap, on: screen)
        XCTAssertEqual(r.outcome, .partial(succeeded: 0, failed: 2))
        XCTAssertNil(r.snapshot)
    }

    func testRereadThrowsFallsBack() throws {
        let (c, ws, snap) = make([1, 2])
        ws.failingWindowIDs = [WindowID(2)]
        ws.onSetFrame = { _, _ in ws.windowsError = FakeWindowSystemError(description: "boom") }
        let r = c.maximizeAndSnapshot(snap, on: screen)
        XCTAssertEqual(r.outcome, .partial(succeeded: 1, failed: 1))
        let new = try XCTUnwrap(r.snapshot)
        XCTAssertEqual(new.after, [WindowID(1): fill, WindowID(2): tiledFrame(2)])
    }

    func testRereadDropsWindow() throws {
        let (c, ws, snap) = make([1, 2])
        ws.onSetFrame = { id, _ in
            if id.rawValue == 2 { ws.windowsByPID[100] = ws.windowsByPID[100]?.filter { $0.id.rawValue != 2 } }
        }
        let r = c.maximizeAndSnapshot(snap, on: screen)
        XCTAssertEqual(r.outcome, .maximized(count: 2))
        let new = try XCTUnwrap(r.snapshot)
        XCTAssertNil(new.after[WindowID(2)])
        XCTAssertEqual(new.after.count, 1)
        XCTAssertEqual(new.after[WindowID(1)], tiledFrame(1))
    }

    func testRereadEmptyGivesNoSnapshot() {
        let (c, ws, snap) = make([1])
        ws.onSetFrame = { _, _ in ws.windowsByPID[100] = [] }
        let r = c.maximizeAndSnapshot(snap, on: screen)
        XCTAssertEqual(r.outcome, .maximized(count: 1))
        XCTAssertNil(r.snapshot)
    }

    func testEmptyAfter() {
        let (c, ws, _) = make([])
        let empty = TileSnapshot(pid: pid, screenID: screen.id, before: [:], after: [:], takenAt: clock)
        let r = c.maximizeAndSnapshot(empty, on: screen)
        XCTAssertEqual(r.outcome, .noWindows)
        XCTAssertNil(r.snapshot)
        XCTAssertTrue(ws.setFrameCalls.isEmpty)
    }

    func testRestoreOfMaximizedSnapshotSetsBeforeFrames() throws {
        let (c, ws, snap) = make([1, 2])
        let new = try XCTUnwrap(c.maximizeAndSnapshot(snap, on: screen).snapshot)
        XCTAssertEqual(c.restore(new), .restored(count: 2))
        let last = ws.setFrameCalls.suffix(2)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: last.map { ($0.0, $0.1) }), snap.before)
    }

    func testMaximizedSelfTestLabel() {
        XCTAssertEqual(TileOutcome.maximized(count: 2).selfTestLabel, "maximized:2")
    }

    func testDefaultPhaseIsTiled() {
        let s = TileSnapshot(pid: pid, screenID: screen.id, before: [:], after: [:], takenAt: clock)
        XCTAssertEqual(s.phase, .tiled)
    }
}
