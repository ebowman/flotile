#!/usr/bin/env bash
# Coverage gate for FloTileCore.
#
# Usage:   scripts/coverage-gate.sh [extra `swift test` args]   (or: make coverage)
#
# Runs `swift test --enable-code-coverage`, then `llvm-cov report` restricted to
# Sources/FloTileCore/*.swift, prints a per-file table and a TOTAL row, and
# compares TOTAL line coverage with the threshold.
#
# Environment:
#   COVERAGE_MIN          Minimum TOTAL line coverage percent (integer or decimal,
#                         default 90). Raise it for a permanent change by editing the
#                         default below (DEFAULT_MIN) or by setting it in CI.
#   COVERAGE_REPORT_PATH  If set, the full table and verdict are also written there.
#
# Reading the table: columns are Regions, Missed Regions, Cover, Functions,
# Missed Functions, Executed, Lines, Missed Lines, Cover, Branches, ... The gate
# uses the line "Cover" column (Lines / Missed Lines / Cover) of the TOTAL row.
#
# Exit codes: 0 pass, 1 below threshold, 2 profile data or test binary not found.
set -euo pipefail

DEFAULT_MIN=90
MIN="${COVERAGE_MIN:-$DEFAULT_MIN}"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || (cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd))"
cd "$ROOT"

swift test --enable-code-coverage "$@"

CODECOV_JSON="$(swift test --show-codecov-path 2>/dev/null | tail -n 1 || true)"
PROFDATA=""
if [ -n "$CODECOV_JSON" ]; then
  CANDIDATE="$(dirname "$CODECOV_JSON")/default.profdata"
  [ -f "$CANDIDATE" ] && PROFDATA="$CANDIDATE"
fi
if [ -z "$PROFDATA" ]; then
  PROFDATA="$(find .build -name default.profdata -print 2>/dev/null | head -n 1 || true)"
  [ -n "$PROFDATA" ] && PROFDATA="$ROOT/${PROFDATA#./}"
fi
if [ -z "$PROFDATA" ] || [ ! -f "$PROFDATA" ]; then
  echo "error: no default.profdata found (did tests run with coverage?)" >&2
  exit 2
fi

# The xctest bundle sits in the products dir, one level above codecov/.
PRODUCTS_DIR="$(dirname "$(dirname "$PROFDATA")")"
BINARY="$PRODUCTS_DIR/FloTileCoreTests.xctest/Contents/MacOS/FloTileCoreTests"
if [ ! -f "$BINARY" ]; then
  BINARY="$(find .build -path '*FloTileCoreTests.xctest/Contents/MacOS/FloTileCoreTests' -print 2>/dev/null | head -n 1 || true)"
  [ -n "$BINARY" ] && BINARY="$ROOT/${BINARY#./}"
fi
if [ -z "$BINARY" ] || [ ! -f "$BINARY" ]; then
  echo "error: FloTileCoreTests xctest binary not found under .build" >&2
  exit 2
fi

REPORT="$(xcrun llvm-cov report "$BINARY" -instr-profile "$PROFDATA" \
  -ignore-filename-regex='(Tests/|\.build/)' \
  "$ROOT"/Sources/FloTileCore/*.swift | sed "s#$ROOT/##g")"

# TOTAL row: fields are TOTAL, regions, missed, cover%, functions, missed,
# executed%, lines (8), missed lines (9), line cover% (10), ...
# Field 10 is therefore the line-coverage percentage (with trailing '%').
PCT="$(printf '%s\n' "$REPORT" | awk '$1=="TOTAL"{gsub(/%/,"",$10); print $10}')"
if ! [[ "$PCT" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
  echo "error: could not parse TOTAL line coverage from llvm-cov report" >&2
  exit 2
fi

if awk -v p="$PCT" -v m="$MIN" 'BEGIN{exit !(p+0 < m+0)}'; then
  VERDICT="Coverage ${PCT}% is below the minimum ${MIN}%"
  RC=1
else
  VERDICT="Coverage ${PCT}% meets the minimum ${MIN}%"
  RC=0
fi

OUT="$REPORT
$VERDICT"
printf '%s\n' "$OUT"
if [ -n "${COVERAGE_REPORT_PATH:-}" ]; then
  printf '%s\n' "$OUT" > "$COVERAGE_REPORT_PATH"
fi
exit "$RC"
