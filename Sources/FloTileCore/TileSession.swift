import Foundation
import CoreGraphics

/// Per-app snapshot store implementing the guarded click cycle.
///
/// In plain words: clicking tiles the frontmost app's windows and remembers where they were.
/// With "maximize on second click" on, click 2 maximizes every moved window in place (stacking
/// order kept) and click 3 restores the original frames; with it off, click 2 restores. The same
/// guards apply to every step: the same app is frontmost on the same screen, every moved window
/// is still present and where the last step left it, and no new eligible window has appeared;
/// windows that never moved are ignored. A lone window that already fills the display skips the
/// maximize step. If anything changed, the click tiles afresh and replaces the old snapshot (only
/// when the new tile produced one; a tile that yields no snapshot keeps the previous snapshot).
/// Explicit undo always restores the originals from either phase.
/// Each app has its own snapshot, and a snapshot is consumed when it is restored.
@MainActor
public final class TileSession {
    private let coordinator: TileCoordinator
    private let windowSystem: any WindowSystem
    private let tolerance: CGFloat
    private let maximizeOnSecondClick: () -> Bool
    private var snapshots: [pid_t: TileSnapshot] = [:]

    /// The decision taken by the most recent `handleClick`/`undo`. It is nil before any call
    /// and after a call that returned early (`.accessibilityNotGranted`, `.noFrontmostApp`,
    /// `.nothingToUndo`), so it never carries a stale value from an earlier call.
    public private(set) var lastDecision: UndoDecision?

    /// Number of stored snapshots (for tests).
    public var snapshotCount: Int { snapshots.count }

    public init(coordinator: TileCoordinator, windowSystem: any WindowSystem, tolerance: CGFloat = 2,
                maximizeOnSecondClick: @escaping () -> Bool = { false }) {
        self.coordinator = coordinator
        self.windowSystem = windowSystem
        self.tolerance = tolerance
        self.maximizeOnSecondClick = maximizeOnSecondClick
    }

    /// Decides for `pid` using a fresh window enumeration. If enumeration throws,
    /// the current window list is treated as empty so the decision is a fresh
    /// tile; the coordinator then reports the real `.failed` error.
    private func decision(for pid: pid_t, on screen: ScreenInfo) -> UndoDecision {
        // No snapshot: decide returns .tileFresh(.noSnapshot) regardless, so skip the AX read.
        guard snapshots[pid] != nil else { return .tileFresh(.noSnapshot) }
        let current = (try? windowSystem.windows(forApplication: pid)) ?? []
        let eligible = WindowSelector.eligibleWindows(current, on: screen)
        return UndoDecision.decide(snapshot: snapshots[pid], frontmostPID: pid, screenID: screen.id,
                                   currentEligibleWindows: eligible, tolerance: tolerance,
                                   maximizeOnSecondClick: maximizeOnSecondClick(),
                                   fillFrame: TilingLayout.insetIntegral(screen.visibleFrame))
    }

    private func restoreAndClear(pid: pid_t, snapshot: TileSnapshot) -> TileOutcome {
        let outcome = coordinator.restore(snapshot)
        snapshots[pid] = nil
        return outcome
    }

    /// Handles a tile click: restores when the guarded toggle allows it, else tiles afresh.
    public func handleClick(on screen: ScreenInfo) -> TileOutcome {
        lastDecision = nil
        guard windowSystem.isTrusted else { return .accessibilityNotGranted }
        guard let pid = windowSystem.frontmostApplicationPID() else { return .noFrontmostApp }
        let decision = decision(for: pid, on: screen)
        lastDecision = decision
        switch decision {
        case .restore:
            // decide returns .restore only when a snapshot exists for pid.
            return restoreAndClear(pid: pid, snapshot: snapshots[pid]!)
        case .maximize:
            // decide returns .maximize only when a snapshot exists for pid. A nil snapshot keeps
            // the tiled one, so the next click retries.
            let result = coordinator.maximizeAndSnapshot(snapshots[pid]!, on: screen)
            if let snapshot = result.snapshot { snapshots[pid] = snapshot }
            return result.outcome
        case .tileFresh:
            let result = coordinator.tileAndSnapshot(on: screen)
            // A tile that produced no snapshot (failed enumeration, no windows, nothing moved)
            // must not discard the previous one; UndoDecision's window-set/frame guards already
            // prevent a stale snapshot from being restored against a changed layout.
            if let snapshot = result.snapshot { snapshots[pid] = snapshot }
            return result.outcome
        }
    }

    /// Whether an undo would currently succeed for `frontmostPID`. No side effects.
    public func canUndo(frontmostPID: pid_t?, on screen: ScreenInfo) -> Bool {
        guard let pid = frontmostPID, windowSystem.isTrusted else { return false }
        let d = decision(for: pid, on: screen)
        return d == .restore || d == .maximize
    }

    /// Explicit undo: restores the frontmost app's snapshot if still valid, else `.nothingToUndo`.
    public func undo(on screen: ScreenInfo) -> TileOutcome {
        lastDecision = nil
        guard let pid = windowSystem.frontmostApplicationPID(),
              canUndo(frontmostPID: pid, on: screen),
              let snapshot = snapshots[pid] else { return .nothingToUndo }
        lastDecision = .restore
        return restoreAndClear(pid: pid, snapshot: snapshot)
    }

    /// Drops snapshots whose process is no longer running.
    public func prune(isRunning: (pid_t) -> Bool) {
        for pid in Array(snapshots.keys) where !isRunning(pid) { snapshots[pid] = nil }
    }

    /// Drops the snapshot for `pid`, if any.
    public func forget(pid: pid_t) {
        snapshots[pid] = nil
    }
}
