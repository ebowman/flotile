import AppKit
import ApplicationServices
import FloTileCore

enum AXWindowSystemError: Error, Equatable, CustomStringConvertible {
    case attributeFailed(attribute: String, code: Int32)
    case unexpectedValue(attribute: String)
    case unknownWindow(Int)

    var description: String {
        switch self {
        case let .attributeFailed(attribute, code):
            "Accessibility call for \(attribute) failed: \(AXRoleClassifier.describe(axErrorCode: code))"
        case let .unexpectedValue(attribute):
            "Accessibility returned an unexpected value for \(attribute)"
        case let .unknownWindow(id):
            "Unknown window handle \(id)"
        }
    }
}

/// `WindowSystem` backed by the Accessibility API.
///
/// Safety: the class is `@MainActor`, so all `AXUIElement` references and the
/// handle table are only touched on the main actor. The `WindowSystem`
/// protocol requirements are nonisolated (and `Sendable`), so they are
/// satisfied by `nonisolated` wrappers that use `MainActor.assumeIsolated`.
/// That is safe because `TileCoordinator` is only ever invoked from the main
/// thread; a violation traps rather than racing.
///
/// Sandbox note: FloTile ships sandboxed (com.apple.security.app-sandbox) for
/// the Mac App Store. The Accessibility API (AXUIElement read/write on other
/// apps' windows) is permitted inside the sandbox once the user grants FloTile
/// in System Settings > Privacy & Security > Accessibility (AXIsProcessTrusted);
/// no entitlement or temporary exception is needed. Without that grant every AX
/// call fails with apiDisabled/cannotComplete, which is why TileCoordinator
/// checks isTrusted first and the app prompts via requestTrust().
@MainActor
final class AXWindowSystem: WindowSystem, @unchecked Sendable {
    private var elements: [WindowID: AXUIElement] = [:]
    private var nextHandle = 0

    init() {}

    nonisolated var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system Accessibility prompt. Not part of the Core protocol.
    func requestTrust() {
        // Literal value of kAXTrustedCheckOptionPrompt (the imported global var is not
        // concurrency-safe under Swift 6).
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    nonisolated func frontmostApplicationPID() -> pid_t? {
        MainActor.assumeIsolated {
            guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
                  pid != ProcessInfo.processInfo.processIdentifier else { return nil }
            return pid
        }
    }

    nonisolated func windows(forApplication pid: pid_t) throws -> [WindowInfo] {
        try MainActor.assumeIsolated { try self.loadWindows(pid: pid) }
    }

    nonisolated func setFrame(_ frame: CGRect, of window: WindowID) throws {
        try MainActor.assumeIsolated { try self.applyFrame(frame, to: window) }
    }

    // MARK: - Implementation

    private func loadWindows(pid: pid_t) throws -> [WindowInfo] {
        elements.removeAll()
        let app = AXUIElementCreateApplication(pid)
        var raw: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &raw)
        guard status == .success else {
            throw AXWindowSystemError.attributeFailed(attribute: "AXWindows", code: status.rawValue)
        }
        guard let list = raw as? [AXUIElement] else {
            throw AXWindowSystemError.unexpectedValue(attribute: "AXWindows")
        }
        let space = CoordinateSpace(primaryScreenHeight: NSScreen.screens.first?.frame.height ?? 0)
        var result: [WindowInfo] = []
        for (index, element) in list.enumerated() {
            guard let origin = Self.point(element, kAXPositionAttribute),
                  let size = Self.size(element, kAXSizeAttribute) else { continue }
            let role = Self.string(element, kAXRoleAttribute)
            let subrole = Self.string(element, kAXSubroleAttribute)
            let minimized = Self.bool(element, kAXMinimizedAttribute) ?? false
            nextHandle += 1
            let id = WindowID(nextHandle)
            elements[id] = element
            result.append(WindowInfo(
                id: id,
                frame: space.appKitRect(fromAXOrigin: origin, size: size),
                isMinimized: minimized,
                isStandard: AXRoleClassifier.isStandardWindow(role: role, subrole: subrole),
                discoveryIndex: index))
        }
        return result
    }

    private func applyFrame(_ frame: CGRect, to window: WindowID) throws {
        guard let element = elements[window] else {
            throw AXWindowSystemError.unknownWindow(window.rawValue)
        }
        let space = CoordinateSpace(primaryScreenHeight: NSScreen.screens.first?.frame.height ?? 0)
        let origin = space.axOrigin(fromAppKit: frame)
        // Many apps clamp the size against the current position, so apply
        // size, then position, then size again so the result converges.
        try Self.setSize(element, frame.size)
        try Self.setPosition(element, origin)
        try Self.setSize(element, frame.size)
    }

    private static func setSize(_ element: AXUIElement, _ size: CGSize) throws {
        var value = size
        try store(element, kAXSizeAttribute, AXValueCreate(.cgSize, &value))
    }

    private static func setPosition(_ element: AXUIElement, _ point: CGPoint) throws {
        var value = point
        try store(element, kAXPositionAttribute, AXValueCreate(.cgPoint, &value))
    }

    private static func store(_ element: AXUIElement, _ attribute: String, _ axValue: AXValue?) throws {
        guard let axValue else { throw AXWindowSystemError.unexpectedValue(attribute: attribute) }
        let status = AXUIElementSetAttributeValue(element, attribute as CFString, axValue)
        guard status == .success else {
            throw AXWindowSystemError.attributeFailed(attribute: attribute, code: status.rawValue)
        }
    }

    private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success else { return nil }
        return raw
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        copy(element, attribute) as? String
    }

    private static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        (copy(element, attribute) as? NSNumber)?.boolValue
    }

    private static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let raw = copy(element, attribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var value = CGPoint.zero
        return AXValueGetValue(raw as! AXValue, .cgPoint, &value) ? value : nil
    }

    private static func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let raw = copy(element, attribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var value = CGSize.zero
        return AXValueGetValue(raw as! AXValue, .cgSize, &value) ? value : nil
    }
}
