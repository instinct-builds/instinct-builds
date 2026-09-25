#include "../src/preset.h"
#include "../src/factory_bank.h"
#include "../src/au_params.h"
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <vector>
using namespace muew;
static int failed=0;
static void ck(bool yes,const char* label){printf("%s %s\n",yes?"ok:":"FAIL:",label);failed+=!yes;}
struct Stereo {std::vector<float> l,r;};
static Stereo play(VoiceParams v,int note=60) {Synth s;s.init(44100);s.setParams(v,{});s.noteOn(note,.9f);Stereo x;x.l.resize(22050);x.r.resize(22050);s.renderPlanar(x.l.data(),x.r.data(),(int)x.l.size());return x;}
static double rms(const std::vector<float>& x){double e=0;for(float a:x)e+=a*a;return std::sqrt(e/x.size());}
static double corr(const Stereo& x){double lr=0,ll=0,rr=0;for(size_t i=0;i<x.l.size();++i){lr+=x.l[i]*x.r[i];ll+=x.l[i]*x.l[i];rr+=x.r[i]*x.r[i];}return lr/std::sqrt(ll*rr);}
static double delta(const std::vector<float>&a,const std::vector<float>&b){double d=0;for(size_t i=0;i<a.size();++i)d+=std::abs(a[i]-b[i]);return d/a.size();}
int main(){
 Preset p,q;p.voice.noiseWidth=.75;p.voice.noiseLevel=.5;p.voice.noiseCharacter=2;
 auto text=p.serialize();ck(text.find("\nnoisew 0.75\n")!=std::string::npos&&text.find("\nnoisex 2 0.5\n")!=std::string::npos,"noisew is append-only after noisex");
 ck(q.parse(text)&&q==p,"stereo width round-trips");
 Preset old;old.voice.noiseLevel=.5;auto legacy=old.serialize();ck(legacy.find("noisew")==std::string::npos&&q.parse(legacy)&&q.voice.noiseWidth==0,"legacy presets keep mono zero default");
 ck(q.parse(legacy+"noisew 42\n")&&q.voice.noiseWidth==1&&q.parse(legacy+"noisew -42\n")&&q.voice.noiseWidth==0,"width clamps to 0..1");
 bool all=true;
 for(const auto& f:factoryPresets())all &= f.voice.noiseWidth==0 && f.serialize().find("noisew ")==std::string::npos;
 ck(all&&factoryPresets().size()==108&&params::Count==40,"108 factory presets mono and 40 AU IDs unchanged");
 for(int mode=0;mode<4;++mode)for(int hq=0;hq<2;++hq){
  VoiceParams v;v.osc1Shape=0;v.osc2Level=0;v.noiseLevel=.7;v.noiseCharacter=mode;v.noiseColor=.65;v.filterMode=2;v.filterCutoff=18000;v.ampA=.001;v.ampS=1;v.oscQuality=hq;
  auto mono=play(v);v.noiseWidth=.5;auto half=play(v);v.noiseWidth=1;auto wide=play(v);
  char label[140];snprintf(label,sizeof(label),"mode %d HQ %d: stereo channels decorrelate and mono remains centered",mode,hq);
  ck(corr(mono)>.999999 && corr(wide)<.8 && rms(wide.l)>.0001 && rms(wide.r)>.0001,label);
  snprintf(label,sizeof(label),"mode %d HQ %d: left legacy audio stays sample-identical",mode,hq);
  ck(delta(mono.l,wide.l)==0,label);
  snprintf(label,sizeof(label),"mode %d HQ %d: intermediate width decorrelates less than full width",mode,hq);
  ck(corr(half)<.999 && corr(half)>corr(wide),label);
  bool finite=true;double peak=0;for(size_t i=0;i<wide.l.size();++i){float l=wide.l[i],r=wide.r[i];float fold=.5f*(l+r);finite &=std::isfinite(l)&&std::isfinite(r)&&std::isfinite(fold);peak=std::max({peak,(double)std::abs(l),(double)std::abs(r),(double)std::abs(fold)});}
  snprintf(label,sizeof(label),"mode %d HQ %d: bounded stereo and fold-down peak",mode,hq);ck(finite&&peak<1,label);
  if(hq){ // Legacy HQ halfband delays 7.5 samples. New right stream must line up as well.
   double onsetL=0,onsetR=0;for(int i=0;i<40;++i){onsetL+=std::abs(wide.l[i]);onsetR+=std::abs(wide.r[i]);}
   ck(onsetL>0&&onsetR>0,"HQ left/right noise both arrive in the first 40 samples");
  }
 }
 puts(failed?"NOISE WIDTH53 FAILED":"ALL NOISE WIDTH53 TESTS PASSED");return failed?1:0;
}
