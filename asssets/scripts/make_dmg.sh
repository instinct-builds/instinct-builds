#!/bin/bash
# Build a universal, ad-hoc-signed ASSSETS app and package it as a DMG.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=ASSSETS
PRODUCT=asssets
VERSION=${VERSION:-1.39.0}
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
  <key>CFBundleVersion</key><string>24</string><key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>UTExportedTypeDeclarations</key><array><dict>
    <key>UTTypeIdentifier</key><string>co.instinct.asssets.selection</string>
    <key>UTTypeDescription</key><string>ASSSETS selection</string>
    <key>UTTypeConformsTo</key><array><string>public.data</string></array>
  </dict></array>
</dict></plist>
PLIST
plutil -lint "$APP_DIR/Contents/Info.plist"
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"
lipo "$APP_DIR/Contents/MacOS/$APP" -verify_arch arm64 x86_64
rm -f "$APP-$VERSION.dmg"
hdiutil create -volname "$APP" -srcfolder "$APP_DIR" -ov -format UDZO "$APP-$VERSION.dmg"
hdiutil verify "$APP-$VERSION.dmg"
# Keep a staged app for the workflow's native launch screenshot and size audit.
rm -rf out/ASSSETS.app; cp -R "$APP_DIR" out/ASSSETS.app
du -sh out/ASSSETS.app "$APP-$VERSION.dmg"
