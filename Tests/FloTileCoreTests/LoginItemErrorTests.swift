import XCTest
@testable import FloTileCore

final class LoginItemErrorTests: XCTestCase {
    private let domains = ["SMAppServiceErrorDomain", "com.apple.ServiceManagement", "SMErrorDomainFramework"]
    private let generic = "Couldn't enable Open at Login. Try again, or set it in System Settings > General > Login Items."

    func testMappedCodesInAllDomains() {
        for d in domains {
            XCTAssertEqual(LoginItemError.userMessage(domain: d, code: 11, whileEnabling: true, appName: "App"),
                           "Open at Login was denied. Enable it for App in System Settings > General > Login Items.", d)
            XCTAssertEqual(LoginItemError.userMessage(domain: d, code: 12, whileEnabling: true, appName: "App"),
                           "App is already set to open at login.", d)
            XCTAssertEqual(LoginItemError.userMessage(domain: d, code: 3, whileEnabling: true, appName: "App"),
                           "Open at Login needs a properly signed copy of App. Move it to /Applications and try again.", d)
        }
    }

    func testCode11InPOSIXDomainIsGeneric() {
        XCTAssertEqual(LoginItemError.userMessage(domain: "NSPOSIXErrorDomain", code: 11, whileEnabling: true, appName: "App"), generic)
    }

    func testUnknownCodeInSMDomainIsGeneric() {
        for d in domains {
            XCTAssertEqual(LoginItemError.userMessage(domain: d, code: 999, whileEnabling: true, appName: "App"), generic)
        }
    }

    func testGenericDiffersByDirection() {
        let on = LoginItemError.userMessage(domain: "X", code: 1, whileEnabling: true, appName: "App")
        let off = LoginItemError.userMessage(domain: "X", code: 1, whileEnabling: false, appName: "App")
        XCTAssertNotEqual(on, off)
        XCTAssertTrue(off.hasPrefix("Couldn't disable Open at Login."))
    }

    func testAppNameInterpolated() {
        let m = LoginItemError.userMessage(domain: domains[0], code: 12, whileEnabling: true, appName: "Zorp")
        XCTAssertTrue(m.contains("Zorp"))
    }

    func testNoRawErrorText() {
        for d in domains + ["NSPOSIXErrorDomain"] {
            for c in [3, 11, 12, 0, 77] {
                let m = LoginItemError.userMessage(domain: d, code: c, whileEnabling: false, appName: "App")
                XCTAssertFalse(m.contains("Error Domain"))
                XCTAssertFalse(m.contains("Code="))
            }
        }
    }
}
