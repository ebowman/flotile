#!/usr/bin/env bash
# Shell-level test for the COVERAGE_MIN validation in scripts/coverage-gate.sh.
# Uses a fake `swift` (exits 0, prints nothing) so the real test suite never runs;
# a value that passes validation then fails later with the "no default.profdata"
# error (exit 2), which distinguishes it from the validation error.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$HERE/coverage-gate.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/work/scripts"
# Run a copy of the gate inside an empty non-git tree so it never sees the real .build.
cp "$GATE" "$TMP/work/scripts/coverage-gate.sh"
printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/swift"
chmod +x "$TMP/bin/swift"

FAILS=0
# run_case <label> <value> <expect: invalid|valid>
run_case() {
  local label="$1" value="$2" expect="$3" out rc ok=1
  set +e
    out="$(cd "$TMP/work" && PATH="$TMP/bin:$PATH" COVERAGE_MIN="$value" bash scripts/coverage-gate.sh 2>&1)"
  rc=$?
  set -e
  local invalid_msg="error: COVERAGE_MIN must be a number between 0 and 100 (got '$value')"
  if [ "$expect" = invalid ]; then
    [ "$rc" -eq 2 ] || ok=0
    case "$out" in *"$invalid_msg"*) ;; *) ok=0 ;; esac
  else
    [ "$rc" -eq 2 ] || ok=0
    case "$out" in *"COVERAGE_MIN must be"*) ok=0 ;; esac
    case "$out" in *"no default.profdata found"*) ;; *) ok=0 ;; esac
  fi
  if [ "$ok" -eq 1 ]; then
    echo "PASS: $label (COVERAGE_MIN='$value', $expect)"
  else
    echo "FAIL: $label (COVERAGE_MIN='$value', $expect, rc=$rc)"
    printf '%s\n' "$out" | sed 's/^/    /'
    FAILS=$((FAILS + 1))
  fi
}

run_case "non-numeric"     "abc"    invalid
run_case "above range"     "101"    invalid
run_case "negative"        "-5"     invalid
run_case "two dots"        "90.5.1" invalid
run_case "exponent"        "1e2"    invalid
run_case "empty->default"  ""       valid
run_case "integer"         "90"     valid
run_case "decimal"         "99.5"   valid
run_case "zero"            "0"      valid
run_case "hundred"         "100"    valid

if [ "$FAILS" -ne 0 ]; then
  echo "$FAILS case(s) failed" >&2
  exit 1
fi
echo "all cases passed"
