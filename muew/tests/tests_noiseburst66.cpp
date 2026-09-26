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
static Stereo render(VoiceParams v,float vel,const std::vector<ModRoute>& routes={}){
 Synth s;s.init(48000);s.setParams(v,routes);s.noteOn(60,vel);Stereo x;x.l.resize(9600);x.r.resize(9600);
 s.renderPlanar(x.l.data(),x.r.data(),(int)x.l.size());return x;
}
static double diff(const Stereo&a,const Stereo&b){double e=0;for(size_t i=0;i<a.l.size();++i)e+=std::fabs(a.l[i]-b.l[i])+std::fabs(a.r[i]-b.r[i]);return e/a.l.size();}
int main(){
 Preset p,q;p.voice.noiseBurst=.2;p.voice.noiseBurstVelColor=.7;auto t=p.serialize();
 ck(t.find("\nnoisebvcolor 0.7\n")!=std::string::npos&&q.parse(t)&&q==p,"optional velocity-color depth round-trips");
 Preset old;old.voice.noiseBurst=.2;auto legacy=old.serialize();
 ck(legacy.find("noisebvcolor")==std::string::npos&&q.parse(legacy)&&q.voice.noiseBurstVelColor==0,"legacy depth zero and line omitted");
 ck(q.parse(legacy+"noisebvcolor -2\n")&&q.voice.noiseBurstVelColor==0&&q.parse(legacy+"noisebvcolor 2\n")&&q.voice.noiseBurstVelColor==1,"depth clamps 0..1");
 ck(q.parse(legacy+"noisebvcolor nan\n")&&q.voice.noiseBurstVelColor==0,"nonfinite depth ignored");
 using S=ModRoute::Source;using D=ModRoute::Dest;
 for(int mode=0;mode<4;++mode)for(int hq=0;hq<2;++hq)for(int stereo=0;stereo<2;++stereo){
  VoiceParams v;v.noiseLevel=.8;v.noiseWidth=stereo?.9:0;v.noiseCharacter=mode;v.noiseColor=.65;
  v.noiseBurst=.18;v.oscQuality=hq;v.ampA=.001;v.ampS=1;v.filterCutoff=18000;
  const auto base=render(v,.3f);v.noiseBurstVelColor=0;const auto zero=render(v,.3f);
  ck(base.l==zero.l&&base.r==zero.r,"default zero is byte-identical mono/stereo/HQ");
  v.noiseBurstVelColor=1;const auto soft=render(v,.3f);
  const auto hard=render(v,1.f);v.noiseBurstVelColor=0;const auto hardOld=render(v,1.f);
  ck(hard.l==hardOld.l&&hard.r==hardOld.r,"full velocity is byte-identical");
  if(mode==0)ck(base.l==soft.l&&base.r==soft.r,"CLASSIC remains byte-identical with depth on");
  else ck(diff(base,soft)>1e-5,"soft hit changes AIR/GRAIN/DUST texture");
  v.noiseBurst=0;v.noiseBurstVelColor=1;const auto sustained=render(v,.3f);v.noiseBurstVelColor=0;const auto sustainedOld=render(v,.3f);
  ck(sustained.l==sustainedOld.l&&sustained.r==sustainedOld.r,"BURST OFF remains byte-identical");
  if(mode>0){
   v.noiseBurst=.18;v.noiseBurstVelColor=1;
   const std::vector<ModRoute> route={{S::Macro1,D::NoiseColor,.24}};
   v.macros[0]=1;
   const auto both=render(v,.3f,route),velOnly=render(v,.3f);
   v.noiseBurstVelColor=0;const auto routeOnly=render(v,.3f,route);
   ck(diff(both,velOnly)>1e-5&&diff(both,routeOnly)>1e-5,"velocity color composes with matrix NOISE COLOR route");
  }
 }
 bool factory=true;for(const auto& f:factoryPresets())factory &= f.voice.noiseBurstVelColor==0&&f.serialize().find("noisebvcolor ")==std::string::npos;
 ck(factory&&factoryPresets().size()==108&&params::Count==40,"factory defaults and 40 AU IDs unchanged");
 printf("%s noise burst66 tests\n",bad?"FAIL":"ALL PASSED");return bad?1:0;
}
