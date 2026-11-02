import XCTest
import FloTileCore
@testable import FloTile

@MainActor
final class TileOutcomePresenterTests: XCTestCase {
    private final class Recorder {
        var logs: [String] = []
        var permissionCalls = 0
    }

    private func make() -> (TileOutcomePresenter, Recorder) {
        let r = Recorder()
        let p = TileOutcomePresenter(log: { r.logs.append($0) }, onAccessibilityNotGranted: { r.permissionCalls += 1 })
        return (p, r)
    }

    func testSilentOutcomes() {
        for outcome in [TileOutcome.tiled(count: 3), .noWindows, .noFrontmostApp] {
            let (p, r) = make()
            p.present(outcome)
            XCTAssertTrue(r.logs.isEmpty)
            XCTAssertEqual(r.permissionCalls, 0)
        }
    }

    func testPartialLogs() {
        let (p, r) = make()
        p.present(.partial(succeeded: 4, failed: 2))
        XCTAssertEqual(r.logs.count, 1)
        XCTAssertTrue(r.logs[0].contains("4") && r.logs[0].contains("2"))
        XCTAssertEqual(r.permissionCalls, 0)
    }

    func testFailedLogs() {
        let (p, r) = make()
        p.present(.failed(reason: "boom"))
        XCTAssertEqual(r.logs.count, 1)
        XCTAssertTrue(r.logs[0].contains("boom"))
        XCTAssertEqual(r.permissionCalls, 0)
    }

    func testAccessibilityNotGranted() {
        let (p, r) = make()
        p.present(.accessibilityNotGranted)
        XCTAssertEqual(r.permissionCalls, 1)
        XCTAssertTrue(r.logs.isEmpty)
    }

    func testIsSilentTable() {
        XCTAssertTrue(TileOutcomePresenter.isSilent(.tiled(count: 1)))
        XCTAssertTrue(TileOutcomePresenter.isSilent(.noWindows))
        XCTAssertTrue(TileOutcomePresenter.isSilent(.noFrontmostApp))
        XCTAssertFalse(TileOutcomePresenter.isSilent(.partial(succeeded: 1, failed: 1)))
        XCTAssertFalse(TileOutcomePresenter.isSilent(.failed(reason: "x")))
        XCTAssertFalse(TileOutcomePresenter.isSilent(.accessibilityNotGranted))
    }
}
