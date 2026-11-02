import Foundation
import CoreGraphics

/// Pure selection and ordering of windows for tiling.
public enum WindowSelector {
    /// Returns the windows eligible for tiling on `screen`, preserving input order.
    ///
    /// A window is kept iff all of these hold:
    /// - `isStandard` is true and `isMinimized` is false;
    /// - its frame has strictly positive width and height;
    /// - the center of its frame, `CGPoint(x: midX, y: midY)`, lies inside `screen.frame`.
    ///
    /// `CGRect.contains` treats a point exactly on the max-x or max-y edge as
    /// OUTSIDE, and a point on the min edges as inside; this relies on that.
    /// A window overlapping several screens is therefore owned by the screen
    /// containing its center.
    public static func eligibleWindows(_ windows: [WindowInfo], on screen: ScreenInfo) -> [WindowInfo] {
        windows.filter { window in
            guard window.isStandard, !window.isMinimized else { return false }
            let frame = window.frame
            guard frame.width > 0, frame.height > 0 else { return false }
            let center = CGPoint(x: frame.midX, y: frame.midY)
            return screen.frame.contains(center)
        }
    }

    /// Sorts windows into reading order (top-to-bottom, then left-to-right).
    ///
    /// Keys, in order: `frame.maxY` descending (top first in AppKit
    /// coordinates), `frame.minX` ascending, `discoveryIndex` ascending.
    /// This is a stable total order: `discoveryIndex` is assumed unique per
    /// enumeration, and if two windows tie on all three keys their input
    /// order is kept (ties are broken by original position).
    public static func readingOrder(_ windows: [WindowInfo]) -> [WindowInfo] {
        windows.enumerated().sorted { lhs, rhs in
            let a = lhs.element, b = rhs.element
            if a.frame.maxY != b.frame.maxY { return a.frame.maxY > b.frame.maxY }
            if a.frame.minX != b.frame.minX { return a.frame.minX < b.frame.minX }
            if a.discoveryIndex != b.discoveryIndex { return a.discoveryIndex < b.discoveryIndex }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }
}
