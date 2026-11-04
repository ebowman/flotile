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
        var skipped: String?
        var gate: CheckedContinuation<UpdateCheckResult, Error>?
        var suspendFetch = false
    }

    private static let manifest = UpdateManifest(
        latestVersion: "2.0.0", notes: "Shiny", dmgURL: "https://example.com/a.dmg", dmgSHA256: "abc")
    private let dmg = URL(fileURLWithPath: "/tmp/x.dmg")

    private func deps(_ r: Recorder) -> UpdateCheckerDependencies {
        let dmg = self.dmg
        return UpdateCheckerDependencies(
            fetch: { _ in
                r.events.append("fetch")
                if r.suspendFetch {
                    return try await withCheckedThrowingContinuation { r.gate = $0 }
                }
                return try r.fetchResult.get()
            },
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
            activate: { r.events.append("activate") },
            recordCheck: { _ in r.events.append("record") },
            skippedVersion: { r.skipped },
            recordSkippedVersion: { r.events.append("skip:\($0)") }
        )
    }

    func testUpToDate() async {
        let r = Recorder()
        await UpdateChecker.run(currentVersion: "2.0.0", dependencies: deps(r))
        XCTAssertEqual(r.events, ["fetch", "record", "activate", "alert"])
        XCTAssertEqual(r.alerts.first?.messageText, UpdateCopy.upToDateTitle)
        XCTAssertTrue(r.alerts.first?.informativeText.contains("2.0.0") == true)
    }

    func testUpdateAvailableConfirmed() async {
        let r = Recorder()
        r.fetchResult = .success(.updateAvailable(manifest: Self.manifest))
        await UpdateChecker.run(currentVersion: "1.0.0", dependencies: deps(r))
        XCTAssertEqual(r.events, ["fetch", "record", "activate", "alert", "download", "verify", "launch"])
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
        XCTAssertEqual(r.events, ["fetch", "record", "activate", "alert"])
    }

    func testVerifyFailureShowsErrorAndDoesNotLaunch() async {
        let r = Recorder()
        r.fetchResult = .success(.updateAvailable(manifest: Self.manifest))
        r.verifyError = UpdateVerificationError.notarizationFailed
        await UpdateChecker.run(currentVersion: "1.0.0", dependencies: deps(r))
        XCTAssertFalse(r.events.contains("launch"))
        XCTAssertEqual(r.events, ["fetch", "record", "activate", "alert", "download", "verify", "discard", "activate", "alert"])
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

    // MARK: background presentation

    private func runBackground(_ r: Recorder) async {
        await UpdateChecker.run(currentVersion: "1.0.0", dependencies: deps(r), presentation: .background)
    }

    func testBackgroundUpToDateIsSilent() async {
        let r = Recorder()
        await runBackground(r)
        XCTAssertEqual(r.events, ["fetch", "record"])
    }

    func testBackgroundFetchErrorIsSilentAndNotRecorded() async {
        let r = Recorder()
        r.fetchResult = .failure(UpdateFetchError.badResponse(status: 404))
        await runBackground(r)
        XCTAssertEqual(r.events, ["fetch"])
    }

    func testBackgroundInstall() async {
        let r = Recorder()
        r.fetchResult = .success(.updateAvailable(manifest: Self.manifest))
        await runBackground(r)
        XCTAssertEqual(r.events, ["fetch", "record", "activate", "alert", "download", "verify", "launch"])
        XCTAssertEqual(r.alerts[0].buttons.map(\.title), ["Install and Relaunch", "Remind Me Later", "Skip This Version"])
    }

    func testBackgroundRemindLater() async {
        let r = Recorder()
        r.fetchResult = .success(.updateAvailable(manifest: Self.manifest))
        r.response = .alertSecondButtonReturn
        await runBackground(r)
        XCTAssertEqual(r.events, ["fetch", "record", "activate", "alert"])
    }

    func testBackgroundSkipRecordsVersion() async {
        let r = Recorder()
        r.fetchResult = .success(.updateAvailable(manifest: Self.manifest))
        r.response = .alertThirdButtonReturn
        await runBackground(r)
        XCTAssertEqual(r.events, ["fetch", "record", "activate", "alert", "skip:2.0.0"])
    }

    func testBackgroundSkippedVersionIsSilent() async {
        let r = Recorder()
        r.fetchResult = .success(.updateAvailable(manifest: Self.manifest))
        r.skipped = "2.0.0"
        await runBackground(r)
        XCTAssertEqual(r.events, ["fetch", "record"])
    }

    func testBackgroundDifferentSkippedVersionStillAlerts() async {
        let r = Recorder()
        r.fetchResult = .success(.updateAvailable(manifest: Self.manifest))
        r.skipped = "1.5.0"
        r.response = .alertSecondButtonReturn
        await runBackground(r)
        XCTAssertEqual(r.events, ["fetch", "record", "activate", "alert"])
    }

    func testInteractiveIgnoresSkippedVersion() async {
        let r = Recorder()
        r.fetchResult = .success(.updateAvailable(manifest: Self.manifest))
        r.skipped = "2.0.0"
        r.response = .alertSecondButtonReturn
        await UpdateChecker.run(currentVersion: "1.0.0", dependencies: deps(r))
        XCTAssertEqual(r.events, ["fetch", "record", "activate", "alert"])
        XCTAssertEqual(r.alerts[0].buttons.map(\.title), ["Install and Relaunch", "Cancel"])
    }

    func testBackgroundVerifyFailureStillAlerts() async {
        let r = Recorder()
        r.fetchResult = .success(.updateAvailable(manifest: Self.manifest))
        r.verifyError = UpdateVerificationError.notarizationFailed
        await runBackground(r)
        XCTAssertTrue(r.events.contains("discard"))
        XCTAssertFalse(r.events.contains("launch"))
        XCTAssertEqual(r.events.filter { $0 == "alert" }.count, 2)
        XCTAssertEqual(r.alerts[1].messageText, UpdateCopy.errorTitle)
    }

    // MARK: in-flight guard

    func testSecondRunWhileFetchInFlightIsDropped() async {
        let r = Recorder()
        r.suspendFetch = true
        let first = Task { @MainActor in
            await UpdateChecker.run(currentVersion: "1.0.0", dependencies: deps(r), presentation: .background)
        }
        for _ in 0..<500 where !r.events.contains("fetch") { try? await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertEqual(r.events, ["fetch"])

        let second = await UpdateChecker.run(currentVersion: "1.0.0", dependencies: deps(r), presentation: .interactive)
        XCTAssertFalse(second)
        XCTAssertEqual(r.events, ["fetch"])
        XCTAssertTrue(r.alerts.isEmpty)

        r.gate?.resume(returning: .upToDate(manifest: Self.manifest))
        let firstRan = await first.value
        XCTAssertTrue(firstRan)
        XCTAssertEqual(r.events.filter { $0 == "fetch" }.count, 1)
        XCTAssertEqual(r.events.filter { $0 == "record" }.count, 1)
    }

    func testGuardResetsAfterCompletedAndFailedRuns() async {
        let r = Recorder()
        r.fetchResult = .failure(UpdateFetchError.badResponse(status: 500))
        let failed = await UpdateChecker.run(currentVersion: "1.0.0", dependencies: deps(r), presentation: .background)
        XCTAssertTrue(failed)
        r.fetchResult = .success(.upToDate(manifest: Self.manifest))
        let ok = await UpdateChecker.run(currentVersion: "1.0.0", dependencies: deps(r), presentation: .background)
        XCTAssertTrue(ok)
        let again = await UpdateChecker.run(currentVersion: "1.0.0", dependencies: deps(r), presentation: .background)
        XCTAssertTrue(again)
        XCTAssertEqual(r.events, ["fetch", "fetch", "record", "fetch", "record"])
    }
}
