import Foundation

/// Which mouse button produced a click. Core-owned; the app layer maps AppKit events to this.
public enum ClickButton: Sendable, CaseIterable, Hashable {
    case left, right, other
}

/// Modifier keys held during a click. Core-owned bits; the app layer maps
/// `NSEvent.ModifierFlags` to these. Core never imports AppKit.
public struct ClickModifiers: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let option  = ClickModifiers(rawValue: 1)
    public static let control = ClickModifiers(rawValue: 2)
    public static let shift   = ClickModifiers(rawValue: 4)
    public static let command = ClickModifiers(rawValue: 8)
}

/// What the app should do in response to a click.
///
/// Rule table (see `action(for:modifiers:)`):
/// - right button: `.showMenu`, regardless of modifiers
/// - left button with option and/or control held: `.showMenu`
/// - left button otherwise (none, shift, command, shift+command): `.tile`
/// - any other button: `.ignore`, regardless of modifiers
public enum ClickAction: Sendable, Hashable {
    case tile, showMenu, ignore

    /// Maps a click to an action per the rule table on `ClickAction`.
    public static func action(for button: ClickButton, modifiers: ClickModifiers) -> ClickAction {
        switch button {
        case .right:
            return .showMenu
        case .left:
            return modifiers.isDisjoint(with: [.option, .control]) ? .tile : .showMenu
        case .other:
            return .ignore
        }
    }
}
