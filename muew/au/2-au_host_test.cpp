// Host-level validation: discovery, factory presets, selection, sample-accurate MIDI and audio.
#include <AudioToolbox/AudioToolbox.h>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <vector>
#include <string>
#include "MUEWProperties.h"
#include "preset.h"
#include "au_params.h"

static AudioUnit openUnit() {
    AudioComponentDescription desc{};
    desc.componentType = kAudioUnitType_MusicDevice;
    desc.componentSubType = 'Muew';
    desc.componentManufacturer = 'Inst';
    AudioComponent comp = AudioComponentFindNext(nullptr, &desc);
    if (!comp) return nullptr;
    AudioUnit unit = nullptr;
    if (AudioComponentInstanceNew(comp, &unit) != noErr) return nullptr;
    AudioStreamBasicDescription fmt{};
    fmt.mSampleRate = 44100.0; fmt.mFormatID = kAudioFormatLinearPCM;
    fmt.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsNonInterleaved | kAudioFormatFlagsNativeEndian;
    fmt.mBytesPerPacket = fmt.mBytesPerFrame = sizeof(float); fmt.mFramesPerPacket = 1;
    fmt.mChannelsPerFrame = 2; fmt.mBitsPerChannel = 32;
    if (AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &fmt, sizeof(fmt)) != noErr ||
        AudioUnitInitialize(unit) != noErr) { AudioComponentInstanceDispose(unit); return nullptr; }
    return unit;
}

static bool getState(AudioUnit u, muew::Preset& out) {
    CFStringRef str = nullptr; UInt32 size = sizeof(str);
    if (AudioUnitGetProperty(u, kMUEWProperty_PresetState, kAudioUnitScope_Global, 0, &str, &size) != noErr || !str) return false;
    char buf[65536];
    bool ok = CFStringGetCString(str, buf, sizeof(buf), kCFStringEncodingUTF8);
    CFRelease(str);
    return ok && out.parse(buf);
}

static bool setState(AudioUnit u, const muew::Preset& p) {
    CFStringRef str = CFStringCreateWithCString(nullptr, p.serialize().c_str(), kCFStringEncodingUTF8);
    OSStatus st = AudioUnitSetProperty(u, kMUEWProperty_PresetState, kAudioUnitScope_Global, 0, &str, sizeof(str));
    CFRelease(str);
    return st == noErr;
}

static SInt32 presetNumber(AudioUnit u) {
    AUPreset p{}; UInt32 size = sizeof(p);
    if (AudioUnitGetProperty(u, kAudioUnitProperty_PresentPreset, kAudioUnitScope_Global, 0, &p, &size) != noErr) return -99;
    if (p.presetName) CFRelease(p.presetName);
    return p.presetNumber;
}

static bool render(AudioUnit u, std::vector<float>& l, std::vector<float>& r) {
    UInt32 frames = (UInt32)l.size();
    AudioBufferList* b = (AudioBufferList*)calloc(1, sizeof(AudioBufferList) + sizeof(AudioBuffer));
    b->mNumberBuffers=2; b->mBuffers[0]={1,static_cast<UInt32>(frames*sizeof(float)),l.data()}; b->mBuffers[1]={1,static_cast<UInt32>(frames*sizeof(float)),r.data()};
    AudioUnitRenderActionFlags flags=0; AudioTimeStamp ts{};
    bool ok=AudioUnitRender(u,&flags,&ts,0,frames,b)==noErr; free(b); return ok;
}

static constexpr int kExpectedPresets = 108; // 0.8.0 appended 38-41, 0.9.0 42-44, 0.10.0 45-48, 0.11.0 49-79, 0.32.0 80-103, 0.34.0 104-107

static double energy(const std::vector<float>& x, size_t a, size_t b) {
    double e=0; for(size_t i=a;i<b;++i)e+=double(x[i])*x[i]; return e;
}

