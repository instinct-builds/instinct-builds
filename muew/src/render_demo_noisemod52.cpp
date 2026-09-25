// MUEW 0.52.0: compare a static AIR/GRAIN/DUST palette with moving NOISE COLOR.
#include "synth.h"
#include "wav_writer.h"
#include <algorithm>
#include <cmath>
#include <cstdio>
using namespace muew;
int main(int argc,char** argv){
 const char* path=argc>1?argv[1]:"out/MUEW-0.52.0-noise-modulation-demo.wav";
 constexpr int sr=44100;std::vector<float> out;
 for(int mode=1;mode<=3;++mode)for(int moving=0;moving<2;++moving){
  Synth s;s.init(sr);VoiceParams v;v.noiseCharacter=mode;v.noiseColor=.45;v.noiseLevel=.52;
  v.osc1Shape=3;v.osc2Level=0;v.ampA=.003;v.ampS=.8;v.filterCutoff=8500;v.lfo1Rate=3;
  ModRoute route{ModRoute::Source::LFO1,ModRoute::Dest::NoiseColor,.4};
  s.setParams(v,moving?std::vector<ModRoute>{route}:std::vector<ModRoute>{});s.noteOn(60,.85f);
  for(int t=0;t<sr;++t){float x[2];s.renderStereo(x,1);out.push_back(x[0]);out.push_back(x[1]);}
 }
 float peak=0;for(float x:out)peak=std::max(peak,std::abs(x));
 if(!writeWav(path,out,sr,2))return 1;
 printf("MUEW noise modulation demo: AIR, GRAIN, DUST each static then LFO color; %.2fs peak %.3f; %s\n",out.size()/(2.0*sr),peak,path);return 0;
}
