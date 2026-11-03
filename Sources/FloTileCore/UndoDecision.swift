import Foundation
import CoreGraphics

/// Outcome of deciding what a tile click should do given the last snapshot.
///
/// A second click undoes the previous tiling only when nothing has changed since:
/// same app, same screen, same set of eligible windows (ignoring windows that failed to
/// move), and every moved window still (approximately) where tiling left it. Otherwise the click tiles afresh.
public enum UndoDecision: Equatable, Sendable {
    /// Restore the `before` frames.
    case restore
    /// Tile again from scratch, for the given reason.
    case tileFresh(Reason)

    /// Why undo was not chosen.
    public enum Reason: Equatable, Sendable {
        case noSnapshot, differentApp, differentScreen, windowSetChanged, framesChanged
    }

    /// Decides between undo and a fresh tile. Checks run in this binding order:
    /// no snapshot, pid mismatch, screen mismatch, window-set mismatch, frame drift.
    public static func decide(
        snapshot: TileSnapshot?,
        frontmostPID: pid_t,
        screenID: ScreenID,
        currentEligibleWindows: [WindowInfo],
        tolerance: CGFloat = 2
    ) -> UndoDecision {
        guard let snapshot else { return .tileFresh(.noSnapshot) }
        if snapshot.pid != frontmostPID { return .tileFresh(.differentApp) }
        if snapshot.screenID != screenID { return .tileFresh(.differentScreen) }
        // Windows that failed to move (in `before` but not `after`) are ignored for both the
        // set check and the frame check; any other added or closed window forces a fresh tile.
        let unmoved = Set(snapshot.before.keys).subtracting(snapshot.after.keys)
        if Set(currentEligibleWindows.map(\.id)).subtracting(unmoved) != Set(snapshot.after.keys) {
            return .tileFresh(.windowSetChanged)
        }
        for w in currentEligibleWindows {
            if unmoved.contains(w.id) { continue }
            guard let expected = snapshot.after[w.id],
                  FrameComparison.approximatelyEqual(w.frame, expected, tolerance: tolerance) else {
                return .tileFresh(.framesChanged)
            }
        }
        return .restore
    }
}
