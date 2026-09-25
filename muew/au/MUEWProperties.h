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
    // 0.25.0 arpeggiator (editor step display)
    UInt32 arpOn;        // 1 while the arp is on
    SInt32 arpStep;      // steps played since the pool filled
    SInt32 arpIndex;     // position in the cycle of the last step
    SInt32 arpNote;      // note sounding now, -1 between gates
    SInt32 poolCount;    // held (or latched) keys
    SInt32 pool[8];      // the first 8, in press order
    // 0.26.0
    SInt32 arpPatCell;   // pattern cell of the current step, -1 = pattern off
    UInt32 hostLocked;   // 1 while the clock follows the host bar (sync on, transport playing)
    // 0.30.0 Engine HQ meter
    UInt32 activeVoices; // voices sounding after the last block
    UInt32 voiceLimit;   // POLY voice count (1 in MONO / LEGATO)
    Float32 cpuLoad;     // smoothed share of the real-time budget the engine used (1 = 100%)
    UInt32 oscHQ;        // 1 while the oscillators run oversampled
    UInt32 renderHQ;     // 1 during an offline (HQ) render
    // 0.35.0 live spectral morph per oscillator (0..1), -1 while nothing sounds
    Float32 specMorph[2];
    // 0.36.0 per-voice morph (highest first) and how many voices sound, per oscillator
    Float32 voiceMorph[2][8];
    UInt32 voiceMorphCount[2];
};

// Objective-C class the AU names in kAudioUnitProperty_CocoaUI. Versioned so
// two MUEW builds loaded in one host never collide.
#define MUEW_VIEW_FACTORY_CLASS "MUEWViewFactory_0_38"
#define MUEW_AU_BUNDLE_ID "co.instinct.muew.au"
