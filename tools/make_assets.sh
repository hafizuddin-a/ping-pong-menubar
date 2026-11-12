#!/bin/zsh
# Regenerates assets/logo.png, assets/demo-play.gif and Resources/AppIcon.icns with the app's real renderer and bot.
#   ./tools/make_assets.sh          write all three
#   ./tools/make_assets.sh debug    also write a few still frames to a temp folder and print where
set -euo pipefail
cd "${0:A:h}/.."
TMP="$(mktemp -d)"
cp tools/make_assets.swift "$TMP/main.swift"        # top-level code must live in a file called main.swift
swiftc -O -framework AppKit -framework QuartzCore Sources/Pong.swift Sources/GameView.swift "$TMP/main.swift" \
  -o "$TMP/make_assets" 2>&1 | grep -v warning || true
mkdir -p assets Resources
"$TMP/make_assets" assets/logo.png assets/demo-play.gif "$TMP/icon1024.png" ${1:+"$TMP"}

ICONSET="$TMP/AppIcon.iconset"; mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size "$TMP/icon1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size*2)) $((size*2)) "$TMP/icon1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
ls -la assets Resources
[ "${1:-}" = "debug" ] && echo "stills in $TMP"
true
