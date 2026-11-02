.PHONY: build test coverage clean xcodeproj app-build app-test icon release-build dmg notarize release release-dry-run live-ax-test

build:
	swift build

test:
	swift test

coverage:
	scripts/coverage-gate.sh

clean:
	swift package clean
	rm -rf .build build

xcodeproj:
	xcodegen generate --spec project.yml

app-build: xcodeproj
	xcodebuild -project FloTile.xcodeproj -scheme FloTile -destination 'platform=macOS' \
		-derivedDataPath .build/xcode build CODE_SIGNING_ALLOWED=NO

# SIGNING: uses the project's default automatic signing (team Y5SB82BPYL,
# "Apple Development" identity in the keychain). Verified this works; an ad hoc
# run also passed (append CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual
# DEVELOPMENT_TEAM= for CI machines without the identity). Unsigned
# (CODE_SIGNING_ALLOWED=NO) is NOT sufficient for a hosted test bundle.
app-test: xcodeproj
	xcodebuild test -project FloTile.xcodeproj -scheme FloTile -destination 'platform=macOS' \
		-derivedDataPath .build/xcode

icon:
	scripts/generate-icon.sh

release-build:
	scripts/build-app.sh

dmg:
	scripts/make-dmg.sh

notarize:
	scripts/notarize-dmg.sh

# OPERATOR-INVOKED ONLY: creates a real GitHub release. Not a dependency of any
# other target and never run by default or in CI.
release:
	scripts/publish-release.sh

release-dry-run:
	scripts/publish-release.sh --dry-run

# LOCAL ONLY: live Accessibility self-test against TextEdit. Skips (exit 0)
# unless FLOTILE_LIVE_AX_TESTS=1. Not a dependency of any other target; never CI.
live-ax-test:
	scripts/live-ax-test.sh
