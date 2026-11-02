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
    /// Windows could not be enumerated; `reason` describes the error.
    case failed(reason: String)
}
