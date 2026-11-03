import Foundation
import CoreGraphics

/// Outcome of deciding what a tile click should do given the last snapshot.
///
/// A later click continues the cycle only when the same app is frontmost on the same screen,
/// every window the last step moved is still present and (approximately) where that step left
/// it, and no new eligible window has appeared; windows that never moved are ignored.
/// With "maximize on second click" on, the click after tiling maximizes every moved window and
/// the next click restores the originals; with it off, the click after tiling restores. A lone
/// window that already fills the display skips the maximize step. If a guard fails, the click
/// tiles afresh.
public enum UndoDecision: Equatable, Sendable {
    /// Restore the `before` frames.
    case restore
    /// Give every moved window the fill frame, keeping stacking order.
    case maximize
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
        tolerance: CGFloat = 2,
        maximizeOnSecondClick: Bool = false,
        fillFrame: CGRect? = nil
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
        if snapshot.phase == .tiled, maximizeOnSecondClick, let fillFrame {
            let needsMaximize = currentEligibleWindows.contains { w in
                !unmoved.contains(w.id) && snapshot.after[w.id] != nil
                    && !FrameComparison.approximatelyEqual(w.frame, fillFrame, tolerance: tolerance)
            }
            if needsMaximize { return .maximize }
        }
        return .restore
    }
}
