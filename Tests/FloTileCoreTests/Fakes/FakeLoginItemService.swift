import Foundation
@testable import FloTileCore

final class FakeLoginItemService: LoginItemService, @unchecked Sendable {
    var enabled: Bool
    var errorToThrow: Error?
    var setCalls: [Bool] = []
    var isEnabledReadCount = 0

    init(enabled: Bool = false) { self.enabled = enabled }

    var isEnabled: Bool {
        isEnabledReadCount += 1
        return enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        setCalls.append(enabled)
        if let errorToThrow { throw errorToThrow }
        self.enabled = enabled
    }
}
