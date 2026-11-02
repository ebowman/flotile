import AppKit
import FloTileCore
import os

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let logger = Logger(subsystem: "ie.boboco.FloTile", category: "app")
    private static var delegate: AppDelegate?

    private var statusItemController: StatusItemController?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        Self.delegate = delegate
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.logger.info("FloTile launched")

        let windowSystem = AXWindowSystem()
        let screens = AppKitScreenProvider()
        let coordinator = TileCoordinator(windowSystem: windowSystem, screenProvider: screens)
        let presenter = TileOutcomePresenter(
            log: { message in Self.logger.error("\(message, privacy: .public)") },
            onAccessibilityNotGranted: { [weak self] in
                self?.handleAccessibilityNotGranted(windowSystem: windowSystem)
            }
        )
        let controller = StatusItemController(
            onTile: { screen in presenter.present(coordinator.tile(on: screen)) },
            onOpenSettings: { [weak self] in self?.openSettings() },
            onQuit: { NSApp.terminate(nil) }
        )
        statusItemController = controller
        if !controller.install() {
            Self.logger.warning("Could not install status item")
        }
    }

    private func handleAccessibilityNotGranted(windowSystem: AXWindowSystem) {
        // TODO(FloTile-3kk.12): replace with the explanatory alert flow.
        Self.logger.info("Accessibility not granted")
        windowSystem.requestTrust()
    }

    private func openSettings() {
        // TODO(FloTile-3kk.13): present the settings window.
        Self.logger.info("Settings requested")
    }
}
