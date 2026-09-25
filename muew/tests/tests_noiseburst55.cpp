#include "../src/preset.h"
#include "../src/factory_bank.h"
#include "../src/au_params.h"
#include <cmath>
#include <cstdio>
#include <vector>
using namespace muew;
static int bad=0;
static void ck(bool c,const char* msg){printf("%s %s\n",c?"ok:":"FAIL:",msg); bad+=!c;}
struct Stereo{std::vector<float> l,r;};
static Stereo render(VoiceParams p,int count=44100){Synth s;s.init(44100);s.setParams(p,{});s.noteOn(60,1);Stereo x;x.l.resize(count);x.r.resize(count);s.renderPlanar(x.l.data(),x.r.data(),count);return x;}
static double rms(const std::vector<float>&x,size_t a,size_t n){double sum=0;for(size_t i=a;i<a+n;++i)sum+=x[i]*x[i];return std::sqrt(sum/n);}
int main(){
 Preset p,q;p.voice.noiseLevel=.8;p.voice.noiseCharacter=2;p.voice.noiseColor=.74;p.voice.noiseWidth=.8;p.voice.noiseBurst=.12;
 auto text=p.serialize();ck(text.find("\nnoiseb 0.12\n")!=std::string::npos&&text.find("\nnoisew 0.8\n")!=std::string::npos,"noiseb follows prior noise controls without changing them");
 ck(q.parse(text)&&q==p,"burst duration round trips");
 Preset old; old.voice.noiseLevel=.8;auto legacy=old.serialize();ck(legacy.find("noiseb")==std::string::npos&&q.parse(legacy)&&q.voice.noiseBurst==0,"legacy state defaults to burst off");
 ck(q.parse(legacy+"noiseb 6\n")&&q.voice.noiseBurst==.5&&q.parse(legacy+"noiseb -1\n")&&q.voice.noiseBurst==0&&q.parse(legacy+"noiseb 0.0001\n")&&q.voice.noiseBurst==.005,"burst clamps 0 or 5-500ms");
 bool all=true;for(const auto&f:factoryPresets())all &= f.voice.noiseBurst==0 && f.serialize().find("noiseb ")==std::string::npos;
 ck(all&&factoryPresets().size()==108&&params::Count==40,"factory bank and existing AU IDs unchanged");
 for(int mode=0;mode<4;++mode)for(int hq=0;hq<2;++hq){
  VoiceParams v;v.osc1Shape=0;v.osc2Level=0;v.noiseLevel=.8;v.noiseCharacter=mode;v.noiseColor=.7;v.noiseWidth=.9;v.ampA=.001;v.ampS=1;v.oscQuality=hq;
  auto oldAudio=render(v);auto repeat=render(v);
  ck(oldAudio.l==repeat.l&&oldAudio.r==repeat.r,"default-off noise audio deterministic in both channels");
  v.noiseBurst=.08;auto burst=render(v);
  VoiceParams silent=v; silent.noiseLevel=0; auto bed=render(silent);
  for(size_t k=0;k<burst.l.size();++k){burst.l[k]-=bed.l[k];burst.r[k]-=bed.r[k];}
  const double earlyL=rms(burst.l,300,500),lateL=rms(burst.l,15000,500);
  const double earlyR=rms(burst.r,300,500),lateR=rms(burst.r,15000,500);
  char label[120];snprintf(label,sizeof(label),"mode %d HQ %d burst audible at onset and quiet after decay in both channels",mode,hq);
  ck(earlyL>lateL*3&&earlyR>lateR*3&&earlyL>.0001&&earlyR>.0001,label);
 }
 VoiceParams only;only.noiseLevel=0;only.noiseBurst=.06;only.ampA=.001;only.ampS=1;
 auto a=render(only);only.noiseBurst=0;auto b=render(only);ck(a.l==b.l&&a.r==b.r,"burst setting leaves oscillators untouched when noise is off");
 // Active noise route can bring a zero-base noise layer into the burst.
 VoiceParams v;v.ampA=.001;v.ampS=1;v.noiseBurst=.03;
 Synth s;s.init(44100);s.setParams(v,{{ModRoute::Source::Velocity,ModRoute::Dest::NoiseLevel,.8}});s.noteOn(60,1);
 Stereo first;first.l.resize(4410);first.r.resize(4410);s.renderPlanar(first.l.data(),first.r.data(),4410);
 ck(rms(first.l,20,500)>.0001,"burst works with modulated NOISE level at zero base");
 s.noteOn(60,1);Stereo again;again.l.resize(4410);again.r.resize(4410);s.renderPlanar(again.l.data(),again.r.data(),4410);
 ck(rms(again.l,20,500)>.0001,"retrigger restores onset on the same voice");
 printf("%s noise burst55 tests\n",bad?"FAIL":"ALL PASSED");return bad?1:0;
}
