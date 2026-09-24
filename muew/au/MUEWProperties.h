// MUEWProperties.h - private Audio Unit properties shared by the MUEW AU and
// its Cocoa editor view.
#pragma once
#include <AudioToolbox/AudioToolbox.h>

enum : AudioUnitPropertyID {
    // Global, read/write CFStringRef: the full current sound as preset text
    // (muew-preset 2). Get returns a retained string the caller releases.
    kMUEWProperty_PresetState = 64000,
    // Global, read-only UInt32 that changes whenever the sound changes, so
    // the editor can follow host-side preset changes cheaply.
    kMUEWProperty_StateGeneration = 64001,
    // 0.24.0 global, read-only MUEWPerformance: the live MIDI performance
    // controls as the synth last heard them (editor meters).
    kMUEWProperty_Performance = 64002,
};

struct MUEWPerformance {
    Float32 wheel;       // 0..1
    Float32 aftertouch;  // 0..1 (channel pressure)
    Float32 bend;        // -1..1
    SInt32 lastNote;     // -1 before any note
    UInt32 sustain;      // 1 while the pedal is down
};

// Objective-C class the AU names in kAudioUnitProperty_CocoaUI. Versioned so
// two MUEW builds loaded in one host never collide.
#define MUEW_VIEW_FACTORY_CLASS "MUEWViewFactory_0_24"
#define MUEW_AU_BUNDLE_ID "co.instinct.muew.au"
