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
#     without saving); the script refuses to run in that case. Right after launch
#     the document count must be 0, or exactly 1 pristine untitled document
#     (empty text, unmodified, no file path) that TextEdit created at launch on
#     Macs without iCloud; that one is adopted and closed in cleanup. Any other
#     state (state restoration, a document with content/edits/a path) is refused
#     with a message stating what was found.
#   - TextEdit may show extra unnamed windows (e.g. a 280x168 window on cold
#     launch); windows are always addressed by name, so they are tolerated.
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
# coordinate conversion), and that the Fonts panel never moved. A third run,
# `--self-test-tile-cycle` (click, 1 s, click, 1 s, click), asserts tiled:2 ->
# maximized:2 (both frames equal to the visible frame and the CGWindowList stacking
# order unchanged) -> restored:2 back to the recorded originals; Fonts panel
# unchanged. Then it cleans up.
#
# The self-test refuses to run unless TextEdit is frontmost
# (--self-test-expect-bundle com.apple.TextEdit); the JSON reports the app it hit.
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

# Prints TextEdit's window names and subroles to help diagnose a failed run.
dump_textedit_windows() {
  echo "TextEdit windows (name, subrole):"
  osascript -e 'tell application "System Events" to tell process "TextEdit" to get {name, subrole} of every window' || true
}

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
  # A panel that appeared late (after a failed open attempt) still needs closing.
  if pgrep -x TextEdit >/dev/null 2>&1; then
    declare -F panel_exists >/dev/null && panel_exists && PANEL_OPENED=1
  fi
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
# Launch-state guard: refuse before creating anything unless TextEdit has 0
# documents, or exactly 1 pristine untitled one created at launch (no iCloud).
# CREATED_DOCS is still empty here, so a refusal makes cleanup close nothing.
DOC_COUNT="$(te_query "TextEdit post-launch document-count query" \
  'tell application "TextEdit" to return count of documents')" || exit 1
if [[ "$DOC_COUNT" == "0" ]]; then
  :
elif [[ "$DOC_COUNT" == "1" ]]; then
  DOC1_INFO="$(te_query "TextEdit launch-document inspection" \
    'tell application "TextEdit"' \
    'set t to text of document 1' \
    'set m to modified of document 1' \
    'set hasPath to true' \
    'try' \
    'set p to path of document 1' \
    'if p is missing value then set hasPath to false' \
    'on error' \
    'set hasPath to false' \
    'end try' \
    'return ((t is "") as text) & "," & (m as text) & "," & (hasPath as text)' \
    'end tell')" || exit 1
  if [[ "$DOC1_INFO" == "true,false,false" ]]; then
    echo "adopting pristine untitled document created at launch"
  else
    IFS=',' read -r D_EMPTY D_MOD D_PATH <<<"$DOC1_INFO"
    echo "TextEdit has 1 document after launch and it is not pristine (empty text: ${D_EMPTY:-?}, modified: ${D_MOD:-?}, has file path: ${D_PATH:-?}); close it and rerun. Refusing to adopt a document with content, modifications or a file." >&2
    exit 1
  fi
elif [[ "$DOC_COUNT" =~ ^[1-9][0-9]*$ ]]; then
  echo "TextEdit has $DOC_COUNT documents after launch (state restoration or user documents); close them and rerun." >&2
  exit 1
else
  echo "live-ax-test: unexpected TextEdit document count: '${DOC_COUNT}'" >&2
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
# Record every document now open: the guard ensured the only pre-existing one (if any)
# is a pristine untitled document adopted from launch, so all of them are ours to close.
names="$(te_query "reading TextEdit document names" \
  'tell application "TextEdit" to set AppleScript'"'"'s text item delimiters to linefeed' \
  'tell application "TextEdit" to (name of every document) as text')"
while IFS= read -r name; do
  name="${name#"${name%%[! ]*}"}"
  [[ -n "$name" ]] && CREATED_DOCS+=("$name")
done <<<"$names"
if [[ "${#CREATED_DOCS[@]}" -ne 2 ]]; then
  echo "live-ax-test: expected 2 TextEdit documents after setup, got ${#CREATED_DOCS[@]}: $names" >&2
  exit 1
