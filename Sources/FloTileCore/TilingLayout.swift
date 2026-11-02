import Foundation
import CoreGraphics

/// Pure grid geometry for tiling windows into a rectangle.
///
/// All frames use AppKit screen coordinates: the origin is the bottom-left,
/// and y increases upward. "Row 0" is the TOP row (greatest `maxY`).
public enum TilingLayout {

    /// Grid dimensions for `count` windows.
    ///
    /// `columns` is the smallest integer `c` with `c * c >= count`; `rows` is
    /// `ceil(count / columns)`. Returns `(0, 0)` when `count <= 0`.
    public static func gridDimensions(count: Int) -> (columns: Int, rows: Int) {
        guard count > 0 else { return (0, 0) }
        var columns = 1
        while columns * columns < count { columns += 1 }
        let rows = (count + columns - 1) / columns
        return (columns, rows)
    }

    /// Shrinks `frame` to the largest integral rectangle inside it: the min
    /// edges are rounded up (ceil) and the max edges rounded down (floor).
    /// If that inverts the rectangle (or the input is empty/negative), the
    /// result has zero size at the input origin.
    public static func insetIntegral(_ frame: CGRect) -> CGRect {
        guard frame.size.width > 0, frame.size.height > 0,
              frame.minX.isFinite, frame.minY.isFinite,
              frame.maxX.isFinite, frame.maxY.isFinite else {
            return CGRect(origin: frame.origin, size: .zero)
        }
        let minX = frame.minX.rounded(.up)
        let minY = frame.minY.rounded(.up)
        let maxX = frame.maxX.rounded(.down)
        let maxY = frame.maxY.rounded(.down)
        guard maxX > minX, maxY > minY else {
            return CGRect(origin: frame.origin, size: .zero)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Computes `count` tile frames filling `frame`, in AppKit coordinates
    /// (origin bottom-left, y up).
    ///
    /// - Layout: a `columns x rows` grid from `gridDimensions(count:)`. Row 0
    ///   is the top row. If the last row holds fewer than `columns` windows,
    ///   its cells stretch evenly across the full row width.
    /// - Order: reading order (top row left-to-right, then the next row down).
    /// - Exactness: the input is first normalized with `insetIntegral(_:)`.
    ///   All returned edges are integral; within each row the widths sum
    ///   exactly to the frame width, and row heights sum exactly to the frame
    ///   height. Remainder pixels go to the first cells/rows, never truncated.
    /// - Degenerate input: `count <= 0` returns `[]`. A frame with zero or
    ///   negative width or height (raw `size`, not the standardized `width`/`height`; or one that collapses when normalized)
    ///   returns `count` copies of `CGRect(origin: frame.origin, size: .zero)`.
    public static func frames(count: Int, in frame: CGRect) -> [CGRect] {
        guard count > 0 else { return [] }
        let area = insetIntegral(frame)
        guard area.width > 0, area.height > 0 else {
            return Array(repeating: CGRect(origin: frame.origin, size: .zero), count: count)
        }

        let (columns, rows) = gridDimensions(count: count)
        let heights = distribute(Int(area.height), into: rows)
        var result: [CGRect] = []
        result.reserveCapacity(count)

        var top = area.maxY
        var remaining = count
        for row in 0..<rows {
            let cells = min(columns, remaining)
            remaining -= cells
            let h = CGFloat(heights[row])
            let widths = distribute(Int(area.width), into: cells)
            var x = area.minX
            for w in widths {
                result.append(CGRect(x: x, y: top - h, width: CGFloat(w), height: h))
                x += CGFloat(w)
            }
            top -= h
        }
        return result
    }

    /// Splits `total` into `parts` non-negative integers summing to `total`;
    /// the first `total % parts` entries get one extra unit.
    private static func distribute(_ total: Int, into parts: Int) -> [Int] {
        let base = total / parts
        let extra = total % parts
        return (0..<parts).map { $0 < extra ? base + 1 : base }
    }
}
