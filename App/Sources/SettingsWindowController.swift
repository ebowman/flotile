import AppKit
import FloTileCore
import SwiftUI

/// Singleton settings window hosting `SettingsView`.
@MainActor
final class SettingsWindowController: NSWindowController {
    private static var shared: SettingsWindowController?

    static var sharedWindowForTesting: NSWindow? { shared?.window }

    static func showShared(model: SettingsModel) {
        let controller: SettingsWindowController
        if let existing = shared {
            controller = existing
        } else {
            controller = SettingsWindowController(model: model)
            shared = controller
        }
        NSApp.activate(ignoringOtherApps: true)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private convenience init(model: SettingsModel) {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
        window.title = "FlöTile Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
    }
}
