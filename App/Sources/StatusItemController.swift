import AppKit
import FloTileCore
import os

/// Owns the menu-bar `NSStatusItem`: plain click tiles, option/right/control click shows the menu.
@MainActor
final class StatusItemController: NSObject {
    private static let logger = Logger(subsystem: "ie.boboco.FloTile", category: "statusitem")

    private var statusItem: NSStatusItem?
    private let onTile: (ScreenInfo) -> Void
    private let onOpenSettings: () -> Void
    private let onCheckForUpdates: () -> Void
    private let onQuit: () -> Void

    init(
        onTile: @escaping (ScreenInfo) -> Void,
        onOpenSettings: @escaping () -> Void,
        onCheckForUpdates: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.onTile = onTile
        self.onOpenSettings = onOpenSettings
        self.onCheckForUpdates = onCheckForUpdates
        self.onQuit = onQuit
        super.init()
    }

    /// Returns false (creating nothing) if the system gave no button.
    @discardableResult
    func install() -> Bool {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = item.button else {
            NSStatusBar.system.removeStatusItem(item)
            return false
        }
        let image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "FlöTile")
        image?.isTemplate = true
        button.image = image
        button.toolTip = "FlöTile — click to tile the front app's windows"
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
        return true
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        let button: ClickButton
        let modifiers: ClickModifiers
        if let event = NSApp.currentEvent {
            button = EventMapping.clickButton(for: event.type)
            modifiers = EventMapping.clickModifiers(from: event.modifierFlags)
        } else {
            button = .left
            modifiers = []
        }
        dispatch(ClickAction.action(for: button, modifiers: modifiers))
    }

    func dispatch(_ action: ClickAction) {
        switch action {
        case .tile:
            if let screen = AppKitScreenProvider.targetScreen(forStatusButton: statusItem?.button) {
                onTile(screen)
            } else {
                Self.logger.warning("No target screen; skipping tile")
            }
        case .showMenu:
            showMenu()
        case .ignore:
            break
        }
    }

    func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let settings = NSMenuItem(title: "Settings…", action: #selector(settingsItemSelected), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let updates = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdatesItemSelected), keyEquivalent: "")
        updates.target = self
        menu.addItem(updates)
        menu.addItem(NSMenuItem.separator())
        let quit = NSMenuItem(title: "Quit FlöTile", action: #selector(quitItemSelected), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    private func showMenu() {
        guard let item = statusItem, let button = item.button else {
            Self.logger.warning("showMenu without installed status item")
            return
        }
        item.menu = buildMenu()
        button.performClick(nil)
        // Clearing restores plain-click action behaviour.
        item.menu = nil
    }

    @objc private func settingsItemSelected() { onOpenSettings() }
    @objc private func checkForUpdatesItemSelected() { onCheckForUpdates() }
    @objc private func quitItemSelected() { onQuit() }
}
