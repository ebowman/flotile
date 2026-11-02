import XCTest
import CoreGraphics
@testable import FloTileCore

final class TilingLayoutTests: XCTestCase {

    func testGridDimensionsTable() {
        let expected: [(Int, Int, Int)] = [
            (1, 1, 1), (2, 2, 1), (3, 2, 2), (4, 2, 2), (5, 3, 2), (6, 3, 2),
            (7, 3, 3), (8, 3, 3), (9, 3, 3), (10, 4, 3), (11, 4, 3), (12, 4, 3)
        ]
        for (n, c, r) in expected {
            let d = TilingLayout.gridDimensions(count: n)
            XCTAssertEqual(d.columns, c, "columns for \(n)")
            XCTAssertEqual(d.rows, r, "rows for \(n)")
        }
        for n in [0, -1] {
            let d = TilingLayout.gridDimensions(count: n)
            XCTAssertEqual(d.columns, 0)
            XCTAssertEqual(d.rows, 0)
        }
    }

    func testSingleWindowFillsFrame() {
        let f = CGRect(x: 0, y: 25, width: 1440, height: 877)
        XCTAssertEqual(TilingLayout.frames(count: 1, in: f), [f])
    }

    func testExactTilingProperty() {
        let inputs = [
            CGRect(x: 0, y: 25, width: 1440, height: 877),
            CGRect(x: -2560, y: 0, width: 2560, height: 1415),
            CGRect(x: 0, y: 0, width: 1512, height: 944)
        ]
        for frame in inputs {
            for n in 1...25 {
                let fs = TilingLayout.frames(count: n, in: frame)
                XCTAssertEqual(fs.count, n)
                var total: CGFloat = 0
                for (i, a) in fs.enumerated() {
                    XCTAssertTrue(frame.contains(a), "n=\(n) i=\(i) outside")
                    for v in [a.minX, a.minY, a.maxX, a.maxY] {
                        XCTAssertEqual(v, v.rounded(), "non-integral edge")
                    }
                    total += a.width * a.height
                    for b in fs[(i + 1)...] {
                        let inter = a.intersection(b)
                        XCTAssertFalse(!inter.isNull && inter.width > 0 && inter.height > 0,
                                       "overlap n=\(n)")
                    }
                }
                XCTAssertEqual(total, frame.width * frame.height, "area n=\(n)")
            }
        }
    }

    func testLastRowStretch() {
        let f = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let three = TilingLayout.frames(count: 3, in: f)
        XCTAssertEqual(three[0].minY, three[1].minY)
        XCTAssertEqual(three[0].maxY, 800)
        XCTAssertEqual(three[0].width, 500)
        XCTAssertEqual(three[2], CGRect(x: 0, y: 0, width: 1000, height: 400))

        let five = TilingLayout.frames(count: 5, in: f)
        XCTAssertEqual(five[2].maxY, 800)
        XCTAssertEqual(five[3].maxY, 400)
        XCTAssertEqual(five[4].maxY, 400)
        XCTAssertEqual(five[3].width, 500)
        XCTAssertEqual(five[4].width, 500)
        XCTAssertEqual(five[3].minX, 0)
        XCTAssertEqual(five[4].minX, 500)
    }

    func testReadingOrder() {
        let f = CGRect(x: 10, y: 20, width: 1001, height: 703)
        for n in 1...12 {
            let fs = TilingLayout.frames(count: n, in: f)
            let top = fs.map(\.maxY).max()!
            XCTAssertEqual(fs[0].maxY, top)
            let topRow = fs.filter { $0.maxY == top }
            XCTAssertEqual(fs[0].minX, topRow.map(\.minX).min())
            if n >= 2 {
                XCTAssertTrue(fs[1].minX > fs[0].minX || fs[1].maxY < fs[0].maxY)
            }
        }
        let two = TilingLayout.frames(count: 2, in: f)
        XCTAssertGreaterThan(two[1].minX, two[0].minX)
    }

    func testDegenerateInputs() {
        let f = CGRect(x: 0, y: 0, width: 100, height: 100)
        XCTAssertEqual(TilingLayout.frames(count: 0, in: f), [])
        XCTAssertEqual(TilingLayout.frames(count: -2, in: f), [])

        let zero = CGRect(x: 5, y: 7, width: 0, height: 0)
        let z = TilingLayout.frames(count: 3, in: zero)
        XCTAssertEqual(z, Array(repeating: CGRect(x: 5, y: 7, width: 0, height: 0), count: 3))

        let neg = CGRect(x: 5, y: 7, width: -10, height: 50)
        XCTAssertEqual(TilingLayout.frames(count: 2, in: neg).count, 2)
        XCTAssertTrue(TilingLayout.frames(count: 2, in: neg).allSatisfy { $0.size == .zero })

        // Collapses when normalized inward.
        let sliver = CGRect(x: 0.2, y: 0, width: 0.5, height: 10)
        XCTAssertTrue(TilingLayout.frames(count: 2, in: sliver).allSatisfy { $0.size == .zero })
    }

    func testNonIntegralFrameIsNormalizedInward() {
        let f = CGRect(x: 0.3, y: 10.6, width: 999.5, height: 500.2)
        let fs = TilingLayout.frames(count: 7, in: f)
        XCTAssertEqual(fs.count, 7)
        for a in fs {
            XCTAssertTrue(f.contains(a))
            for v in [a.minX, a.minY, a.maxX, a.maxY] {
                XCTAssertEqual(v, v.rounded())
            }
        }
    }

    func testNonFiniteFrameIsDegenerate() {
        let f = CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 10)
        XCTAssertTrue(TilingLayout.frames(count: 2, in: f).allSatisfy { $0.size == .zero })
    }
}
