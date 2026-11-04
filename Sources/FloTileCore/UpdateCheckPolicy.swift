import Foundation

/// Decides when the automatic update check is due. The check is scheduled for a daily
/// time of day (minutes after local midnight) and catches up if that time was missed.
public enum UpdateCheckPolicy {
    /// Default scheduled time: 10:00 local (600 minutes after midnight).
    public static let defaultMinuteOfDay = 600

    /// The latest scheduled instant that is not after `now`.
    /// `minuteOfDay` is clamped to 0...1439. If today's scheduled time is still in the
    /// future, yesterday's is returned. If the calendar cannot compute a date, returns `now`.
    public static func mostRecentScheduledInstant(
        before now: Date, minuteOfDay: Int, calendar: Calendar = .current
    ) -> Date {
        let minute = min(max(minuteOfDay, 0), 1439)
        guard
            let today = calendar.date(
                bySettingHour: minute / 60, minute: minute % 60, second: 0, of: now)
        else { return now }
        if today <= now { return today }
        return calendar.date(byAdding: .day, value: -1, to: today) ?? now
    }

    /// Whether a check should run now.
    /// - No previous check (`nil`): due.
    /// - `lastCheck` in the future (clock moved back): due, so a bad stored value self-heals.
    /// - `lastCheck` before the most recent scheduled instant: due. This is the catch-up rule:
    ///   a check missed while the Mac was asleep or the app was closed runs at the next opportunity.
    /// - Otherwise: not due.
    public static func isDue(
        lastCheck: Date?, now: Date, minuteOfDay: Int, calendar: Calendar = .current
    ) -> Bool {
        guard let lastCheck else { return true }
        if lastCheck > now { return true }
        return lastCheck
            < mostRecentScheduledInstant(before: now, minuteOfDay: minuteOfDay, calendar: calendar)
    }
}
