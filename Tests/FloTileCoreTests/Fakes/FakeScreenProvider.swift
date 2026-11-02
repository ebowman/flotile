import Foundation
@testable import FloTileCore

final class FakeScreenProvider: ScreenProvider, @unchecked Sendable {
    var screensToReturn: [ScreenInfo]
    init(_ screens: [ScreenInfo] = []) { self.screensToReturn = screens }
    func screens() -> [ScreenInfo] { screensToReturn }
}
