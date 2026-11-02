import Foundation
import CoreGraphics

/// Opaque identifier for a screen.
public struct ScreenID: Hashable, Sendable {
    /// The underlying integer value.
    public let rawValue: Int

    /// Creates a screen identifier from a raw integer.
    public init(_ rawValue: Int) {
        self.rawValue = rawValue
    }
}

/// A snapshot of a screen. Both rects are in AppKit coordinates.
public struct ScreenInfo: Hashable, Sendable {
    /// Screen identifier.
    public let id: ScreenID
    /// Full screen frame, AppKit coordinates.
    public let frame: CGRect
    /// Usable frame, AppKit coordinates; excludes the menu bar and Dock.
    public let visibleFrame: CGRect

    /// Creates a screen snapshot; both rects must be in AppKit coordinates.
    public init(id: ScreenID, frame: CGRect, visibleFrame: CGRect) {
        self.id = id
        self.frame = frame
        self.visibleFrame = visibleFrame
    }
}
