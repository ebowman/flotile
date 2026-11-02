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

    private func handleAccessibilityNotGranted() {
        Self.logger.info("Accessibility not granted")
        permissionFlow?.present()
    }

    private func openSettings() {
        Self.logger.info("Settings requested")
        if let settingsModel { SettingsWindowController.showShared(model: settingsModel) }
    }
}
