import Foundation

/// Result of a tiling attempt.
public enum TileOutcome: Equatable, Sendable {
    /// Accessibility permission has not been granted; nothing was touched.
    case accessibilityNotGranted
    /// There is no frontmost application (or it is our own process).
    case noFrontmostApp
    /// The frontmost application has no eligible windows on the target screen.
    case noWindows
    /// Every eligible window was positioned successfully.
    case tiled(count: Int)
    /// Some windows could not be positioned (includes the all-failed case).
    case partial(succeeded: Int, failed: Int)
    /// Every window of a snapshot was moved back to its pre-tile frame.
    case restored(count: Int)
    /// Every window of a tiled snapshot was given the display's visible frame.
    case maximized(count: Int)
    /// An explicit undo was requested but no valid snapshot exists; silent.
    case nothingToUndo
    /// Windows could not be enumerated; `reason` describes the error.
    case failed(reason: String)
}
