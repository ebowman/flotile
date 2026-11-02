import AppKit
import os

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let logger = Logger(subsystem: "ie.boboco.FloTile", category: "app")
    private static var delegate: AppDelegate?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        Self.delegate = delegate
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.logger.info("FloTile launched")
    }
}
