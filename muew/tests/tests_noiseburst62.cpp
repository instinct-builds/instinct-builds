#include "../src/preset.h"
#include "../src/factory_bank.h"
#include "../src/au_params.h"
#include <cstdio>
#include <vector>
using namespace muew;
static int failures=0;
static void ck(bool b,const char* m){printf("%s %s\n",b?"ok:":"FAIL:",m); failures+=!b;}
static void run(Synth& s,int count,std::vector<float>& l,std::vector<float>& r){
    l.resize(count);r.resize(count);s.renderPlanar(l.data(),r.data(),count);
}
int main(){
    VoiceParams p;p.osc2Level=0;p.noiseLevel=.8;p.noiseWidth=.8;
    p.noiseBurstSync=5;p.noiseBurstAttack=.2;p.noiseBurstCurve=.3;p.ampA=.001;p.ampS=1;
    Synth a,b;a.init(48000);b.init(48000);a.setParams(p,{});b.setParams(p,{});
    a.setTempo(60);b.setTempo(60);a.noteOn(60,1);b.noteOn(60,1);
    ck(a.voice(0).noiseBurstLength()==12000,"note starts with 60 BPM duration");
    std::vector<float> al,ar,bl,br;run(a,2000,al,ar);run(b,2000,bl,br);
    a.setTempo(240);ck(a.voice(0).noiseBurstLength()==12000,"valid faster host BPM does not shorten active note");
    run(a,15000,al,ar);run(b,15000,bl,br);
    ck(al==bl&&ar==br,"tempo jump mid-note leaves stereo noise render byte-identical");
    a.noteOn(60,1);ck(a.voice(0).noiseBurstLength()==3000,"retrigger latches new fast BPM");
    run(a,500,al,ar);a.setTempo(30);
    ck(a.voice(0).noiseBurstLength()==3000,"slower tempo cannot lengthen active note");
    a.noteOn(60,1);ck(a.voice(0).noiseBurstLength()==24000,"next note uses slower tempo");
    run(a,500,al,ar);a.clearBurstHostTempo();
    ck(a.voice(0).noiseBurstLength()==24000,"missing clock cannot cut active note short");
    a.noteOn(60,1);ck(a.voice(0).noiseBurstLength()==6000,"note after clock loss takes 120 BPM fallback");
    run(a,500,al,ar);a.setTempo(60);a.setParams(p,{});
    ck(a.voice(0).noiseBurstLength()==6000,"preset refresh and restored clock cannot retime active note");
    a.noteOn(60,1);ck(a.voice(0).noiseBurstLength()==12000,"retrigger after restored clock uses current tempo");
    a.init(48000);a.setParams(p,{});a.setTempo(60);
    ck(a.voice(0).noiseBurstLength()==12000,"hard reset leaves next note ready for current tempo");
    p.noiseBurstSync=0;p.noiseBurst=.125;a.setParams(p,{});a.setTempo(240);a.noteOn(60,1);
    ck(a.voice(0).noiseBurstLength()==6000,"FREE duration is independent of host tempo");
    a.setTempo(60);ck(a.voice(0).noiseBurstLength()==6000,"FREE active note stays unchanged");
    bool factory=true;for(const auto& f:factoryPresets())factory &= f.voice.noiseBurstSync==0;
    ck(factory&&factoryPresets().size()==108&&params::Count==40,"factory bank and 40 AU parameter IDs unchanged");
    printf("%s noise burst62 tests\n",failures?"FAIL":"ALL PASSED");return failures?1:0;
}
