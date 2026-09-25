// MUEW 0.51.0: dry noise characters, then each layered beneath a pluck.
#include "synth.h"
#include "wav_writer.h"
#include <algorithm>
#include <cmath>
#include <cstdio>
using namespace muew;
int main(int argc,char**argv){
 const char* path=argc>1?argv[1]:"out/MUEW-0.51.0-noise-color-demo.wav";
 constexpr int sr=44100;std::vector<float> out;
 for(int layered=0;layered<2;++layered)for(int mode=1;mode<=3;++mode){
   Synth s;s.init(sr);VoiceParams v;v.noiseCharacter=mode;v.noiseColor=mode==1?.65:mode==2?.55:.75;
   v.noiseLevel=layered?.35:.65;v.osc1Shape=layered?3:0;v.osc2Level=0;v.ampA=.001;v.ampR=.03;
   v.filterCutoff=layered?6500:10000;
   s.setParams(v,{});s.noteOn(60,.85f);
   for(int t=0;t<sr;++t){float x[2];s.renderStereo(x,1);out.push_back(x[0]);out.push_back(x[1]);}
 }
 float peak=0;for(float x:out)peak=std::max(peak,std::fabs(x));
 if(!writeWav(path,out,sr,2))return 1;
 printf("MUEW noise character demo: AIR / GRAIN / DUST, dry then pluck layers; %.2fs peak %.3f; %s\n",out.size()/(2.0*sr),peak,path);return 0;
}
