// MUEW 0.46.0: matched phrases compare normal profile transfer with reversed source ratios.
#include "synth.h"
#include "spectral_clipboard.h"
#include "wav_writer.h"
#include <algorithm>
#include <cmath>
#include <cstdio>
using namespace muew;
int main(int argc,char** argv){
 const char* path=argc>1?argv[1]:"out/MUEW-0.46.0-spectral-reverse-demo.wav";
 constexpr int sr=44100, block=128;
 TableFrames base(16,shapeFrame(2));
 Frame src=base[0]; gainPartial(src,4,-20);gainPartial(src,5,-16);gainPartial(src,15,15);gainPartial(src,16,14);
 SpectralClipboard profile;if(!profile.capture(src,0))return 1;
 profile.span(4,16);profile.feather=3;
 TableFrames normal=base,reverse=base;FrameRange range{3,12};
 if(!applySpectralProfileTable(normal,range,7,profile,1,1,false))return 2;
 profile.reverse=true;if(!applySpectralProfileTable(reverse,range,7,profile,1,1,false))return 3;
 if(normal[7]==reverse[7]||normal[3]!=base[3]||reverse[12]!=base[12]||reverse[0]!=base[0])return 4;
 Synth s(16);s.init(sr);VoiceParams v;v.osc1Shape=kCustomShape;v.osc2Level=0;v.filterCutoff=18000;v.ampA=.008;v.ampR=.12;
 const TableFrames* scenes[]={&base,&normal,&reverse,&normal,&reverse};
 std::vector<float> out;
 for(const auto* frames:scenes){
   s.setTables(*frames,{});v.osc1WtPos=7.0/15;s.setParams(v,{});
   for(int note:{48,55,60,67}){
     s.noteOn(note,.78f);
     for(int j=0;j<96;++j){float buf[block*2]{};s.renderStereo(buf,block);out.insert(out.end(),buf,buf+block*2);}
     s.noteOff(note);
     for(int j=0;j<24;++j){float buf[block*2]{};s.renderStereo(buf,block);out.insert(out.end(),buf,buf+block*2);}
   }
 }
 float peak=0;for(float x:out)peak=std::max(peak,std::fabs(x));
 if(!writeWav(path,out,sr,2))return 5;
 printf("MUEW reverse demo: original / normal / reverse / normal / reverse; %.2fs peak %.3f; %s\n",out.size()/(2.0*sr),peak,path);return 0;
}
