import Foundation
import CoreGraphics

/// Orchestrates tiling of the frontmost application's windows on one screen.
public struct TileCoordinator: Sendable {
    private let windowSystem: any WindowSystem
    private let now: @Sendable () -> Date

    /// Creates a coordinator. `now` supplies snapshot timestamps.
    public init(windowSystem: any WindowSystem, now: @escaping @Sendable () -> Date = Date.init) {
        self.windowSystem = windowSystem
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

        // Adapter contract says ids are unique, but never trap on a misbehaving adapter: last wins.
        let before = Dictionary(eligible.map { ($0.id, $0.frame) }, uniquingKeysWith: { _, last in last })
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

    /// Gives every window in `snapshot.after` the display's visible frame (inset to integral
    /// edges) and returns a `.maximized` snapshot whose `before` is unchanged, so a later
    /// `restore` returns windows to their original frames.
    ///
    /// Stacking order is untouched because only position/size are written via `setFrame`;
    /// nothing is raised, focused or activated. Performs no trust check (same contract as
    /// `restore`; the session checks trust). The snapshot is nil when nothing succeeded or
    /// no window could be recorded. `after` is re-read for every previously tiled window
    /// still present (even ones whose maximize failed, so they are still restored); if the
    /// re-read throws, old frames are used with succeeded ids replaced by the fill frame.
    public func maximizeAndSnapshot(_ snapshot: TileSnapshot, on screen: ScreenInfo)
        -> (outcome: TileOutcome, snapshot: TileSnapshot?) {
        if snapshot.after.isEmpty { return (.noWindows, nil) }
        let fill = TilingLayout.insetIntegral(screen.visibleFrame)
        var movedIDs: Set<WindowID> = []
        var failed = 0
        for id in snapshot.after.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            do {
                try windowSystem.setFrame(fill, of: id)
                movedIDs.insert(id)
            } catch {
                failed += 1
            }
        }
        let succeeded = movedIDs.count
        let outcome: TileOutcome = failed == 0
            ? .maximized(count: succeeded) : .partial(succeeded: succeeded, failed: failed)
        if succeeded == 0 { return (outcome, nil) }

        var newAfter: [WindowID: CGRect] = [:]
        if let reread = try? windowSystem.windows(forApplication: snapshot.pid) {
            for window in reread where snapshot.after[window.id] != nil {
                newAfter[window.id] = window.frame
            }
        } else {
            newAfter = snapshot.after
            for id in movedIDs { newAfter[id] = fill }
        }
        if newAfter.isEmpty { return (outcome, nil) }
        return (outcome, TileSnapshot(pid: snapshot.pid, screenID: snapshot.screenID, before: snapshot.before,
                                      after: newAfter, takenAt: now(), phase: .maximized))
    }

    /// Moves every window in `snapshot.after` (the windows tiling moved) back to its
    /// recorded `before` frame; windows that failed to move are left alone and not counted.
    /// Performs no trust check: callers decide (the session checks trust via
    /// decide/tile). Unknown windows (setFrame throws) count as failures.
    public func restore(_ snapshot: TileSnapshot) -> TileOutcome {
        if snapshot.before.isEmpty || snapshot.after.isEmpty { return .noWindows }
        var succeeded = 0
        var failed = 0
        for id in snapshot.after.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let frame = snapshot.before[id] else { continue }
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
