#!/bin/bash
# Build, (ad-hoc) sign, install and validate MUEW as an AUv2 on macOS.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=out/MUEW.component
rm -rf out
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources" build

echo "== Compiling MUEW.component =="
clang++ -std=c++17 -O2 -bundle -arch arm64 -arch x86_64 \
  -isysroot "$(xcrun --show-sdk-path)" \
  -Isrc -Iau -Iapp -fobjc-arc -DMUEW_EDITOR_CLASS=MUEWEditorView_AU_0_63 \
  au/MUEWAU.cpp au/MUEWAUView.mm app/MUEWEditorView.mm \
  -framework AudioToolbox -framework CoreAudio -framework CoreMIDI -framework CoreFoundation \
  -framework AppKit -framework AudioUnit \
  -o "$OUT/Contents/MacOS/MUEW" 2>&1 | tee out/au_compile.log
cp au/Info.plist "$OUT/Contents/Info.plist"
echo "== Universal architecture check =="
ARCHS=$(lipo -archs "$OUT/Contents/MacOS/MUEW")
echo "architectures: $ARCHS"
[[ "$ARCHS" == *arm64* && "$ARCHS" == *x86_64* ]] || { echo "FAIL: not universal"; exit 1; }

echo "== Ad-hoc signing =="
codesign --force --sign - "$OUT"

echo "== Installing to ~/Library/Audio/Plug-Ins/Components =="
mkdir -p "$HOME/Library/Audio/Plug-Ins/Components"
rm -rf "$HOME/Library/Audio/Plug-Ins/Components/MUEW.component"
cp -R "$OUT" "$HOME/Library/Audio/Plug-Ins/Components/"

echo "== Refreshing AudioComponent registrar cache =="
# macOS caches component registrations; a freshly installed component is
# invisible to auval until the registrar re-scans. This is the documented
# remedy for "didn't find the component" after a new install.
killall -9 AudioComponentRegistrar 2>/dev/null || true
sleep 2

echo "== Discovery check =="
auval -a | grep -i muew || { echo "FAIL: component not discovered after registrar restart"; exit 1; }

echo "== auval =="
auval -v aumu Muew Inst 2>&1 | tee out/auval.log

echo "== Host audio test =="
clang++ -std=c++17 -O2 -isysroot "$(xcrun --show-sdk-path)" -Isrc -Iau \
  au/au_host_test.cpp -framework AudioToolbox -framework CoreAudio -framework CoreMIDI -framework CoreFoundation \
  -o build/au_host_test 2>&1 | tee out/au_host_test_compile.log
./build/au_host_test 2>&1 | tee out/au_host_test.log

echo "== Packaging =="
cd out && zip -qry MUEW-AU-unsigned.zip MUEW.component && cd ..
echo "Done: out/MUEW-AU-unsigned.zip"