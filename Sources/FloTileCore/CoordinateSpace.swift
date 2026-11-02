import Foundation
import CoreGraphics

/// Converts between Accessibility (AX) global coordinates and AppKit coordinates.
///
/// AX: origin at the TOP-left of the primary display, y grows down.
/// AppKit: origin at the BOTTOM-left of the primary display, y grows up.
/// Only the primary display's height is needed.
///
/// Formulas (H = primaryScreenHeight): x is unchanged;
/// - AX to AppKit: `minY = H - origin.y - size.height`
/// - AppKit to AX: `y = H - rect.maxY`
///
/// The mapping is an involution on the y axis: converting there and back
/// round-trips exactly for finite values.
public struct CoordinateSpace: Sendable, Hashable {
    /// Height of the primary display's frame.
    public let primaryScreenHeight: CGFloat

    /// Creates a coordinate space for a primary display of the given height.
    public init(primaryScreenHeight: CGFloat) {
        self.primaryScreenHeight = primaryScreenHeight
    }

    /// Converts an AX origin (top-left based) and size to an AppKit rect.
    /// `minY = primaryScreenHeight - origin.y - size.height`; x unchanged.
    public func appKitRect(fromAXOrigin origin: CGPoint, size: CGSize) -> CGRect {
        CGRect(x: origin.x,
               y: primaryScreenHeight - origin.y - size.height,
               width: size.width,
               height: size.height)
    }

    /// Converts an AppKit rect to an AX origin: `x = rect.minX`, `y = primaryScreenHeight - rect.maxY`.
    public func axOrigin(fromAppKit rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX, y: primaryScreenHeight - rect.maxY)
    }
}