fi
PANEL_NAME="Fonts"
# Open the Fonts panel via Format > Font > Show Fonts (deterministic), retrying
# until the window exists. Last attempt falls back to Cmd-T if the menu path is missing.
panel_exists() {
  [[ "$(osascript -e "tell application \"System Events\" to tell process \"TextEdit\" to exists window \"$PANEL_NAME\"" 2>/dev/null)" == "true" ]]
}
open_fonts_panel() {
  local attempt max=6 has_menu
  for ((attempt = 1; attempt <= max; attempt++)); do
    has_menu="$(osascript -e 'tell application "System Events" to tell process "TextEdit" to exists menu item "Show Fonts" of menu "Font" of menu item "Font" of menu "Format" of menu bar 1' 2>/dev/null)" || has_menu=false
    if [[ "$has_menu" == "true" ]]; then
      osascript >/dev/null 2>&1 <<'OSA' || true
tell application "System Events" to tell process "TextEdit"
  set frontmost to true
  click menu item "Show Fonts" of menu "Font" of menu item "Font" of menu "Format" of menu bar 1
end tell
OSA
    elif [[ "$attempt" == "$max" ]]; then
      osascript >/dev/null 2>&1 <<'OSA' || true
tell application "System Events" to tell process "TextEdit"
  set frontmost to true
  keystroke "t" using command down
end tell
OSA
    fi
    sleep 0.5
    if panel_exists; then
      return 0
    fi
  done
  echo "live-ax-test: the \"$PANEL_NAME\" panel never appeared after $max attempts. TextEdit windows: $(osascript -e 'tell application "System Events" to tell process "TextEdit" to get name of every window' 2>&1)" >&2
  return 1
}
sleep 0.5
open_fonts_panel || exit 1
PANEL_OPENED=1

panel_pos() {
  local out
  out="$(osascript -e "tell application \"System Events\" to tell process \"TextEdit\" to get position of window \"$PANEL_NAME\"" 2>/dev/null)" \
    || { echo "could not read position of window \"$PANEL_NAME\" (panel not found?)" >&2; return 1; }
  echo "${out// /}"
}

ensure_panel_visible() {
  osascript -e 'tell application "System Events" to tell process "TextEdit" to set frontmost to true' >/dev/null
  sleep 0.5
  if panel_exists; then
    return 0
  fi
  echo 'live-ax-test: Fonts panel hidden after focus change; reopening' >&2
  open_fonts_panel
}
echo "TextEdit windows: $(osascript -e 'tell application "System Events" to tell process "TextEdit" to get name of every window')"
ensure_panel_visible || exit 1
BEFORE="$(panel_pos)" || exit 1
echo "Fonts panel position before: $BEFORE"

# TextEdit must be frontmost (FloTile is LSUIElement and does not activate).
osascript -e 'tell application "System Events" to tell process "TextEdit" to set frontmost to true' >/dev/null
# The Fonts panel may hold focus; the app is still TextEdit, which is what matters.
sleep 0.5

run_self_test "$OUT" --self-test-expect-bundle com.apple.TextEdit --self-test-tile || { echo "self-test exited non-zero:"; cat "$OUT"; dump_textedit_windows; exit 1; }
sleep 0.5
ensure_panel_visible || exit 1
AFTER="$(panel_pos)" || exit 1
echo "Fonts panel position after:  $AFTER"
echo "Self-test JSON: $(cat "$OUT")"

python3 -I - "$OUT" "$BEFORE" "$AFTER" <<'PY' || { dump_textedit_windows; exit 1; }
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
if d.get("app") != "com.apple.TextEdit": fail("app != com.apple.TextEdit")
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
ensure_panel_visible || exit 1
PANEL_BEFORE_UNDO="$(panel_pos)" || exit 1

osascript -e 'tell application "System Events" to tell process "TextEdit" to set frontmost to true' >/dev/null
sleep 0.5
UNDO_OUT="build/live-ax-undo.json"
run_self_test "$UNDO_OUT" --self-test-expect-bundle com.apple.TextEdit --self-test-tile-undo || { echo "undo self-test exited non-zero:"; cat "$UNDO_OUT"; dump_textedit_windows; exit 1; }
sleep 0.5
AFTER_A="$(doc_geom "$DOC_A")"; AFTER_B="$(doc_geom "$DOC_B")"
ensure_panel_visible || exit 1
PANEL_AFTER_UNDO="$(panel_pos)" || exit 1
echo "Undo self-test JSON: $(cat "$UNDO_OUT")"
echo "After undo: $DOC_A=$AFTER_A $DOC_B=$AFTER_B"

