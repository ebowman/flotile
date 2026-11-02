import Foundation

/// Pure helpers for interpreting Accessibility roles and error codes.
enum AXRoleClassifier {
    /// True only for ordinary document-style windows.
    static func isStandardWindow(role: String?, subrole: String?) -> Bool {
        // "AXWindow" == kAXWindowRole, "AXStandardWindow" == kAXStandardWindowSubrole
        role == "AXWindow" && subrole == "AXStandardWindow"
    }

    /// Short name for an `AXError` raw value (verified against AXError.h).
    static func describe(axErrorCode code: Int32) -> String {
        switch code {
        case 0: "success"
        case -25200: "failure"
        case -25201: "illegalArgument"
        case -25202: "invalidUIElement"
        case -25203: "invalidUIElementObserver"
        case -25204: "cannotComplete"
        case -25205: "attributeUnsupported"
        case -25206: "actionUnsupported"
        case -25207: "notificationUnsupported"
        case -25208: "notImplemented"
        case -25209: "notificationAlreadyRegistered"
        case -25210: "notificationNotRegistered"
        case -25211: "apiDisabled"
        case -25212: "noValue"
        case -25213: "parameterizedAttributeUnsupported"
        case -25214: "notEnoughPrecision"
        default: "AXError(\(code))"
        }
    }
}
