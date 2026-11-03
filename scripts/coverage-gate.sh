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
#   COVERAGE_MIN          Minimum TOTAL line coverage percent (integer or decimal
#                         in 0-100 inclusive, default 90; anything else exits 2). Raise it for a permanent change by editing the
#                         default below (DEFAULT_MIN) or by setting it in CI.
#   COVERAGE_REPORT_PATH  If set, the full table and verdict are also written there.
#
# Reading the table: columns are Regions, Missed Regions, Cover, Functions,
# Missed Functions, Executed, Lines, Missed Lines, Cover, Branches, ... The gate
# uses the line "Cover" column (Lines / Missed Lines / Cover) of the TOTAL row.
#
# Exit codes: 0 pass, 1 below threshold, 2 invalid COVERAGE_MIN, or profile data or test binary not found.
set -euo pipefail

DEFAULT_MIN=90
MIN="${COVERAGE_MIN:-$DEFAULT_MIN}"
if ! [[ "$MIN" =~ ^[0-9]+([.][0-9]+)?$ ]] || ! awk -v m="$MIN" 'BEGIN{exit !(m+0 >= 0 && m+0 <= 100)}'; then
  echo "error: COVERAGE_MIN must be a number between 0 and 100 (got '$MIN')" >&2
  exit 2
fi
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

# Locate the xctest executable. Layout varies by toolchain (e.g. FloTileCoreTests
# under .build/out/Products/Debug, or FloTilePackageTests under .build/<triple>/debug).
pick_binary() { # $1 = directory to search; prints newest matching executable
  local d="$1" f best="" 
  [ -d "$d" ] || return 0
  while IFS= read -r f; do
    case "$f" in *.dSYM*) continue ;; esac
    case "$(basename "$f")" in *PackageTests*|FloTileCoreTests) ;; *) continue ;; esac
    if [ -z "$best" ] || [ "$f" -nt "$best" ]; then best="$f"; fi
  done < <(find "$d" -type f -path '*.xctest/Contents/MacOS/*' 2>/dev/null)
  [ -n "$best" ] && printf '%s\n' "$best"
  return 0
}
BIN_DIR="$(swift build --show-bin-path --build-tests 2>/dev/null | tail -n 1 || true)"
[ -n "$BIN_DIR" ] || BIN_DIR="$(swift build --show-bin-path 2>/dev/null | tail -n 1 || true)"
BINARY="$(pick_binary "$BIN_DIR")"
[ -n "$BINARY" ] || BINARY="$(pick_binary "$(dirname "$PROFDATA")/..")"
[ -n "$BINARY" ] || BINARY="$(pick_binary .build)"
if [ -z "$BINARY" ] || [ ! -f "$BINARY" ]; then
  echo "error: test xctest binary not found (bin path: ${BIN_DIR:-none}). xctest bundles under .build:" >&2
  find .build -name '*.xctest' 2>&1 | head -n 20 >&2 || true
  exit 2
fi
case "$BINARY" in /*) ;; *) BINARY="$ROOT/${BINARY#./}" ;; esac
echo "using binary: $BINARY profdata: $PROFDATA" >&2

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
