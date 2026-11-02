import XCTest
@testable import FloTile

final class SelfTestReportTests: XCTestCase {
    func testShapeAndSortedKeysWithIntegers() {
        let json = SelfTestReport.json(
            outcome: "tiled:2",
            screen: CGRect(x: 0, y: 25, width: 1440, height: 875),
            frames: [CGRect(x: 0, y: 25, width: 720, height: 875), CGRect(x: 720, y: 25, width: 720, height: 875)],
            ignored: [CGRect(x: 10, y: 20, width: 30, height: 40)])
        XCTAssertEqual(json, """
        {"frames":[[0,25,720,875],[720,25,720,875]],"ignored":[[10,20,30,40]],\
        "outcome":"tiled:2","screen":{"h":875,"w":1440,"x":0,"y":25}}
        """)
        XCTAssertFalse(json.contains("\n"))
    }

    func testFractionalNumbersKeepDecimals() {
        let json = SelfTestReport.json(outcome: "noWindows", screen: CGRect(x: 0, y: 0, width: 10.5, height: 20),
                                       frames: [], ignored: [])
        XCTAssertTrue(json.contains("\"w\":10.5"), json)
        XCTAssertTrue(json.contains("\"frames\":[]"), json)
    }

    func testErrorJSON() {
        XCTAssertEqual(SelfTestReport.errorJSON("bad"), "{\"error\":\"bad\"}")
    }

    func testUndoJSONHasBothPhasesWithSortedKeys() {
        let json = SelfTestReport.undoJSON(
            first: ("tiled:2", [CGRect(x: 0, y: 25, width: 720, height: 875)]),
            second: ("restored:2", [CGRect(x: 120, y: 140, width: 600, height: 400)]),
            screen: CGRect(x: 0, y: 25, width: 1440, height: 875))
        XCTAssertEqual(json, """
        {"first":{"frames":[[0,25,720,875]],"outcome":"tiled:2"},\
        "screen":{"h":875,"w":1440,"x":0,"y":25},\
        "second":{"frames":[[120,140,600,400]],"outcome":"restored:2"}}
        """)
        XCTAssertFalse(json.contains("\n"))
    }

    func testUndoJSONEmptyFramesAndFractions() {
        let json = SelfTestReport.undoJSON(first: ("noWindows", []), second: ("noWindows", []),
                                           screen: CGRect(x: 0, y: 0, width: 10.5, height: 20))
        XCTAssertTrue(json.contains("\"first\":{\"frames\":[],\"outcome\":\"noWindows\"}"), json)
        XCTAssertTrue(json.contains("\"w\":10.5"), json)
    }
}
