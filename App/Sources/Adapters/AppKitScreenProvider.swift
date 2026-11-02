import AppKit
import FloTileCore

/// `ScreenProvider` backed by `NSScreen`. Stateless, hence trivially Sendable.
struct AppKitScreenProvider: ScreenProvider {
    init() {}

    func screens() -> [ScreenInfo] {
        // NSScreen is main-thread API; the coordinator only runs on the main thread.
        MainActor.assumeIsolated {
            NSScreen.screens.map(ScreenInfo.init(nsScreen:))
        }
    }

    /// Semantics #1: the status button's screen, else the screen containing the
    /// mouse, else the main screen.
    @MainActor
    static func targetScreen(forStatusButton button: NSStatusBarButton?) -> ScreenInfo? {
        if let screen = button?.window?.screen {
            return ScreenInfo(nsScreen: screen)
        }
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) {
            return ScreenInfo(nsScreen: screen)
        }
        return NSScreen.main.map(ScreenInfo.init(nsScreen:))
    }
}

extension ScreenInfo {
    /// Frames are already in AppKit coordinates and are passed through unchanged.
    @MainActor
    init(nsScreen screen: NSScreen) {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
        self.init(id: ScreenID(Int(number)), frame: screen.frame, visibleFrame: screen.visibleFrame)
    }
}
