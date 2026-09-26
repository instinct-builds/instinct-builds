#include "../src/preset.h"
#include "../src/factory_bank.h"
#include "../src/au_params.h"
#include <cstdio>
#include <cmath>
using namespace muew;
static int failures=0;
static void ck(bool b,const char* m){printf("%s %s\n",b?"ok:":"FAIL:",m);failures+=!b;}
int main(){
    Preset p,q;p.voice.noiseBurst=.24;p.voice.noiseBurstSync=5;p.voice.noiseBurstAttack=.25;
    auto text=p.serialize();ck(text.find("\nnoiseb 0.24\nnoisebsync 5\nnoiseenv 0.25 0\n")!=std::string::npos,"sync appends state after free duration");
    ck(q.parse(text)&&q==p,"division and retained free duration round trip");
    Preset old;old.voice.noiseBurst=.24;auto legacy=old.serialize();
    ck(legacy.find("noisebsync")==std::string::npos&&q.parse(legacy)&&q.voice.noiseBurstSync==0,"legacy duration remains free");
    ck(q.parse(legacy+"noisebsync 999\n")&&q.voice.noiseBurstSync==kSyncCount-1,"division clamps");
    ck(q.parse(legacy+"noisebsync -2\n")&&q.voice.noiseBurstSync==0,"invalid negative division becomes free");
    ck(noiseBurstSamples(.24,0,200,44100)==10584,"free duration ignores host BPM");
    ck(noiseBurstSamples(0,0,0,44100)==0,"default OFF remains sustained");
    ck(noiseBurstSamples(.24,5,120,48000)==6000&&noiseBurstSamples(.24,5,60,48000)==12000,"1/16 follows 120 and 60 BPM");
    ck(noiseBurstSamples(0,3,120,48000)==24000,"sync can enable burst while free duration is OFF");
    ck(noiseBurstSamples(.24,5,0,48000)==6000&&noiseBurstSamples(.24,5,NAN,48000)==6000&&noiseBurstSamples(.24,5,INFINITY,48000)==6000,"missing or invalid tempo deterministically falls back to 120 BPM");
    ck(noiseBurstSamples(.24,1,20,44100)==529200,"slow host tempo can exceed free 500ms without truncation");
    VoiceParams v;v.noiseBurst=.24;v.noiseBurstSync=5;v.ampA=.001;v.ampS=1;
    Synth s;s.init(48000);s.setParams(v,{});
    ck(s.voice(0).noiseBurstLength()==6000,"standalone without host tempo uses 120 BPM");
    s.setTempo(60);ck(s.voice(0).noiseBurstLength()==12000,"valid tempo updates length");
    s.clearBurstHostTempo();ck(s.voice(0).noiseBurstLength()==6000,"disappearing host clock clears prior BPM");
    s.setTempo(90);s.clearBurstHostTempo();s.setParams(v,{});
    ck(s.voice(0).noiseBurstLength()==6000,"preset update after clock loss cannot revive stale BPM");
    s.setTempo(90);ck(s.voice(0).noiseBurstLength()==8000,"same BPM after clock returns restores host timing");
    s.clearBurstHostTempo();ck(s.voice(0).noiseBurstLength()==6000,"subsequent clock loss returns to fallback again");
    bool unchanged=true;for(const auto& f:factoryPresets())unchanged &= f.voice.noiseBurstSync==0&&f.serialize().find("noisebsync ")==std::string::npos;
    ck(unchanged&&factoryPresets().size()==108&&params::Count==40,"factory bank and 40 AU IDs unchanged");
    printf("%s noise burst60 tests\n",failures?"FAIL":"ALL PASSED");return failures?1:0;
}
