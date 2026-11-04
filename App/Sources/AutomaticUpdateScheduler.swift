import Foundation
import FloTileCore

/// Drives automatic background update checks: a one-shot timer shortly after
/// launch plus a repeating poll, each calling `tick()`, which runs `check`
/// only when the user's chosen time of day has passed since the last check.
///
/// Timers are invalidated by `stop()`. The owner (AppDelegate) keeps the
/// instance alive for the process lifetime. The scheduler never writes to the
/// store; `UpdateChecker` records the check time, and only after a successful
/// fetch. A check that leaves the stored time unchanged is treated as failed
/// and delays the next attempt by `failureBackoff`. That backoff is in memory
/// only (reset on relaunch), applies only after an unsuccessful background
/// check, and clears on the next success.
@MainActor
final class AutomaticUpdateScheduler {
    private let isEnabled: () -> Bool
    private let minuteOfDay: () -> Int
    private let store: UpdateCheckStore
    private let now: () -> Date
    private let calendar: Calendar
    private let check: () async -> Void
    private let initialDelay: TimeInterval
    private let pollInterval: TimeInterval
    private let failureBackoff: TimeInterval

    private var initialTimer: Timer?
    private var pollTimer: Timer?
    private var checkInFlight = false
    /// In-memory only: earliest time to retry after a failed background check.
    private var retryNotBefore: Date?

    init(
        isEnabled: @escaping () -> Bool,
        minuteOfDay: @escaping () -> Int,
        store: UpdateCheckStore,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current,
        check: @escaping () async -> Void,
        initialDelay: TimeInterval = 60,
        pollInterval: TimeInterval = 300,
        failureBackoff: TimeInterval = 3_600
    ) {
        self.isEnabled = isEnabled
        self.minuteOfDay = minuteOfDay
        self.store = store
        self.now = now
        self.calendar = calendar
        self.check = check
        self.initialDelay = initialDelay
        self.pollInterval = pollInterval
        self.failureBackoff = failureBackoff
    }

    /// False under XCTest or any `--self-test*` argument.
    nonisolated static func shouldRunAutomatically(arguments: [String], environment: [String: String]) -> Bool {
        if environment["XCTestConfigurationFilePath"] != nil { return false }
        return !arguments.contains { $0.hasPrefix("--self-test") }
    }

    /// Idempotent: a second call while running is a no-op.
    func start() {
        guard initialTimer == nil, pollTimer == nil else { return }
        let initial = Timer.scheduledTimer(withTimeInterval: initialDelay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.tick() }
        }
        initial.tolerance = initialDelay * 0.1
        initialTimer = initial
        let poll = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.tick() }
        }
        poll.tolerance = pollInterval * 0.1
        pollTimer = poll
    }

    func stop() {
        initialTimer?.invalidate()
        pollTimer?.invalidate()
        initialTimer = nil
        pollTimer = nil
    }

    func tick() async {
        guard isEnabled() else { return }
        guard UpdateCheckPolicy.isDue(lastCheck: store.loadLastCheck(), now: now(),
                                      minuteOfDay: minuteOfDay(), calendar: calendar) else { return }
        if let retryNotBefore, now() < retryNotBefore { return }
        guard !checkInFlight else { return }
        checkInFlight = true
        defer { checkInFlight = false }
        let before = store.loadLastCheck()
        await check()
        // UpdateChecker records the time only on success; unchanged means failed.
        if store.loadLastCheck() == before {
            retryNotBefore = now().addingTimeInterval(failureBackoff)
        } else {
            retryNotBefore = nil
        }
    }
}
