#!/bin/bash
# Builds Ping.app (universal: Apple Silicon + Intel, macOS 14+; Liquid Glass on macOS 26) and signs it ad-hoc.
#   ./build.sh          build
#   ./build.sh run      build and open
set -e
cd "$(dirname "$0")"
APP=Ping.app
VERSION=${VERSION:-1.0.0}
FRAMEWORKS="-framework AppKit -framework QuartzCore -framework ServiceManagement"
rm -rf "$APP" .build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" .build
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
swiftc -O -target arm64-apple-macos14.0 $FRAMEWORKS Sources/*.swift -o .build/arm64
swiftc -O -target x86_64-apple-macos14.0 $FRAMEWORKS Sources/*.swift -o .build/x86_64
lipo -create .build/arm64 .build/x86_64 -output "$APP/Contents/MacOS/Ping"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.hafiz.ping</string>
  <key>CFBundleName</key><string>Ping</string>
  <key>CFBundleDisplayName</key><string>Ping</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleExecutable</key><string>Ping</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
rm -rf .build
echo "Built $APP $VERSION ($(lipo -archs "$APP/Contents/MacOS/Ping")), signed ad-hoc"
if [ "${1:-}" = "run" ]; then open "$APP"; fi
