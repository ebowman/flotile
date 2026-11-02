#!/usr/bin/env bash
# Live Accessibility self-test (LOCAL ONLY; never runs in CI).
#
# Usage:   FLOTILE_LIVE_AX_TESTS=1 scripts/live-ax-test.sh     (or: make live-ax-test)
# Without FLOTILE_LIVE_AX_TESTS=1 this prints "skipped" and exits 0.
#
# Prerequisites:
#   - Accessibility must be granted to the signed Debug FloTile build
#     (.build/xcode/Build/Products/Debug/FloTile.app).
#   - The invoking shell/terminal must be allowed to control "System Events"
#     (Automation + Accessibility) because TextEdit is driven via osascript.
#   - TextEdit must NOT already have documents open (they would be closed
#     without saving); the script refuses to run in that case.
#
# What it does: builds a signed Debug app, makes TextEdit show exactly two
# untitled documents plus the Fonts panel (a non-standard window), runs
# `FloTile --self-test-tile` (DEBUG-only mode, prints one JSON line), and asserts
# the two documents were tiled side by side on the screen's visible frame and the
# Fonts panel was NOT moved. Then it cleans up.
set -euo pipefail

if [[ "${FLOTILE_LIVE_AX_TESTS:-}" != "1" ]]; then
  echo "skipped: set FLOTILE_LIVE_AX_TESTS=1 to run the live Accessibility self-test"
  exit 0
fi

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || (cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd))"
cd "$ROOT"

APP=".build/xcode/Build/Products/Debug/FloTile.app"
OUT="build/live-ax-test.json"
mkdir -p build

if osascript -e 'tell application "TextEdit" to (it is running) and ((count of documents) > 0)' 2>/dev/null | grep -q true; then
  echo "TextEdit already has documents open; quit it first (they would be closed without saving)." >&2
  exit 1
fi

CREATED_DOCS=()
PANEL_OPENED=0
cleanup() {
  # Close the Fonts panel only if this script opened it, and close only the
  # documents this script created (by name). Never "every document".
  if [[ "$PANEL_OPENED" == "1" ]]; then
    osascript >/dev/null 2>&1 <<'OSA' || true
tell application "System Events"
  if exists process "TextEdit" then
    tell process "TextEdit"
      if (exists window "Fonts") then
        set frontmost to true
        keystroke "t" using command down
      end if
    end tell
  end if
end tell
OSA
  fi
  local name
  for name in ${CREATED_DOCS[@]+"${CREATED_DOCS[@]}"}; do
    osascript >/dev/null 2>&1 -e "tell application \"TextEdit\" to if (exists document \"$name\") then close document \"$name\" saving no" || true
  done
  pkill -x FloTile >/dev/null 2>&1 || true
}

trap cleanup EXIT

echo "Building signed Debug app..."
make xcodeproj >/dev/null
xcodebuild -project FloTile.xcodeproj -scheme FloTile -configuration Debug \
  -derivedDataPath .build/xcode build >build/live-ax-build.log 2>&1 \
  || { tail -30 build/live-ax-build.log; echo "build failed" >&2; exit 1; }

osascript <<'OSA'
tell application "TextEdit"
  activate
  delay 1
  repeat while (count of documents) < 2
    make new document
  end repeat
  repeat while (count of documents) > 2
    close document 1 saving no
  end repeat
end tell
OSA
# Record exactly the documents we created (guard above ensured there were none before).
while IFS= read -r name; do
  [[ -n "$name" ]] && CREATED_DOCS+=("$name")
done < <(osascript -e 'tell application "TextEdit" to set AppleScript'"'"'s text item delimiters to linefeed' \
                   -e 'tell application "TextEdit" to (name of every document) as text' | tr ',' '\n' | sed 's/^ *//')
osascript <<'OSA'
delay 0.5
tell application "System Events" to tell process "TextEdit"
  set frontmost to true
  keystroke "t" using command down
end tell
delay 1.5
OSA
PANEL_OPENED=1

PANEL_NAME="Fonts"
panel_pos() {
  local out
  out="$(osascript -e "tell application \"System Events\" to tell process \"TextEdit\" to get position of window \"$PANEL_NAME\"" 2>/dev/null)" \
    || { echo "could not read position of window \"$PANEL_NAME\" (panel not found?)" >&2; return 1; }
  echo "${out// /}"
}
echo "TextEdit windows: $(osascript -e 'tell application "System Events" to tell process "TextEdit" to get name of every window')"
BEFORE="$(panel_pos)" || exit 1
echo "Fonts panel position before: $BEFORE"

# TextEdit must be frontmost (FloTile is LSUIElement and does not activate).
osascript -e 'tell application "System Events" to tell process "TextEdit" to set frontmost to true' >/dev/null
# The Fonts panel may hold focus; the app is still TextEdit, which is what matters.
sleep 0.5

"$APP/Contents/MacOS/FloTile" --self-test-tile >"$OUT" || { echo "self-test exited non-zero:"; cat "$OUT"; exit 1; }
sleep 0.5
AFTER="$(panel_pos)" || exit 1
echo "Fonts panel position after:  $AFTER"
echo "Self-test JSON: $(cat "$OUT")"

python3 -I - "$OUT" "$BEFORE" "$AFTER" <<'PY'
import json, sys
raw = open(sys.argv[1]).read()
before, after = sys.argv[2], sys.argv[3]
def fail(msg):
    print("ASSERTION FAILED: " + msg, file=sys.stderr)
    print(raw, file=sys.stderr)
    sys.exit(1)
try:
    d = json.loads(raw)
except Exception as e:
    fail("invalid JSON: %s" % e)
if "error" in d: fail("self-test reported error")
if d["outcome"] != "tiled:2": fail("outcome != tiled:2")
fr = d["frames"]; s = d["screen"]
if len(fr) != 2: fail("expected exactly 2 frames")
sx, sy, sw, sh = s["x"], s["y"], s["w"], s["h"]
for x, y, w, h in fr:
    if x < sx or y < sy or x + w > sx + sw or y + h > sy + sh: fail("frame outside screen")
(ax, ay, aw, ah), (bx, by, bw, bh) = fr
if min(ax + aw, bx + bw) - max(ax, bx) > 0 and min(ay + ah, by + bh) - max(ay, by) > 0:
    fail("frames overlap")
if aw + bw != sw or ah != sh or bh != sh: fail("frames do not tile the screen side by side")
if before != after: fail("Fonts panel moved: %s -> %s" % (before, after))
if not d["ignored"]: fail("Fonts panel not reported in 'ignored' (expected a non-standard window)")
print("live-ax-test: PASS")
PY
