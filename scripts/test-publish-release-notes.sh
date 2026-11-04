#!/usr/bin/env bash
# Unit-style test for filter_release_subjects in scripts/publish-release.sh.
# Extracts only the function; the release script itself is never executed.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
eval "$(sed -n '/^filter_release_subjects()/,/^}/p' "$HERE/publish-release.sh")"
type filter_release_subjects >/dev/null 2>&1 || { echo "FAIL: function not found" >&2; exit 1; }

expected='- real change
- Another real change
- Rebump something unrelated'

actual="$(filter_release_subjects <<'IN'
Bump version to 0.1.2
Bump project.yml MARKETING_VERSION to 0.1.2
bump VERSION file
beads: export after closing epic
Merge branch 'x'
FloTile-abc.1: real change

Another real change
Rebump something unrelated
IN
)"
if [ "$actual" != "$expected" ]; then
    echo "FAIL: output mismatch" >&2
    diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") >&2 || true
    exit 1
fi

empty="$(filter_release_subjects </dev/null)"
[ -z "$empty" ] || { echo "FAIL: empty input produced output" >&2; exit 1; }

allfiltered="$(printf 'Bump x\nbeads: y\n' | filter_release_subjects)"
[ -z "$allfiltered" ] || { echo "FAIL: fully filtered input produced output" >&2; exit 1; }

echo "test-publish-release-notes: PASS"
