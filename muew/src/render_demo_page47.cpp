// MUEW 0.47.0: a source profile transferred across the H32/H33 page seam.
#include "synth.h"
#include "spectral_clipboard.h"
#include "wav_writer.h"
#include <algorithm>
#include <cmath>
#include <cstdio>
using namespace muew;
int main(int argc,char** argv){
 const char* path=argc>1?argv[1]:"out/MUEW-0.47.0-span-page-demo.wav";
 constexpr int sr=44100, block=128;
 TableFrames base(16,shapeFrame(2));
 Frame src=base[0];
 for(int h=28;h<=38;++h)gainPartial(src,h,(h%2?16:-20));
 SpectralClipboard profile;if(!profile.capture(src,0))return 1;
 profile.span(28,38);profile.feather=2;
 TableFrames edited=base;FrameRange range{3,12};
 if(!applySpectralProfileTable(edited,range,7,profile,1,1,false))return 2;
 if(edited[0]!=base[0]||edited[3]!=base[3]||edited[12]!=base[12]||edited[7]==base[7])return 3;
 Synth s(16);s.init(sr);VoiceParams v;v.osc1Shape=kCustomShape;v.osc2Level=0;v.filterCutoff=19000;v.ampA=.008;v.ampR=.11;
 const TableFrames* scenes[]={&base,&edited,&base,&edited};std::vector<float> out;
 for(const auto* frames:scenes){s.setTables(*frames,{});v.osc1WtPos=7.0/15;s.setParams(v,{});
   for(int note:{36,41,43,48}){s.noteOn(note,.8f);
     for(int j=0;j<100;++j){float buf[block*2]{};s.renderStereo(buf,block);out.insert(out.end(),buf,buf+block*2);}
     s.noteOff(note);
     for(int j=0;j<22;++j){float buf[block*2]{};s.renderStereo(buf,block);out.insert(out.end(),buf,buf+block*2);}
   }
 }
 float peak=0;for(float x:out)peak=std::max(peak,std::fabs(x));
 if(!writeWav(path,out,sr,2))return 4;
 printf("MUEW page-spanning transfer: original / H28-H38 / original / H28-H38; %.2fs peak %.3f; %s\n",out.size()/(2.0*sr),peak,path);return 0;
}
