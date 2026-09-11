#!/bin/bash
# ASSSETS DMG packager — run on macOS with Xcode CLT installed.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=ASSSETS
VERSION=${VERSION:-0.1.0}

echo "== Building release =="
swift build -c release --product asssets

BUILD_DIR=$(swift build -c release --product asssets --show-bin-path)
STAGE=$(mktemp -d)
APP_DIR="$STAGE/$APP.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BUILD_DIR/asssets" "$APP_DIR/Contents/MacOS/$APP"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP</string>
  <key>CFBundleDisplayName</key><string>$APP</string>
  <key>CFBundleIdentifier</key><string>co.instinct.asssets</string>
  <key>CFBundleExecutable</key><string>$APP</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

echo "== Creating DMG =="
hdiutil create -volname "$APP" -srcfolder "$APP_DIR" -ov -format UDZO "$APP-$VERSION.dmg"
echo "Done: $APP-$VERSION.dmg"
echo "Note: unsigned. Distribute signed (codesign + notarize) or users right-click > Open."
