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
        let host = NSHostingController(rootView: SettingsView(model: model))
        host.sizingOptions = [.preferredContentSize]
        host.view.layoutSubtreeIfNeeded()
        let window = NSWindow(contentViewController: host)
        window.title = "FlöTile Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(host.view.fittingSize)
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
    }
}
