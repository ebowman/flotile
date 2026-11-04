import XCTest
import CoreGraphics
@testable import FloTileCore

@MainActor
final class TileSessionTests: XCTestCase {
    private let screen = ScreenInfo(
        id: ScreenID(1),
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875))
    private let otherScreen = ScreenInfo(
        id: ScreenID(2),
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875))

    private func win(_ id: Int, x: CGFloat = 100) -> WindowInfo {
        WindowInfo(id: WindowID(id), frame: CGRect(x: x, y: 100, width: 200, height: 150),
                   isMinimized: false, isStandard: true, discoveryIndex: id)
    }

    /// Fake whose setFrame is reflected in windowsByPID, like a real system.
    private func make(_ windows: [WindowInfo], pid: pid_t = 100,
                      maximize: @escaping () -> Bool = { false }) -> (TileSession, FakeWindowSystem) {
        let ws = FakeWindowSystem()
        ws.frontmostPID = pid
        ws.windowsByPID[pid] = windows
        ws.onSetFrame = { [unowned ws] id, frame in
            for (p, list) in ws.windowsByPID {
                ws.windowsByPID[p] = list.map {
                    $0.id == id ? WindowInfo(id: id, frame: frame, isMinimized: false, isStandard: true,
                                             discoveryIndex: $0.discoveryIndex) : $0
                }
            }
        }
        let c = TileCoordinator(windowSystem: ws)
        return (TileSession(coordinator: c, windowSystem: ws, maximizeOnSecondClick: maximize), ws)
    }

    func testTileThenUnchangedClickRestores() {
        let originals = [win(1, x: 10), win(2, x: 20)]
        let (s, ws) = make(originals)
        XCTAssertEqual(s.handleClick(on: screen), .tiled(count: 2))
        XCTAssertEqual(s.snapshotCount, 1)
        let phase1 = ws.setFrameCalls.count
        XCTAssertEqual(s.handleClick(on: screen), .restored(count: 2))
        let second = ws.setFrameCalls[phase1...]
        let restored = Dictionary(uniqueKeysWithValues: second.map { ($0.0, $0.1) })
        XCTAssertEqual(restored, Dictionary(uniqueKeysWithValues: originals.map { ($0.id, $0.frame) }))
        XCTAssertEqual(s.snapshotCount, 0)
        XCTAssertEqual(s.lastDecision, .restore)
    }

    func testWindowsThrowingKeepsSnapshotAndDoesNotRestore() {
        let (s, ws) = make([win(1, x: 10), win(2, x: 20)])
        XCTAssertEqual(s.handleClick(on: screen), .tiled(count: 2))
        XCTAssertEqual(s.snapshotCount, 1)
        let phase1 = ws.setFrameCalls.count
        ws.windowsError = FakeWindowSystemError(description: "transient")
        let outcome = s.handleClick(on: screen)
        guard case .failed = outcome else { return XCTFail("expected .failed, got \(outcome)") }
        XCTAssertEqual(s.snapshotCount, 1)
        guard case .tileFresh = s.lastDecision else { return XCTFail("expected tileFresh, got \(String(describing: s.lastDecision))") }
        XCTAssertNotEqual(s.lastDecision, .restore)
        XCTAssertEqual(ws.setFrameCalls.count, phase1)
        ws.windowsError = nil
        XCTAssertEqual(s.handleClick(on: screen), .restored(count: 2))
        XCTAssertEqual(s.lastDecision, .restore)
    }

    func testMovedWindowTilesFreshAndReplacesSnapshot() {
        let (s, ws) = make([win(1), win(2)])
        XCTAssertEqual(s.handleClick(on: screen), .tiled(count: 2))
        var list = ws.windowsByPID[100]!
        let moved = CGRect(x: list[0].frame.minX + 10, y: list[0].frame.minY,
                           width: list[0].frame.width, height: list[0].frame.height)
        list[0] = WindowInfo(id: list[0].id, frame: moved, isMinimized: false, isStandard: true,
                             discoveryIndex: list[0].discoveryIndex)
        ws.windowsByPID[100] = list
        let movedLayout = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0.frame) })
        XCTAssertEqual(s.handleClick(on: screen), .tiled(count: 2))
        XCTAssertEqual(s.lastDecision, .tileFresh(.framesChanged))
        XCTAssertEqual(s.snapshotCount, 1)
        // The new snapshot's before is the moved layout: restoring gives it back.
        let n = ws.setFrameCalls.count
        XCTAssertEqual(s.handleClick(on: screen), .restored(count: 2))
        let back = Dictionary(uniqueKeysWithValues: ws.setFrameCalls[n...].map { ($0.0, $0.1) })
        XCTAssertEqual(back, movedLayout)
    }

    func testAddedWindowTilesFresh() {
        let (s, ws) = make([win(1), win(2)])
        _ = s.handleClick(on: screen)
        ws.windowsByPID[100]!.append(win(3, x: 50))
        XCTAssertEqual(s.handleClick(on: screen), .tiled(count: 3))
        XCTAssertEqual(s.lastDecision, .tileFresh(.windowSetChanged))
    }

    func testPerAppSnapshots() {
        let (s, ws) = make([win(1), win(2)], pid: 1)
        ws.windowsByPID[2] = [win(11), win(12)]
        XCTAssertEqual(s.handleClick(on: screen), .tiled(count: 2))
        ws.frontmostPID = 2
        XCTAssertEqual(s.handleClick(on: screen), .tiled(count: 2))
        XCTAssertEqual(s.lastDecision, .tileFresh(.noSnapshot))
        XCTAssertEqual(s.snapshotCount, 2)
        ws.frontmostPID = 1
        XCTAssertEqual(s.handleClick(on: screen), .restored(count: 2))
        XCTAssertEqual(s.snapshotCount, 1)
    }

    func testSnapshotConsumedByRestore() {
        let (s, _) = make([win(1), win(2)])
        let outcomes = [s.handleClick(on: screen), s.handleClick(on: screen), s.handleClick(on: screen)]
        XCTAssertEqual(outcomes, [.tiled(count: 2), .restored(count: 2), .tiled(count: 2)])
    }

    func testPartialTileCanUndoAndRestoresOnlyMovedWindow() {
        let originals = [win(1, x: 10), win(2, x: 20)]
        let (s, ws) = make(originals)
        ws.failingWindowIDs = [WindowID(2)]
        XCTAssertEqual(s.handleClick(on: screen), .partial(succeeded: 1, failed: 1))
        XCTAssertEqual(s.snapshotCount, 1)
        // Windows left as-is: 1 at its tiled frame, 2 still at its original frame.
        XCTAssertTrue(s.canUndo(frontmostPID: 100, on: screen))
        let phase1 = ws.setFrameCalls.count
        XCTAssertEqual(s.handleClick(on: screen), .restored(count: 1))
        XCTAssertEqual(s.lastDecision, .restore)
        let second = ws.setFrameCalls[phase1...]
        XCTAssertEqual(second.map { $0.0 }, [WindowID(1)])
        XCTAssertEqual(second.first?.1, originals[0].frame)
    }

    func testCanUndo() {
        let (s, ws) = make([win(1), win(2)])
        XCTAssertFalse(s.canUndo(frontmostPID: 100, on: screen))
        _ = s.handleClick(on: screen)
        let decisionBefore = s.lastDecision
        XCTAssertTrue(s.canUndo(frontmostPID: 100, on: screen))
        XCTAssertEqual(s.lastDecision, decisionBefore)
        XCTAssertEqual(s.snapshotCount, 1)
        XCTAssertFalse(s.canUndo(frontmostPID: nil, on: screen))
        XCTAssertFalse(s.canUndo(frontmostPID: 999, on: screen))
        XCTAssertFalse(s.canUndo(frontmostPID: 100, on: otherScreen))
        var list = ws.windowsByPID[100]!
        list[0] = win(list[0].id.rawValue, x: 777)
        ws.windowsByPID[100] = list
        XCTAssertFalse(s.canUndo(frontmostPID: 100, on: screen))
        list = ws.windowsByPID[100]!
        ws.isTrusted = false
        XCTAssertFalse(s.canUndo(frontmostPID: 100, on: screen))
    }

    func testUndoNothingAndAfterTile() {
        let (s, ws) = make([win(1), win(2)])
        XCTAssertEqual(s.undo(on: screen), .nothingToUndo)
        XCTAssertTrue(ws.setFrameCalls.isEmpty)
        ws.frontmostPID = nil
        XCTAssertEqual(s.undo(on: screen), .nothingToUndo)
        ws.frontmostPID = 100
        _ = s.handleClick(on: screen)
        XCTAssertEqual(s.undo(on: screen), .restored(count: 2))
        XCTAssertEqual(s.lastDecision, .restore)
        XCTAssertEqual(s.snapshotCount, 0)
    }

    func testUntrustedAndNoFrontmost() {
        let (s, ws) = make([win(1)])
        ws.isTrusted = false
        XCTAssertEqual(s.handleClick(on: screen), .accessibilityNotGranted)
        XCTAssertEqual(s.snapshotCount, 0)
        ws.isTrusted = true
        ws.frontmostPID = nil
        XCTAssertEqual(s.handleClick(on: screen), .noFrontmostApp)
    }

    func testWindowsThrowingYieldsCoordinatorFailure() {
        let (s, ws) = make([win(1)])
        ws.windowsError = FakeWindowSystemError(description: "boom")
        XCTAssertEqual(s.handleClick(on: screen), .failed(reason: "boom"))
        XCTAssertEqual(s.snapshotCount, 0)
    }

    func testPruneAndForget() {
        let (s, ws) = make([win(1)], pid: 1)
        ws.windowsByPID[2] = [win(11)]
        ws.windowsByPID[3] = [win(21)]
        for pid: pid_t in [1, 2, 3] {
            ws.frontmostPID = pid
            _ = s.handleClick(on: screen)
        }
        XCTAssertEqual(s.snapshotCount, 3)
        s.prune(isRunning: { $0 != 2 })
        XCTAssertEqual(s.snapshotCount, 2)
        s.forget(pid: 1)
        XCTAssertEqual(s.snapshotCount, 1)
        ws.frontmostPID = 3
        XCTAssertTrue(s.canUndo(frontmostPID: 3, on: screen))
    }

    func testSingleWindowMaximizeAndUndo() {
        let original = win(1, x: 40)
        let (s, ws) = make([original])
        XCTAssertEqual(s.handleClick(on: screen), .tiled(count: 1))
        XCTAssertEqual(ws.setFrameCalls.last?.1, screen.visibleFrame)
        XCTAssertEqual(s.undo(on: screen), .restored(count: 1))
        XCTAssertEqual(ws.setFrameCalls.last?.1, original.frame)
    }

    func testCanUndoWithoutSnapshotDoesNotEnumerate() {
        let (s, ws) = make([win(1), win(2)])
        let before = ws.windowsCallCount
        XCTAssertFalse(s.canUndo(frontmostPID: 100, on: screen))
        XCTAssertEqual(ws.windowsCallCount, before)
    }

    func testFirstClickDecisionDoesNotEnumerate() {
        let (s, ws) = make([win(1, x: 10), win(2, x: 20)])
        let before = ws.windowsCallCount
        XCTAssertEqual(s.handleClick(on: screen), .tiled(count: 2))
        // Only the coordinator enumerates: one read in prepare and one re-read after
        // setting frames in tileAndSnapshot. The decision step adds none (it used to add a third).
        XCTAssertEqual(ws.windowsCallCount - before, 2)
        XCTAssertEqual(s.lastDecision, .tileFresh(.noSnapshot))
    }

    func testCanUndoWithSnapshotEnumeratesOnce() {
        let (s, ws) = make([win(1, x: 10), win(2, x: 20)])
        XCTAssertEqual(s.handleClick(on: screen), .tiled(count: 2))
        let before = ws.windowsCallCount
        XCTAssertTrue(s.canUndo(frontmostPID: 100, on: screen))
        XCTAssertEqual(ws.windowsCallCount - before, 1)
    }

    func testLastDecisionResetsOnEarlyReturns() {
        let (s, ws) = make([win(1, x: 10), win(2, x: 20)])
        XCTAssertNil(s.lastDecision)
        _ = s.handleClick(on: screen)
        XCTAssertEqual(s.handleClick(on: screen), .restored(count: 2))
        XCTAssertEqual(s.lastDecision, .restore)

        ws.isTrusted = false
        XCTAssertEqual(s.handleClick(on: screen), .accessibilityNotGranted)
        XCTAssertNil(s.lastDecision)
        ws.isTrusted = true

        _ = s.handleClick(on: screen)
        _ = s.handleClick(on: screen)
        XCTAssertEqual(s.lastDecision, .restore)
        ws.frontmostPID = nil
        XCTAssertEqual(s.handleClick(on: screen), .noFrontmostApp)
        XCTAssertNil(s.lastDecision)
        ws.frontmostPID = 100

        _ = s.handleClick(on: screen)
        _ = s.handleClick(on: screen)
        XCTAssertEqual(s.lastDecision, .restore)
        XCTAssertEqual(s.undo(on: screen), .nothingToUndo)
        XCTAssertNil(s.lastDecision)
    }

    // MARK: maximize cycle

    private var fill: CGRect { TilingLayout.insetIntegral(screen.visibleFrame) }

    func testThreeStepCycle() {
        let originals = [win(1, x: 10), win(2, x: 20)]
        let (s, ws) = make(originals, maximize: { true })
        XCTAssertEqual(s.handleClick(on: screen), .tiled(count: 2))
        XCTAssertTrue(s.canUndo(frontmostPID: 100, on: screen))
        XCTAssertEqual(s.handleClick(on: screen), .maximized(count: 2))
        XCTAssertEqual(s.lastDecision, .maximize)
        XCTAssertEqual(s.snapshotCount, 1)
        XCTAssertEqual(ws.windowsByPID[100]!.map(\.frame), [fill, fill])
        XCTAssertTrue(s.canUndo(frontmostPID: 100, on: screen))
        XCTAssertEqual(s.handleClick(on: screen), .restored(count: 2))
        XCTAssertEqual(s.lastDecision, .restore)
        XCTAssertEqual(s.snapshotCount, 0)
        XCTAssertEqual(ws.windowsByPID[100]!.map(\.frame), originals.map(\.frame))
        XCTAssertFalse(s.canUndo(frontmostPID: 100, on: screen))
    }

    func testMovingWindowAfterMaximizeTilesFresh() {
        let (s, ws) = make([win(1, x: 10), win(2, x: 20)], maximize: { true })
        _ = s.handleClick(on: screen)
        _ = s.handleClick(on: screen)
        var list = ws.windowsByPID[100]!
        list[0] = WindowInfo(id: list[0].id, frame: CGRect(x: 50, y: 50, width: 300, height: 300),
                             isMinimized: false, isStandard: true, discoveryIndex: list[0].discoveryIndex)
        ws.windowsByPID[100] = list
        XCTAssertEqual(s.handleClick(on: screen), .tiled(count: 2))
        XCTAssertEqual(s.lastDecision, .tileFresh(.framesChanged))
    }

    func testClosingWindowAfterMaximizeTilesFresh() {
        let (s, ws) = make([win(1, x: 10), win(2, x: 20)], maximize: { true })
        _ = s.handleClick(on: screen)
        _ = s.handleClick(on: screen)
        ws.windowsByPID[100] = [ws.windowsByPID[100]![0]]
        XCTAssertEqual(s.handleClick(on: screen), .tiled(count: 1))
        XCTAssertEqual(s.lastDecision, .tileFresh(.windowSetChanged))
    }

    func testSingleWindowSkipsMaximize() {
        let (s, _) = make([win(1, x: 10)], maximize: { true })
        XCTAssertEqual(s.handleClick(on: screen), .tiled(count: 1))
        XCTAssertEqual(s.handleClick(on: screen), .restored(count: 1))
        XCTAssertEqual(s.lastDecision, .restore)
    }

    func testSettingTurnedOffAfterTileRestores() {
        var on = true
        let (s, _) = make([win(1, x: 10), win(2, x: 20)], maximize: { on })
        _ = s.handleClick(on: screen)
        on = false
        XCTAssertEqual(s.handleClick(on: screen), .restored(count: 2))
    }

    func testSettingTurnedOnAfterMaximizeStillRestores() {
        var setting = true
        let originals = [win(1, x: 10), win(2, x: 20)]
        let (s, ws) = make(originals, maximize: { setting })
        // Setting on: tile, maximize, then flip off within the same session.
        XCTAssertEqual(s.handleClick(on: screen), .tiled(count: 2))
        XCTAssertEqual(s.handleClick(on: screen), .maximized(count: 2))
        XCTAssertEqual(s.lastDecision, .maximize)
        setting = false
        XCTAssertEqual(s.handleClick(on: screen), .restored(count: 2))
        XCTAssertEqual(s.lastDecision, .restore)
        XCTAssertEqual(ws.windowsByPID[100]!.map(\.frame), originals.map(\.frame))
        XCTAssertEqual(s.snapshotCount, 0)

        // Setting off: tile, restore; then flip on and run a full cycle.
        XCTAssertEqual(s.handleClick(on: screen), .tiled(count: 2))
        XCTAssertEqual(s.handleClick(on: screen), .restored(count: 2))
        XCTAssertEqual(s.lastDecision, .restore)
        setting = true
        XCTAssertEqual(s.handleClick(on: screen), .tiled(count: 2))
        XCTAssertEqual(s.handleClick(on: screen), .maximized(count: 2))
        XCTAssertEqual(s.lastDecision, .maximize)
        XCTAssertEqual(s.handleClick(on: screen), .restored(count: 2))
        XCTAssertEqual(s.lastDecision, .restore)
        XCTAssertEqual(ws.windowsByPID[100]!.map(\.frame), originals.map(\.frame))
    }

    func testExplicitUndoAfterMaximizeRestoresOriginals() {
        let originals = [win(1, x: 10), win(2, x: 20)]
        let (s, ws) = make(originals, maximize: { true })
        _ = s.handleClick(on: screen)
        _ = s.handleClick(on: screen)
        XCTAssertEqual(s.undo(on: screen), .restored(count: 2))
        XCTAssertEqual(s.lastDecision, .restore)
        XCTAssertEqual(s.snapshotCount, 0)
        XCTAssertEqual(ws.windowsByPID[100]!.map(\.frame), originals.map(\.frame))
    }

    func testMaximizeAllFailingKeepsTiledSnapshot() {
        let originals = [win(1, x: 10), win(2, x: 20)]
        let (s, ws) = make(originals, maximize: { true })
        _ = s.handleClick(on: screen)
        ws.failingWindowIDs = [WindowID(1), WindowID(2)]
        XCTAssertEqual(s.handleClick(on: screen), .partial(succeeded: 0, failed: 2))
        XCTAssertEqual(s.lastDecision, .maximize)
        XCTAssertEqual(s.snapshotCount, 1)
        let tiledFrames = ws.windowsByPID[100]!.map(\.frame)
        ws.failingWindowIDs = []
        XCTAssertEqual(s.handleClick(on: screen), .maximized(count: 2))
        XCTAssertEqual(s.lastDecision, .maximize)
        XCTAssertNotEqual(ws.windowsByPID[100]!.map(\.frame), tiledFrames)
        XCTAssertEqual(ws.windowsByPID[100]!.map(\.frame), [screen.visibleFrame, screen.visibleFrame])
        XCTAssertEqual(s.handleClick(on: screen), .restored(count: 2))
        XCTAssertEqual(ws.windowsByPID[100]!.map(\.frame), originals.map(\.frame))
    }
}
