import AppKit
import SwiftUI
import XCTest
import FloTileCore
@testable import FloTile

@MainActor
final class SettingsViewLayoutTests: XCTestCase {
    func testSettingsViewHasRealFittingSize() {
        let model = SettingsModel(loginItems: FakeLoginItemService())
        let controller = NSHostingController(rootView: SettingsView(model: model))
        controller.view.layoutSubtreeIfNeeded()
        let size = controller.view.fittingSize
        XCTAssertGreaterThanOrEqual(size.height, 40, "fittingSize was \(size)")
        XCTAssertGreaterThanOrEqual(size.width, 200, "fittingSize was \(size)")
    }

    func testSharedSettingsWindowIsSizedToItsContent() throws {
        SettingsWindowController.showShared(model: SettingsModel(loginItems: FakeLoginItemService()))
        let window = try XCTUnwrap(SettingsWindowController.sharedWindowForTesting)
        window.layoutIfNeeded()
        let content = try XCTUnwrap(window.contentView)
        let fitting = try XCTUnwrap(window.contentViewController).view.fittingSize.height
        XCTAssertGreaterThanOrEqual(content.frame.height, 40, "content height \(content.frame.height)")
        XCTAssertGreaterThanOrEqual(content.frame.height, fitting - 1, "content \(content.frame.height) vs fitting \(fitting)")
        XCTAssertFalse(content.subviews.isEmpty)
    }
}
