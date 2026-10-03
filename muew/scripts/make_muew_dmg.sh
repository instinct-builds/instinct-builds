#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
rm -rf out/MUEW.app out/MUEW-0.110.0.dmg out/MUEW-distribution
mkdir -p out/MUEW.app/Contents/MacOS out/MUEW.app/Contents/Resources
SDK=$(xcrun --show-sdk-path)
clang++ -std=c++17 -O2 -fobjc-arc -arch arm64 -arch x86_64 -isysroot "$SDK" -Isrc -Iapp \
  app/MUEWStandalone.mm app/MUEWEditorView.mm -framework AppKit -framework AVFoundation -framework AudioToolbox -framework CoreMIDI \
  -o out/MUEW.app/Contents/MacOS/MUEW
cat > out/MUEW.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleName</key><string>MUEW</string><key>CFBundleDisplayName</key><string>MUEW</string><key>CFBundleIdentifier</key><string>co.instinct.muew</string><key>CFBundleExecutable</key><string>MUEW</string><key>CFBundleIconFile</key><string>MUEW</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleShortVersionString</key><string>0.110.0</string><key>CFBundleVersion</key><string>73</string><key>LSMinimumSystemVersion</key><string>14.0</string><key>NSHighResolutionCapable</key><true/></dict></plist>
PLIST
# 0.110.0 app icon: committed as base64 text (a patch carries text, not binaries), expanded to an .icns here
rm -rf out/MUEW.iconset out/MUEW-icon-1024.png
mkdir -p out/MUEW.iconset
base64 -D < app/icon/MUEW-icon-1024.png.b64 > out/MUEW-icon-1024.png
test "$(sips -g pixelWidth out/MUEW-icon-1024.png | awk '/pixelWidth/{print $2}')" = 1024
for sz in 16 32 128 256 512; do
  sips -z $sz $sz out/MUEW-icon-1024.png --out out/MUEW.iconset/icon_${sz}x${sz}.png >/dev/null
  sips -z $((sz*2)) $((sz*2)) out/MUEW-icon-1024.png --out out/MUEW.iconset/icon_${sz}x${sz}@2x.png >/dev/null
done
iconutil -c icns out/MUEW.iconset -o out/MUEW.app/Contents/Resources/MUEW.icns
test -s out/MUEW.app/Contents/Resources/MUEW.icns
grep -q '<key>CFBundleIconFile</key><string>MUEW</string>' out/MUEW.app/Contents/Info.plist
codesign --force --deep --sign - out/MUEW.app
mkdir -p out/MUEW-distribution
cp -R out/MUEW.app out/MUEW.component out/MUEW-distribution/
cat > out/MUEW-distribution/INSTALL.txt <<'TXT'
Drag MUEW.app to Applications. Copy MUEW.component to ~/Library/Audio/Plug-Ins/Components, then rescan Audio Units in Ableton Live. This ad-hoc-signed build is not notarized; clear quarantine if macOS blocks first launch.
TXT
ln -s /Applications out/MUEW-distribution/Applications
hdiutil create -volname MUEW -srcfolder out/MUEW-distribution -ov -format UDZO out/MUEW-0.110.0.dmg
