import XCTest
@testable import FloTile

final class AboutCopyTests: XCTestCase {
    func testVersionLineWithDistinctBuild() {
        XCTAssertEqual(AboutCopy.versionLine(shortVersion: "0.1.2", build: "54"), "Version 0.1.2 (54)")
    }

    func testVersionLineWithEmptyBuild() {
        XCTAssertEqual(AboutCopy.versionLine(shortVersion: "0.1.2", build: ""), "Version 0.1.2")
    }

    func testVersionLineWithBuildEqualToShortVersion() {
        XCTAssertEqual(AboutCopy.versionLine(shortVersion: "0.1.2", build: "0.1.2"), "Version 0.1.2")
    }

    func testCreditsContentAndShape() {
        let credits = AboutCopy.credits()
        XCTAssertEqual(credits.components(separatedBy: "\n").count, 3)
        XCTAssertTrue(credits.contains(AboutCopy.tagline))
        XCTAssertTrue(credits.contains("MIT License"))
        XCTAssertTrue(credits.contains("https://github.com/ebowman/flotile"))
        XCTAssertFalse(credits.hasSuffix("\n"))
    }

    func testAppNameHasUmlaut() {
        XCTAssertEqual(AboutCopy.appName, "Fl\u{00F6}Tile")
    }
}
