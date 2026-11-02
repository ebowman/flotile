# FlöTile

![CI](https://github.com/ebowman/flotile/actions/workflows/ci.yml/badge.svg)

FlöTile is a macOS menu bar app that tiles the front app's windows into a tidy grid.

## What it does

A plain click on the FlöTile menu bar icon tiles every standard window of the frontmost app on the display whose menu bar you clicked into a uniform grid that fills that display. A second plain click restores the previous layout, but only if the same app is still frontmost on the same display, the same windows exist and none has moved or resized since the tiling; otherwise the click tiles again. Undo is single level.

Option-click, right-click or control-click opens a menu with these items, in order:

- **Undo Tiling** (enabled only when an undo is currently valid)
- **Settings…** (one toggle: Open at Login)
- **Check for Updates…**
- **Quit FlöTile**

## Install

Requires macOS 14 or later.

1. Download `FloTile-<version>.dmg` from the [Releases page](https://github.com/ebowman/flotile/releases).
2. Open the DMG and drag FlöTile to Applications.
3. Launch it and click the menu bar icon. The first click prompts for the Accessibility permission. Grant it in the pane that the "Open System Settings" button opens (on macOS 27 the pane is titled "Device Control and Data Access").

The app is Developer ID signed and notarized, so Gatekeeper opens it without warnings.

## Why it isn't on the Mac App Store

FlöTile moves and resizes other apps' windows, which requires the Accessibility API. Sandboxed apps cannot drive other apps through Accessibility (Apple DTS confirms this in [this forum thread](https://developer.apple.com/forums/thread/805556)), and the Mac App Store requires the sandbox. So FlöTile is deliberately not sandboxed and is distributed as a notarized DMG through GitHub Releases instead.

## Updates

Choose **Check for Updates…** from the menu. The app fetches the latest `appcast.json` from GitHub Releases and, if a newer version exists, downloads the DMG and verifies its SHA-256 checksum and its notarization before installing. Updates are manual only; the app never checks in the background.

## Building from source

Requires Xcode 26.6 or later (Swift 6).

```bash
brew install xcodegen librsvg
make test       # package tests
make app-test   # generates the Xcode project and runs the app tests
```

A build signed ad hoc or with a personal team gets a new signature on every rebuild, so macOS forgets the Accessibility grant. Re-grant it after each rebuild. The Developer ID release build keeps a stable grant.

## Development

| Target | What it does |
| --- | --- |
| `make build` | Build the Swift package |
| `make test` | Run the package tests |
| `make coverage` | Run tests with coverage and enforce the minimum (`COVERAGE_MIN`, default 90; `COVERAGE_REPORT_PATH` writes the table) |
| `make clean` | Clean package build products |
| `make xcodeproj` | Generate FloTile.xcodeproj with xcodegen |
| `make app-build` | Build the app (Debug, unsigned) |
| `make app-test` | Run the app tests with default automatic signing |
| `make app-test-ci` | Run the app tests ad-hoc signed (no certificate needed) |
| `make icon` | Generate the app icon from the SVG |
| `make release-build` | Developer ID release build |
| `make dmg` | Create the signed DMG |
| `make notarize` | Notarize and staple the DMG |
| `make release` | Publish the release |
| `make release-dry-run` | Release flow without publishing |
| `make live-ax-test` | Live Accessibility self-test (local only, never CI) |

### Repository layout

- `Package.swift`: the `FloTileCore` library (Foundation, CoreGraphics and CryptoKit only, never AppKit). Sources in `Sources/FloTileCore`, tests in `Tests/FloTileCoreTests` (XCTest, Swift Testing and fixtures).
- `project.yml`: xcodegen spec. App target `FloTile` in `App/Sources`, app-hosted tests in `App/Tests`.
- `scripts/`: `coverage-gate.sh`, `generate-icon.sh`, `build-app.sh`, `make-dmg.sh`, `notarize-dmg.sh`, `publish-release.sh`, `live-ax-test.sh`, `read-app-version.sh`, `lib/resolve-codesign-identity.sh`.
- `.github/workflows/ci.yml`: CI on macOS.
- `docs/RELEASING.md`: the release checklist.

### Testing philosophy

- **Pure Core.** All tiling, grid and updater logic lives in `FloTileCore`, which has no AppKit dependency. `make coverage` enforces at least 90% line coverage (currently about 97.7%, with 75 XCTest and 90 Swift Testing cases).
- **App tests with fakes.** The 49 app tests exercise the AppKit layer against fake adapters instead of real windows.
- **Live Accessibility self-test.** `make live-ax-test` (sets `FLOTILE_LIVE_AX_TESTS=1`) drives real windows. It needs the Accessibility permission, so it runs locally only.
- **CI.** GitHub Actions runs the package tests with the coverage gate and the app tests (ad-hoc signed) on every push.

## Releasing

See [docs/RELEASING.md](docs/RELEASING.md).

## License

MIT. See [LICENSE](LICENSE).
