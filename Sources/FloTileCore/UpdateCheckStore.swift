import Foundation

/// Persists the time of the last automatic update check and the version the user chose to skip.
public struct UpdateCheckStore {
    public static let lastCheckKey = "lastUpdateCheck"
    public static let skippedVersionKey = "skippedUpdateVersion"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The last check time, or nil when unset or not a Date.
    public func loadLastCheck() -> Date? {
        defaults.object(forKey: Self.lastCheckKey) as? Date
    }

    public func recordLastCheck(_ date: Date) {
        defaults.set(date, forKey: Self.lastCheckKey)
    }

    /// The skipped version, or nil when unset, not a String, or empty.
    public func loadSkippedVersion() -> String? {
        guard let value = defaults.object(forKey: Self.skippedVersionKey) as? String,
            !value.isEmpty
        else { return nil }
        return value
    }

    public func recordSkippedVersion(_ version: String) {
        defaults.set(version, forKey: Self.skippedVersionKey)
    }
}
