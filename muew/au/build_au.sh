#!/bin/bash
# Build, (ad-hoc) sign, install and validate MUEW as an AUv2 on macOS.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=out/MUEW.component
rm -rf out
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources" build

echo "== Compiling MUEW.component =="
clang++ -std=c++17 -O2 -bundle \
  -isysroot "$(xcrun --show-sdk-path)" \
  -Isrc -Iau \
  au/MUEWAU.cpp \
  -framework AudioToolbox -framework CoreAudio -framework CoreMIDI -framework CoreFoundation \
  -o "$OUT/Contents/MacOS/MUEW"
cp au/Info.plist "$OUT/Contents/Info.plist"

echo "== Ad-hoc signing =="
codesign --force --sign - "$OUT"

echo "== Installing to ~/Library/Audio/Plug-Ins/Components =="
mkdir -p "$HOME/Library/Audio/Plug-Ins/Components"
rm -rf "$HOME/Library/Audio/Plug-Ins/Components/MUEW.component"
cp -R "$OUT" "$HOME/Library/Audio/Plug-Ins/Components/"

echo "== auval =="
auval -v aumu Muew Inst

echo "== Host audio test =="
clang++ -std=c++17 -O2 -isysroot "$(xcrun --show-sdk-path)" \
  au/au_host_test.cpp -framework AudioToolbox -framework CoreAudio -framework CoreMIDI -framework CoreFoundation \
  -o build/au_host_test
./build/au_host_test

echo "== Packaging =="
cd out && zip -qry MUEW-AU-unsigned.zip MUEW.component && cd ..
echo "Done: out/MUEW-AU-unsigned.zip"
