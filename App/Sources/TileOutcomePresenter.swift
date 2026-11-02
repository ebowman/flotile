import FloTileCore

/// Decides what to surface for a `TileOutcome`: silence, a log line, or the permission flow.
@MainActor
struct TileOutcomePresenter {
    let log: (String) -> Void
    let onAccessibilityNotGranted: () -> Void

    init(log: @escaping (String) -> Void, onAccessibilityNotGranted: @escaping () -> Void) {
        self.log = log
        self.onAccessibilityNotGranted = onAccessibilityNotGranted
    }

    static func isSilent(_ outcome: TileOutcome) -> Bool {
        switch outcome {
        case .tiled, .noWindows, .noFrontmostApp: return true
        case .partial, .failed, .accessibilityNotGranted: return false
        }
    }

    func present(_ outcome: TileOutcome) {
        switch outcome {
        case .tiled, .noWindows, .noFrontmostApp:
            break
        case let .partial(succeeded, failed):
            log("Tiled \(succeeded) window(s); \(failed) could not be moved")
        case let .failed(reason):
            log("Tiling failed: \(reason)")
        case .accessibilityNotGranted:
            onAccessibilityNotGranted()
        }
    }
}
