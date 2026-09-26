#include "../src/preset.h"
#include "../src/factory_bank.h"
#include "../src/au_params.h"
#include <cmath>
#include <cstdio>
#include <vector>
using namespace muew;
static int bad=0;
static void ck(bool b,const char* m){printf("%s %s\n",b?"ok:":"FAIL:",m);bad+=!b;}
struct Stereo{std::vector<float> l,r;};
static Stereo render(Synth& s,int n){Stereo x;x.l.resize(n);x.r.resize(n);s.renderPlanar(x.l.data(),x.r.data(),n);return x;}
int main(){
 Preset p,q;p.voice.noiseBurst=.125;p.voice.noiseBurstVelocity=.4;p.voice.noiseBurstVelTime=.6;
 auto text=p.serialize();ck(text.find("\nnoisebvel 0.4\nnoisebvtime 0.6\n")!=std::string::npos,"velocity-time line follows existing velocity level line");
 ck(q.parse(text)&&q==p,"velocity time round-trips");
 Preset old;old.voice.noiseBurst=.125;auto legacy=old.serialize();
 ck(legacy.find("noisebvtime")==std::string::npos&&q.parse(legacy)&&q.voice.noiseBurstVelTime==0,"legacy defaults to full burst time");
 ck(q.parse(legacy+"noisebvtime -1\n")&&q.voice.noiseBurstVelTime==0&&q.parse(legacy+"noisebvtime 2\n")&&q.voice.noiseBurstVelTime==1,"depth clamps");
 ck(q.parse(legacy+"noisebvtime nan\n")&&q.voice.noiseBurstVelTime==0,"nonfinite depth ignored");
 for(int hq=0;hq<2;++hq)for(int mode=0;mode<4;++mode){
  VoiceParams v;v.noiseLevel=.7;v.noiseWidth=.85;v.noiseCharacter=mode;v.noiseColor=.68;
  v.ampA=.001;v.ampS=1;v.oscQuality=hq;v.noiseBurst=.2;v.filterCutoff=18000;
  Synth a,b;a.init(48000);b.init(48000);a.setParams(v,{});v.noiseBurstVelTime=1;b.setParams(v,{});
  a.noteOn(60,.25);b.noteOn(60,.25);
  ck(a.voice(0).noiseBurstLength()==9600&&b.voice(0).noiseBurstLength()==2400,"soft hit shortens from 200ms to 50ms");
  auto longTail=render(a,12000),shortTail=render(b,12000);
  VoiceParams bedP=v;bedP.noiseLevel=0;Synth bed;bed.init(48000);bed.setParams(bedP,{});bed.noteOn(60,.25);auto bedAudio=render(bed,12000);
  auto noiseTail=[&](const std::vector<float>& full,const std::vector<float>& base){
      double e=0;for(int i=4200;i<5000;++i){const double n=full[i]-base[i];e+=n*n;}
      return std::sqrt(e/800);
  };
  const double longL=noiseTail(longTail.l,bedAudio.l),longR=noiseTail(longTail.r,bedAudio.r);
  const double shortL=noiseTail(shortTail.l,bedAudio.l),shortR=noiseTail(shortTail.r,bedAudio.r);
  ck(longL>1e-5&&longR>1e-5&&longL>shortL*3&&longR>shortR*3,
     "stereo/HQ noise tail lasts after soft hit ends");
  v.noiseBurstVelTime=0;Synth hardA,hardB;hardA.init(48000);hardB.init(48000);hardA.setParams(v,{});v.noiseBurstVelTime=1;hardB.setParams(v,{});
  hardA.noteOn(60,1);hardB.noteOn(60,1);auto x=render(hardA,10000),y=render(hardB,10000);
  ck(x.l==y.l&&x.r==y.r,"hard hit audio remains byte-identical with full time depth");
  v.noiseBurst=0;Synth offA,offB;offA.init(48000);offB.init(48000);v.noiseBurstVelTime=0;offA.setParams(v,{});
  v.noiseBurstVelTime=1;offB.setParams(v,{});offA.noteOn(60,.25);offB.noteOn(60,.25);
  x=render(offA,2048);y=render(offB,2048);
  ck(x.l==y.l&&x.r==y.r,"OFF burst retains sustained noise bit-for-bit");
 }
 VoiceParams v;v.noiseBurstSync=5;v.noiseBurstVelTime=.8;v.ampA=.001;v.ampS=1;
 Synth s;s.init(48000);s.setParams(v,{});s.setTempo(60);s.noteOn(60,.5);
 ck(s.voice(0).noiseBurstLength()==7200,"1/16 at 60 BPM and 50% velocity gives 60% of 12000 samples");
 render(s,200);s.setTempo(240);ck(s.voice(0).noiseBurstLength()==7200,"tempo jump cannot retime active velocity-scaled note");
 s.noteOn(60,.5);ck(s.voice(0).noiseBurstLength()==1800,"retrigger takes new tempo and velocity");
 render(s,200);s.clearBurstHostTempo();ck(s.voice(0).noiseBurstLength()==1800,"lost host clock cannot retime active note");
 s.noteOn(60,.5);ck(s.voice(0).noiseBurstLength()==3600,"next note uses 120 fallback then velocity length");
 v.noiseBurstVelTime=0;s.setParams(v,{});s.noteOn(60,.5);ck(s.voice(0).noiseBurstLength()==6000,"zero depth restores original sync length");
 bool factory=true;for(const auto& f:factoryPresets())factory &= f.voice.noiseBurstVelTime==0&&f.serialize().find("noisebvtime ")==std::string::npos;
 ck(factory&&factoryPresets().size()==108&&params::Count==40,"factory defaults and 40 AU IDs unchanged");
 printf("%s noise burst64 tests\n",bad?"FAIL":"ALL PASSED");return bad?1:0;
}
