import AppKit

@MainActor
final class AccessibilityPermissionFlow {
    private let requestTrust: () -> Void
    private let openURL: (URL) -> Bool
    private let runAlert: (NSAlert) -> NSApplication.ModalResponse

    private(set) var lastDecision: AccessibilityPromptDecision?

    init(
        requestTrust: @escaping () -> Void,
        openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) },
        runAlert: ((NSAlert) -> NSApplication.ModalResponse)? = nil
    ) {
        self.requestTrust = requestTrust
        self.openURL = openURL
        self.runAlert = runAlert ?? { alert in
            NSApp.activate(ignoringOtherApps: true)
            return alert.runModal()
        }
    }

    func present() {
        let alert = NSAlert()
        alert.messageText = AccessibilityCopy.alertTitle
        alert.informativeText = AccessibilityCopy.alertBody
        alert.alertStyle = .informational
        alert.addButton(withTitle: AccessibilityCopy.openSettingsButton)
        alert.addButton(withTitle: AccessibilityCopy.notNowButton)

        let decision = AccessibilityCopy.decide(buttonResponse: runAlert(alert))
        lastDecision = decision
        switch decision {
        case .openSettingsAndPrompt:
            requestTrust()  // first, so FloTile appears in the Accessibility list
            _ = openURL(AccessibilityCopy.settingsURL)
        case .dismiss:
            break
        }
    }
}
