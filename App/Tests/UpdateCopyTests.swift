import XCTest
import FloTileCore
@testable import FloTile

final class UpdateCopyTests: XCTestCase {
    func testRemindLaterButton() {
        XCTAssertEqual(UpdateCopy.remindLaterButton, "Remind Me Later")
    }

    func testSkipVersionButton() {
        XCTAssertEqual(UpdateCopy.skipVersionButton, "Skip This Version")
    }

    func testUpToDateMentionsVersion() {
        XCTAssertFalse(UpdateCopy.upToDateTitle.isEmpty)
        XCTAssertTrue(UpdateCopy.upToDateBody(currentVersion: "1.2.3").contains("1.2.3"))
    }

    func testUpdateAvailableMentionsBothVersionsAndNotes() {
        XCTAssertTrue(UpdateCopy.updateAvailableTitle(latestVersion: "2.0").contains("2.0"))
        let body = UpdateCopy.updateAvailableBody(currentVersion: "1.0", notes: "Fixes")
        XCTAssertTrue(body.contains("1.0"))
        XCTAssertTrue(body.contains("Fixes"))
        XCTAssertEqual(UpdateCopy.updateAvailableBody(currentVersion: "1.0", notes: ""), "You have 1.0.")
    }

    func testFetchErrorMessages() {
        XCTAssertTrue(UpdateCopy.fetchErrorMessage(UpdateFetchError.network("offline")).contains("offline"))
        XCTAssertTrue(UpdateCopy.fetchErrorMessage(UpdateFetchError.badResponse(status: 404)).contains("404"))
        XCTAssertFalse(UpdateCopy.fetchErrorMessage(UpdateFetchError.invalidManifestURL("x")).isEmpty)
        XCTAssertFalse(UpdateCopy.fetchErrorMessage(UpdateFetchError.malformedManifest("x")).isEmpty)
        XCTAssertTrue(UpdateCopy.fetchErrorMessage(UpdateFetchError.downloadFailed("boom")).contains("boom"))
        XCTAssertTrue(UpdateCopy.fetchErrorMessage(UpdateFetchError.downloadBadResponse(status: 500)).contains("500"))
        struct Other: LocalizedError { var errorDescription: String? { "other-desc" } }
        XCTAssertTrue(UpdateCopy.fetchErrorMessage(Other()).contains("other-desc"))
        XCTAssertTrue(UpdateCopy.downloadErrorMessage(UpdateFetchError.downloadFailed("boom")).contains("boom"))
    }

    func testVerificationErrorMessages() {
        let errors: [UpdateVerificationError] = [
            .invalidDMGURL("u"), .insecureDMGURL("u"),
            .digestMismatch(expected: "a", actual: "b"), .notarizationFailed, .unreadableFile("f"),
        ]
        for e in errors {
            let m = UpdateCopy.verificationErrorMessage(e)
            XCTAssertTrue(m.contains("could not be verified"))
            XCTAssertTrue(m.contains("has not been changed"))
        }
        XCTAssertTrue(UpdateCopy.verificationErrorMessage(UpdateVerificationError.notarizationFailed).contains("notarized"))
    }

    func testLaunchErrorMessages() {
        for e: UpdateSwapError in [.scriptWriteFailed("w"), .scriptPermissionsFailed("p"), .launchFailed("l")] {
            XCTAssertTrue(UpdateCopy.launchErrorMessage(e).contains("has not been changed"))
        }
        XCTAssertTrue(UpdateCopy.launchErrorMessage(UpdateSwapError.launchFailed("lx")).contains("lx"))
        struct Plain: Error {}
        XCTAssertFalse(UpdateCopy.launchErrorMessage(Plain()).isEmpty)
    }
}