int main() {
    AudioUnit unit=openUnit();
    if(!unit){printf("FAIL: discovery/initialize\n");return 1;}

    CFArrayRef presets=nullptr; UInt32 size=sizeof(presets);
    if(AudioUnitGetProperty(unit,kAudioUnitProperty_FactoryPresets,kAudioUnitScope_Global,0,&presets,&size)!=noErr || !presets || CFArrayGetCount(presets)!=kExpectedPresets){
        printf("FAIL: factory preset list\n"); return 1;
    }
    for(CFIndex i=0;i<kExpectedPresets;++i){
        auto* p=(const AUPreset*)CFArrayGetValueAtIndex(presets,i);
        if(!p || p->presetNumber!=i || !p->presetName){printf("FAIL: preset %ld\n",(long)i);return 1;}
    }
    {
        auto nameIs=[&](CFIndex i,CFStringRef want){auto* p=(const AUPreset*)CFArrayGetValueAtIndex(presets,i);return p&&CFStringCompare(p->presetName,want,0)==kCFCompareEqualTo;};
        if(!nameIs(3,CFSTR("Pluck"))||!nameIs(7,CFSTR("Warm Pad"))||!nameIs(16,CFSTR("Night Bloom"))){printf("FAIL: factory preset names/order\n");return 1;}
    }
    CFRelease(presets);
    AUPreset chosen{3,CFSTR("Pluck")};
    if(AudioUnitSetProperty(unit,kAudioUnitProperty_PresentPreset,kAudioUnitScope_Global,0,&chosen,sizeof(chosen))!=noErr){printf("FAIL: select preset\n");return 1;}
    AUPreset current{}; size=sizeof(current);
    if(AudioUnitGetProperty(unit,kAudioUnitProperty_PresentPreset,kAudioUnitScope_Global,0,&current,&size)!=noErr || current.presetNumber!=3){printf("FAIL: selected preset identity\n");return 1;}
    if(current.presetName) CFRelease(current.presetName); // hosts own the returned name
    size=sizeof(current);
    if(AudioUnitGetProperty(unit,kAudioUnitProperty_PresentPreset,kAudioUnitScope_Global,0,&current,&size)!=noErr || !current.presetName || CFStringCompare(current.presetName,CFSTR("Pluck"),0)!=kCFCompareEqualTo){printf("FAIL: preset name after host release\n");return 1;}
    CFRelease(current.presetName);

    const UInt32 frames=512, offset=257;
    std::vector<float> l(frames),r(frames);
    if(MusicDeviceMIDIEvent(unit,0x90,69,110,offset)!=noErr || !render(unit,l,r)){printf("FAIL: scheduled render\n");return 1;}
    double before=energy(l,0,offset)+energy(r,0,offset);
    double after=energy(l,offset,frames)+energy(r,offset,frames);
    printf("factory presets: %d; selected: Pluck\n",kExpectedPresets);
    printf("timing energy before=%g after=%g offset=%u\n",before,after,offset);
    if(before>1e-14 || after<1e-8){printf("FAIL: note offset timing\n");return 1;}

    MusicDeviceMIDIEvent(unit,0x80,69,0,111);
    std::fill(l.begin(),l.end(),0); std::fill(r.begin(),r.end(),0);
    if(!render(unit,l,r)){printf("FAIL: note-off render\n");return 1;}

    // Every factory preset selects and sounds through the host path.
    for(SInt32 n=0;n<kExpectedPresets;++n){
        AUPreset sel{n,nullptr};
        if(AudioUnitSetProperty(unit,kAudioUnitProperty_PresentPreset,kAudioUnitScope_Global,0,&sel,sizeof(sel))!=noErr){printf("FAIL: select preset %d\n",(int)n);return 1;}
        MusicDeviceMIDIEvent(unit,0x90,60,110,0);
        double e=0; bool finite=true;
        for(int blk=0;blk<32;++blk){
            if(!render(unit,l,r)){printf("FAIL: preset %d render\n",(int)n);return 1;}
            for(UInt32 i=0;i<frames;++i){if(!std::isfinite(l[i])||!std::isfinite(r[i]))finite=false;}
            e+=energy(l,0,frames)+energy(r,0,frames);
        }
        MusicDeviceMIDIEvent(unit,0x80,60,0,0);
        for(int blk=0;blk<400;++blk) render(unit,l,r); // let long releases and tails clear
        if(!finite||e<1e-6){printf("FAIL: preset %d silent or non-finite (energy %g)\n",(int)n,e);return 1;}
    }
    printf("all %d factory presets select and render through the host\n",kExpectedPresets);
    // Editor edits: the full sound is readable/writable, an edit is no
    // longer a factory preset, and the state generation moves.
    {
        AUPreset sel{26, nullptr}; // Bent Circuit
        AudioUnitSetProperty(unit, kAudioUnitProperty_PresentPreset, kAudioUnitScope_Global, 0, &sel, sizeof(sel));
        muew::Preset p;
        if (!getState(unit, p) || p.info.name != "Bent Circuit") { printf("FAIL: read editor state\n"); return 1; }
        UInt32 g0 = 0, gs = sizeof(g0);
        AudioUnitGetProperty(unit, kMUEWProperty_StateGeneration, kAudioUnitScope_Global, 0, &g0, &gs);
        p.voice.filterCutoff = 1234.5; p.voice.osc1Warp = 0.61; p.fx.reverb.mix = 0.17;
        if (!setState(unit, p)) { printf("FAIL: write editor state\n"); return 1; }
        UInt32 g1 = 0; gs = sizeof(g1);
        AudioUnitGetProperty(unit, kMUEWProperty_StateGeneration, kAudioUnitScope_Global, 0, &g1, &gs);
        muew::Preset back;
        if (!getState(unit, back) || !(back == p) || presetNumber(unit) != -1 || g1 == g0) {
            printf("FAIL: editor state round trip\n"); return 1;
        }
        // Project save/recall: ClassInfo from this unit restores the exact
        // edited sound in a fresh instance.
        CFPropertyListRef plist = nullptr; UInt32 ps = sizeof(plist);
        if (AudioUnitGetProperty(unit, kAudioUnitProperty_ClassInfo, kAudioUnitScope_Global, 0, &plist, &ps) != noErr || !plist) {
            printf("FAIL: save class info\n"); return 1;
        }
        AudioUnit other = openUnit();
        if (!other || AudioUnitSetProperty(other, kAudioUnitProperty_ClassInfo, kAudioUnitScope_Global, 0, &plist, sizeof(plist)) != noErr) {
            printf("FAIL: restore class info\n"); return 1;
        }
        CFRelease(plist);
        muew::Preset restored;
        if (!getState(other, restored) || !(restored == p)) { printf("FAIL: edited sound not recalled exactly\n"); return 1; }
        MusicDeviceMIDIEvent(other, 0x90, 60, 110, 0);
        double e = 0;
        for (int blk = 0; blk < 16; ++blk) { if (!render(other, l, r)) { printf("FAIL: recalled render\n"); return 1; } e += energy(l, 0, frames); }
        if (e < 1e-6) { printf("FAIL: recalled sound is silent\n"); return 1; }
        AudioUnitUninitialize(other); AudioComponentInstanceDispose(other);
        // A 0.3-style class info (preset number only) still loads that preset.
        CFMutableDictionaryRef legacy = CFDictionaryCreateMutable(nullptr, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        SInt32 n16 = 16; CFNumberRef num = CFNumberCreate(nullptr, kCFNumberSInt32Type, &n16);
        CFDictionarySetValue(legacy, CFSTR("presetNumber"), num); CFRelease(num);
        CFPropertyListRef lp = legacy;
        AudioUnitSetProperty(unit, kAudioUnitProperty_ClassInfo, kAudioUnitScope_Global, 0, &lp, sizeof(lp));
        CFRelease(legacy);
        muew::Preset nb;
        if (presetNumber(unit) != 16 || !getState(unit, nb) || nb.info.name != "Night Bloom") { printf("FAIL: legacy class info\n"); return 1; }
        printf("editor state, full-sound recall and legacy recall: ok\n");
    }

    // Host automation: parameter list, info, get/set, scheduling, audible
    // effect, preset loads updating parameters, and recall.
    {
        namespace mp = muew::params;
        UInt32 size = 0; Boolean writable = false;
        if (AudioUnitGetPropertyInfo(unit, kAudioUnitProperty_ParameterList, kAudioUnitScope_Global, 0, &size, &writable) != noErr
            || size != mp::Count * sizeof(AudioUnitParameterID)) { printf("FAIL: parameter list size %u\n", size); return 1; }
        std::vector<AudioUnitParameterID> ids(mp::Count);
        if (AudioUnitGetProperty(unit, kAudioUnitProperty_ParameterList, kAudioUnitScope_Global, 0, ids.data(), &size) != noErr) {
            printf("FAIL: parameter list\n"); return 1;
        }
        for (int i = 0; i < mp::Count; ++i) {
            if (ids[i] != (AudioUnitParameterID)i) { printf("FAIL: parameter id %d\n", i); return 1; }
            AudioUnitParameterInfo info{}; UInt32 is = sizeof(info);
            if (AudioUnitGetProperty(unit, kAudioUnitProperty_ParameterInfo, kAudioUnitScope_Global, ids[i], &info, &is) != noErr) {
                printf("FAIL: parameter info %d\n", i); return 1;
            }
            const mp::Def& d = mp::def(i);
            bool ok = std::string(info.name) == d.name && info.minValue == (float)d.lo && info.maxValue == (float)d.hi
                && info.defaultValue >= info.minValue && info.defaultValue <= info.maxValue
                && (info.flags & kAudioUnitParameterFlag_IsReadable) && (info.flags & kAudioUnitParameterFlag_IsWritable)
                && info.cfNameString && CFStringCompare(info.cfNameString, CFStringCreateWithCString(nullptr, d.name, kCFStringEncodingUTF8), 0) == kCFCompareEqualTo;
            if (info.cfNameString && (info.flags & kAudioUnitParameterFlag_CFNameRelease)) CFRelease(info.cfNameString);
            if (!ok) { printf("FAIL: parameter info contents %d (%s)\n", i, d.name); return 1; }
        }
        size = 99;
        if (AudioUnitGetPropertyInfo(unit, kAudioUnitProperty_ParameterList, kAudioUnitScope_Output, 0, &size, &writable) != noErr || size != 0) {
            printf("FAIL: output-scope parameter list should be empty\n"); return 1;
        }
        AudioUnitParameterValue v = 0;
        if (AudioUnitGetParameter(unit, 99, kAudioUnitScope_Global, 0, &v) != kAudioUnitErr_InvalidParameter
            || AudioUnitSetParameter(unit, mp::Cutoff, kAudioUnitScope_Input, 0, 100, 0) != kAudioUnitErr_InvalidScope) {
            printf("FAIL: invalid parameter/scope errors\n"); return 1;
        }

        // A factory preset load updates every parameter to that preset's values.
        const int kInitSaw = 2;
        AUPreset sel{kInitSaw, nullptr};
        if (AudioUnitSetProperty(unit, kAudioUnitProperty_PresentPreset, kAudioUnitScope_Global, 0, &sel, sizeof(sel)) != noErr) {
            printf("FAIL: select Init Saw\n"); return 1;
        }
        const muew::Preset& fp = muew::factoryPresets()[kInitSaw];
        for (int i = 0; i < mp::Count; ++i) {
            AudioUnitGetParameter(unit, i, kAudioUnitScope_Global, 0, &v);
            if (v != (float)mp::get(fp, i)) { printf("FAIL: preset load -> parameter %s (%g vs %g)\n", mp::def(i).name, v, mp::get(fp, i)); return 1; }
        }
        if (presetNumber(unit) != kInitSaw) { printf("FAIL: preset number before automation\n"); return 1; }

        // Automation changes the sound: bright vs dark cutoff on the same note.
        auto brightness = [&](float cutoff) -> double {
            AudioUnitSetParameter(unit, mp::Cutoff, kAudioUnitScope_Global, 0, cutoff, 0);
            AudioUnitReset(unit, kAudioUnitScope_Global, 0);
            MusicDeviceMIDIEvent(unit, 0x90, 48, 110, 0);
            double total = 0, hf = 0;
            for (int blk = 0; blk < 24; ++blk) {
                if (!render(unit, l, r)) return -1;
                if (blk < 4) continue;
                for (UInt32 i = 1; i < frames; ++i) { total += l[i] * l[i]; double d = l[i] - l[i - 1]; hf += d * d; }
            }
            MusicDeviceMIDIEvent(unit, 0x80, 48, 0, 0);
            return total > 1e-9 ? hf / total : -1;
        };
        double bright = brightness(18000), dark = brightness(200);
        printf("automation: cutoff 18000 Hz brightness %.4f, 200 Hz brightness %.4f\n", bright, dark);
        if (bright <= 0 || dark <= 0 || bright < dark * 3) { printf("FAIL: cutoff automation not audible\n"); return 1; }

        AudioUnitGetParameter(unit, mp::Cutoff, kAudioUnitScope_Global, 0, &v);
        muew::Preset st;
        if (v != 200.0f || presetNumber(unit) != -1 || !getState(unit, st) || std::fabs(st.voice.filterCutoff - 200.0) > 1e-3
            || std::fabs(mp::get(st, mp::Resonance) - mp::get(fp, mp::Resonance)) > 1e-6) {
            printf("FAIL: automated value not reflected in state/preset number\n"); return 1;
        }
        // Scheduled (ramped) parameter events land on their end value; out-of-range values clamp.
        AudioUnitParameterEvent ev{};
        ev.scope = kAudioUnitScope_Global; ev.parameter = mp::Resonance; ev.eventType = kParameterEvent_Ramped;
        ev.eventValues.ramp.startValue = 1.0f; ev.eventValues.ramp.endValue = 3.5f; ev.eventValues.ramp.durationInFrames = 256;
        AudioUnitParameterEvent ev2{};
        ev2.scope = kAudioUnitScope_Global; ev2.parameter = mp::ReverbMix; ev2.eventType = kParameterEvent_Immediate;
        ev2.eventValues.immediate.value = 250.0f;
        AudioUnitParameterEvent evs[2] = {ev, ev2};
        if (AudioUnitScheduleParameters(unit, evs, 2) != noErr) { printf("FAIL: schedule parameters\n"); return 1; }
        AudioUnitParameterValue reso = 0, rev = 0;
        AudioUnitGetParameter(unit, mp::Resonance, kAudioUnitScope_Global, 0, &reso);
        AudioUnitGetParameter(unit, mp::ReverbMix, kAudioUnitScope_Global, 0, &rev);
        if (reso != 3.5f || rev != 100.0f) { printf("FAIL: scheduled values %g %g\n", reso, rev); return 1; }

        // Automated values are saved with the project.
        CFPropertyListRef plist = nullptr; UInt32 ps = sizeof(plist);
        AudioUnitGetProperty(unit, kAudioUnitProperty_ClassInfo, kAudioUnitScope_Global, 0, &plist, &ps);
        AudioUnit other = openUnit();
        if (!plist || !other || AudioUnitSetProperty(other, kAudioUnitProperty_ClassInfo, kAudioUnitScope_Global, 0, &plist, sizeof(plist)) != noErr) {
            printf("FAIL: automation recall\n"); return 1;
        }
        CFRelease(plist);
        AudioUnitParameterValue oc = 0, orr = 0;
        AudioUnitGetParameter(other, mp::Cutoff, kAudioUnitScope_Global, 0, &oc);
        AudioUnitGetParameter(other, mp::Resonance, kAudioUnitScope_Global, 0, &orr);
        AudioUnitUninitialize(other); AudioComponentInstanceDispose(other);
        if (std::fabs(oc - 200.0f) > 1e-3 || std::fabs(orr - 3.5f) > 1e-5) { printf("FAIL: recalled parameters %g %g\n", oc, orr); return 1; }
        // Parameters survive Reset and re-Initialize (auval expects this too).
        AudioUnitUninitialize(unit);
        if (AudioUnitInitialize(unit) != noErr) { printf("FAIL: reinitialize\n"); return 1; }
        AudioUnitGetParameter(unit, mp::Cutoff, kAudioUnitScope_Global, 0, &v);
        if (v != 200.0f) { printf("FAIL: parameter lost across initialize\n"); return 1; }
        // Macro knobs (params 12-15): Macro 1 (Bright) opens the filter on every factory preset.
        static_assert(mp::Count == 40, "0.34.0 publishes 40 parameters");
        if (AudioUnitSetProperty(unit, kAudioUnitProperty_PresentPreset, kAudioUnitScope_Global, 0, &sel, sizeof(sel)) != noErr) {
            printf("FAIL: reselect Init Saw\n"); return 1;
        }
        AudioUnitGetParameter(unit, mp::Macro1, kAudioUnitScope_Global, 0, &v);
        if (v != 0.0f) { printf("FAIL: factory preset macro should start at 0 (%g)\n", v); return 1; }
        AudioUnitSetParameter(unit, mp::Cutoff, kAudioUnitScope_Global, 0, 300.0f, 0);
        auto measure = [&]() -> double {
            AudioUnitReset(unit, kAudioUnitScope_Global, 0);
            MusicDeviceMIDIEvent(unit, 0x90, 48, 110, 0);
            double total = 0, hf = 0;
            for (int blk = 0; blk < 24; ++blk) {
                if (!render(unit, l, r)) return -1;
                if (blk < 4) continue;
                for (UInt32 i = 1; i < frames; ++i) { total += l[i] * l[i]; double d = l[i] - l[i - 1]; hf += d * d; }
            }
            MusicDeviceMIDIEvent(unit, 0x80, 48, 0, 0);
            return total > 1e-9 ? hf / total : -1;
        };
        double m0 = measure();
        AudioUnitSetParameter(unit, mp::Macro1, kAudioUnitScope_Global, 0, 100.0f, 0);
        double m1 = measure();
        muew::Preset ms;
        printf("macro 1 (Bright) at 0%% brightness %.4f, at 100%% brightness %.4f\n", m0, m1);
        if (m0 <= 0 || m1 < m0 * 2 || !getState(unit, ms) || ms.voice.macros[0] != 1.0 || presetNumber(unit) != -1) {
            printf("FAIL: macro 1 not audible or not stored in the sound\n"); return 1;
        }
        // 0.7.0: unison width (param 18) on a stacked factory sound, and the
        // distortion drive (param 19) on a distorted one, are audible.
        auto selectPreset = [&](int preset) -> bool {
            AUPreset ps{preset, nullptr};
            if (AudioUnitSetProperty(unit, kAudioUnitProperty_PresentPreset, kAudioUnitScope_Global, 0, &ps, sizeof(ps)) != noErr) return false;
            return true;
        };
        auto measureLR = [&](double& side, double& mid) -> bool {
            AudioUnitReset(unit, kAudioUnitScope_Global, 0);
            MusicDeviceMIDIEvent(unit, 0x90, 60, 110, 0);
            side = mid = 0;
            for (int blk = 0; blk < 24; ++blk) {
                if (!render(unit, l, r)) return false;
                if (blk < 4) continue;
                for (UInt32 i = 0; i < frames; ++i) { double s = l[i] - r[i], m = l[i] + r[i]; side += s * s; mid += m * m; }
            }
            MusicDeviceMIDIEvent(unit, 0x80, 60, 0, 0);
            return mid > 1e-9;
        };
        double side = 0, mid = 0, side0 = 0, mid0 = 0;
        if (!selectPreset(30) || !measureLR(side, mid)) { printf("FAIL: render Hyper Saw\n"); return 1; }
        AudioUnitSetParameter(unit, mp::UnisonWidth, kAudioUnitScope_Global, 0, 0.0f, 0);
        if (!measureLR(side0, mid0)) { printf("FAIL: render Hyper Saw at width 0\n"); return 1; }
        // (Its stereo delay keeps a little side signal even with the stack collapsed.)
        printf("unison: Hyper Saw side/mid %.4f at preset width, %.4f at width 0\n", side / mid, side0 / mid0);
        if (side / mid < 0.02 || side0 / mid0 > 0.5 * side / mid) { printf("FAIL: unison width not audible through the AU\n"); return 1; }
        double dside = 0, dmid = 0, dside2 = 0, dmid2 = 0; (void)dside2;
        if (!selectPreset(34) || !measureLR(dside, dmid)) { printf("FAIL: render Fold Screamer\n"); return 1; }
        AudioUnitSetParameter(unit, mp::DistDrive, kAudioUnitScope_Global, 0, 100.0f, 0);
        if (!measureLR(dside2, dmid2)) { printf("FAIL: render driven Fold Screamer\n"); return 1; }
        muew::Preset fs;
        printf("drive: Fold Screamer level %.1f at preset drive, %.1f at 100%%\n", dmid, dmid2);
        if (std::fabs(dmid2 - dmid) < dmid * 0.02 || !getState(unit, fs) || fs.fx.dist.drive != 1.0) {
            printf("FAIL: distortion drive not audible or not stored\n"); return 1;
        }
        // 0.27.0: HYPER MIX (param 34) widens a mono sound; FILTER FX CUTOFF (param 35) darkens it.
        {
            muew::Preset hp;
            if (!selectPreset(0) || !getState(unit, hp)) { printf("FAIL: select Airy Strings for FX depth\n"); return 1; }
            hp.voice.osc1Unison = 1; hp.voice.osc2Unison = 1; hp.fx = muew::FXParams{};
            hp.fx.hyper.enabled = true; hp.fx.hyper.mix = 0.0;
            hp.fx.filter.enabled = true; hp.fx.filter.cutoffHz = 18000; hp.fx.filter.reso = 0.0; hp.fx.filter.mix = 1.0;
            double hs0 = 0, hm0 = 0, hs1 = 0, hm1 = 0, hs2 = 0, hm2 = 0;
            if (!setState(unit, hp) || !measureLR(hs0, hm0)) { printf("FAIL: render FX depth base\n"); return 1; }
            AudioUnitSetParameter(unit, mp::HyperMix, kAudioUnitScope_Global, 0, 100.0f, 0);
            if (!measureLR(hs1, hm1)) { printf("FAIL: render HYPER mix 100\n"); return 1; }
            AudioUnitSetParameter(unit, mp::FilterFxCutoff, kAudioUnitScope_Global, 0, 80.0f, 0);
            if (!measureLR(hs2, hm2)) { printf("FAIL: render FILTER FX at 80 Hz\n"); return 1; }
            muew::Preset hq;
            printf("fx depth: side/mid %.4f at HYPER mix 0, %.4f at 100; level %.1f -> %.1f with FILTER FX at 80 Hz\n", hs0 / hm0, hs1 / hm1, hm1, hm2);
            if (hs1 / hm1 < hs0 / hm0 + 0.05 || hm2 > hm1 * 0.5 || !getState(unit, hq) || hq.fx.hyper.mix != 1.0 || std::fabs(hq.fx.filter.cutoffHz - 80.0) > 1e-3) {
                printf("FAIL: HYPER mix / FILTER FX cutoff not audible or not stored\n"); return 1;
            }
        }
        // 0.28.0: REVERB SIZE (param 36) reshapes a HALL; MULTIBAND UPWARD (param 37) lifts quiet bands.
        {
            muew::Preset sp;
            if (!selectPreset(0) || !getState(unit, sp)) { printf("FAIL: select Airy Strings for Space + Dynamics\n"); return 1; }
            sp.fx = muew::FXParams{};
            sp.fx.reverb.enabled = true; sp.fx.reverb.mode = 1; sp.fx.reverb.mix = 1.0; sp.fx.reverb.size = 0.0; sp.fx.reverb.decay = 0.8;
            double rs0 = 0, rm0 = 0, rs1 = 0, rm1 = 0;
            if (!setState(unit, sp) || !measureLR(rs0, rm0)) { printf("FAIL: render HALL base\n"); return 1; }
            AudioUnitSetParameter(unit, mp::ReverbSize, kAudioUnitScope_Global, 0, 100.0f, 0);
            if (!measureLR(rs1, rm1)) { printf("FAIL: render HALL size 100\n"); return 1; }
            muew::Preset sq;
            const double dr = std::fabs(rm1 - rm0) / rm0 + std::fabs(rs1 - rs0) / std::max(rs0, 1e-9);
            printf("space: HALL mid %.1f side %.1f at SIZE 0, mid %.1f side %.1f at SIZE 100\n", rm0, rs0, rm1, rs1);
            if (dr < 0.03 || !getState(unit, sq) || sq.fx.reverb.size != 1.0 || sq.fx.reverb.mode != 1) {
                printf("FAIL: REVERB SIZE not audible or not stored\n"); return 1;
            }
            sp.fx = muew::FXParams{};
            sp.fx.comp.enabled = true; sp.fx.comp.mode = 1; sp.fx.comp.amount = 0.9; sp.fx.comp.upward = 0.0;
            // UPWARD only lifts quiet material (loud bands sit above the threshold), so play softly: velocity 16.
            auto quiet = [&]() -> double {
                double e = 0;
                for (int pass = 0; pass < 2; ++pass) { // the second pass is measured
                    AudioUnitReset(unit, kAudioUnitScope_Global, 0);
                    MusicDeviceMIDIEvent(unit, 0x90, 60, 16, 0);
                    e = 0;
                    for (int blk = 0; blk < 24; ++blk) {
                        if (!render(unit, l, r)) return -1;
                        if (blk < 4) continue;
                        for (UInt32 i = 0; i < frames; ++i) { double m = l[i] + r[i]; e += m * m; }
                    }
                    MusicDeviceMIDIEvent(unit, 0x80, 60, 0, 0);
                }
                return e;
            };
            if (!setState(unit, sp)) { printf("FAIL: set MULTIBAND state\n"); return 1; }
            const double cm0 = quiet();
            AudioUnitSetParameter(unit, mp::CompUpward, kAudioUnitScope_Global, 0, 100.0f, 0);
            const double cm1 = quiet();
            if (cm0 <= 0 || cm1 <= 0) { printf("FAIL: render MULTIBAND at velocity 16\n"); return 1; }
            printf("dynamics: MULTIBAND level %.2f at UPWARD 0, %.2f at 100 (velocity 16)\n", cm0, cm1);
            if (cm1 < cm0 * 1.15 || !getState(unit, sq) || sq.fx.comp.upward != 1.0 || sq.fx.comp.mode != 1) {
                printf("FAIL: MULTIBAND UPWARD not audible or not stored\n"); return 1;
            }
        }
        // 0.29.0: a host Reset gives every note the same render (no envelope, tail or LFO phase carried over).
        {
            double s1 = 0, m1 = 0, s2 = 0, m2 = 0, s3 = 0, m3 = 0;
            if (!selectPreset(7) || !measureLR(s1, m1) || !measureLR(s2, m2) || !measureLR(s3, m3)) { printf("FAIL: render preset 7 three times\n"); return 1; }
            printf("reset: preset 7 energy %.6f / %.6f / %.6f\n", m1, m2, m3);
            if (std::fabs(m2 - m1) > 1e-6 * m1 || std::fabs(m3 - m1) > 1e-6 * m1) { printf("FAIL: notes after a Reset render differently\n"); return 1; }
        }
        // 0.30.0 Engine HQ: QUALITY and HQ distortion report latency; an offline render runs HQ; the meter counts voices.
        {
            auto latency = [&]() { Float64 l = -1; UInt32 sz = sizeof(l); AudioUnitGetProperty(unit, kAudioUnitProperty_Latency, kAudioUnitScope_Global, 0, &l, &sz); return l * 44100.0; };
            muew::Preset hq;
            if (!selectPreset(34) || !getState(unit, hq)) { printf("FAIL: select Fold Screamer for HQ\n"); return 1; }
            hq.fx.dist.enabled = true; hq.fx.dist.mode = 1; hq.fx.dist.quality = 0; hq.voice.oscQuality = 0;
            if (!setState(unit, hq)) { printf("FAIL: set STANDARD sound\n"); return 1; }
            const double l0 = latency();
            hq.voice.oscQuality = 1; setState(unit, hq); const double l1 = latency();
            hq.fx.dist.quality = 1; setState(unit, hq); const double l2 = latency();
            hq.voice.oscQuality = 0; hq.fx.dist.quality = 0; setState(unit, hq);
            UInt32 off = 1;
            const bool offOk = AudioUnitSetProperty(unit, kAudioUnitProperty_OfflineRender, kAudioUnitScope_Global, 0, &off, sizeof(off)) == noErr;
            const double l3 = latency();
            UInt32 rd = 0, rsz = sizeof(rd); AudioUnitGetProperty(unit, kAudioUnitProperty_OfflineRender, kAudioUnitScope_Global, 0, &rd, &rsz);
            double so = 0, mo = 0; const bool rOk = measureLR(so, mo);
            MUEWPerformance pf{}; UInt32 psz = sizeof(pf);
            AudioUnitGetProperty(unit, kMUEWProperty_Performance, kAudioUnitScope_Global, 0, &pf, &psz);
            off = 0; AudioUnitSetProperty(unit, kAudioUnitProperty_OfflineRender, kAudioUnitScope_Global, 0, &off, sizeof(off));
            const double l4 = latency();
            printf("hq: latency %.1f / %.1f / %.1f samples, offline %.1f (read %u), back %.1f; offline render energy %.3f; meter hq %u render %u limit %u cpu %.4f\n",
                   l0, l1, l2, l3, (unsigned)rd, l4, mo, (unsigned)pf.oscHQ, (unsigned)pf.renderHQ, (unsigned)pf.voiceLimit, pf.cpuLoad);
            if (std::fabs(l0) > 1e-9 || std::fabs(l1 - 7.5) > 1e-6 || std::fabs(l2 - 30.0) > 1e-6) { printf("FAIL: QUALITY / DIST HQ latency not reported\n"); return 1; }
            if (!offOk || rd != 1 || std::fabs(l3 - 30.0) > 1e-6 || std::fabs(l4) > 1e-9) { printf("FAIL: offline render does not switch to HQ\n"); return 1; }
            if (!rOk || mo <= 0 || pf.oscHQ != 1 || pf.renderHQ != 1 || pf.voiceLimit < 1 || !(pf.cpuLoad > 0)) { printf("FAIL: HQ render or engine meter\n"); return 1; }
            if (!selectPreset(7)) { printf("FAIL: back to Warm Pad\n"); return 1; }
        }
        printf("parameters: %d published; get/set, schedule, preset sync, audible automation, macros, unison width, drive, HYPER / FILTER FX, SIZE / UPWARD and recall: ok\n", (int)mp::Count);
    }

    // Render notifications fire before and after each render (auval checks this).
    {
        static int pre = 0, post = 0;
        AURenderCallback cb = [](void*, AudioUnitRenderActionFlags* f, const AudioTimeStamp*, UInt32, UInt32, AudioBufferList*) -> OSStatus {
            if (*f & kAudioUnitRenderAction_PreRender) ++pre;
            if (*f & kAudioUnitRenderAction_PostRender) ++post;
            return noErr;
        };
        if (AudioUnitAddRenderNotify(unit, cb, nullptr) != noErr) { printf("FAIL: add render notify\n"); return 1; }
        for (int i = 0; i < 3; ++i) render(unit, l, r);
        AudioUnitRemoveRenderNotify(unit, cb, nullptr);
        render(unit, l, r);
        if (pre != 3 || post != 3) { printf("FAIL: render notify pre %d post %d\n", pre, post); return 1; }
        // A host-named custom preset keeps its name in PresentPreset and class info.
        AUPreset custom{-1, CFSTR("My Riser")};
        AudioUnitSetProperty(unit, kAudioUnitProperty_PresentPreset, kAudioUnitScope_Global, 0, &custom, sizeof(custom));
        CFPropertyListRef plist = nullptr; UInt32 ps = sizeof(plist);
        AudioUnitGetProperty(unit, kAudioUnitProperty_ClassInfo, kAudioUnitScope_Global, 0, &plist, &ps);
        CFStringRef nm = plist ? (CFStringRef)CFDictionaryGetValue((CFDictionaryRef)plist, CFSTR("name")) : nullptr;
        bool ok = nm && CFStringCompare(nm, CFSTR("My Riser"), 0) == kCFCompareEqualTo;
        if (plist) CFRelease(plist);
        if (!ok) { printf("FAIL: custom preset name not kept in class info\n"); return 1; }
        printf("render notify pre/post and custom preset name: ok\n");
    }

    // 0.8.0: a mod route added through the state is audible, and a synced
    // LFO follows the host tempo from kAudioUnitProperty_HostCallbacks.
    {
        static Float64 hostTempo = 120.0;
        auto take = [&](const muew::Preset& p, double bpm, std::vector<float>& out) -> bool {
            AudioUnit t = openUnit();
            if (!t) return false;
            hostTempo = bpm;
            HostCallbackInfo hc{};
            hc.beatAndTempoProc = [](void*, Float64* beat, Float64* tempo) -> OSStatus {
                if (beat) { *beat = 0; }
                if (tempo) { *tempo = hostTempo; }
                return noErr;
            };
            bool ok = AudioUnitSetProperty(t, kAudioUnitProperty_HostCallbacks, kAudioUnitScope_Global, 0, &hc, sizeof(hc)) == noErr
                      && setState(t, p);
            std::vector<float> bl(512), br(512);
            out.clear();
            ok = ok && render(t, bl, br) && MusicDeviceMIDIEvent(t, 0x90, 48, 110, 0) == noErr;
            for (int i = 0; ok && i < 172; ++i) { ok = render(t, bl, br); out.insert(out.end(), bl.begin(), bl.end()); }
            AudioUnitUninitialize(t); AudioComponentInstanceDispose(t);
            return ok;
        };
        muew::Preset p = muew::factoryPresets()[0];
        p.voice.osc2Level = 0; p.voice.filterCutoff = 900; p.routes.clear();
        p.fx = muew::FXParams{};
        std::vector<float> dry, routed, fast, freeA, freeB;
        muew::Preset q = p; q.voice.lfoSync[2] = 3; q.routes.push_back({muew::ModRoute::Source::LFO3, muew::ModRoute::Dest::FilterCutoff, 3.0});
        muew::Preset f = q; f.voice.lfoSync[2] = 0; f.voice.lfo3Rate = 2.0;
        if (!take(p, 120, dry) || !take(q, 120, routed) || !take(q, 180, fast) || !take(f, 120, freeA) || !take(f, 180, freeB)) {
            printf("FAIL: tempo/route renders\n"); return 1;
        }
        auto diff = [](const std::vector<float>& a, const std::vector<float>& b) { double d = 0; for (size_t i = 0; i < a.size() && i < b.size(); ++i) d = std::max(d, (double)std::fabs(a[i] - b[i])); return d; };
        muew::Preset back; AudioUnit t = openUnit(); bool kept = t && setState(t, q) && getState(t, back) && back.routes.size() == 1
            && back.routes[0].source == muew::ModRoute::Source::LFO3 && back.voice.lfoSync[2] == 3;
        if (t) { AudioUnitUninitialize(t); AudioComponentInstanceDispose(t); }
        printf("matrix: route delta %.3f, synced 120 vs 180 BPM delta %.3f, free-running delta %.6f\n", diff(dry, routed), diff(routed, fast), diff(freeA, freeB));
        if (!kept || diff(dry, routed) < 0.01 || diff(routed, fast) < 0.01 || diff(freeA, freeB) != 0.0) {
            printf("FAIL: state route, host tempo sync or recall\n"); return 1;
        }
        printf("mod matrix route via state, host-tempo LFO sync and recall: ok\n");
    }

    // 0.9.0: a user wavetable set through the state plays on oscillator A,
    // survives getState, and the WT POS A parameter morphs it audibly.
    {
        muew::Preset p = muew::factoryPresets()[0];
        p.voice.osc2Level = 0; p.voice.filterCutoff = 12000; p.routes.clear(); p.fx = muew::FXParams{};
        p.voice.osc1Shape = muew::kCustomShape; p.voice.osc1WtPos = 0.0;
        p.tables[0] = {muew::shapeFrame(0), muew::shapeFrame(3)}; // sine -> square
        auto take = [&](double wtpos, std::vector<float>& out, muew::Preset* back) -> bool {
            AudioUnit t = openUnit();
            if (!t) return false;
            bool ok = setState(t, p)
                      && AudioUnitSetParameter(t, muew::params::WtPosA, kAudioUnitScope_Global, 0, (AudioUnitParameterValue)(wtpos * 100.0), 0) == noErr; // percent, like the other AU params
            std::vector<float> bl(512), br(512);
            out.clear();
            ok = ok && render(t, bl, br) && MusicDeviceMIDIEvent(t, 0x90, 48, 110, 0) == noErr;
            for (int i = 0; ok && i < 40; ++i) { ok = render(t, bl, br); out.insert(out.end(), bl.begin(), bl.end()); }
            if (ok && back) ok = getState(t, *back);
            AudioUnitUninitialize(t); AudioComponentInstanceDispose(t);
            return ok;
        };
        std::vector<float> a0, a1; muew::Preset back;
        if (!take(0.0, a0, nullptr) || !take(1.0, a1, &back)) { printf("FAIL: user table renders\n"); return 1; }
        double d = 0, pk = 0;
        for (size_t i = 0; i < a0.size() && i < a1.size(); ++i) { d = std::max(d, (double)std::fabs(a0[i] - a1[i])); pk = std::max(pk, (double)std::fabs(a0[i])); }
        printf("user table: peak %.3f, WT POS 0 vs 1 delta %.3f, recalled frames %d, wtpos %.2f\n", pk, d, (int)back.tables[0].size(), back.voice.osc1WtPos);
        if (pk < 0.01 || d < 0.01 || back.tables[0].size() != 2 || back.tables[0] != p.tables[0] || std::fabs(back.voice.osc1WtPos - 1.0) > 1e-6) {
            printf("FAIL: user table state, WT POS automation or recall\n"); return 1;
        }
        printf("user wavetable via state, WT POS parameter and recall: ok\n");
    }

    // 0.10.0: the SUB LEVEL parameter is audible and a filter 2 set through
    // the state (comb, parallel) survives getState.
    {
        muew::Preset p = muew::factoryPresets()[0];
        p.voice.osc2Level = 0; p.voice.osc1Shape = 0; p.voice.filterCutoff = 12000; p.routes.clear(); p.fx = muew::FXParams{};
        p.voice.filter2Type = 4; p.voice.filter2Cutoff = 440; p.voice.filter2Reso = 5; p.voice.filterRouting = 1;
        auto take = [&](double subPct, std::vector<float>& out, muew::Preset* back) -> bool {
            AudioUnit t = openUnit();
            if (!t) return false;
            bool ok = setState(t, p)
                      && AudioUnitSetParameter(t, muew::params::SubLevel, kAudioUnitScope_Global, 0, (AudioUnitParameterValue)subPct, 0) == noErr;
            std::vector<float> bl(512), br(512);
            out.clear();
            ok = ok && render(t, bl, br) && MusicDeviceMIDIEvent(t, 0x90, 48, 110, 0) == noErr;
            for (int i = 0; ok && i < 40; ++i) { ok = render(t, bl, br); out.insert(out.end(), bl.begin(), bl.end()); }
            if (ok && back) ok = getState(t, *back);
            AudioUnitUninitialize(t); AudioComponentInstanceDispose(t);
            return ok;
        };
        std::vector<float> s0, s1; muew::Preset back;
        if (!take(0, s0, nullptr) || !take(100, s1, &back)) { printf("FAIL: layer renders\n"); return 1; }
        double d = 0, pk = 0; bool fin = true;
        for (size_t i = 0; i < s0.size() && i < s1.size(); ++i) { d = std::max(d, (double)std::fabs(s0[i] - s1[i])); pk = std::max(pk, (double)std::fabs(s1[i])); fin = fin && std::isfinite(s1[i]); }
        printf("layers: peak %.3f, SUB 0 vs 100%% delta %.3f, filter 2 type %d routing %d cutoff %.0f, sub %.2f\n", pk, d,
               back.voice.filter2Type, back.voice.filterRouting, back.voice.filter2Cutoff, back.voice.subLevel);
        if (!fin || pk < 0.01 || d < 0.01 || back.voice.filter2Type != 4 || back.voice.filterRouting != 1 || back.voice.filter2Cutoff != 440
            || std::fabs(back.voice.subLevel - 1.0) > 1e-6) {
            printf("FAIL: sub parameter, filter 2 state or recall\n"); return 1;
        }
        printf("sub level parameter, filter 2 via state and recall: ok\n");
    }

    // 0.24.0 MIDI performance: pitch bend (RANGE 12) moves the pitch an
    // octave, CC 1 / pressure / sustain reach the synth, the pedal holds a
    // released key, CC 123 silences, and the performance property reports it.
    {
        muew::Preset p = muew::factoryPresets()[0];
        p.voice.osc2Level = 0; p.voice.osc1Shape = 0; p.voice.filterCutoff = 16000; p.voice.ampR = 0.05; p.routes.clear(); p.fx = muew::FXParams{};
        p.voice.bendRange = 12; p.voice.ampA = 0.005; p.voice.ampD = 0.2; p.voice.ampS = 0.8;
        p.voice.osc1Unison = 1; p.voice.osc2Unison = 1; p.voice.subLevel = 0; p.voice.noiseLevel = 0; p.voice.filter2Type = 0;
        auto cycles = [](const std::vector<float>& x) { int c = 0; for (size_t i = 1; i < x.size(); ++i) if (x[i - 1] <= 0 && x[i] > 0) ++c; return c; };
        auto play = [&](bool bend, std::vector<float>& out, int note) -> bool {
            AudioUnit t = openUnit();
            if (!t) return false;
            std::vector<float> bl(512), br(512);
            bool ok = setState(t, p) && render(t, bl, br);
            if (bend) ok = ok && MusicDeviceMIDIEvent(t, 0xE0, 0x7F, 0x7F, 0) == noErr; // full bend up
            ok = ok && MusicDeviceMIDIEvent(t, 0x90, note, 110, 0) == noErr;
            out.clear();
            for (int i = 0; ok && i < 86; ++i) { ok = render(t, bl, br); if (i >= 8) out.insert(out.end(), bl.begin(), bl.end()); }
            AudioUnitUninitialize(t); AudioComponentInstanceDispose(t);
            return ok;
        };
        std::vector<float> bent, octave;
        if (!play(true, bent, 48) || !play(false, octave, 60)) { printf("FAIL: bend renders\n"); return 1; }
        const int cb = cycles(bent), co = cycles(octave);
        printf("pitch bend: note 48 bent +12 st = %d cycles, note 60 = %d cycles\n", cb, co);
        if (std::abs(cb - co) > 1 || co < 100) { printf("FAIL: pitch bend range\n"); return 1; }

        AudioUnit t = openUnit();
        std::vector<float> bl(512), br(512);
        bool ok = t && setState(t, p) && render(t, bl, br);
        ok = ok && MusicDeviceMIDIEvent(t, 0xB0, 1, 64, 0) == noErr && MusicDeviceMIDIEvent(t, 0xD0, 100, 0, 0) == noErr
                && MusicDeviceMIDIEvent(t, 0xE0, 0x00, 0x20, 0) == noErr && MusicDeviceMIDIEvent(t, 0xB0, 64, 127, 0) == noErr
                && MusicDeviceMIDIEvent(t, 0x90, 57, 110, 0) == noErr && render(t, bl, br);
        MUEWPerformance pf{}; UInt32 sz = sizeof(pf);
        ok = ok && AudioUnitGetProperty(t, kMUEWProperty_Performance, kAudioUnitScope_Global, 0, &pf, &sz) == noErr;
        printf("performance: wheel %.3f, pressure %.3f, bend %.3f, note %d, sustain %u\n", pf.wheel, pf.aftertouch, pf.bend, (int)pf.lastNote, (unsigned)pf.sustain);
        if (!ok || std::fabs(pf.wheel - 64 / 127.0f) > 1e-4 || std::fabs(pf.aftertouch - 100 / 127.0f) > 1e-4 || std::fabs(pf.bend + 0.5f) > 1e-3
            || pf.lastNote != 57 || pf.sustain != 1) { printf("FAIL: performance controls\n"); return 1; }
        ok = MusicDeviceMIDIEvent(t, 0x80, 57, 0, 0) == noErr;
        for (int i = 0; ok && i < 100; ++i) ok = render(t, bl, br); // 1.2 s after key up, pedal down
        const double held = energy(bl, 0, bl.size());
        ok = ok && MusicDeviceMIDIEvent(t, 0xB0, 64, 0, 0) == noErr;
        for (int i = 0; ok && i < 100; ++i) ok = render(t, bl, br);
        const double released = energy(bl, 0, bl.size());
        ok = ok && MusicDeviceMIDIEvent(t, 0x90, 60, 110, 0) == noErr && render(t, bl, br) && render(t, bl, br);
        const double playing = energy(bl, 0, bl.size());
        ok = ok && MusicDeviceMIDIEvent(t, 0xB0, 123, 0, 0) == noErr;
        for (int i = 0; ok && i < 100; ++i) ok = render(t, bl, br);
        const double off = energy(bl, 0, bl.size());
        printf("sustain: held %.4f, after pedal up %.6f, new note %.4f, after CC123 %.6f\n", held, released, playing, off);
        if (!ok || held < 1e-3 || released > 1e-7 || playing < 1e-3 || off > 1e-7) { printf("FAIL: sustain pedal / all notes off\n"); return 1; }
        AudioUnitUninitialize(t); AudioComponentInstanceDispose(t);
        printf("MIDI performance (bend, wheel, pressure, sustain, CC123): ok\n");
    }

    // 0.25.0 arpeggiator: held keys play UP at 1/16 (120 BPM without host
    // tempo), the performance property reports the pool and the sounding step,
    // ARP GATE / SWING are automatable, key up stops it.
    {
        muew::Preset p = muew::factoryPresets()[0];
        p.voice.osc2Level = 0; p.voice.osc1Shape = 0; p.voice.filterCutoff = 16000; p.voice.ampR = 0.02; p.routes.clear(); p.fx = muew::FXParams{};
        p.voice.arpOn = true; p.voice.arpMode = 0; p.voice.arpRate = 3; p.voice.arpGate = 0.5;
        AudioUnit t = openUnit();
        std::vector<float> bl(512), br(512);
        bool ok = t && setState(t, p) && render(t, bl, br);
        for (int k : {67, 60, 64}) ok = ok && MusicDeviceMIDIEvent(t, 0x90, k, 100, 0) == noErr;
        std::vector<int> notes; int last = -2; double e = 0; MUEWPerformance pf{};
        for (int i = 0; ok && i < 120; ++i) { // 1.39 s = 11 steps
            ok = render(t, bl, br); e += energy(bl, 0, bl.size());
            UInt32 sz = sizeof(pf);
            ok = ok && AudioUnitGetProperty(t, kMUEWProperty_Performance, kAudioUnitScope_Global, 0, &pf, &sz) == noErr;
            if (pf.arpNote >= 0 && pf.arpNote != last) notes.push_back(pf.arpNote);
            last = pf.arpNote;
        }
        printf("arp: on %u, pool %d (%d %d %d), step %d, notes", (unsigned)pf.arpOn, (int)pf.poolCount, (int)pf.pool[0], (int)pf.pool[1], (int)pf.pool[2], (int)pf.arpStep);
        for (int n : notes) printf(" %d", n);
        printf(", energy %.3f\n", e);
        static const int kUp[3] = {60, 64, 67};
        bool upOrder = notes.size() >= 9;
        for (size_t i = 0; upOrder && i < notes.size(); ++i) upOrder = notes[i] == kUp[i % 3];
        if (!ok || pf.arpOn != 1 || pf.poolCount != 3 || pf.pool[0] != 67 || pf.arpStep < 9 || !upOrder || e < 0.05) { printf("FAIL: arp plays the held keys UP\n"); return 1; }
        ok = AudioUnitSetParameter(t, muew::params::ArpGate, kAudioUnitScope_Global, 0, 25.0f, 0) == noErr
          && AudioUnitSetParameter(t, muew::params::ArpSwing, kAudioUnitScope_Global, 0, 40.0f, 0) == noErr && render(t, bl, br);
        muew::Preset st;
        if (!ok || !getState(t, st) || std::fabs(st.voice.arpGate - 0.25) > 1e-6 || std::fabs(st.voice.arpSwing - 0.4) > 1e-6
            || st.serialize().find("\narp 1 0 1 3 0.25 0.4 0\n") == std::string::npos) { printf("FAIL: ARP GATE / SWING parameters\n"); return 1; }
        for (int k : {67, 60, 64}) ok = ok && MusicDeviceMIDIEvent(t, 0x80, k, 0, 0) == noErr;
        for (int i = 0; ok && i < 40; ++i) ok = render(t, bl, br);
        UInt32 sz = sizeof(pf);
        ok = ok && AudioUnitGetProperty(t, kMUEWProperty_Performance, kAudioUnitScope_Global, 0, &pf, &sz) == noErr;
        const double after = energy(bl, 0, bl.size());
        printf("arp: after key up pool %d note %d energy %.8f\n", (int)pf.poolCount, (int)pf.arpNote, after);
        if (!ok || pf.poolCount != 0 || pf.arpNote != -1 || after > 1e-7) { printf("FAIL: arp stops when the keys come up\n"); return 1; }
        AudioUnitUninitialize(t); AudioComponentInstanceDispose(t);
        printf("arpeggiator (UP 1/16, pool, gate / swing automation, key up): ok\n");
    }

    // 0.26.0 clock sync + step pattern: with the host transport playing, a key
    // pressed in the last quarter of a 1/16 waits for the host's grid line;
    // pattern REST/ON lands on the host's odd steps; stopped = free clock.
    {
        static Float64 hBeat = 0.2; static Boolean hPlay = true;
        muew::Preset p = muew::factoryPresets()[0];
        p.voice.osc2Level = 0; p.voice.osc1Shape = 0; p.voice.filterCutoff = 16000; p.voice.ampR = 0.02; p.routes.clear(); p.fx = muew::FXParams{};
        p.voice.arpOn = true; p.voice.arpMode = 0; p.voice.arpRate = 3; p.voice.arpGate = 0.5; p.voice.clockSync = true;
        p.voice.arpPatOn = true; p.voice.arpPatLen = 2; p.voice.arpPatKind[0] = muew::arp::StepRest;
        AudioUnit t = openUnit();
        HostCallbackInfo hc{};
        hc.beatAndTempoProc = [](void*, Float64* beat, Float64* tempo) -> OSStatus { if (beat) *beat = hBeat; if (tempo) *tempo = 120.0; return noErr; };
        hc.transportStateProc2 = [](void*, Boolean* play, Boolean* rec, Boolean* changed, Float64* sample, Boolean* cyc, Float64* cs, Float64* ce) -> OSStatus {
            if (play) *play = hPlay; if (rec) *rec = false; if (changed) *changed = false; if (sample) *sample = hBeat * 22050.0;
            if (cyc) *cyc = false; if (cs) *cs = 0; if (ce) *ce = 0; return noErr;
        };
        std::vector<float> bl(512), br(512);
        const double blockBeats = 512.0 * 2.0 / 44100.0;
        auto step = [&]() { bool r = render(t, bl, br); hBeat += blockBeats; return r; };
        MUEWPerformance pf{}; UInt32 sz = sizeof(pf);
        bool ok = t && AudioUnitSetProperty(t, kAudioUnitProperty_HostCallbacks, kAudioUnitScope_Global, 0, &hc, sizeof(hc)) == noErr && setState(t, p);
        hBeat = 0.2 - blockBeats; ok = ok && step(); // hBeat now 0.2
        ok = ok && MusicDeviceMIDIEvent(t, 0x90, 60, 100, 0) == noErr && step();
        ok = ok && AudioUnitGetProperty(t, kMUEWProperty_Performance, kAudioUnitScope_Global, 0, &pf, &sz) == noErr;
        const int waitNote = pf.arpNote; const unsigned locked = pf.hostLocked;
        ok = ok && step() && step(); sz = sizeof(pf); // beats 0.2232 -> 0.2697: crosses the 0.25 grid line
        ok = ok && AudioUnitGetProperty(t, kMUEWProperty_Performance, kAudioUnitScope_Global, 0, &pf, &sz) == noErr;
        const int gridNote = pf.arpNote, gridStep = pf.arpStep;
        bool evenOnly = true; int sounded = 0;
        for (int i = 0; ok && i < 60; ++i) {
            ok = step(); sz = sizeof(pf);
            ok = ok && AudioUnitGetProperty(t, kMUEWProperty_Performance, kAudioUnitScope_Global, 0, &pf, &sz) == noErr;
            if (pf.arpNote >= 0) { ++sounded; if (pf.arpStep % 2 != 1 || pf.arpPatCell != 1) evenOnly = false; }
        }
        printf("clock sync: waiting note %d locked %u, at grid note %d step %d, pattern odd-only %d (%d blocks sounding)\n", waitNote, locked, gridNote, gridStep, evenOnly ? 1 : 0, sounded);
        if (!ok || locked != 1 || waitNote != -1 || gridNote != 60 || gridStep != 1 || !evenOnly || sounded < 10) { printf("FAIL: arp clock sync to the host bar\n"); return 1; }
        hPlay = false; ok = step() && step(); sz = sizeof(pf);
        ok = ok && AudioUnitGetProperty(t, kMUEWProperty_Performance, kAudioUnitScope_Global, 0, &pf, &sz) == noErr;
        muew::Preset st;
        if (!ok || pf.hostLocked != 0 || !getState(t, st) || st.serialize().find("\narpx 1 1 2 127 1 127 0") == std::string::npos) { printf("FAIL: transport stop / arpx state\n"); return 1; }
        AudioUnitUninitialize(t); AudioComponentInstanceDispose(t);
        printf("arp clock sync + step pattern (grid wait, odd steps, stop, state): ok\n");
    }

    // 0.48.0: host-recalled per-step ratchet counts are an optional line,
    // while the original arpx layout and factory preset numbering stay fixed.
    {
        muew::Preset p = muew::factoryPresets()[0], got;
        p.voice.arpOn = true; p.voice.arpPatOn = true; p.voice.arpPatLen = 2;
        p.voice.arpPatRatchet[0] = 3; p.voice.arpPatRatchet[1] = 4;
        AudioUnit t = openUnit();
        bool ok = t && setState(t, p) && getState(t, got);
        auto saved = got.serialize();
        if (!ok || !(got == p) || saved.find("\narpr 3 4 1 1 ") == std::string::npos ||
            saved.find("\narpx 0 1 2 ") == std::string::npos) {
            printf("FAIL: AU ratchet state / append-only arpr line\n"); return 1;
        }
        AudioUnitUninitialize(t); AudioComponentInstanceDispose(t);
        printf("ARP ratchet state recalled through AU; arpx layout unchanged\n");
    }

    // 0.49.0: per-step octave data is separate from the older arpx/arpr lines.
    {
        muew::Preset p = muew::factoryPresets()[0], got;
        p.voice.arpOn = true; p.voice.arpPatOn = true; p.voice.arpPatLen = 2;
        p.voice.arpPatRatchet[0] = 3;
        p.voice.arpPatOctave[0] = 1; p.voice.arpPatOctave[1] = -1;
        AudioUnit t = openUnit();
        bool ok = t && setState(t, p) && getState(t, got);
        auto saved = got.serialize();
        if (!ok || !(got == p) || saved.find("\narpo 1 -1 0 0 ") == std::string::npos ||
            saved.find("\narpr 3 1 1 1 ") == std::string::npos ||
            saved.find("\narpx 0 1 2 ") == std::string::npos) {
            printf("FAIL: AU octave state / append-only arpo line\n"); return 1;
        }
        AudioUnitUninitialize(t); AudioComponentInstanceDispose(t);
        printf("ARP octave shift recalled through AU; arpx/arpr layouts unchanged\n");
    }

    // 0.50.0: chance and LIVE recall without changing the prior pattern lines.
    {
        muew::Preset p = muew::factoryPresets()[0], got;
        p.voice.arpOn = true; p.voice.arpPatOn = true; p.voice.arpPatLen = 2;
        p.voice.arpPatRatchet[0] = 3; p.voice.arpPatOctave[0] = 1;
        p.voice.arpPatChance[0] = 75; p.voice.arpPatChance[1] = 50; p.voice.arpChanceLive = true;
        AudioUnit t = openUnit();
        bool ok = t && setState(t, p) && getState(t, got);
        auto saved = got.serialize();
        if (!ok || !(got == p) || saved.find("\narpc 1 75 50 100 100 ") == std::string::npos ||
            saved.find("\narpo 1 0 0 0 ") == std::string::npos ||
            saved.find("\narpr 3 1 1 1 ") == std::string::npos ||
            saved.find("\narpx 0 1 2 ") == std::string::npos) {
            printf("FAIL: AU chance state / append-only arpc line\n"); return 1;
        }
        AudioUnitUninitialize(t); AudioComponentInstanceDispose(t);
        printf("ARP chance and LIVE recalled through AU; arpx/arpr/arpo layouts unchanged\n");
    }

    // 0.51.0: new character state is optional and preserves the old noise line.
    {
        muew::Preset p = muew::factoryPresets()[0], got;
        p.voice.noiseLevel = .6; p.voice.noiseTone = .4;
        p.voice.noiseCharacter = 3; p.voice.noiseColor = .75;
        AudioUnit t = openUnit();
        bool ok = t && setState(t, p) && getState(t, got);
        auto saved = got.serialize();
        if (!ok || !(got == p) || saved.find("\nnoise 0.6 0.4\n") == std::string::npos ||
            saved.find("\nnoisex 3 0.75\n") == std::string::npos) {
            printf("FAIL: AU noise character state / append-only noisex line\n"); return 1;
        }
        AudioUnitUninitialize(t); AudioComponentInstanceDispose(t);
        printf("noise character and color recalled through AU; old noise line unchanged\n");
    }

    // Cocoa editor is advertised with a loadable bundle and class name.
    {
        UInt32 size = 0; Boolean writable = false;
        if (AudioUnitGetPropertyInfo(unit, kAudioUnitProperty_CocoaUI, kAudioUnitScope_Global, 0, &size, &writable) != noErr
            || size < sizeof(AudioUnitCocoaViewInfo)) { printf("FAIL: CocoaUI property info\n"); return 1; }
        AudioUnitCocoaViewInfo info{}; size = sizeof(info);
        if (AudioUnitGetProperty(unit, kAudioUnitProperty_CocoaUI, kAudioUnitScope_Global, 0, &info, &size) != noErr
            || !info.mCocoaAUViewBundleLocation || !info.mCocoaAUViewClass[0]
            || CFStringCompare(info.mCocoaAUViewClass[0], CFSTR(MUEW_VIEW_FACTORY_CLASS), 0) != kCFCompareEqualTo) {
            printf("FAIL: CocoaUI view info\n"); return 1;
        }
        CFRelease(info.mCocoaAUViewBundleLocation); CFRelease(info.mCocoaAUViewClass[0]);
        printf("cocoa editor advertised: %s\n", MUEW_VIEW_FACTORY_CLASS);
    }

    AudioUnitUninitialize(unit); AudioComponentInstanceDispose(unit);
    printf("PASS: host presets, sample offsets and audio render\n");
    return 0;
}
