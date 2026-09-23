// Host-level validation: discovery, factory presets, selection, sample-accurate MIDI and audio.
#include <AudioToolbox/AudioToolbox.h>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <vector>
#include <string>
#include "MUEWProperties.h"
#include "preset.h"

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

static constexpr int kExpectedPresets = 30;

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
