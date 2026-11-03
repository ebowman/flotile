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
#     without saving); the script refuses to run in that case. It also refuses
#     if TextEdit still shows documents right after launch (macOS state
#     restoration): the count must be 0 before the script creates its own.
#   - No other FloTile process may be running (e.g. the installed
#     /Applications/FloTile.app): UI scripting would be ambiguous and the
#     cleanup must never kill a FloTile it did not launch. Quit it first.
#
# What it does: builds a signed Debug app, makes TextEdit show exactly two
# untitled documents plus the Fonts panel (a non-standard window), runs
# `FloTile --self-test-tile` (DEBUG-only mode, prints one JSON line), and asserts
# the two documents were tiled side by side on the screen's visible frame and the
# Fonts panel was NOT moved. It then moves the two documents to known arbitrary
# frames (System Events), runs `FloTile --self-test-tile-undo` (click, wait 1 s,
# click) and asserts first.outcome == tiled:2, second.outcome == restored:2, the
# restored sizes/x match the recorded originals (2 pt) and the documents' positions
# re-read via System Events after the undo equal the recorded originals (2 pt, no
# coordinate conversion), and that the Fonts panel never moved. Then it cleans up.
#
# Fails closed: if TextEdit cannot be queried (Automation permission denied,
# TextEdit not responding, osascript error) the script aborts with a clear
# message instead of assuming TextEdit has no documents.
set -euo pipefail

# te_query <description> <applescript line>...
# Runs the AppleScript lines via osascript inside a 10 s timeout block (so a hung
# TextEdit cannot block forever) and prints the trimmed stdout. On any osascript
# failure prints a specific message to stderr and exits 1. Call it as
#   out="$(te_query ...)" || exit 1
# because exit inside $(...) only ends the subshell.
te_query() {
  local desc="$1"; shift
  local args=(-e 'with timeout of 10 seconds') line out errfile err rc=0
  for line in "$@"; do args+=(-e "$line"); done
  args+=(-e 'end timeout')
  errfile="$(mktemp)"
  out="$(osascript "${args[@]}" 2>"$errfile")" || rc=$?
  if [[ "$rc" != "0" ]]; then
    err="$(head -n 1 "$errfile")"
    rm -f "$errfile"
    echo "live-ax-test: $desc failed (osascript exit $rc): $err" >&2
    echo "If this is an Automation permission problem, allow your terminal to control TextEdit and System Events in System Settings > Privacy & Security, then rerun." >&2
    exit 1
  fi
  rm -f "$errfile"
  out="${out#"${out%%[![:space:]]*}"}"
  out="${out%"${out##*[![:space:]]}"}"
  printf '%s\n' "$out"
}

if [[ "${FLOTILE_LIVE_AX_TESTS:-}" != "1" ]]; then
  echo "skipped: set FLOTILE_LIVE_AX_TESTS=1 to run the live Accessibility self-test"
  exit 0
fi

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || (cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd))"
cd "$ROOT"

APP=".build/xcode/Build/Products/Debug/FloTile.app"
OUT="build/live-ax-test.json"
mkdir -p build

TE_DOCS="$(te_query "TextEdit document-count query" \
  'tell application "TextEdit"' \
  'if it is running then' \
  'return count of documents' \
  'else' \
  'return -1' \
  'end if' \
  'end tell')" || exit 1
if [[ "$TE_DOCS" == "-1" || "$TE_DOCS" == "0" ]]; then
  :
elif [[ "$TE_DOCS" =~ ^[1-9][0-9]*$ ]]; then
  echo "TextEdit already has documents open; quit it first (they would be closed without saving)." >&2
  exit 1
else
  echo "live-ax-test: unexpected TextEdit response: '$TE_DOCS'" >&2
  exit 1
fi

# Never run alongside another FloTile: UI scripting would be ambiguous and we
# must never kill a process we did not launch.
if FT_PIDS="$(pgrep -x FloTile 2>/dev/null)" && [[ -n "$FT_PIDS" ]]; then
  echo "FloTile is already running (pid(s): $(echo "$FT_PIDS" | tr '\n' ' ')). Quit the installed/other FloTile first;" >&2
  echo "the live test would be ambiguous and cleanup never kills a FloTile it did not launch." >&2
  exit 1
fi

CREATED_DOCS=()
PANEL_OPENED=0
SELF_TEST_PID=""

# Run the Debug FloTile in the background so cleanup can kill exactly this pid
# if the script is interrupted. Usage: run_self_test <outfile> <args...>
# Returns the child's exit code (set -e safe).
run_self_test() {
  local outfile="$1"; shift
  local rc=0
  "$APP/Contents/MacOS/FloTile" "$@" >"$outfile" &
  SELF_TEST_PID=$!
  wait "$SELF_TEST_PID" || rc=$?
  SELF_TEST_PID=""
  return "$rc"
}
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
  # Kill only the self-test process this script launched (if still alive).
  if [[ -n "${SELF_TEST_PID:-}" ]] && kill -0 "$SELF_TEST_PID" 2>/dev/null; then
    kill "$SELF_TEST_PID" 2>/dev/null || true
    wait "$SELF_TEST_PID" 2>/dev/null || true
  fi
}

trap cleanup EXIT