python3 -I - "$UNDO_OUT" "$ORIG_A" "$AFTER_A" "$ORIG_B" "$AFTER_B" "$BEFORE" "$PANEL_BEFORE_UNDO" "$PANEL_AFTER_UNDO" <<'PY' || { dump_textedit_windows; exit 1; }
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
if d.get("app") != "com.apple.TextEdit": fail("app != com.apple.TextEdit")
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
print("live-ax-test: undo assertions OK")
PY

ensure_panel_visible || exit 1
PANEL_BEFORE_CYCLE="$(panel_pos)" || exit 1
CYC_ORIG_A="$(doc_geom "$DOC_A")"; CYC_ORIG_B="$(doc_geom "$DOC_B")"
echo "Cycle originals: $DOC_A=$CYC_ORIG_A $DOC_B=$CYC_ORIG_B"

osascript -e 'tell application "System Events" to tell process "TextEdit" to set frontmost to true' >/dev/null
sleep 0.5
CYCLE_OUT="build/live-ax-cycle.json"
run_self_test "$CYCLE_OUT" --self-test-expect-bundle com.apple.TextEdit --self-test-tile-cycle || { echo "cycle self-test exited non-zero:"; cat "$CYCLE_OUT"; dump_textedit_windows; exit 1; }
sleep 0.5
CYC_AFTER_A="$(doc_geom "$DOC_A")"; CYC_AFTER_B="$(doc_geom "$DOC_B")"
ensure_panel_visible || exit 1
PANEL_AFTER_CYCLE="$(panel_pos)" || exit 1
echo "Cycle self-test JSON: $(cat "$CYCLE_OUT")"
echo "After cycle: $DOC_A=$CYC_AFTER_A $DOC_B=$CYC_AFTER_B"

python3 -I - "$CYCLE_OUT" "$CYC_ORIG_A" "$CYC_AFTER_A" "$CYC_ORIG_B" "$CYC_AFTER_B" "$BEFORE" "$PANEL_BEFORE_CYCLE" "$PANEL_AFTER_CYCLE" <<'PY' || { dump_textedit_windows; exit 1; }
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
if "error" in d: fail("cycle self-test reported error")
if d.get("app") != "com.apple.TextEdit": fail("app != com.apple.TextEdit")
if d["first"]["outcome"] != "tiled:2": fail("first.outcome != tiled:2")
if d["second"]["outcome"] != "maximized:2": fail("second.outcome != maximized:2")
if d["third"]["outcome"] != "restored:2": fail("third.outcome != restored:2")
if len(d["second"]["frames"]) != 2: fail("expected 2 maximized frames")
s = d["screen"]
screen = [float(s["x"]), float(s["y"]), float(s["w"]), float(s["h"])]
for f in d["second"]["frames"]:
    if any(abs(x - y) > 2 for x, y in zip(f, screen)):
        fail("maximized frame %s != screen %s" % (f, screen))
if len(d["first"]["order"]) < 2: fail("expected at least 2 windows in first.order (the two documents; extra TextEdit windows such as the Fonts panel are allowed): %s" % d["first"]["order"])
if d["second"]["order"] != d["first"]["order"]: fail("z-order changed on maximize: %s -> %s" % (d["first"]["order"], d["second"]["order"]))
if d["third"]["order"] != d["first"]["order"]: fail("z-order changed on restore: %s -> %s" % (d["first"]["order"], d["third"]["order"]))
if len(d["third"]["frames"]) != 2: fail("expected 2 restored frames")
origs = [geom(sys.argv[2]), geom(sys.argv[4])]
afters = [geom(sys.argv[3]), geom(sys.argv[5])]
for o, a in zip(origs, afters):
    if any(abs(x - y) > 2 for x, y in zip(o, a)):
        fail("document not restored to original: %s -> %s" % (o, a))
want = sorted((o[0], o[2], o[3]) for o in origs)
got = sorted((f[0], f[2], f[3]) for f in d["third"]["frames"])
for w, g in zip(want, got):
    if any(abs(x - y) > 2 for x, y in zip(w, g)): fail("third.frames x/size differ from originals: %s vs %s" % (want, got))
if not (sys.argv[6] == sys.argv[7] == sys.argv[8]): fail("Fonts panel moved: %s / %s / %s" % tuple(sys.argv[6:9]))
print("live-ax-test: cycle assertions OK")
print("live-ax-test: PASS")
PY
