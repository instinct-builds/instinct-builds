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
};

// Objective-C class the AU names in kAudioUnitProperty_CocoaUI. Versioned so
// two MUEW builds loaded in one host never collide.
#define MUEW_VIEW_FACTORY_CLASS "MUEWViewFactory_0_13"
#define MUEW_AU_BUNDLE_ID "co.instinct.muew.au"
