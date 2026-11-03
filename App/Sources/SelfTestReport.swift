import CoreGraphics
import Foundation

/// Builds the one-line JSON report printed by the DEBUG `--self-test-tile` mode.
/// Pure so it can be unit tested; keys are sorted for stable output.
enum SelfTestReport {
    static func json(app: String, outcome: String, screen: CGRect, frames: [CGRect],
                     ignored: [CGRect]) -> String {
        let object: [String: Any] = [
            "app": app,
            "outcome": outcome,
            "screen": ["x": number(screen.minX), "y": number(screen.minY),
                       "w": number(screen.width), "h": number(screen.height)],
            "frames": frames.map(array),
            "ignored": ignored.map(array),
        ]
        return serialize(object)
    }

    /// Two-phase report for `--self-test-tile-undo`: the first and second click.
    static func undoJSON(first: (outcome: String, frames: [CGRect]),
                         second: (outcome: String, frames: [CGRect]),
                         screen: CGRect, app: String) -> String {
        func phase(_ p: (outcome: String, frames: [CGRect])) -> [String: Any] {
            ["outcome": p.outcome, "frames": p.frames.map(array)]
        }
        let object: [String: Any] = [
            "app": app,
            "first": phase(first),
            "second": phase(second),
            "screen": ["x": number(screen.minX), "y": number(screen.minY),
                       "w": number(screen.width), "h": number(screen.height)],
        ]
        return serialize(object)
    }

    static func errorJSON(_ description: String) -> String {
        serialize(["error": description])
    }

    private static func array(_ r: CGRect) -> [NSNumber] {
        [number(r.minX), number(r.minY), number(r.width), number(r.height)]
    }

    /// Integral values become integers so the output has no "1440.0".
    private static func number(_ v: CGFloat) -> NSNumber {
        let d = Double(v)
        if d.rounded() == d, abs(d) < 1e15 { return NSNumber(value: Int(d)) }
        return NSNumber(value: d)
    }

    private static func serialize(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return "{\"error\":\"report serialization failed\"}"
        }
        return text
    }
}
