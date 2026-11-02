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

    /// Whether the outcome came from a tiling click or from restoring a snapshot (affects log wording).
    enum Context { case tiling, restoring }

    static func isSilent(_ outcome: TileOutcome) -> Bool {
        switch outcome {
        case .tiled, .restored, .noWindows, .noFrontmostApp, .nothingToUndo: return true
        case .partial, .failed, .accessibilityNotGranted: return false
        }
    }

    func present(_ outcome: TileOutcome, context: Context = .tiling) {
        switch outcome {
        case .tiled, .restored, .noWindows, .noFrontmostApp, .nothingToUndo:
            break
        case let .partial(succeeded, failed):
            let verb = context == .restoring ? "Restored" : "Tiled"
            log("\(verb) \(succeeded) window(s); \(failed) could not be moved")
        case let .failed(reason):
            log("Tiling failed: \(reason)")
        case .accessibilityNotGranted:
            onAccessibilityNotGranted()
        }
    }
}
