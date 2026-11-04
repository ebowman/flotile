import Foundation
import CoreGraphics

/// Abstraction over the platform window APIs (Accessibility). Implemented by the app layer.
public protocol WindowSystem: Sendable {
    /// Whether the process currently has the Accessibility permission.
    var isTrusted: Bool { get }

    /// PID of the frontmost application, or nil when there is no frontmost
    /// app OR when it is our own process.
    func frontmostApplicationPID() -> pid_t?

    /// Windows of the given application. Frames are already in AppKit coordinates.
    ///
    /// Stability contract: a `WindowID` MUST be stable for the lifetime of a window
    /// within the process (the same window returns the same id on every enumeration).
    /// Ids are retired when the window disappears from an enumeration of its app.
    /// Adapters should use `StableHandleRegistry` to achieve this.
    func windows(forApplication pid: pid_t) throws -> [WindowInfo]

    /// Moves/resizes a window to `frame` (AppKit coordinates). Throws on per-window failure.
    func setFrame(_ frame: CGRect, of window: WindowID) throws
}
