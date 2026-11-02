#!/usr/bin/env bash
# Renders App/Resources/AppIcon.svg into the AppIcon asset catalog and writes Contents.json.
# The SVG is the source of truth. The generated PNGs ARE committed so CI and
# archive builds need no renderer; rerun this script (`make icon`) after editing the SVG.
# Deterministic: running twice yields identical bytes.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
SVG="$ROOT/App/Resources/AppIcon.svg"
SET="$ROOT/App/Resources/Assets.xcassets/AppIcon.appiconset"

if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "error: rsvg-convert not found. Install it with: brew install librsvg" >&2
  exit 1
fi
[ -f "$SVG" ] || { echo "error: missing $SVG" >&2; exit 1; }
mkdir -p "$SET"

# name:pixels
SLOTS="icon_16x16.png:16 icon_16x16@2x.png:32 icon_32x32.png:32 icon_32x32@2x.png:64 icon_128x128.png:128 icon_128x128@2x.png:256 icon_256x256.png:256 icon_256x256@2x.png:512 icon_512x512.png:512 icon_512x512@2x.png:1024"

for slot in $SLOTS; do
  name="${slot%%:*}"; px="${slot##*:}"
  rsvg-convert -w "$px" -h "$px" "$SVG" -o "$SET/$name"
  info="$(sips -g pixelWidth -g pixelHeight "$SET/$name")"
  w="$(awk '/pixelWidth/{print $2}' <<<"$info")"
  h="$(awk '/pixelHeight/{print $2}' <<<"$info")"
  if [ "$w" != "$px" ] || [ "$h" != "$px" ]; then
    echo "error: $name is ${w}x${h}, expected ${px}x${px}" >&2
    exit 1
  fi
done

{
  echo '{'
  echo '  "images" : ['
  first=1
  for base in 16 32 128 256 512; do
    for scale in 1 2; do
      suffix=""; [ "$scale" = 2 ] && suffix="@2x"
      [ $first = 1 ] || echo ','
      first=0
      printf '    {\n      "filename" : "icon_%sx%s%s.png",\n      "idiom" : "mac",\n      "scale" : "%sx",\n      "size" : "%sx%s"\n    }' \
        "$base" "$base" "$suffix" "$scale" "$base" "$base"
    done
  done
  echo
  echo '  ],'
  echo '  "info" : {'
  echo '    "author" : "xcode",'
  echo '    "version" : 1'
  echo '  }'
  echo '}'
} > "$SET/Contents.json"

echo "Generated 10 icon PNGs and Contents.json in $SET"
