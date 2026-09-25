// MUEWAU.cpp - MUEW as an Audio Unit v2 music device (instrument).
// Original implementation wrapping the MUEW DSP engine (src/synth.h).
#include "MUEWPluginInterface.h"
#include "synth.h"
#include "preset.h"
#include "factory_bank.h"
#include "MUEWProperties.h"
#include "au_params.h"

#include <AudioToolbox/AudioUnitProperties.h>
#include <AudioToolbox/MusicDevice.h>
#include <AudioToolbox/AudioUnitUtilities.h>
#include <CoreFoundation/CoreFoundation.h>
#include <cstring>
#include <new>
#include <algorithm>
#include <vector>
#include <mutex>
#include <atomic>
#include <cmath>
#include <string>
#include <mach/mach_time.h>

namespace {

constexpr OSType kSubType = 'Muew';
constexpr OSType kManufacturer = 'Inst';

struct Listener {
    AudioUnitPropertyID id;
    AudioUnitPropertyListenerProc proc;
    void* userData;
};

enum class EventKind { NoteOn, NoteOff, Wheel, Aftertouch, PolyAftertouch, Bend, Sustain, AllNotesOff }; // 0.24.0 performance events
struct ScheduledEvent {
    UInt32 offset;
    EventKind kind;
    int note;
    float velocity;
};

// Factory bank: the same authored presets the standalone app embeds
// (generated from presets/bank.txt; index = AU preset number).
static constexpr SInt32 kPresetCount = (SInt32)muew::kFactoryPresetCount;

static CFStringRef PresetName(SInt32 n) {
    static const std::vector<CFStringRef> names = [] {
        std::vector<CFStringRef> v;
        for (const auto& p : muew::factoryPresets())
            v.push_back(CFStringCreateWithCString(nullptr, p.info.name.c_str(), kCFStringEncodingUTF8));
        return v;
    }();
    return (n >= 0 && n < (SInt32)names.size() && names[n]) ? names[n] : CFSTR("Custom");
}

struct MUEWInstance {
    AudioComponentPlugInInterface vtable;
    AudioComponentInstance componentInstance = nullptr;
    muew::Synth synth{16};
    double sampleRate = 44100.0;
    UInt32 maxFrames = 512;
    UInt32 renderQuality = 0x7F;
    bool initialized = false;
    SInt32 presentPreset = 7;
    std::vector<Listener> listeners;
    // Render notifications (hosts and auval use these around each render
    // call, e.g. to schedule parameter changes).
    struct RenderNotify { AURenderCallback proc; void* userData; };
    std::vector<RenderNotify> renderNotifies;
    // Name a host gave a custom (-1) preset, kept for PresentPreset and ClassInfo.
    CFStringRef customName = nullptr;
    ~MUEWInstance() { if (customName) CFRelease(customName); }
    void setCustomName(CFStringRef n) {
        if (n) CFRetain(n);
        if (customName) CFRelease(customName);
        customName = n;
    }
    // Retained name of the current sound; caller releases.
    CFStringRef copyCurrentName(SInt32 number) {
        if (number < 0 && customName) return (CFStringRef)CFRetain(customName);
        return (CFStringRef)CFRetain(PresetName(number));
    }
    // Current sound. Host/UI threads write it under stateLock; the render
    // thread picks up changes at the top of the next block, so the engine is
    // never modified while it is rendering.
    std::mutex stateLock;
    muew::Preset state = muew::factoryPresets()[7]; // Warm Pad power-on sound
    bool stateDirty = true;
    std::atomic<UInt32> generation{1};
    // Host-facing parameter values (automation, MIDI mapping). Any thread may
    // set them without locking, including a host's render thread; they are
    // folded into `state` under stateLock at the next block or state read.
    std::atomic<float> paramValues[muew::params::Count];
    // 0.24.0: performance controls as last applied on the render thread (editor meters).
    std::atomic<float> perfWheel{0}, perfAT{0}, perfBend{0};
    std::atomic<int> perfNote{-1};
    std::atomic<unsigned> perfSustain{0};
    // 0.25.0: arp state after each block (editor step display).
    std::atomic<unsigned> arpOn{0};
    std::atomic<int> arpStep{0}, arpIndex{0}, arpNote{-1}, arpPoolN{0};
    std::atomic<int> arpPool[8] = {};
    std::atomic<int> arpPatCell{-1}; std::atomic<unsigned> hostLocked{0}; // 0.26.0
    std::atomic<bool> paramsDirty{false};
    // 0.30.0 Engine HQ: offline bounces render HQ; the editor meter reads voices and CPU load.
    std::atomic<bool> offline{false};
    std::atomic<float> cpuLoad{0};
    std::atomic<int> activeVoices{0}, voiceLimit{16};
    std::atomic<unsigned> oscHQ{0};
    std::atomic<float> liveMorph[2]{{-1.0f}, {-1.0f}}; // 0.35.0 editor morph meter
    std::atomic<float> voiceMorph[2][8]{};              // 0.36.0 per-voice ghosts
    std::atomic<UInt32> voiceMorphN[2]{{0u}, {0u}};
    std::atomic<float> routeMeter[muew::kMaxRoutes]{}; // 0.54.0 block peaks
    double cpuSmooth = 0.0;
    double notifiedLatency = 0.0; // samples, as last announced to the host
    // Samples the current sound runs late (oscillator HQ 7.5, HQ distortion 22.5).
    static double latencyOf(const muew::Preset& s, bool off) {
        const double osc = (s.voice.oscQuality == 1 || off) ? muew::Voice::kHQLatency : 0.0;
        const bool dist = s.fx.dist.enabled && s.fx.dist.mode != 2 && (s.fx.dist.quality == 1 || off);
        return osc + (dist ? muew::Distortion::kHQLatencyExact : 0.0);
    }
    double latencySamples() { std::lock_guard<std::mutex> g(stateLock); return latencyOf(state, offline.load()); }

