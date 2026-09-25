// MUEW 0.48.0: straight arp, then alternating three/four-note retriggers.
#include "synth.h"
#include "wav_writer.h"
#include <algorithm>
#include <cmath>
#include <cstdio>
using namespace muew;
int main(int argc,char** argv){
 const char* path=argc>1?argv[1]:"out/MUEW-0.48.0-arp-ratchet-demo.wav";
 constexpr int sr=44100, block=128;std::vector<float> out;
 for(int scene=0;scene<4;++scene){
   Synth s;s.init(sr);s.setTempo(120);
   VoiceParams v;v.osc1Shape=3;v.osc2Level=0;v.filterCutoff=12000;v.ampA=.002;v.ampR=.025;
   v.arpOn=true;v.arpPatOn=true;v.arpPatLen=4;v.arpRate=3;v.arpGate=.42;
   v.arpPatKind[3]=arp::StepRest;v.arpPatVel[1]=100;v.arpPatVel[2]=82;
   if(scene%2){v.arpPatRatchet[0]=3;v.arpPatRatchet[1]=4;v.arpPatRatchet[2]=2;}
   s.setParams(v,{});s.noteOn(48,.8f);s.noteOn(55,.77f);s.noteOn(60,.72f);
   for(int t=0;t<sr*2;++t){float x[2];s.renderStereo(x,1);out.push_back(x[0]);out.push_back(x[1]);}
 }
 float peak=0;for(float x:out)peak=std::max(peak,std::fabs(x));
 if(!writeWav(path,out,sr,2))return 1;
 printf("MUEW ratchet demo: straight / ratchet / straight / ratchet; %.2fs peak %.3f; %s\n",out.size()/(2.0*sr),peak,path);return 0;
}
