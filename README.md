# FlöTile

![CI](https://github.com/ebowman/flotile/actions/workflows/ci.yml/badge.svg)

FlöTile is a macOS menu bar app. Click its icon to tile the front app's windows uniformly on the current display; option-click or right-click for Settings…, Check for Updates…, and Quit.

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