    MUEWInstance() { syncParamsFromState(); }
    std::vector<ScheduledEvent> events;
    // Host transport callbacks (tempo for synced LFOs). Zeroed = no host info.
    HostCallbackInfo hostCallbacks{};

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

    // stateLock held (or no other thread yet).
    void syncParamsFromState() {
        for (int id = 0; id < muew::params::Count; ++id)
            paramValues[id].store(static_cast<float>(muew::params::get(state, id)));
        paramsDirty.store(false);
    }

    // stateLock held. Moves pending parameter changes into the sound. A real
    // change makes the sound custom (no longer a factory preset).
    void foldParams() {
        if (!paramsDirty.exchange(false)) return;
        bool changed = false;
        for (int id = 0; id < muew::params::Count; ++id) {
            float v = paramValues[id].load();
            if (static_cast<float>(muew::params::get(state, id)) != v) {
                muew::params::set(state, id, v);
                changed = true;
            }
        }
        if (changed) { stateDirty = true; presentPreset = -1; }
    }

    void setState(const muew::Preset& p, SInt32 number) {
        std::lock_guard<std::mutex> g(stateLock);
        state = p;
        presentPreset = number;
        stateDirty = true;
        syncParamsFromState();
        ++generation;
    }

    float getParameter(int id) { return paramValues[id].load(); }

    void setParameter(int id, float v) {
        v = static_cast<float>(muew::params::clampValue(id, v));
        if (paramValues[id].exchange(v) != v) {
            paramsDirty.store(true);
            ++generation;
        }
    }

    // Render thread: never blocks. Host thread (initialize/reset): blocks.
    void applyPendingState(bool block) {
        std::unique_lock<std::mutex> g(stateLock, std::defer_lock);
        if (block) g.lock(); else if (!g.try_lock()) return;
        foldParams();
        if (synth.renderHQ() != offline.load()) synth.setRenderHQ(offline.load()); // 0.30.0
        if (!stateDirty) return;
        voiceLimit = state.voice.voiceMode != 0 ? 1 : std::clamp(state.voice.polyVoices, 1, 16);
        synth.setTables(state.tables[0], state.tables[1]);
        synth.setParams(state.voice, state.routes);
        synth.setFX(state.fx);
        stateDirty = false;
    }

    bool loadFactoryPreset(SInt32 number) {
        const auto& bank = muew::factoryPresets();
        if (number < 0 || number >= (SInt32)bank.size()) return false;
        setState(bank[number], number);
        return true;
    }

