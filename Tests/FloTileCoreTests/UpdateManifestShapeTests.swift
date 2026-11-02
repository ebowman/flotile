import Foundation
import Testing
@testable import FloTileCore

/// Pins the exact JSON shape the release script emits as `appcast.json`.
struct UpdateManifestShapeTests {
    private static let sha = String(repeating: "ab12", count: 16)

    private static var json: String {
        "{\"latestVersion\":\"0.1.0\",\"notes\":\"https://github.com/ebowman/flotile/releases/tag/v0.1.0\",\"dmgURL\":\"https://github.com/ebowman/flotile/releases/download/v0.1.0/FloTile-0.1.0.dmg\",\"dmgSHA256\":\"\(sha)\"}"
    }

    @Test func decodesReleaseScriptJSON() throws {
        let manifest = try JSONDecoder().decode(UpdateManifest.self, from: Data(Self.json.utf8))
        #expect(Self.sha.count == 64)
        #expect(manifest.latestVersion == "0.1.0")
        #expect(manifest.notes == "https://github.com/ebowman/flotile/releases/tag/v0.1.0")
        #expect(manifest.dmgURL == "https://github.com/ebowman/flotile/releases/download/v0.1.0/FloTile-0.1.0.dmg")
        #expect(manifest.dmgSHA256 == Self.sha)
    }

    @Test func roundTripsThroughEncodeAndDecode() throws {
        let decoded = try JSONDecoder().decode(UpdateManifest.self, from: Data(Self.json.utf8))
        let encoded = try JSONEncoder().encode(decoded)
        let again = try JSONDecoder().decode(UpdateManifest.self, from: encoded)
        #expect(again == decoded)
    }
}
