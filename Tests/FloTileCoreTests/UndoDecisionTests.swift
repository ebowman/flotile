import XCTest
import CoreGraphics
@testable import FloTileCore

final class UndoDecisionTests: XCTestCase {
    private let f1 = CGRect(x: 0, y: 0, width: 500, height: 400)
    private let f2 = CGRect(x: 500, y: 0, width: 500, height: 400)
    private let screen1 = ScreenID(1)

    private func snapshot() -> TileSnapshot {
        TileSnapshot(pid: 100, screenID: screen1,
                     before: [WindowID(1): f1.offsetBy(dx: 7, dy: 7), WindowID(2): f2.offsetBy(dx: 7, dy: 7)],
                     after: [WindowID(1): f1, WindowID(2): f2],
                     takenAt: Date(timeIntervalSince1970: 0))
    }

    private func win(_ id: Int, _ frame: CGRect) -> WindowInfo {
        WindowInfo(id: WindowID(id), frame: frame, isMinimized: false, isStandard: true, discoveryIndex: id)
    }

    private func decide(_ snap: TileSnapshot?, pid: pid_t = 100, screen: ScreenID? = nil, _ wins: [WindowInfo]) -> UndoDecision {
        UndoDecision.decide(snapshot: snap, frontmostPID: pid, screenID: screen ?? screen1, currentEligibleWindows: wins)
    }

    private var exact: [WindowInfo] { [win(1, f1), win(2, f2)] }

    /// before {1,2}, after {1}: window 2 failed to move.
    private func partialSnapshot() -> TileSnapshot {
        TileSnapshot(pid: 100, screenID: screen1,
                     before: [WindowID(1): f1.offsetBy(dx: 7, dy: 7), WindowID(2): f2.offsetBy(dx: 7, dy: 7)],
                     after: [WindowID(1): f1],
                     takenAt: Date(timeIntervalSince1970: 0))
    }

    func testPartialSnapshotIgnoresUnmovedWindow() {
        let p = partialSnapshot()
        XCTAssertEqual(decide(p, [win(1, f1), win(2, f2.offsetBy(dx: 300, dy: 9))]), .restore)
        XCTAssertEqual(decide(p, [win(1, f1)]), .restore)
        XCTAssertEqual(decide(p, [win(1, f1), win(2, f2), win(3, f2)]), .tileFresh(.windowSetChanged))
        XCTAssertEqual(decide(p, [win(1, f1.offsetBy(dx: 10, dy: 0)), win(2, f2)]), .tileFresh(.framesChanged))
    }

    func testNilSnapshot() {
        XCTAssertEqual(decide(nil, exact), .tileFresh(.noSnapshot))
    }

    func testDifferentApp() {
        XCTAssertEqual(decide(snapshot(), pid: 101, exact), .tileFresh(.differentApp))
    }

    func testDifferentScreen() {
        XCTAssertEqual(decide(snapshot(), screen: ScreenID(2), exact), .tileFresh(.differentScreen))
    }

    func testExtraWindow() {
        XCTAssertEqual(decide(snapshot(), exact + [win(3, f1)]), .tileFresh(.windowSetChanged))
    }

    func testMissingWindow() {
        XCTAssertEqual(decide(snapshot(), [win(1, f1)]), .tileFresh(.windowSetChanged))
    }

    func testMovedWindow() {
        XCTAssertEqual(decide(snapshot(), [win(1, f1), win(2, f2.offsetBy(dx: 10, dy: 0))]), .tileFresh(.framesChanged))
    }

    func testWithinTolerance() {
        XCTAssertEqual(decide(snapshot(), [win(1, f1), win(2, f2.offsetBy(dx: 1, dy: 0))]), .restore)
    }

    func testExact() {
        XCTAssertEqual(decide(snapshot(), exact), .restore)
    }

    func testPidMismatchWinsOverWindowSet() {
        XCTAssertEqual(decide(snapshot(), pid: 101, [win(1, f1)]), .tileFresh(.differentApp))
    }

    func testWindowSetWinsOverFrames() {
        XCTAssertEqual(decide(snapshot(), [win(1, f1.offsetBy(dx: 50, dy: 0))]), .tileFresh(.windowSetChanged))
    }
}
