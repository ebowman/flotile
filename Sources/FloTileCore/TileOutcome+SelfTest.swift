import Foundation

public extension TileOutcome {
    /// Stable, machine-readable label used by the DEBUG `--self-test-tile` mode.
    var selfTestLabel: String {
        switch self {
        case .accessibilityNotGranted: return "accessibilityNotGranted"
        case .noFrontmostApp: return "noFrontmostApp"
        case .noWindows: return "noWindows"
        case .tiled(let count): return "tiled:\(count)"
        case .partial(let succeeded, let failed): return "partial:\(succeeded)/\(failed)"
        case .restored(let count): return "restored:\(count)"
        case .failed(let reason): return "failed:\(reason)"
        }
    }
}