echo "Building signed Debug app..."
make xcodeproj >/dev/null
xcodebuild -project FloTile.xcodeproj -scheme FloTile -configuration Debug \
  -derivedDataPath .build/xcode build >build/live-ax-build.log 2>&1 \
  || { tail -30 build/live-ax-build.log; echo "build failed" >&2; exit 1; }

osascript -e 'tell application "TextEdit" to activate' -e 'delay 1'
# State restoration guard: TextEdit may have reopened documents on launch. Refuse
# before creating anything (CREATED_DOCS is still empty, so cleanup closes nothing).
DOC_COUNT="$(te_query "TextEdit post-launch document-count query" \
  'tell application "TextEdit" to return count of documents')" || exit 1
if [[ "$DOC_COUNT" != "0" ]]; then
  echo "TextEdit reopened ${DOC_COUNT:-an unknown number of} document(s) via state restoration; close them and rerun." >&2
  exit 1
fi
osascript <<'OSA'
tell application "TextEdit"
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

run_self_test "$OUT" --self-test-tile || { echo "self-test exited non-zero:"; cat "$OUT"; exit 1; }
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
print("live-ax-test: tiling assertions OK")
PY

# ---- Undo phase -------------------------------------------------------------
doc_geom() { # $1 = document/window name -> "x,y,w,h" (AppleScript top-left coords)
  osascript -e "tell application \"System Events\" to tell process \"TextEdit\" to set p to position of window \"$1\"" \
            -e "tell application \"System Events\" to tell process \"TextEdit\" to set z to size of window \"$1\"" \
            -e 'return ((item 1 of p) as text) & "," & ((item 2 of p) as text) & "," & ((item 1 of z) as text) & "," & ((item 2 of z) as text)' \
    | tr -d ' '
}
if [[ "${#CREATED_DOCS[@]}" != "2" ]]; then
  echo "expected 2 created documents, got ${#CREATED_DOCS[@]}" >&2; exit 1
fi
DOC_A="${CREATED_DOCS[0]}"; DOC_B="${CREATED_DOCS[1]}"
set_geom() { # name x y w h
  osascript -e "tell application \"System Events\" to tell process \"TextEdit\" to set size of window \"$1\" to {$4, $5}" \
            -e "tell application \"System Events\" to tell process \"TextEdit\" to set position of window \"$1\" to {$2, $3}" >/dev/null
}
set_geom "$DOC_A" 120 140 600 400
set_geom "$DOC_B" 700 420 520 380
sleep 0.5
ORIG_A="$(doc_geom "$DOC_A")"; ORIG_B="$(doc_geom "$DOC_B")"
echo "Recorded originals: $DOC_A=$ORIG_A $DOC_B=$ORIG_B"
PANEL_BEFORE_UNDO="$(panel_pos)" || exit 1

osascript -e 'tell application "System Events" to tell process "TextEdit" to set frontmost to true' >/dev/null
sleep 0.5
UNDO_OUT="build/live-ax-undo.json"
run_self_test "$UNDO_OUT" --self-test-tile-undo || { echo "undo self-test exited non-zero:"; cat "$UNDO_OUT"; exit 1; }
sleep 0.5
AFTER_A="$(doc_geom "$DOC_A")"; AFTER_B="$(doc_geom "$DOC_B")"
PANEL_AFTER_UNDO="$(panel_pos)" || exit 1
echo "Undo self-test JSON: $(cat "$UNDO_OUT")"
echo "After undo: $DOC_A=$AFTER_A $DOC_B=$AFTER_B"

python3 -I - "$UNDO_OUT" "$ORIG_A" "$AFTER_A" "$ORIG_B" "$AFTER_B" "$BEFORE" "$PANEL_BEFORE_UNDO" "$PANEL_AFTER_UNDO" <<'PY'
import json, sys
raw = open(sys.argv[1]).read()
def fail(msg):
    print("ASSERTION FAILED: " + msg, file=sys.stderr)
    print(raw, file=sys.stderr)
    sys.exit(1)
def geom(t): return [float(v) for v in t.split(",")]
try:
    d = json.loads(raw)
except Exception as e:
    fail("invalid JSON: %s" % e)
if "error" in d: fail("undo self-test reported error")
if d["first"]["outcome"] != "tiled:2": fail("first.outcome != tiled:2")
if d["second"]["outcome"] != "restored:2": fail("second.outcome != restored:2")
if len(d["second"]["frames"]) != 2: fail("expected 2 restored frames")
origs = [geom(sys.argv[2]), geom(sys.argv[4])]
afters = [geom(sys.argv[3]), geom(sys.argv[5])]
for o, a in zip(origs, afters):
    if any(abs(x - y) > 2 for x, y in zip(o, a)):
        fail("document not restored to original: %s -> %s" % (o, a))
# JSON frames (AppKit coords): sizes and x must match the originals, in some order.
want = sorted((o[0], o[2], o[3]) for o in origs)
got = sorted((f[0], f[2], f[3]) for f in d["second"]["frames"])
for w, g in zip(want, got):
    if any(abs(x - y) > 2 for x, y in zip(w, g)): fail("second.frames x/size differ from originals: %s vs %s" % (want, got))
if not (sys.argv[6] == sys.argv[7] == sys.argv[8]): fail("Fonts panel moved: %s / %s / %s" % tuple(sys.argv[6:9]))
print("live-ax-test: PASS")
PY
