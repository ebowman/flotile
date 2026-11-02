# Releasing FlöTile

Releases are Developer ID signed, notarized DMGs published to GitHub Releases, together with an `appcast.json` the in-app updater reads.

## Prerequisites

1. A "Developer ID Application" certificate in your login keychain.
2. Notarization credentials, either:
   - a notarytool keychain profile, named by `NOTARY_PROFILE`; or
   - a gitignored `.env` holding the App Store Connect API key ids (see `.env.example`). Never commit `.env`.
3. `gh` installed and authenticated (`gh auth status`).
4. A clean git tree on the branch you are releasing.

## Checklist

1. Bump the version in `VERSION`.
2. `make test coverage app-test` (all must pass; coverage must meet `COVERAGE_MIN`).
3. `make release-build` (Developer ID build).
4. `make dmg` (signed DMG).
5. `make notarize` (submit, wait, staple, verify with spctl).
6. `make release-dry-run` (runs the release flow without publishing; check the output).
7. `make release` (creates the GitHub release and uploads the assets).

## What gets published

- `FloTile-<version>.dmg`
- `appcast.json`, reachable at the stable URL https://github.com/ebowman/flotile/releases/latest/download/appcast.json

## How the updater uses it

"Check for Updates…" fetches the stable `appcast.json` URL, compares its version with the running app, and if newer downloads the DMG. It verifies the SHA-256 from the appcast and the notarization of the download before installing. Checks are manual only.

## First-launch checklist

Install the published DMG into `/Applications` and run it from there:

1. Click the menu bar icon with another app's windows open: they tile on the current display.
2. Open Settings… and toggle Open at Login. FlöTile appears in System Settings > General > Login Items accordingly.
3. Choose Check for Updates…: it reports that you are up to date.

## Troubleshooting

- **xcodebuild signing errors.** Confirm the Developer ID Application certificate is in the keychain (`security find-identity -v -p codesigning`) and has not expired.
- **notarytool reports Invalid.** Read `build/notarize-log-<id>.json` for the specific rejection reasons, fix them and re-run `make notarize`.
- **Dirty tree.** Release scripts refuse to publish with uncommitted changes. Commit or stash, then retry.
