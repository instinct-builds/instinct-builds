#!/bin/bash
# Build a universal, ad-hoc-signed ASSSETS app and package it as a DMG.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=ASSSETS
PRODUCT=asssets
VERSION=${VERSION:-2.0.0}
# CFBundleVersion: a separate monotonic release build counter, bumped by hand
# per release (Apple: "For macOS apps, increment the build version before you
# distribute a build"). Kept independent of the marketing version, digits only,
# four digits max: the current Apple reference (one to three period-separated
# integers; a single integer reads as N.0.0) states no magnitude cap, and the
# four-digit bound conservatively honors the stricter archived first-component
# limit identified in the suite's signing review. 24 was the last hardcoded
# CFBundleVersion shipped through 1.95.0, so the counter starts above it.
BUILD=$(cat BUILD_NUMBER)
echo "$BUILD" | grep -qxE '[0-9]+' || { echo "BUILD_NUMBER must be a single integer, got: $BUILD" >&2; exit 1; }
test "$BUILD" -gt 24 || { echo "BUILD_NUMBER must be above 24 (last shipped hardcoded CFBundleVersion), got $BUILD" >&2; exit 1; }
test "$BUILD" -le 9999 || { echo "BUILD_NUMBER must stay within four digits (archived Apple first-component limit), got $BUILD" >&2; exit 1; }
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
APP_DIR="$STAGE/$APP.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" out
for ARCH in arm64 x86_64; do swift build -c release --product "$PRODUCT" --arch "$ARCH" --scratch-path ".build-$ARCH"; done
ARM_DIR=$(swift build -c release --product "$PRODUCT" --arch arm64 --scratch-path .build-arm64 --show-bin-path)
INTEL_DIR=$(swift build -c release --product "$PRODUCT" --arch x86_64 --scratch-path .build-x86_64 --show-bin-path)
lipo -create "$ARM_DIR/$PRODUCT" "$INTEL_DIR/$PRODUCT" -output "$APP_DIR/Contents/MacOS/$APP"
# The physical original starter library is shipped inside the app and copied to Application Support on first launch.
cp Sources/AsssetsApp/StarterLibrary.zip "$APP_DIR/Contents/Resources/StarterLibrary.zip"
# Original layered PSD mockups, seamless textures and vectors are generated at build time from MockupFactory and added to the archive.
swift build -c release --product asssets-mockgen --scratch-path .build-mockgen
"$(swift build -c release --product asssets-mockgen --scratch-path .build-mockgen --show-bin-path)/asssets-mockgen" "$STAGE/mockups"
python3 scripts/recompress_png.py "$STAGE"/mockups/*.png
(cd "$STAGE/mockups" && zip -q -X "$APP_DIR/Contents/Resources/StarterLibrary.zip" *.psd *.png *.svg)
unzip -l "$APP_DIR/Contents/Resources/StarterLibrary.zip" | grep -c '\.psd$' | grep -qx 10
test "$(unzip -Z1 "$APP_DIR/Contents/Resources/StarterLibrary.zip" | wc -l | tr -d ' ')" -eq 57
cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$APP</string><key>CFBundleDisplayName</key><string>$APP</string>
  <key>CFBundleIdentifier</key><string>co.instinct.asssets</string><key>CFBundleExecutable</key><string>$APP</string>
  <key>CFBundlePackageType</key><string>APPL</string><key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleIconFile</key><string>$APP</string>
  <key>CFBundleVersion</key><string>$BUILD</string><key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>UTExportedTypeDeclarations</key><array><dict>
    <key>UTTypeIdentifier</key><string>co.instinct.asssets.selection</string>
    <key>UTTypeDescription</key><string>ASSSETS selection</string>
    <key>UTTypeConformsTo</key><array><string>public.data</string></array>
  </dict></array>
</dict></plist>
PLIST
plutil -lint "$APP_DIR/Contents/Info.plist"
# 2.0.0 app icon: committed as base64 text (a patch carries text, not binaries), expanded to an .icns here.
rm -rf out/ASSSETS.iconset
mkdir -p out/ASSSETS.iconset
base64 -D < app/icon/ASSSETS-icon-1024.png.b64 > out/ASSSETS-icon-1024.png
test "$(sips -g pixelWidth out/ASSSETS-icon-1024.png | awk '/pixelWidth/{print $2}')" = 1024
base64 -D < app/icon/ASSSETS-icon-small-256.png.b64 > out/ASSSETS-icon-small-256.png
test "$(sips -g pixelWidth out/ASSSETS-icon-small-256.png | awk '/pixelWidth/{print $2}')" = 256
for spec in icon_16x16.png:16 icon_16x16@2x.png:32 icon_32x32.png:32 icon_32x32@2x.png:64 icon_128x128.png:128 icon_128x128@2x.png:256 icon_256x256.png:256 icon_256x256@2x.png:512 icon_512x512.png:512 icon_512x512@2x.png:1024; do
  name=${spec%%:*}; size=${spec##*:}
  if [ "$size" -le 64 ]; then sips -z "$size" "$size" out/ASSSETS-icon-small-256.png --out "out/ASSSETS.iconset/$name" >/dev/null
  else sips -z "$size" "$size" out/ASSSETS-icon-1024.png --out "out/ASSSETS.iconset/$name" >/dev/null; fi
done
iconutil -c icns out/ASSSETS.iconset -o "$APP_DIR/Contents/Resources/ASSSETS.icns"
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"
lipo "$APP_DIR/Contents/MacOS/$APP" -verify_arch arm64 x86_64
rm -f "$APP-$VERSION.dmg"
hdiutil create -volname "$APP" -srcfolder "$APP_DIR" -ov -format UDZO "$APP-$VERSION.dmg"
# macOS runners can briefly hold the image resource after create, and degraded
# runners hold it for longer. Retry only that transient error, with growing
# waits (3, 6, 9 ... 21 seconds, about 2 minutes total over 8 attempts).
# Every other verification failure remains fatal.
verify_dmg() {
  local log max=8
  log=$(mktemp)
  for attempt in $(seq 1 "$max"); do
    if hdiutil verify "$APP-$VERSION.dmg" >"$log" 2>&1; then cat "$log"; rm -f "$log"; return 0; fi
    cat "$log" >&2
    if ! grep -q 'Resource temporarily unavailable' "$log" || [ "$attempt" -eq "$max" ]; then
      rm -f "$log"; return 1
    fi
    echo "hdiutil verify busy (attempt $attempt of $max); waiting $((attempt * 3))s" >&2
    sleep $((attempt * 3))
  done
}
verify_dmg
# Keep a staged app for the workflow's native launch screenshot and size audit.
rm -rf out/ASSSETS.app; cp -R "$APP_DIR" out/ASSSETS.app
du -sh out/ASSSETS.app "$APP-$VERSION.dmg"
