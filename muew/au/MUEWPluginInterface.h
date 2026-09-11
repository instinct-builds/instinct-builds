// MUEWPluginInterface.h - declarations for the macOS Audio Unit v2 plug-in ABI.
//
// Apple no longer ships the AUv2 *authoring* headers (AudioComponentPlugIn.h /
// AudioUnitPlugInInterface.h) in current Xcode SDKs, but the ABI itself is
// stable, public, and unchanged since OS X 10.11: hosts and auval still load
// and validate AUv2 components. This header declares that public ABI so MUEW
// can be built as an AUv2 against any modern SDK. Field order, selector values
// and prototypes were written from Apple's published API documentation and
// cross-checked against two independent public reconstructions of the same ABI
// (the D Derelict bindings, whose struct sizes were asserted against the real
// SDK, and the Rust au-sys crate). auval is the final conformance check in CI.
#pragma once

#include <CoreAudioTypes/CoreAudioTypes.h>
#include <AudioToolbox/AUComponent.h>

#ifndef MUEW_AU_PLUGIN_INTERFACE_DECLARED
#define MUEW_AU_PLUGIN_INTERFACE_DECLARED

#ifdef __cplusplus
extern "C" {
#endif

// Generic method pointer dispatched through the Lookup vtable entry.
typedef OSStatus (*AudioComponentMethod)(void *self, ...);

// The vtable every AUv2 plug-in instance begins with. The factory function
// returns a pointer to one of these (embedded in the plug-in's instance).
typedef struct AudioComponentPlugInInterface {
    OSStatus (*Open)(void *self, AudioComponentInstance mInstance);
    OSStatus (*Close)(void *self);
    AudioComponentMethod (*Lookup)(SInt16 selector);
    void *reserved;
} AudioComponentPlugInInterface;

// The entry point named in the bundle's AudioComponents plist dictionary.
typedef AudioComponentPlugInInterface *(*AudioComponentFactoryFunction)(
    const AudioComponentDescription *inDesc);

// Method selectors (AudioUnit range 0x00xx, MusicDevice range 0x01xx).
enum {
    kAudioUnitInitializeSelect                          = 0x0001,
    kAudioUnitUninitializeSelect                        = 0x0002,
    kAudioUnitGetPropertyInfoSelect                     = 0x0003,
    kAudioUnitGetPropertySelect                         = 0x0004,
    kAudioUnitSetPropertySelect                         = 0x0005,
    kAudioUnitGetParameterSelect                        = 0x0006,
    kAudioUnitSetParameterSelect                        = 0x0007,
    kAudioUnitResetSelect                               = 0x0009,
    kAudioUnitAddPropertyListenerSelect                 = 0x000A,
    kAudioUnitRemovePropertyListenerSelect              = 0x000B,
    kAudioUnitRenderSelect                              = 0x000E,
    kAudioUnitAddRenderNotifySelect                     = 0x000F,
    kAudioUnitRemoveRenderNotifySelect                  = 0x0010,
    kAudioUnitScheduleParametersSelect                  = 0x0011,
    kAudioUnitRemovePropertyListenerWithUserDataSelect  = 0x0012,
    kMusicDeviceMIDIEventSelect                         = 0x0101,
    kMusicDeviceSysExSelect                             = 0x0102,
    kMusicDevicePrepareInstrumentSelect                 = 0x0103,
    kMusicDeviceReleaseInstrumentSelect                 = 0x0104,
    kMusicDeviceStartNoteSelect                         = 0x0105,
    kMusicDeviceStopNoteSelect                          = 0x0106
};

#ifdef __cplusplus
}
#endif

#endif // MUEW_AU_PLUGIN_INTERFACE_DECLARED
