#!/usr/bin/env bash
# Builds ARCHITER.app + ARCHITER-<version>.dmg from the built binaries.
# Ad-hoc signed (open via right-click -> Open); notarization needs a paid
# Apple Developer account and is tracked separately.
set -euo pipefail
VERSION=3.87.0
APP_DIR=out/ARCHITER.app/Contents
rm -rf out/ARCHITER.app
mkdir -p "$APP_DIR/MacOS" "$APP_DIR/Frameworks" "$APP_DIR/Resources"
cp .build/release/ARCHITER "$APP_DIR/MacOS/ARCHITER"
cp .build/release/ARCHITERRender "$APP_DIR/MacOS/ARCHITERRender"
cp .build/release/libArchiterCore.dylib "$APP_DIR/Frameworks/"
install_name_tool -id @executable_path/../Frameworks/libArchiterCore.dylib "$APP_DIR/Frameworks/libArchiterCore.dylib"
install_name_tool -change @rpath/libArchiterCore.dylib @executable_path/../Frameworks/libArchiterCore.dylib "$APP_DIR/MacOS/ARCHITER"
install_name_tool -change @rpath/libArchiterCore.dylib @executable_path/../Frameworks/libArchiterCore.dylib "$APP_DIR/MacOS/ARCHITERRender"
lipo "$APP_DIR/MacOS/ARCHITER" -verify_arch x86_64 arm64
lipo "$APP_DIR/MacOS/ARCHITERRender" -verify_arch x86_64 arm64
lipo "$APP_DIR/Frameworks/libArchiterCore.dylib" -verify_arch x86_64 arm64
# App icon: decode the committed art (b64) and build the .icns on the runner
# so the icon also shows up in the proof uploads, and the binary icns never
# sits in git. The 256 small variant keeps its thicker line for tiny sizes.
base64 -d app/icon/ARCHITER-icon-1024.png.b64 > out/ARCHITER-icon-1024.png
base64 -d app/icon/ARCHITER-icon-small-256.png.b64 > out/ARCHITER-icon-small-256.png
ICONSET=out/ARCHITER.iconset
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
sips -z 1024 1024 out/ARCHITER-icon-1024.png --out "$ICONSET/icon_512x512@2x.png" >/dev/null
sips -z 512 512 out/ARCHITER-icon-1024.png --out "$ICONSET/icon_512x512.png" >/dev/null
sips -z 512 512 out/ARCHITER-icon-1024.png --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 256 256 out/ARCHITER-icon-small-256.png --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 256 256 out/ARCHITER-icon-small-256.png --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 128 128 out/ARCHITER-icon-small-256.png --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 64 64 out/ARCHITER-icon-small-256.png --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 32 32 out/ARCHITER-icon-small-256.png --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 32 32 out/ARCHITER-icon-small-256.png --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 16 16 out/ARCHITER-icon-small-256.png --out "$ICONSET/icon_16x16.png" >/dev/null
iconutil -c icns "$ICONSET" -o "$APP_DIR/Resources/ARCHITER.icns"
test -s "$APP_DIR/Resources/ARCHITER.icns"
cat > "$APP_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>ARCHITER</string>
  <key>CFBundleDisplayName</key><string>ARCHITER</string>
  <key>CFBundleIdentifier</key><string>works.instinct.architer</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleExecutable</key><string>ARCHITER</string>
  <key>CFBundleIconFile</key><string>ARCHITER</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
</dict>
</plist>
EOF
# CI-visible self-checks: the bundle carries the real version (monotonic
# over the "2" shipped through 3.86.0) and the icon wiring.
test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP_DIR/Info.plist")" = "$VERSION"
test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIconFile' "$APP_DIR/Info.plist")" = "ARCHITER"
test "$(echo "$VERSION" | cut -d. -f1)" -gt 2
codesign --force --deep --sign - "$APP_DIR/.."
hdiutil create -volname ARCHITER -srcfolder out/ARCHITER.app -ov -format UDZO "out/ARCHITER-$VERSION.dmg"
