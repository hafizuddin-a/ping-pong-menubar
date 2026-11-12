#!/bin/bash
# Builds dist/Ping-<version>.zip for GitHub Releases and prints its SHA-256 (get.sh checks it).
#   VERSION=1.0.1 ./release.sh
set -e
cd "$(dirname "$0")"
./build.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Ping.app/Contents/Info.plist)
codesign --verify --deep --strict Ping.app
mkdir -p dist
ZIP="dist/Ping-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --norsrc --noextattr --keepParent Ping.app "$ZIP"
echo "Created $ZIP"
shasum -a 256 "$ZIP"
