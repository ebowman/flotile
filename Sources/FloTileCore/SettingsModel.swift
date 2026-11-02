import Combine
import Foundation

/// Observable settings state for the UI. The system is the source of truth for `openAtLogin`.
@MainActor
public final class SettingsModel: ObservableObject {
    @Published public private(set) var openAtLogin: Bool
    @Published public private(set) var errorMessage: String?

    private let loginItems: any LoginItemService
    private let appName: String

    public init(loginItems: any LoginItemService, appName: String = "FlöTile") {
        self.loginItems = loginItems
        self.appName = appName
        self.openAtLogin = loginItems.isEnabled
    }

    /// Re-reads the system state.
    public func refresh() {
        openAtLogin = loginItems.isEnabled
    }

    public func setOpenAtLogin(_ wanted: Bool) {
        do {
            try loginItems.setEnabled(wanted)
            errorMessage = nil
        } catch let error as LoginItemError {
            errorMessage = error.message
        } catch {
            let ns = error as NSError
            errorMessage = LoginItemError.userMessage(
                domain: ns.domain, code: ns.code, whileEnabling: wanted, appName: appName)
        }
        openAtLogin = loginItems.isEnabled
    }
}
