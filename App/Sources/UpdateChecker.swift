// Ported from GateOpener (MIT).
import AppKit
import FloTileCore
import Foundation
import os

/// How a check is surfaced: `interactive` (menu click, always answers with an
/// alert) or `background` (scheduled, silent unless an update is available).
enum UpdateCheckPresentation {
    case interactive
    case background
}

/// Injectable side effects for `UpdateChecker` so the state -> alert mapping
/// can be tested without network, disk or UI.
@MainActor
struct UpdateCheckerDependencies {
    var fetch: (_ currentVersion: String) async throws -> UpdateCheckResult
    var download: (_ manifest: UpdateManifest) async throws -> URL
    var verify: (_ dmgURL: URL, _ manifest: UpdateManifest) throws -> Void
    var launch: (_ dmgURL: URL) throws -> Void
    var discard: (_ dmgURL: URL) -> Void
    var runAlert: (_ alert: NSAlert) -> NSApplication.ModalResponse
    var activate: () -> Void
    var recordCheck: (_ date: Date) -> Void
    var skippedVersion: () -> String?
    var recordSkippedVersion: (_ version: String) -> Void

    static var live: UpdateCheckerDependencies {
        UpdateCheckerDependencies(
            fetch: { try await UpdateFetcher.checkForUpdate(currentVersion: $0) },
            download: { try await UpdateFetcher.downloadDMG(manifest: $0) },
            verify: { try UpdateInstaller.verify(dmgURL: $0, manifest: $1) },
            launch: { try UpdateInstallerRunner.launchSwap(dmgURL: $0) },
            discard: { try? FileManager.default.removeItem(at: $0) },
            runAlert: { $0.runModal() },
            activate: { NSApp.activate(ignoringOtherApps: true) },
            recordCheck: { UpdateCheckStore().recordLastCheck($0) },
            skippedVersion: { UpdateCheckStore().loadSkippedVersion() },
            recordSkippedVersion: { UpdateCheckStore().recordSkippedVersion($0) }
        )
    }
}

/// Drives update checks: fetch the manifest, compare versions, verify a
/// candidate DMG, and (only on explicit user confirmation) hand off to
/// `UpdateInstallerRunner` for the irreversible swap.
///
/// Two presentations. `.interactive` (the "Check for Updates…" menu item)
/// shows an `NSAlert` for every outcome: up to date, update available
/// (Install and Relaunch / Cancel) and fetch error; any skipped version is
/// ignored. `.background` (scheduled checks) is silent when up to date, on a
/// fetch error (logged only) and when the available version is the skipped
/// one; otherwise it activates the app and offers Install and Relaunch /
/// Remind Me Later / Skip This Version. Skip stores the exact version string
/// and applies to background checks only. Install failures (download,
/// verification, launch) alert in both presentations. Every successful fetch
/// records the check time before any alert; a failed fetch does not.
@MainActor
enum UpdateChecker {
    private static let logger = Logger(subsystem: "ie.boboco.FloTile", category: "update-checker")

    /// Entry point for the "Check for Updates…" menu item.
    static func checkForUpdates(
        currentVersion: String,
        dependencies: UpdateCheckerDependencies = .live,
        presentation: UpdateCheckPresentation = .interactive
    ) {
        Task { @MainActor in
            await run(currentVersion: currentVersion, dependencies: dependencies, presentation: presentation)
        }
    }

    /// The whole flow, awaitable for tests.
    static func run(
        currentVersion: String,
        dependencies deps: UpdateCheckerDependencies,
        presentation: UpdateCheckPresentation = .interactive
    ) async {
        let result: UpdateCheckResult
        do {
            result = try await deps.fetch(currentVersion)
        } catch {
            if presentation == .background {
                logger.info("background update check failed: \(UpdateCopy.fetchErrorMessage(error), privacy: .public)")
                return
            }
            present(error: UpdateCopy.fetchErrorMessage(error), deps)
            return
        }

        deps.recordCheck(Date())

        switch result {
        case .upToDate:
            if presentation == .background { return }
            let alert = makeAlert(
                title: UpdateCopy.upToDateTitle,
                body: UpdateCopy.upToDateBody(currentVersion: currentVersion),
                style: .informational,
                buttons: [UpdateCopy.okButton]
            )
            deps.activate()
            _ = deps.runAlert(alert)
        case .updateAvailable(let manifest):
            if presentation == .background, manifest.latestVersion == deps.skippedVersion() {
                logger.info("background update check: version \(manifest.latestVersion, privacy: .public) is skipped")
                return
            }
            let buttons = presentation == .background
                ? [UpdateCopy.installButton, UpdateCopy.remindLaterButton, UpdateCopy.skipVersionButton]
                : [UpdateCopy.installButton, UpdateCopy.cancelButton]
            let alert = makeAlert(
                title: UpdateCopy.updateAvailableTitle(latestVersion: manifest.latestVersion),
                body: UpdateCopy.updateAvailableBody(currentVersion: currentVersion, notes: manifest.notes),
                style: .informational,
                buttons: buttons
            )
            deps.activate()
            switch deps.runAlert(alert) {
            case .alertFirstButtonReturn:
                await downloadVerifyAndInstall(manifest: manifest, deps)
            case .alertThirdButtonReturn where presentation == .background:
                deps.recordSkippedVersion(manifest.latestVersion)
            default:
                return
            }
        }
    }

    /// ORDER OF OPERATIONS IS THE SAFETY PROPERTY: download and verification
    /// failures both return BEFORE anything destructive is attempted, leaving
    /// the app untouched. A failed verification also deletes the downloaded
    /// temp file. `launch` is only reached after `verify` succeeded.
    private static func downloadVerifyAndInstall(manifest: UpdateManifest, _ deps: UpdateCheckerDependencies) async {
        let dmgURL: URL
        do {
            dmgURL = try await deps.download(manifest)
        } catch {
            present(error: UpdateCopy.downloadErrorMessage(error), deps)
            return
        }

        do {
            try deps.verify(dmgURL, manifest)
        } catch {
            deps.discard(dmgURL)
            logger.error("update verification failed: \(String(describing: error), privacy: .public)")
            present(error: UpdateCopy.verificationErrorMessage(error), deps)
            return
        }

        do {
            try deps.launch(dmgURL)
            // launchSwap calls NSApp.terminate(nil) on success.
        } catch {
            logger.error("update swap launch failed: \(String(describing: error), privacy: .public)")
            present(error: UpdateCopy.launchErrorMessage(error), deps)
        }
    }

    private static func present(error message: String, _ deps: UpdateCheckerDependencies) {
        let alert = makeAlert(
            title: UpdateCopy.errorTitle,
            body: message,
            style: .warning,
            buttons: [UpdateCopy.okButton]
        )
        deps.activate()
        _ = deps.runAlert(alert)
    }

    private static func makeAlert(title: String, body: String, style: NSAlert.Style, buttons: [String]) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.alertStyle = style
        for b in buttons { alert.addButton(withTitle: b) }
        return alert
    }
}
