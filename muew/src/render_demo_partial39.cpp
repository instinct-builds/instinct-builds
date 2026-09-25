// MUEW 0.39.0: original partial four gain contrast with a shared table.
#include "synth.h"
#include "partial_edit.h"
#include "wav_writer.h"
#include <algorithm>
#include <cmath>
#include <cstdio>
using namespace muew;
int main(int argc,char** argv){
    const char* path=argc>1?argv[1]:"out/MUEW-0.39.0-partial-editor-demo.wav";
    constexpr int sr=44100, block=128;
    TableFrames t(4,shapeFrame(2));
    if(!gainPartial(t[1],4,-9)||!gainPartial(t[2],4,9))return 1;
    FrameRange r{1,2}; if(!gainPartialRange(t,r,3,3))return 2;
    Synth s(16);s.init(sr);s.setTables(t,{});
    VoiceParams v;v.osc1Shape=kCustomShape;v.osc2Level=0;v.filterCutoff=10000;v.ampA=.01;v.ampR=.13;s.setParams(v,{});
    std::vector<float> out;
    const int notes[]={48,52,55,60};
    for(int scene=0;scene<4;++scene){
        v.osc1WtPos=scene/3.0;s.setParams(v,{});
        for(int n:notes){
            s.noteOn(n,.8f);
            for(int pos=0;pos<(int)(sr*.30);pos+=block){float b[block*2]{};s.renderStereo(b,block);out.insert(out.end(),b,b+block*2);}
            s.noteOff(n);
            for(int pos=0;pos<(int)(sr*.07);pos+=block){float b[block*2]{};s.renderStereo(b,block);out.insert(out.end(),b,b+block*2);}
        }
    }
    float peak=0;for(float x:out)peak=std::max(peak,std::fabs(x));
    if(!writeWav(path,out,sr,2))return 3;
    printf("MUEW partial demo: base, H4 -9 dB, H4 +9 dB, base; %.2f s, peak %.3f; %s\n",out.size()/(2.0*sr),peak,path);
    return 0;
}
