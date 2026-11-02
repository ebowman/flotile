import Foundation
import CoreGraphics

/// Record of one tiling operation, used to decide whether a second click can undo it.
public struct TileSnapshot: Equatable, Sendable {
    /// Process id of the app whose windows were tiled.
    public let pid: pid_t
    /// Screen the windows were tiled on.
    public let screenID: ScreenID
    /// Frames of the eligible windows prior to tiling (what undo restores).
    public let before: [WindowID: CGRect]
    /// Frames observed AFTER tiling, re-read from the system (not the requested
    /// frames), because some apps clamp sizes.
    public let after: [WindowID: CGRect]
    /// When the snapshot was taken.
    public let takenAt: Date

    /// Creates a snapshot.
    public init(pid: pid_t, screenID: ScreenID, before: [WindowID: CGRect], after: [WindowID: CGRect], takenAt: Date) {
        self.pid = pid
        self.screenID = screenID
        self.before = before
        self.after = after
        self.takenAt = takenAt
    }
}
