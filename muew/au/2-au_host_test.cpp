// Host-level validation: discovery, factory presets, selection, sample-accurate MIDI and audio.
#include <AudioToolbox/AudioToolbox.h>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <vector>

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
    AudioUnitUninitialize(unit); AudioComponentInstanceDispose(unit);
    printf("PASS: host presets, sample offsets and audio render\n");
    return 0;
}
