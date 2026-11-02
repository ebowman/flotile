import AppKit
import XCTest
@testable import FloTile

@MainActor
final class AccessibilityPermissionFlowTests: XCTestCase {
    func testCopyConstants() {
        XCTAssertFalse(AccessibilityCopy.alertTitle.isEmpty)
        XCTAssertFalse(AccessibilityCopy.alertBody.isEmpty)
        XCTAssertFalse(AccessibilityCopy.openSettingsButton.isEmpty)
        XCTAssertFalse(AccessibilityCopy.notNowButton.isEmpty)
        XCTAssertTrue(AccessibilityCopy.alertTitle.contains("Accessibility"))
        XCTAssertFalse(AccessibilityCopy.alertBody.contains("Privacy & Security"))
        XCTAssertTrue(AccessibilityCopy.alertBody.contains("click the icon again"))
    }

    func testSettingsURL() {
        XCTAssertEqual(
            AccessibilityCopy.settingsURLString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        XCTAssertNotNil(URL(string: AccessibilityCopy.settingsURLString))
        XCTAssertEqual(AccessibilityCopy.settingsURL.scheme, "x-apple.systempreferences")
    }

    func testDecideMapping() {
        XCTAssertEqual(AccessibilityCopy.decide(buttonResponse: .alertFirstButtonReturn), .openSettingsAndPrompt)
        XCTAssertEqual(AccessibilityCopy.decide(buttonResponse: .alertSecondButtonReturn), .dismiss)
        XCTAssertEqual(AccessibilityCopy.decide(buttonResponse: .cancel), .dismiss)
    }

    func testOpenSettingsPath() {
        var events: [String] = []
        var urls: [URL] = []
        var buttons: [String] = []
        let flow = AccessibilityPermissionFlow(
            requestTrust: { events.append("trust") },
            openURL: { url in events.append("open"); urls.append(url); return true },
            runAlert: { alert in
                buttons = alert.buttons.map(\.title)
                return .alertFirstButtonReturn
            })
        flow.present()
        XCTAssertEqual(events, ["trust", "open"])
        XCTAssertEqual(urls, [AccessibilityCopy.settingsURL])
        XCTAssertEqual(buttons, ["Open System Settings", "Not Now"])
        XCTAssertEqual(flow.lastDecision, .openSettingsAndPrompt)
    }

    func testNotNowPath() {
        var events: [String] = []
        let flow = AccessibilityPermissionFlow(
            requestTrust: { events.append("trust") },
            openURL: { _ in events.append("open"); return true },
            runAlert: { _ in .alertSecondButtonReturn })
        flow.present()
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(flow.lastDecision, .dismiss)
    }
}
