import Combine
import Foundation

/// Observable settings state for the UI. UserDefaults is the source of truth for
/// `maximizeOnSecondClick` (default on when unset), `automaticUpdateChecks` (default on when unset)
/// and `automaticUpdateCheckMinute` (minutes since local midnight, 0...1439, default
/// `UpdateCheckPolicy.defaultMinuteOfDay`); the system is the source of truth for `openAtLogin`.
@MainActor
public final class SettingsModel: ObservableObject {
    @Published public private(set) var openAtLogin: Bool
    @Published public private(set) var maximizeOnSecondClick: Bool
    @Published public private(set) var automaticUpdateChecks: Bool
    @Published public private(set) var automaticUpdateCheckMinute: Int
    @Published public private(set) var errorMessage: String?

    public static let maximizeOnSecondClickKey = "maximizeOnSecondClick"
    public static let automaticUpdateChecksKey = "automaticUpdateChecks"
    public static let automaticUpdateCheckMinuteKey = "automaticUpdateCheckMinute"

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
        self.automaticUpdateChecks = Self.readChecks(defaults)
        self.automaticUpdateCheckMinute = Self.readMinute(defaults)
    }

    private static func readChecks(_ defaults: UserDefaults) -> Bool {
        let key = automaticUpdateChecksKey
        return defaults.object(forKey: key) == nil ? true : defaults.bool(forKey: key)
    }

    private static func readMinute(_ defaults: UserDefaults) -> Int {
        guard let stored = defaults.object(forKey: automaticUpdateCheckMinuteKey) as? Int,
            (0...1439).contains(stored)
        else { return UpdateCheckPolicy.defaultMinuteOfDay }
        return stored
    }

    public func setAutomaticUpdateChecks(_ wanted: Bool) {
        defaults.set(wanted, forKey: Self.automaticUpdateChecksKey)
        automaticUpdateChecks = Self.readChecks(defaults)
    }

    public func setAutomaticUpdateCheckMinute(_ minute: Int) {
        defaults.set(min(max(minute, 0), 1439), forKey: Self.automaticUpdateCheckMinuteKey)
        automaticUpdateCheckMinute = Self.readMinute(defaults)
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
        automaticUpdateChecks = Self.readChecks(defaults)
        automaticUpdateCheckMinute = Self.readMinute(defaults)
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
