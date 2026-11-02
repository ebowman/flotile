.PHONY: build test coverage clean

build:
	swift build

test:
	swift test

coverage:
	scripts/coverage-gate.sh

clean:
	swift package clean
	rm -rf .build
