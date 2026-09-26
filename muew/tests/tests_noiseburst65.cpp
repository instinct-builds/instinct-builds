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
static double tail(const std::vector<float>& full,const std::vector<float>& bed){double e=0;for(int i=6500;i<7200;++i){double v=full[i]-bed[i];e+=v*v;}return std::sqrt(e/700);}
int main(){
 Preset p,q;p.voice.noiseBurst=.2;p.voice.noiseBurstKeyTime=-.75;
 auto text=p.serialize();ck(text.find("\nnoisebkey -0.75\n")!=std::string::npos,"optional bipolar key time serializes");
 ck(q.parse(text)&&q==p,"key time round-trips");
 Preset old;old.voice.noiseBurst=.2;auto legacy=old.serialize();
 ck(legacy.find("noisebkey")==std::string::npos&&q.parse(legacy)&&q.voice.noiseBurstKeyTime==0,"old presets default zero");
 ck(q.parse(legacy+"noisebkey -5\n")&&q.voice.noiseBurstKeyTime==-1&&q.parse(legacy+"noisebkey 5\n")&&q.voice.noiseBurstKeyTime==1,"key time clamps bipolar");
 ck(q.parse(legacy+"noisebkey nan\n")&&q.voice.noiseBurstKeyTime==0,"nonfinite key depth ignored");
 for(int hq=0;hq<2;++hq)for(int stereo=0;stereo<2;++stereo){
  VoiceParams v;v.noiseLevel=.75;v.noiseWidth=stereo?.9:0;v.noiseBurst=.2;
  v.ampA=.001;v.ampS=1;v.oscQuality=hq;v.filterCutoff=18000;
  Synth zero,depth;zero.init(48000);depth.init(48000);zero.setParams(v,{});v.noiseBurstKeyTime=0;depth.setParams(v,{});
  zero.noteOn(108,.7);depth.noteOn(108,.7);
  auto za=render(zero,12000),da=render(depth,12000);
  ck(za.l==da.l&&za.r==da.r,"zero depth preserves complete audio at high note in mono/stereo/HQ");
  v.noiseBurstKeyTime=1;Synth low,high,bed;low.init(48000);high.init(48000);bed.init(48000);
  low.setParams(v,{});high.setParams(v,{});VoiceParams silent=v;silent.noiseLevel=0;bed.setParams(silent,{});
  low.noteOn(12,.7);high.noteOn(108,.7);bed.noteOn(108,.7);
  ck(low.voice(0).noiseBurstLength()==38400&&high.voice(0).noiseBurstLength()==2400,"extreme high shortens to quarter and low extends fourfold");
  auto highAudio=render(high,12000),bedAudio=render(bed,12000);
  VoiceParams neutral=v;neutral.noiseBurstKeyTime=0;Synth longHigh;longHigh.init(48000);longHigh.setParams(neutral,{});longHigh.noteOn(108,.7);
  auto neutralAudio=render(longHigh,12000);
  ck(tail(neutralAudio.l,bedAudio.l)>tail(highAudio.l,bedAudio.l)*3 &&
     tail(neutralAudio.r,bedAudio.r)>tail(highAudio.r,bedAudio.r)*3,"both stereo/HQ noise channels lose high-key tail as expected");
  v.noiseBurstKeyTime=-1;Synth inverted;inverted.init(48000);inverted.setParams(v,{});
  inverted.noteOn(108,.7);ck(inverted.voice(0).noiseBurstLength()==38400,"negative depth inverts the keyboard slope");
  v.noiseBurst=0;Synth offA,offB;offA.init(48000);offB.init(48000);v.noiseBurstKeyTime=0;offA.setParams(v,{});v.noiseBurstKeyTime=1;offB.setParams(v,{});
  offA.noteOn(108,.7);offB.noteOn(108,.7);za=render(offA,2048);da=render(offB,2048);
  ck(za.l==da.l&&za.r==da.r,"burst OFF leaves sustained noise byte-identical");
 }
 VoiceParams v;v.noiseBurstSync=5;v.noiseBurstKeyTime=1;v.ampA=.001;v.ampS=1;
 Synth s;s.init(48000);s.setParams(v,{});s.setTempo(60);s.noteOn(60,.7);
 ck(s.voice(0).noiseBurstLength()==12000,"middle C is neutral");
 s.noteOn(60,.7);s.noteOn(84,.7);ck(s.voice(0).noiseBurstLength()==12000&&s.voice(1).noiseBurstLength()==6000,"new note gets key time while prior voice keeps its latch");
 render(s,500);s.setTempo(120);ck(s.voice(1).noiseBurstLength()==6000,"tempo jump leaves active key-scaled note latched");
 s.noteOn(84,.7);ck(s.voice(1).noiseBurstLength()==3000,"retrigger takes new BPM");
 render(s,200);s.clearBurstHostTempo();ck(s.voice(1).noiseBurstLength()==3000,"lost clock leaves active note latched");
 s.noteOn(84,.7);ck(s.voice(1).noiseBurstLength()==3000,"clock fallback computes from 120 BPM");
 s.setTempo(60);for(int n=20;n<36;++n)s.noteOn(n,.7);s.noteOn(108,.7);
 bool stolen=false;for(int i=0;i<16;++i)if(s.voice(i).isActive()&&s.voice(i).note()==108){stolen=s.voice(i).noiseBurstLength()==3000;break;}
 ck(stolen,"voice steal latches high note rather than retaining low-note duration");
 bool factory=true;for(const auto& f:factoryPresets())factory &= f.voice.noiseBurstKeyTime==0&&f.serialize().find("noisebkey ")==std::string::npos;
 ck(factory&&factoryPresets().size()==108&&params::Count==40,"factory defaults and 40 AU IDs unchanged");
 printf("%s noise burst65 tests\n",bad?"FAIL":"ALL PASSED");return bad?1:0;
}
