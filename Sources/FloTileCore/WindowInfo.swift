import Foundation
import CoreGraphics

/// Opaque handle for a window. The platform adapter maps it back to an AXUIElement.
public struct WindowID: Hashable, Sendable {
    /// The underlying integer value.
    public let rawValue: Int

    /// Creates a window identifier from a raw integer.
    public init(_ rawValue: Int) {
        self.rawValue = rawValue
    }
}

/// A snapshot of a window as seen by the tiling engine.
public struct WindowInfo: Hashable, Sendable {
    /// Opaque window identifier.
    public let id: WindowID
    /// Window frame. INVARIANT: always in AppKit coordinates (origin at the
    /// primary display's bottom-left, y growing up), never raw AX coordinates.
    public let frame: CGRect
    /// Whether the window is minimized.
    public let isMinimized: Bool
    /// Whether the window has role AXWindow and subrole AXStandardWindow (decided by the adapter).
    public let isStandard: Bool
    /// Order in which the window was discovered.
    public let discoveryIndex: Int

    /// Creates a window snapshot; `frame` must be in AppKit coordinates.
    public init(id: WindowID, frame: CGRect, isMinimized: Bool, isStandard: Bool, discoveryIndex: Int) {
        self.id = id
        self.frame = frame
        self.isMinimized = isMinimized
        self.isStandard = isStandard
        self.discoveryIndex = discoveryIndex
    }
}
