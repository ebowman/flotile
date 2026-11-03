import AppKit
import XCTest
@testable import FloTile

@MainActor
final class AboutPanelPresenterTests: XCTestCase {
    func testOptionsNameAndCredits() throws {
        let options = AboutPanelPresenter.options(bundle: Bundle(for: AboutPanelPresenterTests.self))
        XCTAssertEqual(options[.applicationName] as? String, "FlöTile")
        let credits = try XCTUnwrap(options[.credits] as? NSAttributedString)
        XCTAssertGreaterThan(credits.length, 0)
        XCTAssertTrue(credits.string.contains("MIT License"))
    }

    func testCreditsLinkOnRepositoryURL() throws {
        let options = AboutPanelPresenter.options(bundle: Bundle(for: AboutPanelPresenterTests.self))
        let credits = try XCTUnwrap(options[.credits] as? NSAttributedString)
        let range = (credits.string as NSString).range(of: AboutCopy.repositoryURL.absoluteString, options: .backwards)
        XCTAssertNotEqual(range.location, NSNotFound)
        XCTAssertEqual(range.location + range.length, credits.length)
        let link = credits.attribute(.link, at: range.location, effectiveRange: nil) as? URL
        XCTAssertEqual(link, AboutCopy.repositoryURL)
    }

    func testVersionKeysAreSplit() {
        let options = AboutPanelPresenter.options(bundle: Bundle(for: AboutPanelPresenterTests.self))
        XCTAssertNotNil(options[.applicationVersion] as? String)
        XCTAssertNotNil(options[.version] as? String)
    }

    func testHostBundleCopyright() throws {
        try XCTSkipUnless(Bundle.main.bundleIdentifier == "ie.boboco.FloTile", "not hosted by the FloTile app")
        let copyright = Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
        XCTAssertTrue(try XCTUnwrap(copyright).contains("2026 Eric Bowman"))
    }
}
