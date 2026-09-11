// MUEWAU.cpp - MUEW as an Audio Unit v2 music device (instrument).
// Original implementation wrapping the MUEW DSP engine (src/synth.h).
#include "MUEWPluginInterface.h"
#include "synth.h"
#include "preset.h"

#include <AudioToolbox/AudioUnitProperties.h>
#include <AudioToolbox/MusicDevice.h>
#include <CoreFoundation/CoreFoundation.h>
#include <cstring>
#include <new>
#include <vector>

namespace {

constexpr OSType kSubType = 'Muew';
constexpr OSType kManufacturer = 'Inst';

struct Listener {
    AudioUnitPropertyID id;
    AudioUnitPropertyListenerProc proc;
    void* userData;
};

struct MUEWInstance {
    AudioComponentPlugInInterface vtable;
    AudioComponentInstance componentInstance = nullptr;
    muew::Synth synth{16};
    double sampleRate = 44100.0;
    UInt32 maxFrames = 512;
    UInt32 renderQuality = 0x7F;
    bool initialized = false;
    SInt32 presentPreset = 0;
    std::vector<Listener> listeners;

    AudioStreamBasicDescription streamFormat() const {
        AudioStreamBasicDescription d;
        std::memset(&d, 0, sizeof(d));
        d.mSampleRate = sampleRate;
        d.mFormatID = kAudioFormatLinearPCM;
        d.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsNonInterleaved | kAudioFormatFlagsNativeEndian;
        d.mBytesPerPacket = sizeof(float);
        d.mFramesPerPacket = 1;
        d.mBytesPerFrame = sizeof(float);
        d.mChannelsPerFrame = 2;
        d.mBitsPerChannel = 32;
        return d;
    }

    void loadDefaultSound() {
        // Warm Pad (original factory preset, embedded) as the power-on sound.
        static const char* kWarmPad = R"MUEW(muew-preset 1
osc1Shape 2
osc2Shape 2
osc2Detune 0.08
osc2Level 0.5
filterCutoff 2400
filterReso 0.4
filterMode 0
amp 1.2 1.5 0.7 1.6
mod 0.8 1.2 0.3 1
lfo1Rate 0.2
lfo1Shape 0
routes 2
route 1 2 1.5
route 0 3 0.1
chorus 1 0.5 5 12 0.3
delay 0 0.28 0.42 0.35 0.22
reverb 1 0.75 0.4 0.35
)MUEW";
        muew::Preset preset;
        if (preset.parse(kWarmPad)) {
            synth.setParams(preset.voice, preset.routes);
            synth.setFX(preset.fx);
        } else {
            muew::VoiceParams p;
            p.osc1Shape = 2; p.ampA = 0.01; p.ampD = 0.2; p.ampS = 0.7; p.ampR = 0.3;
            synth.setParams(p, muew::Synth::defaultRoutes());
        }
    }
};

MUEWInstance* Self(void* self) { return reinterpret_cast<MUEWInstance*>(self); }

void NotifyListeners(MUEWInstance* u, AudioUnitPropertyID id, AudioUnitScope scope, AudioUnitElement elem) {
    for (auto& l : u->listeners)
        l.proc(l.userData, u->componentInstance, id, scope, elem);
}

// ---- AudioComponentPlugInInterface ----

OSStatus MUEWOpen(void* self, AudioComponentInstance mInstance) {
    Self(self)->componentInstance = mInstance;
    return noErr;
}

OSStatus MUEWClose(void* self) {
    delete Self(self);
    return noErr;
}

// ---- AudioUnit methods ----

OSStatus MUEWInitialize(void* self) {
    MUEWInstance* u = Self(self);
    u->synth.init(u->sampleRate);
    u->loadDefaultSound();
    u->initialized = true;
    return noErr;
}

OSStatus MUEWUninitialize(void* self) {
    Self(self)->initialized = false;
    return noErr;
}

bool FormatIsAcceptable(const AudioStreamBasicDescription& d) {
    return d.mFormatID == kAudioFormatLinearPCM &&
           (d.mFormatFlags & kAudioFormatFlagIsFloat) &&
           (d.mFormatFlags & kAudioFormatFlagIsNonInterleaved) &&
           d.mBitsPerChannel == 32 && d.mChannelsPerFrame == 2;
}

