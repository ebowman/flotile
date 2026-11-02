import Foundation
import CoreGraphics

/// Orchestrates tiling of the frontmost application's windows on one screen.
public struct TileCoordinator: Sendable {
    private let windowSystem: any WindowSystem
    private let screenProvider: any ScreenProvider

    /// Creates a coordinator. `screenProvider` is stored for the app layer /
    /// future use; `tile(on:)` does not call it.
    public init(windowSystem: any WindowSystem, screenProvider: any ScreenProvider) {
        self.windowSystem = windowSystem
        self.screenProvider = screenProvider
    }

    /// Tiles the frontmost app's eligible windows into a grid on `screen.visibleFrame`.
    public func tile(on screen: ScreenInfo) -> TileOutcome {
        guard windowSystem.isTrusted else { return .accessibilityNotGranted }
        guard let pid = windowSystem.frontmostApplicationPID() else { return .noFrontmostApp }

        let all: [WindowInfo]
        do {
            all = try windowSystem.windows(forApplication: pid)
        } catch {
            return .failed(reason: String(describing: error))
        }

        let eligible = WindowSelector.readingOrder(WindowSelector.eligibleWindows(all, on: screen))
        if eligible.isEmpty { return .noWindows }

        let frames = TilingLayout.frames(count: eligible.count, in: screen.visibleFrame)
        var succeeded = 0
        var failed = 0
        for (window, frame) in zip(eligible, frames) {
            do {
                try windowSystem.setFrame(frame, of: window.id)
                succeeded += 1
            } catch {
                failed += 1
            }
        }
        return failed == 0 ? .tiled(count: succeeded) : .partial(succeeded: succeeded, failed: failed)
    }
}
