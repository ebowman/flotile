import Foundation
import CoreGraphics

/// Tolerant rectangle comparison.
public enum FrameComparison {
    /// True iff each of the four edges (minX, minY, maxX, maxY) differs by at most
    /// `tolerance` (inclusive).
    ///
    /// Edges are compared rather than origin+size so that the allowed error on each
    /// side is uniform and a size change cannot hide behind an offsetting origin
    /// change. The default of 2 points absorbs the rounding and pixel-snapping
    /// that apps and the Accessibility API introduce when frames are set and re-read.
    public static func approximatelyEqual(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(a.minX - b.minX) <= tolerance
            && abs(a.minY - b.minY) <= tolerance
            && abs(a.maxX - b.maxX) <= tolerance
            && abs(a.maxY - b.maxY) <= tolerance
    }
}
