import FloTileCore
import Foundation

/// Pure text builders for the updater's alerts (no AppKit; unit tested).
enum UpdateCopy {
    static let appName = "FlöTile"

    static let upToDateTitle = "You're up to date"
    static let errorTitle = "Couldn't Check for Updates"
    static let installButton = "Install and Relaunch"
    static let cancelButton = "Cancel"
    static let okButton = "OK"

    static func upToDateBody(currentVersion: String) -> String {
        "\(appName) \(currentVersion) is the latest version."
    }

    static func updateAvailableTitle(latestVersion: String) -> String {
        "\(appName) \(latestVersion) is available"
    }

    static func updateAvailableBody(currentVersion: String, notes: String) -> String {
        var info = "You have \(currentVersion)."
        if !notes.isEmpty {
            info += "\n\n\(notes)"
        }
        return info
    }

    static func fetchErrorMessage(_ error: Error) -> String {
        guard let fetchError = error as? UpdateFetchError else {
            return error.localizedDescription
        }
        switch fetchError {
        case .invalidManifestURL:
            return "The update manifest URL is invalid."
        case .network(let message):
            return "Network error: \(message)"
        case .badResponse(let status):
            return "Update server returned an unexpected response (status \(status))."
        case .malformedManifest:
            return "The update manifest could not be read."
        case .downloadFailed(let message):
            return "Download failed: \(message)"
        case .downloadBadResponse(let status):
            return "Update server returned an unexpected response while downloading (status \(status))."
        }
    }

    static func downloadErrorMessage(_ error: Error) -> String {
        "Could not download the update: \(fetchErrorMessage(error))"
    }

    static func verificationErrorMessage(_ error: Error) -> String {
        "The downloaded update could not be verified and was discarded. \(appName) has not been changed. (\(describe(error)))"
    }

    static func launchErrorMessage(_ error: Error) -> String {
        "Could not start the update installer. \(appName) has not been changed. (\(describe(error)))"
    }

    private static func describe(_ error: Error) -> String {
        if let v = error as? UpdateVerificationError {
            switch v {
            case .invalidDMGURL(let s): return "Invalid update URL: \(s)"
            case .insecureDMGURL(let s): return "Update URL is not a trusted HTTPS location: \(s)"
            case .digestMismatch: return "The SHA-256 checksum did not match."
            case .notarizationFailed: return "The update is not notarized."
            case .unreadableFile(let s): return "The downloaded file could not be read: \(s)"
            }
        }
        if let s = error as? UpdateSwapError {
            switch s {
            case .scriptWriteFailed(let m), .scriptPermissionsFailed(let m), .launchFailed(let m): return m
            }
        }
        return error.localizedDescription
    }
}
