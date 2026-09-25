#include "../src/preset.h"
#include "../src/factory_bank.h"
#include "../src/synth.h"
#include "../src/ui_model.h"
#include "../src/au_params.h"
#include <cmath>
#include <cstdio>
#include <vector>
using namespace muew;
static int failures=0;
static void ck(bool ok,const char* msg){printf("%s %s\n",ok?"ok:":"FAIL:",msg); failures+=!ok;}
static std::vector<float> render(const VoiceParams& v,const std::vector<ModRoute>& routes,int velocity=100) {
 Synth s;s.init(44100);s.setParams(v,routes);s.noteOn(60,velocity/127.0f);
 std::vector<float> left(22050),right(22050);s.renderPlanar(left.data(),right.data(),(int)left.size());return left;
}
static double delta(const std::vector<float>&a,const std::vector<float>&b){double d=0;for(size_t i=0;i<a.size();++i)d+=std::abs(a[i]-b[i]);return d/a.size();}
int main(){
 using D=ModRoute::Dest;using S=ModRoute::Source;
 ck((int)D::NoiseColor==32 && params::Count==40 && ui::matrixDests().back()==D::NoiseColor && std::string(ui::destName(D::NoiseColor))=="NOISE COLOR", "destination 32 appended, 40 published AU IDs unchanged, matrix label visible");
 VoiceParams v;v.noiseLevel=.8;v.noiseColor=.5;v.osc1Shape=0;v.osc2Level=0;v.ampA=.001;v.ampS=1;v.filterMode=2;v.filterCutoff=18000;
 std::vector<S> src={S::LFO1,S::MSEG1,S::Velocity,S::Macro1};
 for(S source:src){ModRoute r{source,D::NoiseColor,.65};VoiceParams driven=v;
  if(source==S::Macro1)driven.macros[0]=1;
  if(source==S::MSEG1){driven.mseg1Points={{0,0},{.1,1},{.4,-1},{1,0}};}
  for(int mode=1;mode<=3;++mode){driven.noiseCharacter=mode;
   auto dry=render(driven,{}), wet=render(driven,{r});char label[120];snprintf(label,sizeof(label),"mode %d source %d audibly changes color",mode,(int)source);ck(delta(dry,wet)>0.00001,label);
   bool bounded=true;for(float x:wet)bounded&=std::isfinite(x)&&std::abs(x)<1.0f;snprintf(label,sizeof(label),"mode %d source %d remains finite/bounded",mode,(int)source);ck(bounded,label);
  }
  driven.noiseCharacter=0;ck(delta(render(driven,{}),render(driven,{r}))==0,"CLASSIC ignores NOISE COLOR route sample-identically");
 }
 Preset p;p.voice.noiseLevel=.6;p.voice.noiseCharacter=2;p.voice.noiseColor=.45;
 p.routes={ModRoute{S::LFO1,D::NoiseColor,.6},ModRoute{S::MSEG2,D::NoiseColor,-.4},ModRoute{S::Velocity,D::NoiseColor,.2},ModRoute{S::Macro1,D::NoiseColor,-.2}};
 auto text=p.serialize();Preset q;ck(q.parse(text)&&q==p&&text.find("route 0 32 0.6")!=std::string::npos,"all new routes round-trip through old route line with numeric ID 32");
 ck(ui::routeActive(p.routes[0])&&ui::routeScale(D::NoiseColor)==1.0,"NOISE COLOR accepts voice modulation and normalized amount");
 ModRoute vel{S::Velocity,D::NoiseColor,.8};v.noiseCharacter=1;
 ck(delta(render(v,{vel},30),render(v,{vel},120))>.0001,"velocity changes noise color between two notes");
 ModRoute bad{S::FxLfo1,D::NoiseColor,.8};ck(!ui::routeActive(bad),"rack-only LFO cannot modulate voice-local noise color");
 bool factories=factoryPresets().size()==108;for(const auto&f:factoryPresets())for(const auto&r:f.routes)factories&=(int)r.dest<32;
 ck(factories,"all 108 factory presets predate destination 32");
 printf("%s\n",failures?"NOISE MOD 52 FAILED":"ALL NOISE MOD 52 TESTS PASSED");return failures?1:0;
}
