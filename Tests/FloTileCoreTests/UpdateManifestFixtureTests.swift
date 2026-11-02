import Foundation
import Testing
@testable import FloTileCore

/// Decodes a manifest actually produced by `scripts/publish-release.sh --dry-run`.
struct UpdateManifestFixtureTests {
    @Test func decodesDryRunGeneratedAppcast() throws {
        let url = try #require(Bundle.module.url(forResource: "appcast-sample", withExtension: "json"))
        let manifest = try JSONDecoder().decode(UpdateManifest.self, from: Data(contentsOf: url))
        #expect(manifest.latestVersion == "0.1.0")
        #expect(manifest.notes == "https://github.com/ebowman/flotile/releases/tag/v0.1.0")
        #expect(manifest.dmgURL == "https://github.com/ebowman/flotile/releases/download/v0.1.0/FloTile-0.1.0.dmg")
        #expect(manifest.dmgSHA256.count == 64)
    }
}
