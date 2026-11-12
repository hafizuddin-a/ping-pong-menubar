#!/bin/bash
# Builds, copies the app to ~/Applications and opens it.
set -e
cd "$(dirname "$0")"
DEST="$HOME/Applications/Ping.app"

./build.sh
pkill -x Ping 2>/dev/null || true
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
cp -R Ping.app "$DEST"
open "$DEST"
echo "Installed to $DEST. Right-click its menu bar icon for Difficulty and Launch at Login."
