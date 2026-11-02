import AppKit
import FloTileCore
import os

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let logger = Logger(subsystem: "ie.boboco.FloTile", category: "app")
    private static var delegate: AppDelegate?

    private var statusItemController: StatusItemController?
    private var permissionFlow: AccessibilityPermissionFlow?
    private var settingsModel: SettingsModel?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        Self.delegate = delegate
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.logger.info("FloTile launched")

        #if DEBUG
        if CommandLine.arguments.contains("--self-test-tile") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { Self.runSelfTest() }
            return
        }
        #endif

        settingsModel = SettingsModel(loginItems: SMAppServiceLoginItem())
        let windowSystem = AXWindowSystem()
        let screens = AppKitScreenProvider()
        let coordinator = TileCoordinator(windowSystem: windowSystem, screenProvider: screens)
        permissionFlow = AccessibilityPermissionFlow(requestTrust: { windowSystem.requestTrust() })
        let presenter = TileOutcomePresenter(
            log: { message in Self.logger.error("\(message, privacy: .public)") },
            onAccessibilityNotGranted: { [weak self] in
                self?.handleAccessibilityNotGranted()
            }
        )
        let controller = StatusItemController(
            onTile: { screen in presenter.present(coordinator.tile(on: screen)) },
            onOpenSettings: { [weak self] in self?.openSettings() },
            onCheckForUpdates: {
                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
                UpdateChecker.checkForUpdates(currentVersion: version)
            },
            onQuit: { NSApp.terminate(nil) }
        )
        statusItemController = controller
        if !controller.install() {
            Self.logger.warning("Could not install status item")
        }
    }

    #if DEBUG
    /// Live Accessibility self-test (see scripts/live-ax-test.sh): tiles the
    /// frontmost app on the screen under the mouse, re-reads the windows and
    /// prints one JSON line, then exits.
    private static func runSelfTest() {
        func finish(_ line: String, code: Int32) -> Never {
            print(line)
            fflush(stdout)
            exit(code)
        }
        guard let screen = AppKitScreenProvider.targetScreen(forStatusButton: nil) else {
            finish(SelfTestReport.errorJSON("no screen available"), code: 1)
        }
        let windowSystem = AXWindowSystem()
        let coordinator = TileCoordinator(windowSystem: windowSystem, screenProvider: AppKitScreenProvider())
        // Capture the pid BEFORE tiling so the re-read targets the same app.
        let pid = windowSystem.frontmostApplicationPID()
        let outcome = coordinator.tile(on: screen)
        var frames: [CGRect] = []
        var ignored: [CGRect] = []
        if let pid {
            do {
                let all = try windowSystem.windows(forApplication: pid)
                let eligible = WindowSelector.eligibleWindows(all, on: screen)
                let eligibleIDs = Set(eligible.map(\.id))
                frames = WindowSelector.readingOrder(eligible).map(\.frame)
                ignored = all.filter { !eligibleIDs.contains($0.id) }.map(\.frame)
            } catch {
                finish(SelfTestReport.errorJSON(String(describing: error)), code: 1)
            }
        }
        finish(SelfTestReport.json(outcome: outcome.selfTestLabel, screen: screen.visibleFrame,
                                   frames: frames, ignored: ignored), code: 0)
    }
    #endif

    private func handleAccessibilityNotGranted() {
        Self.logger.info("Accessibility not granted")
        permissionFlow?.present()
    }

    private func openSettings() {
        Self.logger.info("Settings requested")
        if let settingsModel { SettingsWindowController.showShared(model: settingsModel) }
    }
}
