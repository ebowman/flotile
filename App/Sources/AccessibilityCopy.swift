import AppKit

enum AccessibilityPromptDecision: Equatable {
    case openSettingsAndPrompt
    case dismiss
}

/// User-facing copy and decision logic for the Accessibility permission prompt.
/// Deliberately avoids naming a System Settings breadcrumb: the pane title
/// differs across macOS versions (e.g. "Device Control and Data Access" on macOS 27).
enum AccessibilityCopy {
    static let alertTitle = "FlöTile needs Accessibility access"
    static let alertBody = """
        FlöTile uses macOS Accessibility only to move and resize the front app's windows when you click its menu bar icon. \
        It never reads window contents or keystrokes, and nothing leaves your Mac.

        After you enable FlöTile in the Accessibility permissions pane, click the icon again.
        """
    static let openSettingsButton = "Open System Settings"
    static let notNowButton = "Not Now"
    static let settingsURLString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

    /// Guarded by a unit test proving the constant parses.
    static var settingsURL: URL { URL(string: settingsURLString)! }

    static func decide(buttonResponse: NSApplication.ModalResponse) -> AccessibilityPromptDecision {
        buttonResponse == .alertFirstButtonReturn ? .openSettingsAndPrompt : .dismiss
    }
}
