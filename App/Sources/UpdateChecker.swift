// Ported from GateOpener (MIT).
import AppKit
import FloTileCore
import Foundation
import os

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

    static var live: UpdateCheckerDependencies {
        UpdateCheckerDependencies(
            fetch: { try await UpdateFetcher.checkForUpdate(currentVersion: $0) },
            download: { try await UpdateFetcher.downloadDMG(manifest: $0) },
            verify: { try UpdateInstaller.verify(dmgURL: $0, manifest: $1) },
            launch: { try UpdateInstallerRunner.launchSwap(dmgURL: $0) },
            discard: { try? FileManager.default.removeItem(at: $0) },
            runAlert: { $0.runModal() },
            activate: { NSApp.activate(ignoringOtherApps: true) }
        )
    }
}

/// Drives the "Check for Updates…" menu item: fetch the manifest, compare
/// versions, verify a candidate DMG, and (only on explicit user
/// confirmation) hand off to `UpdateInstallerRunner` for the irreversible
/// swap.
///
/// Deliberately plain: an `NSAlert` per state (up-to-date,
/// update-available-with-confirm, error) and nothing else. Manual only: no
/// timer, no nag. The app activates before each alert; that is safe because
/// this is only reached via a deliberate click on the status-item menu.
@MainActor
enum UpdateChecker {
    private static let logger = Logger(subsystem: "ie.boboco.FloTile", category: "update-checker")

    /// Entry point for the "Check for Updates…" menu item.
    static func checkForUpdates(
        currentVersion: String,
        dependencies: UpdateCheckerDependencies = .live
    ) {
        Task { @MainActor in
            await run(currentVersion: currentVersion, dependencies: dependencies)
        }
    }

    /// The whole flow, awaitable for tests.
    static func run(currentVersion: String, dependencies deps: UpdateCheckerDependencies) async {
        let result: UpdateCheckResult
        do {
            result = try await deps.fetch(currentVersion)
        } catch {
            present(error: UpdateCopy.fetchErrorMessage(error), deps)
            return
        }

        switch result {
        case .upToDate:
            let alert = makeAlert(
                title: UpdateCopy.upToDateTitle,
                body: UpdateCopy.upToDateBody(currentVersion: currentVersion),
                style: .informational,
                buttons: [UpdateCopy.okButton]
            )
            deps.activate()
            _ = deps.runAlert(alert)
        case .updateAvailable(let manifest):
            let alert = makeAlert(
                title: UpdateCopy.updateAvailableTitle(latestVersion: manifest.latestVersion),
                body: UpdateCopy.updateAvailableBody(currentVersion: currentVersion, notes: manifest.notes),
                style: .informational,
                buttons: [UpdateCopy.installButton, UpdateCopy.cancelButton]
            )
            deps.activate()
            guard deps.runAlert(alert) == .alertFirstButtonReturn else { return }
            await downloadVerifyAndInstall(manifest: manifest, deps)
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
