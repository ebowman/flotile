import Combine
import Foundation

/// Observable settings state for the UI. UserDefaults is the source of truth for
/// `maximizeOnSecondClick` (default on when unset); the system is the source of truth for `openAtLogin`.
@MainActor
public final class SettingsModel: ObservableObject {
    @Published public private(set) var openAtLogin: Bool
    @Published public private(set) var maximizeOnSecondClick: Bool
    @Published public private(set) var errorMessage: String?

    public static let maximizeOnSecondClickKey = "maximizeOnSecondClick"

    private let loginItems: any LoginItemService
    private let appName: String
    private let defaults: UserDefaults

    public init(
        loginItems: any LoginItemService, appName: String = "FlöTile",
        defaults: UserDefaults = .standard
    ) {
        self.loginItems = loginItems
        self.appName = appName
        self.defaults = defaults
        self.openAtLogin = loginItems.isEnabled
        self.maximizeOnSecondClick = Self.readMaximize(defaults)
    }

    private static func readMaximize(_ defaults: UserDefaults) -> Bool {
        let key = maximizeOnSecondClickKey
        return defaults.object(forKey: key) == nil ? true : defaults.bool(forKey: key)
    }

    public func setMaximizeOnSecondClick(_ wanted: Bool) {
        defaults.set(wanted, forKey: Self.maximizeOnSecondClickKey)
        maximizeOnSecondClick = Self.readMaximize(defaults)
    }

    /// Re-reads the system state.
    public func refresh() {
        openAtLogin = loginItems.isEnabled
        maximizeOnSecondClick = Self.readMaximize(defaults)
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
