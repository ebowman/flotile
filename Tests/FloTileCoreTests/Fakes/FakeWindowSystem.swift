import Foundation
import CoreGraphics
@testable import FloTileCore

struct FakeWindowSystemError: Error, CustomStringConvertible {
    let description: String
}

final class FakeWindowSystem: WindowSystem, @unchecked Sendable {
    var isTrusted = true
    var frontmostPID: pid_t? = 100
    var windowsByPID: [pid_t: [WindowInfo]] = [:]
    var windowsError: Error?
    var failingWindowIDs: Set<WindowID> = []
    private(set) var setFrameCalls: [(WindowID, CGRect)] = []
    private(set) var windowsCallCount = 0
    private(set) var frontmostCallCount = 0

    func frontmostApplicationPID() -> pid_t? {
        frontmostCallCount += 1
        return frontmostPID
    }

    func windows(forApplication pid: pid_t) throws -> [WindowInfo] {
        windowsCallCount += 1
        if let windowsError { throw windowsError }
        return windowsByPID[pid] ?? []
    }

    func setFrame(_ frame: CGRect, of window: WindowID) throws {
        setFrameCalls.append((window, frame))
        if failingWindowIDs.contains(window) {
            throw FakeWindowSystemError(description: "setFrame failed for \(window.rawValue)")
        }
    }
}