OSStatus MUEWGetPropertyInfo(void* self, AudioUnitPropertyID inID, AudioUnitScope inScope,
                             AudioUnitElement inElement, UInt32* outDataSize, Boolean* outWritable) {
    MUEWInstance* u = Self(self);
    if (outWritable) *outWritable = false;
    switch (inID) {
        case kAudioUnitProperty_SampleRate:
            if (inScope == kAudioUnitScope_Global || inScope == kAudioUnitScope_Output) {
                *outDataSize = sizeof(Float64); if (outWritable) *outWritable = true; return noErr;
            }
            break;
        case kAudioUnitProperty_StreamFormat:
            if (inScope == kAudioUnitScope_Output && inElement == 0) {
                *outDataSize = sizeof(AudioStreamBasicDescription); if (outWritable) *outWritable = true; return noErr;
            }
            break;
        case kAudioUnitProperty_ElementCount:
            *outDataSize = sizeof(UInt32); return noErr;
        case kAudioUnitProperty_MaximumFramesPerSlice:
            if (inScope == kAudioUnitScope_Global) {
                *outDataSize = sizeof(UInt32); if (outWritable) *outWritable = true; return noErr;
            }
            break;
        case kAudioUnitProperty_Latency:
            if (inScope == kAudioUnitScope_Global) { *outDataSize = sizeof(Float64); return noErr; }
            break;
        case kAudioUnitProperty_SupportedNumChannels:
            if (inScope == kAudioUnitScope_Global) { *outDataSize = sizeof(AUChannelInfo); return noErr; }
            break;
        case kAudioUnitProperty_RenderQuality:
            if (inScope == kAudioUnitScope_Global) {
                *outDataSize = sizeof(UInt32); if (outWritable) *outWritable = true; return noErr;
            }
            break;
        case kMusicDeviceProperty_InstrumentCount:
            if (inScope == kAudioUnitScope_Global) { *outDataSize = sizeof(UInt32); return noErr; }
            break;
        case kAudioUnitProperty_PresentPreset:
            if (inScope == kAudioUnitScope_Global) {
                *outDataSize = sizeof(AUPreset); if (outWritable) *outWritable = true; return noErr;
            }
            break;
        case kAudioUnitProperty_ClassInfo:
            if (inScope == kAudioUnitScope_Global) {
                *outDataSize = sizeof(CFPropertyListRef); if (outWritable) *outWritable = true; return noErr;
            }
            break;
        default: break;
    }
    (void)u;
    return kAudioUnitErr_InvalidProperty;
}

