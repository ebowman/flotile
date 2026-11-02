import Foundation
import CoreGraphics

/// Orchestrates tiling of the frontmost application's windows on one screen.
public struct TileCoordinator: Sendable {
    private let windowSystem: any WindowSystem
    private let screenProvider: any ScreenProvider
    private let now: @Sendable () -> Date

    /// Creates a coordinator. `screenProvider` is stored for the app layer /
    /// future use; `tile(on:)` does not call it. `now` supplies snapshot timestamps.
    public init(windowSystem: any WindowSystem, screenProvider: any ScreenProvider,
                now: @escaping @Sendable () -> Date = Date.init) {
        self.windowSystem = windowSystem
        self.screenProvider = screenProvider
        self.now = now
    }

    private enum Preparation {
        case early(TileOutcome)
        case ready(pid: pid_t, eligible: [WindowInfo])
    }

    private func prepare(on screen: ScreenInfo) -> Preparation {
        guard windowSystem.isTrusted else { return .early(.accessibilityNotGranted) }
        guard let pid = windowSystem.frontmostApplicationPID() else { return .early(.noFrontmostApp) }

        let all: [WindowInfo]
        do {
            all = try windowSystem.windows(forApplication: pid)
        } catch {
            return .early(.failed(reason: String(describing: error)))
        }

        let eligible = WindowSelector.readingOrder(WindowSelector.eligibleWindows(all, on: screen))
        if eligible.isEmpty { return .early(.noWindows) }
        return .ready(pid: pid, eligible: eligible)
    }

    /// Positions `eligible` into the grid; returns the outcome, the requested frames
    /// and the ids that were moved successfully.
    private func applyLayout(_ eligible: [WindowInfo], on screen: ScreenInfo)
        -> (outcome: TileOutcome, requested: [WindowID: CGRect]) {
        let frames = TilingLayout.frames(count: eligible.count, in: screen.visibleFrame)
        var succeededFrames: [WindowID: CGRect] = [:]
        var failed = 0
        for (window, frame) in zip(eligible, frames) {
            do {
                try windowSystem.setFrame(frame, of: window.id)
                succeededFrames[window.id] = frame
            } catch {
                failed += 1
            }
        }
        let succeeded = succeededFrames.count
        let outcome: TileOutcome = failed == 0
            ? .tiled(count: succeeded) : .partial(succeeded: succeeded, failed: failed)
        return (outcome, succeededFrames)
    }

    /// Tiles the frontmost app's eligible windows into a grid on `screen.visibleFrame`.
    public func tile(on screen: ScreenInfo) -> TileOutcome {
        switch prepare(on: screen) {
        case .early(let outcome): return outcome
        case .ready(_, let eligible): return applyLayout(eligible, on: screen).outcome
        }
    }

    /// Like `tile(on:)`, but also returns a `TileSnapshot` for undo. The snapshot is
    /// nil unless the outcome is `.tiled` or `.partial` with at least one success.
    /// `after` is re-read from the window system after tiling (apps may clamp sizes);
    /// if that re-read throws, the requested frames of the moved windows are used.
    public func tileAndSnapshot(on screen: ScreenInfo) -> (outcome: TileOutcome, snapshot: TileSnapshot?) {
        let pid: pid_t
        let eligible: [WindowInfo]
        switch prepare(on: screen) {
        case .early(let outcome): return (outcome, nil)
        case .ready(let p, let e): pid = p; eligible = e
        }

        let before = Dictionary(uniqueKeysWithValues: eligible.map { ($0.id, $0.frame) })
        let (outcome, requested) = applyLayout(eligible, on: screen)
        if requested.isEmpty { return (outcome, nil) }

        var after = requested
        if let reread = try? windowSystem.windows(forApplication: pid) {
            after = [:]
            for window in reread where requested[window.id] != nil {
                after[window.id] = window.frame
            }
        }
        // An empty `after` would make UndoDecision treat "no windows at all" (e.g. a later
        // enumeration failure) as unchanged and restore a stale layout, so store no snapshot.
        if after.isEmpty { return (outcome, nil) }
        let snapshot = TileSnapshot(pid: pid, screenID: screen.id, before: before, after: after, takenAt: now())
        return (outcome, snapshot)
    }

    /// Moves every window in `snapshot.before` back to its recorded frame.
    /// Performs no trust check: callers decide (the session checks trust via
    /// decide/tile). Unknown windows (setFrame throws) count as failures.
    public func restore(_ snapshot: TileSnapshot) -> TileOutcome {
        if snapshot.before.isEmpty { return .noWindows }
        var succeeded = 0
        var failed = 0
        for (id, frame) in snapshot.before.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            do {
                try windowSystem.setFrame(frame, of: id)
                succeeded += 1
            } catch {
                failed += 1
            }
        }
        return failed == 0 ? .restored(count: succeeded) : .partial(succeeded: succeeded, failed: failed)
    }
}
