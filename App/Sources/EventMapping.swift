import AppKit
import FloTileCore

/// Pure mapping from AppKit event data to Core click types.
enum EventMapping {
    static func clickButton(for eventType: NSEvent.EventType) -> ClickButton {
        switch eventType {
        case .leftMouseUp, .leftMouseDown: return .left
        case .rightMouseUp, .rightMouseDown: return .right
        default: return .other
        }
    }

    static func clickModifiers(from flags: NSEvent.ModifierFlags) -> ClickModifiers {
        var result: ClickModifiers = []
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.command) { result.insert(.command) }
        return result
    }
}