OSStatus MUEWGetProperty(void* self, AudioUnitPropertyID inID, AudioUnitScope inScope,
                         AudioUnitElement inElement, void* outData, UInt32* ioDataSize) {
    MUEWInstance* u = Self(self);
    switch (inID) {
        case kAudioUnitProperty_SampleRate:
            if ((inScope == kAudioUnitScope_Global || inScope == kAudioUnitScope_Output) && *ioDataSize >= sizeof(Float64)) {
                *static_cast<Float64*>(outData) = u->sampleRate;
                *ioDataSize = sizeof(Float64);
                return noErr;
            }
            break;
        case kAudioUnitProperty_StreamFormat:
            if (inScope == kAudioUnitScope_Output && inElement == 0 && *ioDataSize >= sizeof(AudioStreamBasicDescription)) {
                *static_cast<AudioStreamBasicDescription*>(outData) = u->streamFormat();
                *ioDataSize = sizeof(AudioStreamBasicDescription);
                return noErr;
            }
            break;
        case kAudioUnitProperty_ElementCount:
            if (inScope == kAudioUnitScope_Input) {
                *static_cast<UInt32*>(outData) = 0; *ioDataSize = sizeof(UInt32); return noErr;
            }
            *static_cast<UInt32*>(outData) = 1; *ioDataSize = sizeof(UInt32); return noErr;
        case kAudioUnitProperty_MaximumFramesPerSlice:
            if (inScope == kAudioUnitScope_Global) {
                *static_cast<UInt32*>(outData) = u->maxFrames; *ioDataSize = sizeof(UInt32); return noErr;
            }
            break;
        case kAudioUnitProperty_Latency:
            if (inScope == kAudioUnitScope_Global) {
                *static_cast<Float64*>(outData) = 0.0; *ioDataSize = sizeof(Float64); return noErr;
            }
            break;
        case kAudioUnitProperty_SupportedNumChannels:
            if (inScope == kAudioUnitScope_Global) {
                AUChannelInfo* info = static_cast<AUChannelInfo*>(outData);
                info->inChannels = 0; info->outChannels = 2;
                *ioDataSize = sizeof(AUChannelInfo);
                return noErr;
            }
            break;
        case kAudioUnitProperty_RenderQuality:
            if (inScope == kAudioUnitScope_Global) {
                *static_cast<UInt32*>(outData) = u->renderQuality; *ioDataSize = sizeof(UInt32); return noErr;
            }
            break;
        case kMusicDeviceProperty_InstrumentCount:
            if (inScope == kAudioUnitScope_Global) {
                *static_cast<UInt32*>(outData) = 1; *ioDataSize = sizeof(UInt32); return noErr;
            }
            break;
        case kAudioUnitProperty_PresentPreset:
            if (inScope == kAudioUnitScope_Global && *ioDataSize >= sizeof(AUPreset)) {
                AUPreset* p = static_cast<AUPreset*>(outData);
                p->presetNumber = u->presentPreset;
                p->presetName = CFSTR("Warm Pad");
                *ioDataSize = sizeof(AUPreset);
                return noErr;
            }
            break;
        case kAudioUnitProperty_ClassInfo:
            if (inScope == kAudioUnitScope_Global && *ioDataSize >= sizeof(CFPropertyListRef)) {
                // auval requires the component identity fields plus our state.
                UInt32 type = kAudioUnitType_MusicDevice, sub = kSubType, mfr = kManufacturer;
                CFStringRef keys[] = {CFSTR("type"), CFSTR("subtype"), CFSTR("manufacturer"),
                                      CFSTR("name"), CFSTR("version"), CFSTR("presetNumber"), CFSTR("renderQuality")};
                CFNumberRef t = CFNumberCreate(nullptr, kCFNumberIntType, &type);
                CFNumberRef st = CFNumberCreate(nullptr, kCFNumberIntType, &sub);
                CFNumberRef m = CFNumberCreate(nullptr, kCFNumberIntType, &mfr);
                SInt32 ver = 0x00010000;
                CFNumberRef v = CFNumberCreate(nullptr, kCFNumberSInt32Type, &ver);
                CFNumberRef num = CFNumberCreate(nullptr, kCFNumberSInt32Type, &u->presentPreset);
                CFNumberRef rq = CFNumberCreate(nullptr, kCFNumberSInt32Type, &u->renderQuality);
                CFTypeRef vals[] = {t, st, m, CFSTR("Instinct: MUEW"), v, num, rq};
                CFDictionaryRef dict = CFDictionaryCreate(nullptr, (const void**)keys, (const void**)vals, 7,
                    &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
                CFRelease(t); CFRelease(st); CFRelease(m); CFRelease(v); CFRelease(num); CFRelease(rq);
                *static_cast<CFPropertyListRef*>(outData) = dict; // caller releases
                *ioDataSize = sizeof(CFPropertyListRef);
                return noErr;
            }
            break;
        default: break;
    }
    return kAudioUnitErr_InvalidProperty;
}

OSStatus MUEWSetProperty(void* self, AudioUnitPropertyID inID, AudioUnitScope inScope,
                         AudioUnitElement inElement, const void* inData, UInt32 inDataSize) {
    MUEWInstance* u = Self(self);
    switch (inID) {
        case kAudioUnitProperty_SampleRate:
            if (inDataSize >= sizeof(Float64)) {
                double sr = *static_cast<const Float64*>(inData);
                if (sr < 8000.0 || sr > 192000.0) return kAudioUnitErr_InvalidPropertyValue;
                if (u->initialized) return kAudioUnitErr_CannotDoInCurrentContext;
                u->sampleRate = sr;
                NotifyListeners(u, kAudioUnitProperty_SampleRate, kAudioUnitScope_Global, 0);
                return noErr;
            }
            break;
        case kAudioUnitProperty_StreamFormat:
            if (inScope == kAudioUnitScope_Output && inDataSize >= sizeof(AudioStreamBasicDescription)) {
                const auto& d = *static_cast<const AudioStreamBasicDescription*>(inData);
                if (!FormatIsAcceptable(d)) return kAudioUnitErr_InvalidPropertyValue;
                if (d.mSampleRate != u->sampleRate) {
                    if (u->initialized) return kAudioUnitErr_CannotDoInCurrentContext;
                    u->sampleRate = d.mSampleRate;
                }
                return noErr;
            }
            break;
        case kAudioUnitProperty_MaximumFramesPerSlice:
            if (inScope == kAudioUnitScope_Global && inDataSize >= sizeof(UInt32)) {
                u->maxFrames = *static_cast<const UInt32*>(inData);
                NotifyListeners(u, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0);
                return noErr;
            }
            break;
        case kAudioUnitProperty_RenderQuality:
            if (inScope == kAudioUnitScope_Global && inDataSize >= sizeof(UInt32)) {
                u->renderQuality = *static_cast<const UInt32*>(inData);
                NotifyListeners(u, kAudioUnitProperty_RenderQuality, kAudioUnitScope_Global, 0);
                return noErr;
            }
            break;
        case kAudioUnitProperty_PresentPreset:
            if (inScope == kAudioUnitScope_Global && inDataSize >= sizeof(AUPreset)) {
                const AUPreset* p = static_cast<const AUPreset*>(inData);
                // One factory sound; -1 marks host-applied custom state. Both accepted.
                u->presentPreset = (p->presetNumber == -1) ? -1 : 0;
                return noErr;
            }
            break;
        case kAudioUnitProperty_ClassInfo:
            if (inScope == kAudioUnitScope_Global && inDataSize >= sizeof(CFPropertyListRef)) {
                CFPropertyListRef plist = *static_cast<const CFPropertyListRef*>(inData);
                if (plist && CFGetTypeID(plist) == CFDictionaryGetTypeID()) {
                    CFDictionaryRef dict = (CFDictionaryRef)plist;
                    CFNumberRef num = (CFNumberRef)CFDictionaryGetValue(dict, CFSTR("presetNumber"));
                    if (num && CFGetTypeID(num) == CFNumberGetTypeID()) {
                        SInt32 n = 0;
                        if (CFNumberGetValue(num, kCFNumberSInt32Type, &n))
                            u->presentPreset = (n == -1) ? -1 : 0;
                    }
                }
                return noErr;
            }
            break;
        default: break;
    }
    return kAudioUnitErr_InvalidProperty;
}

OSStatus MUEWReset(void* self, AudioUnitScope inScope, AudioUnitElement inElement) {
    (void)inScope; (void)inElement;
    MUEWInstance* u = Self(self);
    u->synth.init(u->sampleRate);
    u->loadDefaultSound();
    return noErr;
}

OSStatus MUEWRender(void* self, AudioUnitRenderActionFlags* ioActionFlags,
                    const AudioTimeStamp* inTimeStamp, UInt32 inOutputBusNumber,
                    UInt32 inNumberFrames, AudioBufferList* ioData) {
    (void)inTimeStamp;
    MUEWInstance* u = Self(self);
    if (!u->initialized) return kAudioUnitErr_Uninitialized;
    if (inOutputBusNumber != 0) return kAudioUnitErr_InvalidElement;
    if (inNumberFrames > u->maxFrames) return kAudioUnitErr_TooManyFramesToProcess;
    if (!ioData || ioData->mNumberBuffers < 2) return kAudioUnitErr_InvalidPropertyValue;

    float* left = static_cast<float*>(ioData->mBuffers[0].mData);
    float* right = static_cast<float*>(ioData->mBuffers[1].mData);
    u->synth.renderPlanar(left, right, static_cast<int>(inNumberFrames));

    if (ioActionFlags) {
        // Always producing tail-capable audio; never claim silence while any voice is active.
        if (u->synth.activeVoiceCount() == 0)
            *ioActionFlags |= kAudioUnitRenderAction_OutputIsSilence;
        else
            *ioActionFlags &= ~kAudioUnitRenderAction_OutputIsSilence;
    }
    return noErr;
}

// ---- MusicDevice methods ----

OSStatus MUEWMIDIEvent(void* self, UInt32 inStatus, UInt32 inData1, UInt32 inData2,
                       UInt32 inOffsetSampleFrame) {
    (void)inOffsetSampleFrame; // sample-accurate scheduling is a future refinement
    MUEWInstance* u = Self(self);
    UInt32 type = inStatus & 0xF0;
    if (type == 0x90 && inData2 > 0) {
        u->synth.noteOn(static_cast<int>(inData1), static_cast<float>(inData2) / 127.0f);
    } else if (type == 0x80 || (type == 0x90 && inData2 == 0)) {
        u->synth.noteOff(static_cast<int>(inData1));
    }
    return noErr;
}

OSStatus MUEWSysEx(void* self, const UInt8* inData, UInt32 inLength) {
    (void)self; (void)inData; (void)inLength;
    return noErr;
}

OSStatus MUEWStartNote(void* self, MusicDeviceInstrumentID inInstrument,
                       MusicDeviceGroupID inGroupID, NoteInstanceID* outNoteInstanceID,
                       UInt32 inOffsetSampleFrame, const MusicDeviceNoteParams* inParams) {
    (void)inInstrument; (void)inGroupID; (void)inOffsetSampleFrame;
    MUEWInstance* u = Self(self);
    int note = static_cast<int>(inParams->mPitch + 0.5f);
    float vel = inParams->mVelocity > 0 ? inParams->mVelocity / 127.0f : 0.8f;
    u->synth.noteOn(note, vel);
    if (outNoteInstanceID) *outNoteInstanceID = static_cast<NoteInstanceID>(note);
    return noErr;
}

OSStatus MUEWStopNote(void* self, MusicDeviceGroupID inGroupID, NoteInstanceID inNoteInstanceID,
                      UInt32 inOffsetSampleFrame) {
    (void)inGroupID; (void)inOffsetSampleFrame;
    Self(self)->synth.noteOff(static_cast<int>(inNoteInstanceID));
    return noErr;
}

OSStatus MUEWAddPropertyListener(void* self, AudioUnitPropertyID inID,
                                 AudioUnitPropertyListenerProc inProc, void* inProcUserData) {
    Self(self)->listeners.push_back({inID, inProc, inProcUserData});
    return noErr;
}

OSStatus MUEWRemovePropertyListener(void* self, AudioUnitPropertyID inID,
                                    AudioUnitPropertyListenerProc inProc) {
    auto& ls = Self(self)->listeners;
    for (auto it = ls.begin(); it != ls.end(); ++it)
        if (it->id == inID && it->proc == inProc) { ls.erase(it); break; }
    return noErr;
}

OSStatus MUEWRemovePropertyListenerWithUserData(void* self, AudioUnitPropertyID inID,
                                                AudioUnitPropertyListenerProc inProc,
                                                void* inProcUserData) {
    auto& ls = Self(self)->listeners;
    for (auto it = ls.begin(); it != ls.end(); ++it)
        if (it->id == inID && it->proc == inProc && it->userData == inProcUserData) { ls.erase(it); break; }
    return noErr;
}

AudioComponentMethod MUEWLookup(SInt16 selector) {
    switch (selector) {
        case kAudioUnitInitializeSelect:   return (AudioComponentMethod)MUEWInitialize;
        case kAudioUnitUninitializeSelect: return (AudioComponentMethod)MUEWUninitialize;
        case kAudioUnitGetPropertyInfoSelect: return (AudioComponentMethod)MUEWGetPropertyInfo;
        case kAudioUnitGetPropertySelect:  return (AudioComponentMethod)MUEWGetProperty;
        case kAudioUnitSetPropertySelect:  return (AudioComponentMethod)MUEWSetProperty;
        case kAudioUnitResetSelect:        return (AudioComponentMethod)MUEWReset;
        case kAudioUnitAddPropertyListenerSelect: return (AudioComponentMethod)MUEWAddPropertyListener;
        case kAudioUnitRemovePropertyListenerSelect: return (AudioComponentMethod)MUEWRemovePropertyListener;
        case kAudioUnitRemovePropertyListenerWithUserDataSelect: return (AudioComponentMethod)MUEWRemovePropertyListenerWithUserData;
        case kAudioUnitRenderSelect:       return (AudioComponentMethod)MUEWRender;
        case kMusicDeviceMIDIEventSelect:  return (AudioComponentMethod)MUEWMIDIEvent;
        case kMusicDeviceSysExSelect:      return (AudioComponentMethod)MUEWSysEx;
        case kMusicDeviceStartNoteSelect:  return (AudioComponentMethod)MUEWStartNote;
        case kMusicDeviceStopNoteSelect:   return (AudioComponentMethod)MUEWStopNote;
        default: return nullptr;
    }
}

} // namespace

extern "C" __attribute__((visibility("default")))
AudioComponentPlugInInterface* MUEWFactory(const AudioComponentDescription* inDesc) {
    (void)inDesc;
    MUEWInstance* inst = new (std::nothrow) MUEWInstance();
    if (!inst) return nullptr;
    inst->vtable.Open = MUEWOpen;
    inst->vtable.Close = MUEWClose;
    inst->vtable.Lookup = MUEWLookup;
    inst->vtable.reserved = nullptr;
    return &inst->vtable;
}
