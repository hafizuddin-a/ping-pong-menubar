#!/bin/bash
# Installs the latest Ping release, no Xcode or Homebrew needed:
#
#   curl -fsSL https://raw.githubusercontent.com/hafizuddin-a/ping-pong-menubar/main/get.sh | bash
#
# It downloads the release zip from GitHub, checks it, puts Ping.app in /Applications (or ~/Applications if
# that isn't writable) and opens it. Files downloaded with curl aren't quarantined, so macOS doesn't show its
# "can't verify the developer" warning. Running it again reinstalls the latest version.
# PING_DIR=<folder> installs somewhere else; PING_NO_OPEN=1 doesn't open the app afterwards.
set -euo pipefail

REPO=hafizuddin-a/ping-pong-menubar
say() { printf '%s\n' "$*"; }
fail() { printf 'Ping install failed: %s\n' "$*" >&2; exit 1; }

[ "$(uname)" = "Darwin" ] || fail "Ping is a Mac app."
[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 14 ] || fail "it needs macOS 14 or later."

if [ -n "${PING_DIR:-}" ]; then
  DIR="$PING_DIR"
elif [ -w /Applications ]; then
  DIR=/Applications
else
  DIR="$HOME/Applications"
fi
mkdir -p "$DIR" || fail "can't create $DIR."
[ -w "$DIR" ] || fail "can't write to $DIR."

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

say "Looking up the latest release..."
curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" -o "$WORK/release.json" || fail "couldn't reach GitHub."
TAG=$(grep -m1 '"tag_name"' "$WORK/release.json" | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')
URL=$(grep '"browser_download_url"' "$WORK/release.json" | grep -E '\.zip"' | head -1 | sed -E 's/.*"(https[^"]+)".*/\1/')
[ -n "$TAG" ] && [ -n "$URL" ] || fail "couldn't find the download in the latest release."

say "Downloading Ping $TAG..."
curl -fSL --progress-bar "$URL" -o "$WORK/Ping.zip" || fail "the download didn't finish."

# The release notes list the zip's SHA-256; check it when it's there.
WANT=$(grep -oE 'SHA-256 of [^`]*`[0-9a-f]{64}`' "$WORK/release.json" | head -1 | grep -oE '[0-9a-f]{64}' || true)
if [ -n "$WANT" ]; then
  GOT=$(shasum -a 256 "$WORK/Ping.zip" | awk '{print $1}')
  [ "$GOT" = "$WANT" ] || fail "the download doesn't match its published checksum. Nothing was installed."
fi

ditto -x -k "$WORK/Ping.zip" "$WORK/unzipped" || fail "couldn't unzip the download."
[ -d "$WORK/unzipped/Ping.app" ] || fail "Ping.app isn't in the download."
codesign --verify --deep "$WORK/unzipped/Ping.app" 2>/dev/null || fail "the app's signature doesn't check out. Nothing was installed."

pkill -x Ping 2>/dev/null && sleep 1 || true
rm -rf "$DIR/Ping.app"
ditto "$WORK/unzipped/Ping.app" "$DIR/Ping.app"
xattr -dr com.apple.quarantine "$DIR/Ping.app" 2>/dev/null || true

say "Installed Ping $TAG to $DIR."
if [ -z "${PING_NO_OPEN:-}" ]; then
  open "$DIR/Ping.app"
  say "Look for the two paddles and a ball in your menu bar. Right-click it for Launch at Login."
fi
