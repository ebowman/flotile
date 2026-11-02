import AppKit
import XCTest
import FloTileCore
@testable import FloTile

@MainActor
final class UpdateCheckerTests: XCTestCase {
    @MainActor private final class Recorder {
        var events: [String] = []
        var alerts: [NSAlert] = []
        var response: NSApplication.ModalResponse = .alertFirstButtonReturn
        var fetchResult: Result<UpdateCheckResult, Error> = .success(.upToDate(manifest: manifest))
        var downloadError: Error?
        var verifyError: Error?
        var launchError: Error?
    }

    private static let manifest = UpdateManifest(
        latestVersion: "2.0.0", notes: "Shiny", dmgURL: "https://example.com/a.dmg", dmgSHA256: "abc")
    private let dmg = URL(fileURLWithPath: "/tmp/x.dmg")

    private func deps(_ r: Recorder) -> UpdateCheckerDependencies {
        let dmg = self.dmg
        return UpdateCheckerDependencies(
            fetch: { _ in r.events.append("fetch"); return try r.fetchResult.get() },
            download: { _ in
                r.events.append("download")
                if let e = r.downloadError { throw e }
                return dmg
            },
            verify: { _, _ in
                r.events.append("verify")
                if let e = r.verifyError { throw e }
            },
            launch: { _ in
                r.events.append("launch")
                if let e = r.launchError { throw e }
            },
            discard: { _ in r.events.append("discard") },
            runAlert: { alert in r.events.append("alert"); r.alerts.append(alert); return r.response },
            activate: { r.events.append("activate") }
        )
    }

    func testUpToDate() async {
        let r = Recorder()
        await UpdateChecker.run(currentVersion: "2.0.0", dependencies: deps(r))
        XCTAssertEqual(r.events, ["fetch", "activate", "alert"])
        XCTAssertEqual(r.alerts.first?.messageText, UpdateCopy.upToDateTitle)
        XCTAssertTrue(r.alerts.first?.informativeText.contains("2.0.0") == true)
    }

    func testUpdateAvailableConfirmed() async {
        let r = Recorder()
        r.fetchResult = .success(.updateAvailable(manifest: Self.manifest))
        await UpdateChecker.run(currentVersion: "1.0.0", dependencies: deps(r))
        XCTAssertEqual(r.events, ["fetch", "activate", "alert", "download", "verify", "launch"])
        let alert = r.alerts[0]
        XCTAssertTrue(alert.messageText.contains("2.0.0"))
        XCTAssertTrue(alert.informativeText.contains("1.0.0"))
        XCTAssertEqual(alert.buttons.map(\.title), ["Install and Relaunch", "Cancel"])
    }

    func testUpdateAvailableDeclined() async {
        let r = Recorder()
        r.fetchResult = .success(.updateAvailable(manifest: Self.manifest))
        r.response = .alertSecondButtonReturn
        await UpdateChecker.run(currentVersion: "1.0.0", dependencies: deps(r))
        XCTAssertEqual(r.events, ["fetch", "activate", "alert"])
    }

    func testVerifyFailureShowsErrorAndDoesNotLaunch() async {
        let r = Recorder()
        r.fetchResult = .success(.updateAvailable(manifest: Self.manifest))
        r.verifyError = UpdateVerificationError.notarizationFailed
        await UpdateChecker.run(currentVersion: "1.0.0", dependencies: deps(r))
        XCTAssertFalse(r.events.contains("launch"))
        XCTAssertEqual(r.events, ["fetch", "activate", "alert", "download", "verify", "discard", "activate", "alert"])
        XCTAssertEqual(r.alerts[1].messageText, UpdateCopy.errorTitle)
        XCTAssertTrue(r.alerts[1].informativeText.contains("notarized"))
    }

    func testDownloadFailureShowsError() async {
        let r = Recorder()
        r.fetchResult = .success(.updateAvailable(manifest: Self.manifest))
        r.downloadError = UpdateFetchError.downloadFailed("boom")
        await UpdateChecker.run(currentVersion: "1.0.0", dependencies: deps(r))
        XCTAssertFalse(r.events.contains("verify"))
        XCTAssertFalse(r.events.contains("launch"))
        XCTAssertTrue(r.alerts[1].informativeText.contains("boom"))
    }

    func testLaunchFailureShowsError() async {
        let r = Recorder()
        r.fetchResult = .success(.updateAvailable(manifest: Self.manifest))
        r.launchError = UpdateSwapError.launchFailed("nope")
        await UpdateChecker.run(currentVersion: "1.0.0", dependencies: deps(r))
        XCTAssertEqual(r.alerts[1].messageText, UpdateCopy.errorTitle)
        XCTAssertTrue(r.alerts[1].informativeText.contains("nope"))
    }

    func testFetchFailureShowsMappedMessage() async {
        let r = Recorder()
        r.fetchResult = .failure(UpdateFetchError.badResponse(status: 404))
        await UpdateChecker.run(currentVersion: "1.0.0", dependencies: deps(r))
        XCTAssertEqual(r.events, ["fetch", "activate", "alert"])
        XCTAssertEqual(r.alerts[0].messageText, UpdateCopy.errorTitle)
        XCTAssertTrue(r.alerts[0].informativeText.contains("404"))
    }

    func testCheckForUpdatesEntryPointRunsFlow() async {
        let r = Recorder()
        UpdateChecker.checkForUpdates(currentVersion: "2.0.0", dependencies: deps(r))
        for _ in 0..<100 where r.alerts.isEmpty { try? await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(r.alerts.count, 1)
    }
}
