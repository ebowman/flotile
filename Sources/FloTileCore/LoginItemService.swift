import Foundation

/// Abstraction over the system "Open at Login" registration.
public protocol LoginItemService: Sendable {
    /// Whether the app is currently registered to open at login.
    /// Implementations must read this fresh from the system on every call and never cache it.
    var isEnabled: Bool { get }

    /// Registers or unregisters the app. Throws on failure.
    func setEnabled(_ enabled: Bool) throws
}

/// A login-item failure carrying a ready-to-display, user-facing message.
public struct LoginItemError: Error, Equatable, Sendable {
    public let message: String
    public init(message: String) { self.message = message }
}

public extension LoginItemError {
    /// Error domains used by ServiceManagement. Codes are only meaningful within these
    /// domains, so domain and code are always matched together (e.g. code 11 in
    /// NSPOSIXErrorDomain is unrelated to a user denial).
    static let serviceManagementDomains: Set<String> = [
        "SMAppServiceErrorDomain", "com.apple.ServiceManagement", "SMErrorDomainFramework",
    ]
    /// kSMErrorLaunchDeniedByUser
    static let launchDeniedByUserCode = 11
    /// kSMErrorAlreadyRegistered
    static let alreadyRegisteredCode = 12
    /// kSMErrorInvalidSignature
    static let invalidSignatureCode = 3

    /// Maps an error domain/code to a user-facing message. Never includes raw error descriptions.
    static func userMessage(domain: String, code: Int, whileEnabling: Bool, appName: String) -> String {
        if serviceManagementDomains.contains(domain) {
            switch code {
            case launchDeniedByUserCode:
                return "Open at Login was denied. Enable it for \(appName) in System Settings > General > Login Items."
            case alreadyRegisteredCode:
                return "\(appName) is already set to open at login."
            case invalidSignatureCode:
                return "Open at Login needs a properly signed copy of \(appName). Move it to /Applications and try again."
            default:
                break
            }
        }
        let verb = whileEnabling ? "enable" : "disable"
        return "Couldn't \(verb) Open at Login. Try again, or set it in System Settings > General > Login Items."
    }
}
