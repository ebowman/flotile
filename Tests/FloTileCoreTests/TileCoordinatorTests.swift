import XCTest
import CoreGraphics
@testable import FloTileCore

final class TileCoordinatorTests: XCTestCase {
    private let screen = ScreenInfo(
        id: ScreenID(1),
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875))

    private let pid: pid_t = 100

    private func win(_ id: Int, x: CGFloat = 100, y: CGFloat = 100, minimized: Bool = false) -> WindowInfo {
        WindowInfo(id: WindowID(id), frame: CGRect(x: x, y: y, width: 200, height: 150),
                   isMinimized: minimized, isStandard: true, discoveryIndex: id)
    }

    private func make(_ windows: [WindowInfo]) -> (TileCoordinator, FakeWindowSystem) {
        let ws = FakeWindowSystem()
        ws.windowsByPID[pid] = windows
        let c = TileCoordinator(windowSystem: ws, screenProvider: FakeScreenProvider([screen]))
        return (c, ws)
    }

    func testUntrustedShortCircuits() {
        let (c, ws) = make([win(1)])
        ws.isTrusted = false
        XCTAssertEqual(c.tile(on: screen), .accessibilityNotGranted)
        XCTAssertEqual(ws.frontmostCallCount, 0)
        XCTAssertEqual(ws.windowsCallCount, 0)
    }

    func testNoFrontmostApp() {
        let (c, ws) = make([win(1)])
        ws.frontmostPID = nil
        XCTAssertEqual(c.tile(on: screen), .noFrontmostApp)
        XCTAssertEqual(ws.windowsCallCount, 0)
    }

    func testWindowsThrowing() {
        let (c, ws) = make([win(1)])
        ws.windowsError = FakeWindowSystemError(description: "boom-AX")
        guard case .failed(let reason) = c.tile(on: screen) else { return XCTFail("expected failed") }
        XCTAssertTrue(reason.contains("boom-AX"))
        XCTAssertTrue(ws.setFrameCalls.isEmpty)
    }

    func testZeroEligible() {
        let (c, ws) = make([win(1, minimized: true), win(2, minimized: true)])
        XCTAssertEqual(c.tile(on: screen), .noWindows)
        XCTAssertTrue(ws.setFrameCalls.isEmpty)
    }

    func testSingleWindowFillsVisibleFrame() {
        let (c, ws) = make([win(1)])
        XCTAssertEqual(c.tile(on: screen), .tiled(count: 1))
        XCTAssertEqual(ws.setFrameCalls.count, 1)
        XCTAssertEqual(ws.setFrameCalls[0].0, WindowID(1))
        XCTAssertEqual(ws.setFrameCalls[0].1, screen.visibleFrame)
        XCTAssertNotEqual(ws.setFrameCalls[0].1, screen.frame)
    }

    func testFourWindowsAssignedInReadingOrder() {
        // Scrambled input; reading order: top row (higher y) left-to-right, then bottom row.
        let a = win(1, x: 800, y: 100)  // bottom right
        let b = win(2, x: 100, y: 600)  // top left
        let d = win(3, x: 100, y: 100)  // bottom left
        let e = win(4, x: 800, y: 600)  // top right
        let (c, ws) = make([a, b, d, e])
        XCTAssertEqual(c.tile(on: screen), .tiled(count: 4))
        let expectedIDs = [2, 4, 3, 1].map(WindowID.init)
        let expectedFrames = TilingLayout.frames(count: 4, in: screen.visibleFrame)
        XCTAssertEqual(ws.setFrameCalls.count, 4)
        for (i, call) in ws.setFrameCalls.enumerated() {
            XCTAssertEqual(call.0, expectedIDs[i])
            XCTAssertEqual(call.1, expectedFrames[i])
        }
    }

    func testWindowsOnOtherScreenUntouched() {
        let off = win(9, x: 3000, y: 100)
        let (c, ws) = make([win(1), off, win(2, x: 500)])
        XCTAssertEqual(c.tile(on: screen), .tiled(count: 2))
        XCTAssertFalse(ws.setFrameCalls.contains { $0.0 == WindowID(9) })
        XCTAssertEqual(Set(ws.setFrameCalls.map(\.0)), [WindowID(1), WindowID(2)])
    }

    func testPartialFailure() {
        let (c, ws) = make((1...5).map { win($0, x: CGFloat($0) * 100) })
        ws.failingWindowIDs = [WindowID(2), WindowID(4)]
        XCTAssertEqual(c.tile(on: screen), .partial(succeeded: 3, failed: 2))
        XCTAssertEqual(ws.setFrameCalls.count, 5)
        XCTAssertEqual(Set(ws.setFrameCalls.map(\.0)), Set((1...5).map(WindowID.init)))
    }

    func testAllFailing() {
        let (c, ws) = make((1...3).map { win($0, x: CGFloat($0) * 100) })
        ws.failingWindowIDs = Set((1...3).map(WindowID.init))
        XCTAssertEqual(c.tile(on: screen), .partial(succeeded: 0, failed: 3))
        XCTAssertEqual(ws.setFrameCalls.count, 3)
    }
}
