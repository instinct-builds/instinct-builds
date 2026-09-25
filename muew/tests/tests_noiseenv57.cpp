#include "../src/preset.h"
#include "../src/factory_bank.h"
#include "../src/au_params.h"
#include <cmath>
#include <cstdio>
#include <vector>
using namespace muew;
static int bad=0;
static void ck(bool ok,const char*msg){printf("%s %s\n",ok?"ok:":"FAIL:",msg);bad+=!ok;}
struct Stereo {std::vector<float> l,r;};
static Stereo render(VoiceParams p){Synth s;s.init(44100);s.setParams(p,{});s.noteOn(60,1);Stereo x;x.l.resize(16000);x.r.resize(16000);s.renderPlanar(x.l.data(),x.r.data(),16000);return x;}
static double rms(const std::vector<float>&x,int a,int n){double sum=0;for(int i=a;i<a+n;++i)sum+=x[i]*x[i];return std::sqrt(sum/n);}
int main(){
 Preset p,q;p.voice.noiseBurst=.2;p.voice.noiseBurstAttack=.25;p.voice.noiseBurstCurve=-.75;
 auto text=p.serialize();ck(text.find("\nnoiseb 0.2\nnoiseenv 0.25 -0.75\n")!=std::string::npos,"new envelope appends state after legacy duration");
 ck(q.parse(text)&&q==p,"attack and curve round trip");
 Preset old;old.voice.noiseBurst=.12;auto legacy=old.serialize();ck(legacy.find("noiseenv")==std::string::npos&&q.parse(legacy)&&q.voice.noiseBurstAttack==0&&q.voice.noiseBurstCurve==0,"legacy linear burst has unchanged defaults and serialization");
 ck(q.parse(legacy+"noiseenv 9 -9\n")&&q.voice.noiseBurstAttack==.8&&q.voice.noiseBurstCurve==-1,"attack and curve clamp");
 ck(q.parse(legacy+"noiseenv nan 0\n")&&q.voice.noiseBurstAttack==0&&q.voice.noiseBurstCurve==0,"nonfinite envelope input ignored");
 ck(noiseBurstGain(400,0,.8,1)==1&&noiseBurstGain(0,100,0,0)==1&&noiseBurstGain(25,100,0,0)==.75f&&noiseBurstGain(100,100,0,0)==0,"OFF bypass and linear legacy math");
 ck(noiseBurstGain(0,100,.2,0)==0&&noiseBurstGain(10,100,.2,0)==.5f&&noiseBurstGain(20,100,.2,0)==1,"attack rises within fixed total duration");
 ck(noiseBurstGain(60,100,.2,-1)<noiseBurstGain(60,100,.2,0)&&noiseBurstGain(60,100,.2,1)>noiseBurstGain(60,100,.2,0),"fast and slow decay shapes bracket linear");
 bool factory=true;for(const auto& f:factoryPresets())factory &= f.voice.noiseBurst==0&&f.voice.noiseBurstAttack==0&&f.voice.noiseBurstCurve==0&&f.serialize().find("noiseenv ")==std::string::npos;
 ck(factory&&factoryPresets().size()==108&&params::Count==40,"factory content and 40 AU IDs unchanged");
 for(int mode=0;mode<4;++mode)for(int hq=0;hq<2;++hq){
  VoiceParams v;v.osc1Shape=0;v.osc2Level=0;v.noiseLevel=.8;v.noiseCharacter=mode;v.noiseColor=.7;v.noiseWidth=.9;v.ampA=.001;v.ampS=1;v.oscQuality=hq;
  auto off=render(v);v.noiseBurstAttack=.5;v.noiseBurstCurve=1;auto offShape=render(v);
  ck(off.l==offShape.l&&off.r==offShape.r,"OFF ignores shape byte-exact in both channels");
  v.noiseBurst=.12;v.noiseBurstAttack=0;v.noiseBurstCurve=0;auto linear=render(v);
  v.noiseBurstAttack=.25;v.noiseBurstCurve=0;auto attack=render(v);
  v.noiseBurstAttack=0;v.noiseBurstCurve=-1;auto fast=render(v);
  v.noiseBurstCurve=1;auto slow=render(v);
  VoiceParams silent=v;silent.noiseLevel=0;auto bed=render(silent);
  auto energy=[&](const Stereo& a,int begin){std::vector<float> l(500),r(500);for(int i=0;i<500;++i){l[i]=a.l[begin+i]-bed.l[begin+i];r[i]=a.r[begin+i]-bed.r[begin+i];}return std::min(rms(l,0,500),rms(r,0,500));};
  ck(energy(attack,100)<energy(linear,100)*.7&&energy(attack,1700)>energy(attack,100)*2,"attack suppresses first transient then opens in both channels");
  ck(energy(fast,2500)<energy(linear,2500)*.75&&energy(slow,2500)>energy(linear,2500)*1.1,"curve shapes later noise decay in both channels");
  ck(energy(fast,6500)<.00001&&energy(slow,6500)<.00001,"all curves end at fixed total duration");
 }
 printf("%s noise env57 tests\n",bad?"FAIL":"ALL PASSED");return bad?1:0;
}
