// MUEW 0.40.0: an audible high harmonic seeded into an original frame.
#include "synth.h"
#include "partial_view.h"
#include "wav_writer.h"
#include <algorithm>
#include <cmath>
#include <cstdio>
using namespace muew;
int main(int argc,char** argv){
    const char* path=argc>1?argv[1]:"out/MUEW-0.40.0-partial-zoom-demo.wav";
    constexpr int sr=44100,block=128;
    TableFrames t(4,shapeFrame(0));
    if(!seedPartial(t[1],31)||!seedPartial(t[2],63)||!seedPartial(t[3],127))return 1;
    Synth s(16);s.init(sr);s.setTables(t,{});
    VoiceParams v;v.osc1Shape=kCustomShape;v.osc2Level=0;v.filterCutoff=16000;v.ampA=.01;v.ampR=.12;s.setParams(v,{});
    std::vector<float> out;const int notes[]={48,52,55,60};
    for(int scene=0;scene<4;++scene){
        v.osc1WtPos=scene/3.0;s.setParams(v,{});
        for(int n:notes){s.noteOn(n,.82f);
            for(int pos=0;pos<(int)(sr*.29);pos+=block){float b[block*2]{};s.renderStereo(b,block);out.insert(out.end(),b,b+block*2);}
            s.noteOff(n);
            for(int pos=0;pos<(int)(sr*.08);pos+=block){float b[block*2]{};s.renderStereo(b,block);out.insert(out.end(),b,b+block*2);}
        }
    }
    float peak=0;for(float x:out)peak=std::max(peak,std::fabs(x));
    if(!writeWav(path,out,sr,2))return 2;
    printf("MUEW partial zoom demo: sine, H31, H63, H127; %.2f s, peak %.3f; %s\n",out.size()/(2.0*sr),peak,path);
    return 0;
}
