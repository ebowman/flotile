import Foundation

/// Pure text builders for the About panel (no AppKit; unit tested).
enum AboutCopy {
    static let appName = "FlöTile"
    static let tagline = "Window tiling from the menu bar."
    static let license = "MIT License"
    static let repositoryURL = URL(string: "https://github.com/ebowman/flotile")!

    static func versionLine(shortVersion: String, build: String) -> String {
        if build.isEmpty || build == shortVersion {
            return "Version \(shortVersion)"
        }
        return "Version \(shortVersion) (\(build))"
    }

    static func credits() -> String {
        [tagline, license, repositoryURL.absoluteString].joined(separator: "\n")
    }
}
