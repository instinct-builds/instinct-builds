#!/bin/bash
# Build a universal, ad-hoc-signed ARCHITER app and package it as a DMG.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=ARCHITER
PRODUCT=architer
VERSION=${VERSION:-2.28.0}
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
APP_DIR="$STAGE/$APP.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

for ARCH in arm64 x86_64; do
  swift build -c release --product "$PRODUCT" --arch "$ARCH" --scratch-path ".build-$ARCH"
done
ARM_BIN=$(swift build -c release --product "$PRODUCT" --arch arm64 --scratch-path .build-arm64 --show-bin-path)/$PRODUCT
INTEL_BIN=$(swift build -c release --product "$PRODUCT" --arch x86_64 --scratch-path .build-x86_64 --show-bin-path)/$PRODUCT
lipo -create "$ARM_BIN" "$INTEL_BIN" -output "$APP_DIR/Contents/MacOS/$APP"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$APP</string>
  <key>CFBundleDisplayName</key><string>$APP</string>
  <key>CFBundleIdentifier</key><string>co.instinct.architer</string>
  <key>CFBundleExecutable</key><string>$APP</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
plutil -lint "$APP_DIR/Contents/Info.plist"
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"
lipo "$APP_DIR/Contents/MacOS/$APP" -verify_arch arm64 x86_64
hdiutil create -volname "$APP" -srcfolder "$APP_DIR" -ov -format UDZO "$APP-$VERSION.dmg"
hdiutil verify "$APP-$VERSION.dmg"