    SInt32 currentPresetNumber() { std::lock_guard<std::mutex> g(stateLock); foldParams(); return presentPreset; }
    std::string stateText() { std::lock_guard<std::mutex> g(stateLock); foldParams(); return state.serialize(); }
};

MUEWInstance* Self(void* self) { return reinterpret_cast<MUEWInstance*>(self); }

bool ParseStateString(CFStringRef str, muew::Preset& out) {
    CFIndex len = CFStringGetLength(str);
    CFIndex max = CFStringGetMaximumSizeForEncoding(len, kCFStringEncodingUTF8) + 1;
    // 0.36.0 fix1: the cap was 1 MB of worst-case UTF-8 (3 bytes per character), which a
    // sound with two full 64-frame tables (~410k characters) exceeded, so hosts could not
    // restore it. 16 MB leaves room for any MUEW state.
    if (max <= 1 || max > (1 << 24)) return false;
    std::string buf(static_cast<size_t>(max), '\0');
    if (!CFStringGetCString(str, &buf[0], max, kCFStringEncodingUTF8)) return false;
    buf.resize(std::strlen(buf.c_str()));
    return out.parse(buf);
}

void NotifyListeners(MUEWInstance* u, AudioUnitPropertyID id, AudioUnitScope scope, AudioUnitElement elem) {
    for (auto& l : u->listeners)
        l.proc(l.userData, u->componentInstance, id, scope, elem);
}

// Tells the host (automation lanes, generic views) that every parameter may
// have a new value, after a preset load or state recall.
// 0.30.0: tell the host when the sound's latency changed (QUALITY, DIST HQ, offline render).
void SyncLatency(MUEWInstance* u) {
    const double l = u->latencySamples();
    if (l == u->notifiedLatency) return;
    u->notifiedLatency = l;
    NotifyListeners(u, kAudioUnitProperty_Latency, kAudioUnitScope_Global, 0);
}
void NotifyAllParameters(MUEWInstance* u) {
    for (int id = 0; id < muew::params::Count; ++id) {
        AudioUnitParameter p{u->componentInstance, static_cast<AudioUnitParameterID>(id), kAudioUnitScope_Global, 0};
        AUParameterListenerNotify(nullptr, nullptr, &p);
    }
}

AudioUnitParameterUnit UnitFor(muew::params::Unit unit) {
    switch (unit) {
        case muew::params::Percent: return kAudioUnitParameterUnit_Percent;
        case muew::params::Hertz: return kAudioUnitParameterUnit_Hertz;
        case muew::params::Semitones: return kAudioUnitParameterUnit_RelativeSemiTones;
        case muew::params::Seconds: return kAudioUnitParameterUnit_Seconds;
        default: return kAudioUnitParameterUnit_Generic;
    }
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
    { std::lock_guard<std::mutex> g(u->stateLock); u->stateDirty = true; }
    u->applyPendingState(true); // keep whatever sound the host restored
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
        case kAudioUnitProperty_FactoryPresets:
            if (inScope == kAudioUnitScope_Global) {
                *outDataSize = sizeof(CFArrayRef); return noErr;
            }
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
        case kAudioUnitProperty_ParameterList:
            *outDataSize = inScope == kAudioUnitScope_Global ? muew::params::Count * sizeof(AudioUnitParameterID) : 0;
            return noErr;
        case kAudioUnitProperty_ParameterInfo:
            if (inScope != kAudioUnitScope_Global) return kAudioUnitErr_InvalidScope;
            if (!muew::params::valid(static_cast<int>(inElement))) return kAudioUnitErr_InvalidParameter;
            *outDataSize = sizeof(AudioUnitParameterInfo);
            return noErr;
        case kAudioUnitProperty_CocoaUI:
            if (inScope == kAudioUnitScope_Global) {
                *outDataSize = sizeof(AudioUnitCocoaViewInfo); if (outWritable) *outWritable = false; return noErr;
            }
            break;
        case kMUEWProperty_PresetState:
            if (inScope == kAudioUnitScope_Global) {
                *outDataSize = sizeof(CFStringRef); if (outWritable) *outWritable = true; return noErr;
            }
            break;
        case kMUEWProperty_StateGeneration:
            if (inScope == kAudioUnitScope_Global) {
                *outDataSize = sizeof(UInt32); if (outWritable) *outWritable = false; return noErr;
            }
            break;
        case kMUEWProperty_Performance: // 0.24.0
            if (inScope == kAudioUnitScope_Global) {
                *outDataSize = sizeof(MUEWPerformance); if (outWritable) *outWritable = false; return noErr;
            }
            break;
        case kAudioUnitProperty_OfflineRender: // 0.30.0
            if (inScope == kAudioUnitScope_Global) {
                *outDataSize = sizeof(UInt32); if (outWritable) *outWritable = true; return noErr;
            }
            break;
        case kAudioUnitProperty_HostCallbacks:
            if (inScope == kAudioUnitScope_Global) {
                *outDataSize = sizeof(HostCallbackInfo); if (outWritable) *outWritable = true; return noErr;
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
                *static_cast<Float64*>(outData) = u->latencySamples() / u->sampleRate; *ioDataSize = sizeof(Float64); return noErr; // 0.30.0
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
        case kAudioUnitProperty_FactoryPresets:
            if (inScope == kAudioUnitScope_Global && *ioDataSize >= sizeof(CFArrayRef)) {
                static AUPreset presets[kPresetCount];
                static const void* values[kPresetCount];
                static bool ready = false;
                if (!ready) {
                    for (SInt32 i = 0; i < kPresetCount; ++i) {
                        presets[i].presetNumber = i;
                        presets[i].presetName = PresetName(i);
                        values[i] = &presets[i];
                    }
                    ready = true;
                }
                CFArrayRef array = CFArrayCreate(nullptr, values, kPresetCount, nullptr);
                *static_cast<CFArrayRef*>(outData) = array;
                *ioDataSize = sizeof(CFArrayRef);
                return noErr;
            }
            break;
        case kAudioUnitProperty_PresentPreset:
            if (inScope == kAudioUnitScope_Global && *ioDataSize >= sizeof(AUPreset)) {
                AUPreset* p = static_cast<AUPreset*>(outData);
                p->presetNumber = u->currentPresetNumber();
                // AU convention: the caller owns and releases presetName.
                // Names are created CFStrings now (not CFSTR literals), so
                // hand out a retained reference or hosts over-release it.
                p->presetName = u->copyCurrentName(p->presetNumber);
                *ioDataSize = sizeof(AUPreset);
                return noErr;
            }
            break;
        case kAudioUnitProperty_ClassInfo:
            if (inScope == kAudioUnitScope_Global && *ioDataSize >= sizeof(CFPropertyListRef)) {
                // auval requires the component identity fields plus our state.
                UInt32 type = kAudioUnitType_MusicDevice, sub = kSubType, mfr = kManufacturer;
                CFStringRef keys[] = {CFSTR("type"), CFSTR("subtype"), CFSTR("manufacturer"),
                                      CFSTR("name"), CFSTR("version"), CFSTR("presetNumber"), CFSTR("renderQuality"),
                                      CFSTR("muewState")};
                CFNumberRef t = CFNumberCreate(nullptr, kCFNumberIntType, &type);
                CFNumberRef st = CFNumberCreate(nullptr, kCFNumberIntType, &sub);
                CFNumberRef m = CFNumberCreate(nullptr, kCFNumberIntType, &mfr);
                SInt32 ver = 0x00010000;
                CFNumberRef v = CFNumberCreate(nullptr, kCFNumberSInt32Type, &ver);
                SInt32 presetNumber = u->currentPresetNumber();
                CFNumberRef num = CFNumberCreate(nullptr, kCFNumberSInt32Type, &presetNumber);
                CFNumberRef rq = CFNumberCreate(nullptr, kCFNumberSInt32Type, &u->renderQuality);
                // Full sound, so knob edits made in the editor survive a project reload.
                CFStringRef stateStr = CFStringCreateWithCString(nullptr, u->stateText().c_str(), kCFStringEncodingUTF8);
                CFStringRef nameStr = u->copyCurrentName(presetNumber); // the preset name, as hosts expect
                CFTypeRef vals[] = {t, st, m, nameStr, v, num, rq, stateStr};
                CFDictionaryRef dict = CFDictionaryCreate(nullptr, (const void**)keys, (const void**)vals, 8,
                    &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
                CFRelease(t); CFRelease(st); CFRelease(m); CFRelease(v); CFRelease(num); CFRelease(rq); CFRelease(stateStr); CFRelease(nameStr);
                *static_cast<CFPropertyListRef*>(outData) = dict; // caller releases
                *ioDataSize = sizeof(CFPropertyListRef);
                return noErr;
            }
            break;
        case kAudioUnitProperty_ParameterList: {
            UInt32 need = inScope == kAudioUnitScope_Global ? muew::params::Count * sizeof(AudioUnitParameterID) : 0;
            if (*ioDataSize < need) return kAudioUnitErr_InvalidPropertyValue;
            AudioUnitParameterID* ids = static_cast<AudioUnitParameterID*>(outData);
            for (UInt32 i = 0; i < need / sizeof(AudioUnitParameterID); ++i) ids[i] = i;
            *ioDataSize = need;
            return noErr;
        }
        case kAudioUnitProperty_ParameterInfo: {
            if (inScope != kAudioUnitScope_Global) return kAudioUnitErr_InvalidScope;
            int id = static_cast<int>(inElement);
            if (!muew::params::valid(id)) return kAudioUnitErr_InvalidParameter;
            if (*ioDataSize < sizeof(AudioUnitParameterInfo)) return kAudioUnitErr_InvalidPropertyValue;
            const muew::params::Def& d = muew::params::def(id);
            AudioUnitParameterInfo* info = static_cast<AudioUnitParameterInfo*>(outData);
            std::memset(info, 0, sizeof(*info));
            std::strncpy(info->name, d.name, sizeof(info->name) - 1);
            info->cfNameString = CFStringCreateWithCString(nullptr, d.name, kCFStringEncodingUTF8); // host releases (CFNameRelease)
            info->unit = UnitFor(d.unit);
            info->minValue = static_cast<AudioUnitParameterValue>(d.lo);
            info->maxValue = static_cast<AudioUnitParameterValue>(d.hi);
            info->defaultValue = static_cast<AudioUnitParameterValue>(muew::params::defaultValue(id));
            info->flags = kAudioUnitParameterFlag_IsReadable | kAudioUnitParameterFlag_IsWritable |
                          kAudioUnitParameterFlag_HasCFNameString | kAudioUnitParameterFlag_CFNameRelease |
                          (d.log ? kAudioUnitParameterFlag_DisplayLogarithmic : 0);
            *ioDataSize = sizeof(AudioUnitParameterInfo);
            return noErr;
        }
        case kAudioUnitProperty_CocoaUI:
            if (inScope == kAudioUnitScope_Global && *ioDataSize >= sizeof(AudioUnitCocoaViewInfo)) {
                CFBundleRef bundle = CFBundleGetBundleWithIdentifier(CFSTR(MUEW_AU_BUNDLE_ID));
                if (!bundle) return kAudioUnitErr_InvalidProperty;
                AudioUnitCocoaViewInfo* info = static_cast<AudioUnitCocoaViewInfo*>(outData);
                info->mCocoaAUViewBundleLocation = CFBundleCopyBundleURL(bundle);               // caller releases
                info->mCocoaAUViewClass[0] = CFStringCreateWithCString(nullptr, MUEW_VIEW_FACTORY_CLASS,
                                                                       kCFStringEncodingUTF8); // caller releases
                *ioDataSize = sizeof(AudioUnitCocoaViewInfo);
                return noErr;
            }
            break;
        case kMUEWProperty_PresetState:
            if (inScope == kAudioUnitScope_Global && *ioDataSize >= sizeof(CFStringRef)) {
                *static_cast<CFStringRef*>(outData) =
                    CFStringCreateWithCString(nullptr, u->stateText().c_str(), kCFStringEncodingUTF8); // caller releases
                *ioDataSize = sizeof(CFStringRef);
                return noErr;
            }
            break;
        case kMUEWProperty_StateGeneration:
            if (inScope == kAudioUnitScope_Global && *ioDataSize >= sizeof(UInt32)) {
                std::lock_guard<std::mutex> g(u->stateLock);
                *static_cast<UInt32*>(outData) = u->generation;
                *ioDataSize = sizeof(UInt32);
                return noErr;
            }
            break;
        case kAudioUnitProperty_OfflineRender: // 0.30.0
            if (inScope == kAudioUnitScope_Global) {
                *static_cast<UInt32*>(outData) = u->offline.load() ? 1 : 0; *ioDataSize = sizeof(UInt32); return noErr;
            }
            break;
        case kMUEWProperty_Performance: // 0.24.0
            if (inScope == kAudioUnitScope_Global && *ioDataSize >= sizeof(MUEWPerformance)) {
                MUEWPerformance pf{u->perfWheel.load(), u->perfAT.load(), u->perfBend.load(), u->perfNote.load(), u->perfSustain.load(),
                                   u->arpOn.load(), u->arpStep.load(), u->arpIndex.load(), u->arpNote.load(), u->arpPoolN.load(), {},
                                   u->arpPatCell.load(), u->hostLocked.load(),
                                   (UInt32)u->activeVoices.load(), (UInt32)u->voiceLimit.load(), u->cpuLoad.load(),
                                   u->oscHQ.load(), u->offline.load() ? 1u : 0u, // 0.30.0
                                   {u->liveMorph[0].load(), u->liveMorph[1].load()}}; // 0.35.0
                for (int i = 0; i < 8; ++i) pf.pool[i] = u->arpPool[i].load();
                for (int o = 0; o < 2; ++o) { // 0.36.0
                    pf.voiceMorphCount[o] = u->voiceMorphN[o].load();
                    for (int i = 0; i < 8; ++i) pf.voiceMorph[o][i] = u->voiceMorph[o][i].load();
                }
                for (int i = 0; i < muew::kMaxRoutes; ++i) pf.routeMeter[i] = u->routeMeter[i].load();
                *static_cast<MUEWPerformance*>(outData) = pf;
                *ioDataSize = sizeof(MUEWPerformance);
                return noErr;
            }
            break;
        case kAudioUnitProperty_HostCallbacks:
            if (inScope == kAudioUnitScope_Global && *ioDataSize >= sizeof(HostCallbackInfo)) {
                std::memcpy(outData, &u->hostCallbacks, sizeof(HostCallbackInfo));
                *ioDataSize = sizeof(HostCallbackInfo); return noErr;
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
        case kAudioUnitProperty_HostCallbacks:
            if (inScope != kAudioUnitScope_Global) return kAudioUnitErr_InvalidScope;
            // Hosts may pass an older, shorter struct; copy what they gave.
            std::memset(&u->hostCallbacks, 0, sizeof(HostCallbackInfo));
            if (inData) std::memcpy(&u->hostCallbacks, inData, std::min<size_t>(inDataSize, sizeof(HostCallbackInfo)));
            return noErr;
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
        case kAudioUnitProperty_OfflineRender: // 0.30.0: a bounce renders HQ
            if (inScope == kAudioUnitScope_Global && inDataSize >= sizeof(UInt32)) {
                u->offline = *static_cast<const UInt32*>(inData) != 0;
                NotifyListeners(u, kAudioUnitProperty_OfflineRender, kAudioUnitScope_Global, 0);
                SyncLatency(u);
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
                if (p->presetNumber < 0) {
                    { std::lock_guard<std::mutex> g(u->stateLock); u->presentPreset = -1; } // host-applied custom state
                    if (p->presetName && CFGetTypeID(p->presetName) == CFStringGetTypeID()) u->setCustomName(p->presetName);
                } else {
                    if (p->presetNumber >= kPresetCount || !u->loadFactoryPreset(p->presetNumber))
                        return kAudioUnitErr_InvalidPropertyValue;
                }
                NotifyListeners(u, kAudioUnitProperty_PresentPreset, kAudioUnitScope_Global, 0); SyncLatency(u);
                NotifyAllParameters(u);
                return noErr;
            }
            break;
        case kAudioUnitProperty_ClassInfo:
            if (inScope == kAudioUnitScope_Global && inDataSize >= sizeof(CFPropertyListRef)) {
                CFPropertyListRef plist = *static_cast<const CFPropertyListRef*>(inData);
                if (plist && CFGetTypeID(plist) == CFDictionaryGetTypeID()) {
                    CFDictionaryRef dict = (CFDictionaryRef)plist;
                    SInt32 n = -1;
                    CFNumberRef num = (CFNumberRef)CFDictionaryGetValue(dict, CFSTR("presetNumber"));
                    if (num && CFGetTypeID(num) == CFNumberGetTypeID()) CFNumberGetValue(num, kCFNumberSInt32Type, &n);
                    if (n < 0 || n >= kPresetCount) n = -1;
                    CFStringRef savedName = (CFStringRef)CFDictionaryGetValue(dict, CFSTR("name"));
                    if (n < 0 && savedName && CFGetTypeID(savedName) == CFStringGetTypeID()) u->setCustomName(savedName);
                    muew::Preset saved;
                    CFStringRef stateStr = (CFStringRef)CFDictionaryGetValue(dict, CFSTR("muewState"));
                    if (stateStr && CFGetTypeID(stateStr) == CFStringGetTypeID() && ParseStateString(stateStr, saved))
                        u->setState(saved, n);          // 0.4+: exact sound, edits included
                    else if (n >= 0)
                        u->loadFactoryPreset(n);        // 0.3 and earlier: preset number only
                    NotifyListeners(u, kAudioUnitProperty_PresentPreset, kAudioUnitScope_Global, 0); SyncLatency(u);
                    NotifyAllParameters(u);
                }
                return noErr;
            }
            break;
        case kMUEWProperty_PresetState:
            if (inScope == kAudioUnitScope_Global && inDataSize >= sizeof(CFStringRef)) {
                CFStringRef str = *static_cast<const CFStringRef*>(inData);
                muew::Preset p;
                if (!str || CFGetTypeID(str) != CFStringGetTypeID() || !ParseStateString(str, p))
                    return kAudioUnitErr_InvalidPropertyValue;
                u->setState(p, -1); // an edited sound is no longer a factory preset
                NotifyListeners(u, kAudioUnitProperty_PresentPreset, kAudioUnitScope_Global, 0); SyncLatency(u);
                NotifyAllParameters(u);
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
    u->synth.init(u->sampleRate); // clears voices and tails; the sound stays
    { std::lock_guard<std::mutex> g(u->stateLock); u->stateDirty = true; }
    u->applyPendingState(true);
    return noErr;
}

OSStatus MUEWRender(void* self, AudioUnitRenderActionFlags* ioActionFlags,
                    const AudioTimeStamp* inTimeStamp, UInt32 inOutputBusNumber,
                    UInt32 inNumberFrames, AudioBufferList* ioData) {
    MUEWInstance* u = Self(self);
    if (!u->initialized) return kAudioUnitErr_Uninitialized;
    if (inOutputBusNumber != 0) return kAudioUnitErr_InvalidElement;
    if (inNumberFrames > u->maxFrames) return kAudioUnitErr_TooManyFramesToProcess;
    if (!ioData || ioData->mNumberBuffers < 2) return kAudioUnitErr_InvalidPropertyValue;

    AudioUnitRenderActionFlags notifyFlags = (ioActionFlags ? *ioActionFlags : 0) | kAudioUnitRenderAction_PreRender;
    for (const auto& n : u->renderNotifies)
        n.proc(n.userData, &notifyFlags, inTimeStamp, inOutputBusNumber, inNumberFrames, ioData);
    const uint64_t t0 = mach_absolute_time(); // 0.30.0 CPU meter
    u->applyPendingState(false);
    if (u->hostCallbacks.beatAndTempoProc) {
        Float64 beat = 0, tempo = 0;
        if (u->hostCallbacks.beatAndTempoProc(u->hostCallbacks.hostUserData, &beat, &tempo) == noErr && tempo > 0) {
            u->synth.setTempo(tempo);
            // 0.26.0 clock sync: the arp grid and synced LFOs follow the host
            // bar while its transport plays. No transport callback = free clock.
            Boolean playing = false;
            if (u->hostCallbacks.transportStateProc2) {
                Boolean changed = false, cycling = false, recording = false; Float64 sample = 0, cs = 0, ce = 0;
                if (u->hostCallbacks.transportStateProc2(u->hostCallbacks.hostUserData, &playing, &recording, &changed, &sample, &cycling, &cs, &ce) != noErr) playing = false;
            } else if (u->hostCallbacks.transportStateProc) {
                Boolean changed = false, cycling = false; Float64 sample = 0, cs = 0, ce = 0;
                if (u->hostCallbacks.transportStateProc(u->hostCallbacks.hostUserData, &playing, &changed, &sample, &cycling, &cs, &ce) != noErr) playing = false;
            }
            u->synth.setTransport(beat, playing);
        } else u->synth.setTransport(0.0, false);
    } else u->synth.setTransport(0.0, false);
    float* left = static_cast<float*>(ioData->mBuffers[0].mData);
    float* right = static_cast<float*>(ioData->mBuffers[1].mData);
    // Never set kAudioUnitRenderAction_OutputIsSilence: hosts may answer that
    // flag with null buffers next cycle, and the engine's FX tail still counts
    // as active output. If a host hands null buffers anyway, render into a
    // scratch buffer and drop it.
    static thread_local std::vector<float> scratch;
    if (!left || !right) {
        if (scratch.size() < inNumberFrames * 2) scratch.resize(inNumberFrames * 2, 0.0f);
        left = scratch.data();
        right = scratch.data() + inNumberFrames;
    }
    std::stable_sort(u->events.begin(), u->events.end(), [](const ScheduledEvent& a, const ScheduledEvent& b) {
        return a.offset < b.offset;
    });
    UInt32 cursor = 0;
    size_t consumed = 0;
    while (consumed < u->events.size() && u->events[consumed].offset < inNumberFrames) {
        UInt32 at = u->events[consumed].offset;
        if (at > cursor) u->synth.renderPlanar(left + cursor, right + cursor, static_cast<int>(at - cursor));
        do {
            const auto& e = u->events[consumed];
            switch (e.kind) {
            case EventKind::NoteOn: u->synth.noteOn(e.note, e.velocity); break;
            case EventKind::NoteOff: u->synth.noteOff(e.note); break;
            case EventKind::Wheel: u->synth.setModWheel(e.velocity); break;
            case EventKind::Aftertouch: u->synth.setAftertouch(e.velocity); break;
            case EventKind::PolyAftertouch: u->synth.setPolyAftertouch(e.note, e.velocity); break;
            case EventKind::Bend: u->synth.setPitchBend(e.velocity); break;
            case EventKind::Sustain: u->synth.setSustain(e.velocity > 0.5f); break;
            case EventKind::AllNotesOff: u->synth.allNotesOff(); break;
            }
            ++consumed;
        } while (consumed < u->events.size() && u->events[consumed].offset == at);
        cursor = at;
    }
    if (cursor < inNumberFrames)
        u->synth.renderPlanar(left + cursor, right + cursor, static_cast<int>(inNumberFrames - cursor));
    if (consumed > 0) { // 0.24.0 meters
        const auto& pf = u->synth.performance();
        u->perfWheel = (float)pf.wheel; u->perfAT = (float)pf.aftertouch; u->perfBend = (float)pf.bend;
        u->perfNote = u->synth.lastNote(); u->perfSustain = u->synth.sustain() ? 1u : 0u;
    }
    if (u->synth.arpOn() || u->arpOn.load()) { // 0.25.0 arp display
        const auto& sy = u->synth;
        u->arpOn = sy.arpOn() ? 1u : 0u; u->arpStep = sy.arpStep(); u->arpIndex = sy.arpCycleIndex(); u->arpNote = sy.arpSoundingNote();
        const int n = sy.arpPoolCount(); u->arpPoolN = n;
        for (int i = 0; i < 8; ++i) u->arpPool[i] = i < n ? sy.arpPoolNote(i) : -1;
        u->arpPatCell = sy.arpPatternStep();
    }
    u->hostLocked = u->synth.hostLocked() ? 1u : 0u; // 0.26.0
    { // 0.30.0 voice / CPU meter: share of the block's real-time budget spent rendering it
        static const double tick = [] { mach_timebase_info_data_t tb; mach_timebase_info(&tb); return (double)tb.numer / tb.denom * 1e-9; }();
        const double used = (double)(mach_absolute_time() - t0) * tick, budget = inNumberFrames / u->sampleRate;
        if (budget > 0) { u->cpuSmooth += 0.1 * (std::min(used / budget, 4.0) - u->cpuSmooth); u->cpuLoad = (float)u->cpuSmooth; }
        u->activeVoices = u->synth.activeVoiceCount();
        u->liveMorph[0] = u->synth.specMorphMeter(0); u->liveMorph[1] = u->synth.specMorphMeter(1); // 0.35.0
        for (int o = 0; o < 2; ++o) { // 0.36.0 per-voice ghosts
            float vm[8]; const int n = u->synth.specMorphVoices(o, vm, 8);
            for (int i = 0; i < 8; ++i) u->voiceMorph[o][i] = i < n ? vm[i] : -1.0f;
            u->voiceMorphN[o] = (UInt32)n;
        }
        for (int i = 0; i < muew::kMaxRoutes; ++i) u->routeMeter[i] = u->synth.routeMeter(i);
        u->oscHQ = u->synth.oscHQ() ? 1u : 0u;
    }
    u->events.erase(u->events.begin(), u->events.begin() + static_cast<long>(consumed));
    for (auto& e : u->events) e.offset -= inNumberFrames;
    notifyFlags = (ioActionFlags ? *ioActionFlags : 0) | kAudioUnitRenderAction_PostRender;
    for (const auto& n : u->renderNotifies)
        n.proc(n.userData, &notifyFlags, inTimeStamp, inOutputBusNumber, inNumberFrames, ioData);
    return noErr;
}

// ---- Parameters ----

OSStatus MUEWGetParameter(void* self, AudioUnitParameterID inID, AudioUnitScope inScope,
                          AudioUnitElement inElement, AudioUnitParameterValue* outValue) {
    (void)inElement;
    if (inScope != kAudioUnitScope_Global) return kAudioUnitErr_InvalidScope;
    if (!muew::params::valid(static_cast<int>(inID))) return kAudioUnitErr_InvalidParameter;
    if (!outValue) return kAudio_ParamError;
    *outValue = Self(self)->getParameter(static_cast<int>(inID));
    return noErr;
}

OSStatus MUEWSetParameter(void* self, AudioUnitParameterID inID, AudioUnitScope inScope,
                          AudioUnitElement inElement, AudioUnitParameterValue inValue,
                          UInt32 inBufferOffsetInFrames) {
    (void)inElement; (void)inBufferOffsetInFrames; // applied at block start
    if (inScope != kAudioUnitScope_Global) return kAudioUnitErr_InvalidScope;
    if (!muew::params::valid(static_cast<int>(inID))) return kAudioUnitErr_InvalidParameter;
    Self(self)->setParameter(static_cast<int>(inID), inValue);
    return noErr;
}

OSStatus MUEWScheduleParameters(void* self, const AudioUnitParameterEvent* inEvents, UInt32 inNumEvents) {
    for (UInt32 i = 0; i < inNumEvents; ++i) {
        const AudioUnitParameterEvent& e = inEvents[i];
        if (e.scope != kAudioUnitScope_Global) return kAudioUnitErr_InvalidScope;
        if (!muew::params::valid(static_cast<int>(e.parameter))) return kAudioUnitErr_InvalidParameter;
        float v = e.eventType == kParameterEvent_Ramped ? e.eventValues.ramp.endValue : e.eventValues.immediate.value;
        Self(self)->setParameter(static_cast<int>(e.parameter), v);
    }
    return noErr;
}

// ---- MusicDevice methods ----

OSStatus MUEWMIDIEvent(void* self, UInt32 inStatus, UInt32 inData1, UInt32 inData2,
                       UInt32 inOffsetSampleFrame) {
    MUEWInstance* u = Self(self);
    UInt32 type = inStatus & 0xF0;
    if (type == 0x90 && inData2 > 0) {
        u->events.push_back({inOffsetSampleFrame, EventKind::NoteOn, static_cast<int>(inData1), static_cast<float>(inData2) / 127.0f});
    } else if (type == 0x80 || (type == 0x90 && inData2 == 0)) {
        u->events.push_back({inOffsetSampleFrame, EventKind::NoteOff, static_cast<int>(inData1), 0.0f});
    } else if (type == 0xB0) { // 0.24.0 controllers: mod wheel, sustain, all notes / sound off
        if (inData1 == 1) u->events.push_back({inOffsetSampleFrame, EventKind::Wheel, 0, static_cast<float>(inData2 & 0x7F) / 127.0f});
        else if (inData1 == 64) u->events.push_back({inOffsetSampleFrame, EventKind::Sustain, 0, inData2 >= 64 ? 1.0f : 0.0f});
        else if (inData1 == 120 || inData1 == 123) u->events.push_back({inOffsetSampleFrame, EventKind::AllNotesOff, 0, 0.0f});
    } else if (type == 0xD0) { // channel pressure
        u->events.push_back({inOffsetSampleFrame, EventKind::Aftertouch, 0, static_cast<float>(inData1 & 0x7F) / 127.0f});
    } else if (type == 0xA0) { // polyphonic key pressure
        u->events.push_back({inOffsetSampleFrame, EventKind::PolyAftertouch, static_cast<int>(inData1 & 0x7F), static_cast<float>(inData2 & 0x7F) / 127.0f});
    } else if (type == 0xE0) { // pitch bend, 14 bit, 8192 = center
        const int raw = (static_cast<int>(inData2 & 0x7F) << 7) | static_cast<int>(inData1 & 0x7F);
        const float b = raw >= 8192 ? (raw - 8192) / 8191.0f : (raw - 8192) / 8192.0f;
        u->events.push_back({inOffsetSampleFrame, EventKind::Bend, 0, b});
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
    (void)inInstrument; (void)inGroupID;
    MUEWInstance* u = Self(self);
    int note = static_cast<int>(inParams->mPitch + 0.5f);
    float vel = inParams->mVelocity > 0 ? inParams->mVelocity / 127.0f : 0.8f;
    u->events.push_back({inOffsetSampleFrame, EventKind::NoteOn, note, vel});
    if (outNoteInstanceID) *outNoteInstanceID = static_cast<NoteInstanceID>(note);
    return noErr;
}

OSStatus MUEWStopNote(void* self, MusicDeviceGroupID inGroupID, NoteInstanceID inNoteInstanceID,
                      UInt32 inOffsetSampleFrame) {
    (void)inGroupID;
    Self(self)->events.push_back({inOffsetSampleFrame, EventKind::NoteOff, static_cast<int>(inNoteInstanceID), 0.0f});
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

OSStatus MUEWAddRenderNotify(void* self, AURenderCallback inProc, void* inProcUserData) {
    if (!inProc) return kAudio_ParamError;
    Self(self)->renderNotifies.push_back({inProc, inProcUserData});
    return noErr;
}

OSStatus MUEWRemoveRenderNotify(void* self, AURenderCallback inProc, void* inProcUserData) {
    auto& ns = Self(self)->renderNotifies;
    for (auto it = ns.begin(); it != ns.end(); ++it)
        if (it->proc == inProc && it->userData == inProcUserData) { ns.erase(it); break; }
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
        case kAudioUnitGetParameterSelect: return (AudioComponentMethod)MUEWGetParameter;
        case kAudioUnitSetParameterSelect: return (AudioComponentMethod)MUEWSetParameter;
        case kAudioUnitScheduleParametersSelect: return (AudioComponentMethod)MUEWScheduleParameters;
        case kAudioUnitAddRenderNotifySelect: return (AudioComponentMethod)MUEWAddRenderNotify;
        case kAudioUnitRemoveRenderNotifySelect: return (AudioComponentMethod)MUEWRemoveRenderNotify;
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
