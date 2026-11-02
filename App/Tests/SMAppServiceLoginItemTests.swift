import XCTest
import FloTileCore
@testable import FloTile

final class SMAppServiceLoginItemTests: XCTestCase {
    func testIsEnabledReturnsWithoutThrowing() {
        _ = SMAppServiceLoginItem().isEnabled
    }

    /// From the test host (Debug-signed, not in /Applications) register/unregister may succeed or
    /// fail; either way the error must be a friendly LoginItemError. Any success is undone
    /// immediately so no login item is left behind.
    func testSetEnabledSucceedsOrThrowsFriendlyError() {
        let item = SMAppServiceLoginItem()
        for wanted in [true, false] {
            do {
                try item.setEnabled(wanted)
                if wanted { try? item.setEnabled(false) }
            } catch let error as LoginItemError {
                XCTAssertFalse(error.message.contains("Error Domain"), error.message)
                XCTAssertFalse(error.message.contains("Code="), error.message)
            } catch {
                XCTFail("Unexpected non-LoginItemError: \(error)")
            }
        }
        try? item.setEnabled(false)
    }
}
