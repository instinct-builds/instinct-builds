#include "../src/preset.h"
#include "../src/factory_bank.h"
#include "../src/synth.h"
#include "../src/au_params.h"
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <vector>
using namespace muew;
static int bad=0;static void ck(bool x,const char*s){printf("%s %s\n",x?"ok:":"FAIL:",s);bad+=!x;}
static std::vector<float> render(Preset p,int note=60){Synth s;s.init(44100);s.setParams(p.voice,p.routes);s.setFX(p.fx);s.noteOn(note,.8f);std::vector<float> x(22050),r(22050);s.renderPlanar(x.data(),r.data(),(int)x.size());return x;}
static double energy(const std::vector<float>& x){double e=0;for(float v:x)e+=v*v;return e/x.size();}
static double diff(const std::vector<float>&a,const std::vector<float>&b){double d=0;for(size_t i=0;i<a.size();++i)d+=std::fabs(a[i]-b[i]);return d/a.size();}
int main(){
 Preset p,q;p.voice.noiseLevel=.6;p.voice.noiseTone=.37;p.voice.noiseCharacter=2;p.voice.noiseColor=.73;
 auto t=p.serialize();ck(t.find("\nnoise 0.6 0.37\n")!=std::string::npos&&t.find("\nnoisex 2 0.73\n")!=std::string::npos,"new noisex appends without changing noise line");
 ck(q.parse(t)&&q==p,"noise character and color round-trip");
 p.voice.noiseCharacter=0;p.voice.noiseColor=.5;const auto old=p.serialize();ck(old.find("\nnoisex ")==std::string::npos,"legacy noise omits new line");
 Preset legacy;ck(legacy.parse(old)&&legacy.voice.noiseCharacter==0&&legacy.voice.noiseColor==.5,"old preset defaults to unchanged classic character");
 Preset bounded;ck(bounded.parse(old+"noisex 99 -20\n")&&bounded.voice.noiseCharacter==3&&bounded.voice.noiseColor==0,"noisex clamps mode and color");
 Preset x=p;x.voice.osc1Shape=0;x.voice.osc2Level=0;x.voice.filterMode=2;x.voice.filterCutoff=18000;x.voice.ampA=.001;x.voice.ampS=1;x.voice.noiseLevel=.8;
 auto classic=render(x);std::vector<std::vector<float>> modes;
 bool boundedSound=true;double e[4]={};for(int m=0;m<4;++m){x.voice.noiseCharacter=m;x.voice.noiseColor=.5;modes.push_back(render(x));e[m]=energy(modes.back());for(float a:modes.back()) boundedSound &= std::isfinite(a)&&std::fabs(a)<1;}
 printf("mode energies classic %.6g air %.6g grain %.6g dust %.6g\n",e[0],e[1],e[2],e[3]);
 ck(boundedSound&&e[1]>1e-6&&e[2]>1e-6&&e[3]>1e-6,"three distinct characters are audible, finite and bounded");
 ck(diff(modes[0],modes[1])>.001&&diff(modes[1],modes[2])>.001&&diff(modes[2],modes[3])>.001,"AIR GRAIN DUST sound distinct from each other");
 x.voice.noiseCharacter=1;x.voice.noiseColor=0;auto airDark=render(x);x.voice.noiseColor=1;auto airBright=render(x);ck(diff(airDark,airBright)>.001,"continuous COLOR changes AIR sound");
 x.voice.noiseCharacter=2;x.voice.noiseColor=0;auto slow=render(x);x.voice.noiseColor=1;auto fast=render(x);ck(diff(slow,fast)>.001,"continuous COLOR changes GRAIN sound");
 x.voice.noiseCharacter=3;x.voice.noiseColor=0;auto sparse=render(x);x.voice.noiseColor=1;auto dense=render(x);ck(diff(sparse,dense)>.001,"continuous COLOR changes DUST sound");
 x.voice.noiseLevel=0;x.voice.noiseCharacter=3;auto muted=render(x);x.voice.noiseCharacter=0;ck(diff(muted,render(x))==0,"zero noise level skips new character sample-identically");
 ck(params::Count==40&&params::NoiseTone==25,"published AU parameter IDs stay at 40");
 // Old factory presets must all select the unchanged CLASSIC path. Full
 // render-byte parity is checked against 0.50.0 on the *same* macOS runner.
 bool legacyFactory = factoryPresets().size()==108;
 for (const Preset& f : factoryPresets()) legacyFactory &= f.voice.noiseCharacter==0 && f.voice.noiseColor==.5f && f.serialize().find("\nnoisex ")==std::string::npos;
 ck(legacyFactory,"all 108 factory presets keep CLASSIC and legacy serialization");
 puts(bad?"NOISE51 FAILED":"ALL NOISE51 TESTS PASSED");return bad?1:0;
}
