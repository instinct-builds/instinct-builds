// MUEWPluginInterface.h - includes for the macOS Audio Unit v2 plug-in ABI.
//
// Current Xcode SDKs declare the AUv2 plug-in ABI directly in
// AudioToolbox/AudioComponent.h (AudioComponentPlugInInterface: Open/Close/
// Lookup/reserved, plus the factory typedef) and AudioToolbox/AUComponent.h
// (the AudioUnit/MusicDevice method selectors). Apple only removed the old
// standalone AudioComponentPlugIn.h / AudioUnitPlugInInterface.h files; the
// ABI declarations live on in these headers, so MUEW compiles against the real
// SDK definitions. auval remains the conformance check in CI.
#pragma once

#include <CoreAudioTypes/CoreAudioTypes.h>
#include <AudioToolbox/AudioComponent.h>
#include <AudioToolbox/AUComponent.h>
