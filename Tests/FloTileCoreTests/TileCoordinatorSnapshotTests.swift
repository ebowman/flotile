import XCTest
import CoreGraphics
@testable import FloTileCore

final class TileCoordinatorSnapshotTests: XCTestCase {
    private let screen = ScreenInfo(
        id: ScreenID(1),
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875))
    private let pid: pid_t = 100
    private let clock = Date(timeIntervalSince1970: 1234)

    private func win(_ id: Int, x: CGFloat = 100) -> WindowInfo {
        WindowInfo(id: WindowID(id), frame: CGRect(x: x, y: 100, width: 200, height: 150),
                   isMinimized: false, isStandard: true, discoveryIndex: id)
    }

    private func make(_ windows: [WindowInfo]) -> (TileCoordinator, FakeWindowSystem) {
        let ws = FakeWindowSystem()
        ws.windowsByPID[pid] = windows
        let date = clock
        let c = TileCoordinator(windowSystem: ws, now: { date })
        return (c, ws)
    }

    func testBeforeIsPreTileFramesAndClockInjected() throws {
        let ws3 = [win(1, x: 10), win(2, x: 20), win(3, x: 30)]
        let (c, _) = make(ws3)
        let r = c.tileAndSnapshot(on: screen)
        XCTAssertEqual(r.outcome, .tiled(count: 3))
        let snap = try XCTUnwrap(r.snapshot)
        XCTAssertEqual(snap.before, Dictionary(uniqueKeysWithValues: ws3.map { ($0.id, $0.frame) }))
        XCTAssertEqual(snap.pid, pid)
        XCTAssertEqual(snap.screenID, screen.id)
        XCTAssertEqual(snap.takenAt, clock)
    }

    func testDuplicateWindowIDDoesNotTrapAndLastFrameWins() throws {
        let (c, _) = make([win(1, x: 10), win(1, x: 50)])
        let r = c.tileAndSnapshot(on: screen)
        switch r.outcome {
        case .tiled, .partial: break
        default: XCTFail("unexpected outcome \(r.outcome)")
        }
        let snap = try XCTUnwrap(r.snapshot)
        XCTAssertEqual(snap.before.count, 1)
        XCTAssertEqual(snap.before[WindowID(1)], win(1, x: 50).frame)
    }

    func testDefaultClockInit() {
        let ws = FakeWindowSystem()
        ws.windowsByPID[pid] = [win(1)]
        let c = TileCoordinator(windowSystem: ws)
        XCTAssertNotNil(c.tileAndSnapshot(on: screen).snapshot)
    }

    func testAfterComesFromReread() throws {
        let (c, ws) = make([win(1), win(2)])
        ws.onSetFrame = { id, frame in
            let adjusted = CGRect(x: frame.minX, y: frame.minY, width: frame.width - 1, height: frame.height)
            var list = ws.windowsByPID[100] ?? []
            list.removeAll { $0.id == id }
            list.append(WindowInfo(id: id, frame: adjusted, isMinimized: false, isStandard: true,
                                   discoveryIndex: id.rawValue))
            ws.windowsByPID[100] = list
        }
        let snap = try XCTUnwrap(c.tileAndSnapshot(on: screen).snapshot)
        let requested = Dictionary(uniqueKeysWithValues: ws.setFrameCalls.map { ($0.0, $0.1) })
        XCTAssertEqual(snap.after.count, 2)
        for (id, frame) in snap.after {
            let req = try XCTUnwrap(requested[id])
            XCTAssertNotEqual(frame, req)
            XCTAssertEqual(frame.width, req.width - 1)
        }
    }

    func testAfterIgnoresWindowsNotTiled() throws {
        let (c, ws) = make([win(1)])
        ws.onSetFrame = { _, _ in
            ws.windowsByPID[100] = (ws.windowsByPID[100] ?? []) + [self.win(9)]
        }
        let snap = try XCTUnwrap(c.tileAndSnapshot(on: screen).snapshot)
        XCTAssertEqual(Set(snap.after.keys), [WindowID(1)])
    }

    func testRereadWithNoTiledIdsYieldsNilSnapshot() {
        let (c, ws) = make([win(1), win(2)])
        ws.onSetFrame = { _, _ in ws.windowsByPID[100] = [self.win(9)] }
        let result = c.tileAndSnapshot(on: screen)
        XCTAssertEqual(result.outcome, .tiled(count: 2))
        XCTAssertNil(result.snapshot)
    }

    func testRereadThrowingFallsBackToRequested() throws {
        let (c, ws) = make([win(1)])
        ws.onSetFrame = { _, _ in ws.windowsError = FakeWindowSystemError(description: "gone") }
        let snap = try XCTUnwrap(c.tileAndSnapshot(on: screen).snapshot)
        XCTAssertEqual(snap.after[WindowID(1)], ws.setFrameCalls.first?.1)
    }

    func testNilSnapshotOnEarlyOutcomes() {
        var (c, ws) = make([win(1)])
        ws.isTrusted = false
        var r = c.tileAndSnapshot(on: screen)
        XCTAssertEqual(r.outcome, .accessibilityNotGranted)
        XCTAssertNil(r.snapshot)

        (c, ws) = make([win(1)])
        ws.frontmostPID = nil
        r = c.tileAndSnapshot(on: screen)
        XCTAssertEqual(r.outcome, .noFrontmostApp)
        XCTAssertNil(r.snapshot)

        (c, _) = make([])
        r = c.tileAndSnapshot(on: screen)
        XCTAssertEqual(r.outcome, .noWindows)
        XCTAssertNil(r.snapshot)

        (c, ws) = make([win(1)])
        ws.windowsError = FakeWindowSystemError(description: "x")
        r = c.tileAndSnapshot(on: screen)
        XCTAssertEqual(r.outcome, .failed(reason: "x"))
        XCTAssertNil(r.snapshot)
    }

    func testAllFailuresNilSnapshot() {
        let (c, ws) = make([win(1), win(2)])
        ws.failingWindowIDs = [WindowID(1), WindowID(2)]
        let r = c.tileAndSnapshot(on: screen)
        XCTAssertEqual(r.outcome, .partial(succeeded: 0, failed: 2))
        XCTAssertNil(r.snapshot)
    }

    func testPartialKeepsSnapshot() throws {
        let (c, ws) = make([win(1), win(2), win(3)])
        ws.failingWindowIDs = [WindowID(2)]
        let r = c.tileAndSnapshot(on: screen)
        XCTAssertEqual(r.outcome, .partial(succeeded: 2, failed: 1))
        let snap = try XCTUnwrap(r.snapshot)
        XCTAssertEqual(snap.before.count, 3)
        XCTAssertEqual(Set(snap.after.keys), [WindowID(1), WindowID(3)])
    }

    func testRestoreOnlyRestoresMovedWindowsAfterPartialTile() throws {
        let (c, ws) = make([win(1, x: 10), win(2, x: 20)])
        ws.failingWindowIDs = [WindowID(2)]
        let r = c.tileAndSnapshot(on: screen)
        XCTAssertEqual(r.outcome, .partial(succeeded: 1, failed: 1))
        let snap = try XCTUnwrap(r.snapshot)
        XCTAssertEqual(Set(snap.after.keys), [WindowID(1)])
        let calls = ws.setFrameCalls.count
        XCTAssertEqual(c.restore(snap), .restored(count: 1))
        let restoreCalls = ws.setFrameCalls[calls...]
        XCTAssertEqual(restoreCalls.map { $0.0 }, [WindowID(1)])
        XCTAssertEqual(restoreCalls.first?.1, snap.before[WindowID(1)])
    }

    func testRestoreWithEmptyAfterIsNoWindows() {
        let (c, ws) = make([])
        let snap = TileSnapshot(pid: pid, screenID: screen.id,
                                before: [WindowID(1): CGRect(x: 1, y: 1, width: 5, height: 5)],
                                after: [:], takenAt: clock)
        XCTAssertEqual(c.restore(snap), .noWindows)
        XCTAssertTrue(ws.setFrameCalls.isEmpty)
    }

    private func snapshot(_ ids: [Int]) -> TileSnapshot {
        let before = Dictionary(uniqueKeysWithValues: ids.map {
            (WindowID($0), CGRect(x: $0, y: 2 * $0, width: 300, height: 200))
        })
        return TileSnapshot(pid: pid, screenID: screen.id, before: before, after: before, takenAt: clock)
    }

    func testRestoreSetsBeforeFrames() {
        let (c, ws) = make([])
        let snap = snapshot([3, 1, 2])
        XCTAssertEqual(c.restore(snap), .restored(count: 3))
        XCTAssertEqual(ws.setFrameCalls.map { $0.0.rawValue }, [1, 2, 3])
        let got = Set(ws.setFrameCalls.map { "\($0.0.rawValue)|\($0.1)" })
        let want = Set(snap.before.map { "\($0.key.rawValue)|\($0.value)" })
        XCTAssertEqual(got, want)
    }

    func testRestorePartial() {
        let (c, ws) = make([])
        ws.failingWindowIDs = [WindowID(2)]
        XCTAssertEqual(c.restore(snapshot([1, 2, 3])), .partial(succeeded: 2, failed: 1))
    }

    func testRestoreEmpty() {
        let (c, ws) = make([])
        XCTAssertEqual(c.restore(snapshot([])), .noWindows)
        XCTAssertTrue(ws.setFrameCalls.isEmpty)
    }
}
