#!/bin/bash
# Build a universal, ad-hoc-signed ARCHITER app and package it as a DMG.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=ARCHITER
PRODUCT=architer
VERSION=${VERSION:-3.87.0}
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

# 3.87.0 app icon: committed as base64 text (a patch carries text, not
# binaries), expanded to an .icns here. The 256 small variant keeps its
# thicker line for the sizes where the fine line vanishes.
mkdir -p out
base64 -D < app/icon/ARCHITER-icon-1024.png.b64 > out/ARCHITER-icon-1024.png
base64 -D < app/icon/ARCHITER-icon-small-256.png.b64 > out/ARCHITER-icon-small-256.png
test "$(sips -g pixelWidth out/ARCHITER-icon-1024.png | awk '/pixelWidth/{print $2}')" = 1024
test "$(sips -g pixelWidth out/ARCHITER-icon-small-256.png | awk '/pixelWidth/{print $2}')" = 256
ICONSET=out/ARCHITER.iconset
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for spec in icon_512x512@2x.png:1024 icon_512x512.png:512 icon_256x256@2x.png:512 icon_256x256.png:256 icon_128x128@2x.png:256 icon_128x128.png:128 icon_32x32@2x.png:64 icon_32x32.png:32 icon_16x16@2x.png:32 icon_16x16.png:16; do
  name=${spec%%:*}; size=${spec##*:}
  if [ "$size" -le 64 ]; then sips -z "$size" "$size" out/ARCHITER-icon-small-256.png --out "$ICONSET/$name" >/dev/null
  else sips -z "$size" "$size" out/ARCHITER-icon-1024.png --out "$ICONSET/$name" >/dev/null; fi
done
test "$(ls "$ICONSET" | wc -l | tr -d ' ')" = 10
iconutil -c icns "$ICONSET" -o "$APP_DIR/Contents/Resources/$APP.icns"
test -s "$APP_DIR/Contents/Resources/$APP.icns"

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
  <key>CFBundleIconFile</key><string>$APP</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
plutil -lint "$APP_DIR/Contents/Info.plist"
# Self-checks: the bundle carries the real version (monotonic over the "2"
# shipped through 3.86.0) and the icon wiring.
test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP_DIR/Contents/Info.plist")" = "$VERSION"
test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIconFile' "$APP_DIR/Contents/Info.plist")" = "$APP"
test "$(echo "$VERSION" | cut -d. -f1)" -gt 2
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"
lipo "$APP_DIR/Contents/MacOS/$APP" -verify_arch arm64 x86_64
hdiutil create -volname "$APP" -srcfolder "$APP_DIR" -ov -format UDZO "$APP-$VERSION.dmg"
# CI runners intermittently return EAGAIN on verify right after create (it has
# outlasted 4 tight retries); flush, then retry with growing backoff, never mask
# a real failure: the final attempt still exits non-zero.
sync
MAX_VERIFY=8
for attempt in $(seq 1 "$MAX_VERIFY"); do
  if hdiutil verify "$APP-$VERSION.dmg"; then break; fi
  [ "$attempt" = "$MAX_VERIFY" ] && { echo "hdiutil verify failed after $attempt attempts"; exit 1; }
  delay=$((attempt * 5))
  echo "hdiutil verify attempt $attempt failed, retrying in ${delay}s"; sleep "$delay"
done
