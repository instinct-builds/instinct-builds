// MUEW 0.53.0: AIR/GRAIN/DUST, narrow then full stereo width.
#include "synth.h"
#include "wav_writer.h"
#include <algorithm>
#include <cmath>
#include <cstdio>
using namespace muew;
int main(int argc,char**argv){
 const char* path=argc>1?argv[1]:"out/MUEW-0.53.0-noise-stereo-demo.wav";
 constexpr int sr=44100;std::vector<float> out;
 for(int mode=1;mode<=3;++mode)for(int width=0;width<2;++width){
  Synth s;s.init(sr);VoiceParams v;v.noiseCharacter=mode;v.noiseColor=.65;v.noiseWidth=width?1:0;
  v.noiseLevel=.55;v.osc1Shape=3;v.osc2Level=0;v.ampA=.002;v.ampS=.8;v.filterCutoff=9000;
  s.setParams(v,{});s.noteOn(60,.8f);
  for(int t=0;t<sr;++t){float x[2];s.renderStereo(x,1);out.push_back(x[0]);out.push_back(x[1]);}
 }
 float peak=0;for(float x:out)peak=std::max(peak,std::abs(x));
 if(!writeWav(path,out,sr,2))return 1;
 printf("MUEW stereo noise demo: AIR/GRAIN/DUST each mono then wide; %.2fs peak %.3f; %s\n",out.size()/(2.0*sr),peak,path);return 0;
}
