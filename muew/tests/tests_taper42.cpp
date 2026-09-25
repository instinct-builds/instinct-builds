#include "../src/partial_brush.h"
#include "../src/table_history.h"
#include "../src/preset.h"
#include <cmath>
#include <cstdio>
using namespace muew;
static int bad=0;
static void check(bool ok,const char* name){printf("%s %s\n",ok?"ok:  ":"FAIL:",name);bad+=!ok;}
int main(){
 FrameRange r{2,10};
 check(brushRangeStrength(2,r,16,0)==1&&brushRangeStrength(10,r,16,0)==1,"zero taper is uniform legacy stroke");
 check(brushRangeStrength(2,r,16,1)==0&&brushRangeStrength(6,r,16,1)==1&&brushRangeStrength(10,r,16,1)==0,"full taper has exact untouched edges and full center");
 check(brushRangeStrength(4,r,16,1)==.5&&brushRangeStrength(8,r,16,1)==.5,"symmetric intermediate strength");
 FrameRange even{2,9};check(brushRangeStrength(2,even,16,1)==0&&brushRangeStrength(5,even,16,1)==1&&brushRangeStrength(6,even,16,1)==1&&brushRangeStrength(9,even,16,1)==0,"even range holds full center pair");
 FrameRange shortRange{3,4};check(brushRangeStrength(3,shortRange,16,1)==1&&brushRangeStrength(4,shortRange,16,1)==1,"short range stays editable");
 PartialBrush brush;brush.line(4,-6,8,-18);
 TableFrames original(16,shapeFrame(2));for(int i=0;i<16;++i)smoothFrame(original[i],i/5);
 TableFrames tapered=original,uniform=original;
 check(applyBrushTable(tapered,r,6,brush,1),"full-edge-taper brush edits table");
 check(applyBrushTable(uniform,r,6,brush,0),"uniform comparator edits table");
 bool outside=true;for(int i=0;i<16;++i)if(i<2||i>10)outside &= tapered[i]==original[i];
 check(outside&&tapered[2]==original[2]&&tapered[10]==original[10],"outside and edge frames are bit-identical to baseline");
 check(tapered[6]==uniform[6]&&tapered[6]!=original[6],"center uses exact full-strength painted result");
 auto level=[](const Frame& f){auto s=frameSpectrum(f);return 20*std::log10(std::abs(s[4])/std::abs(s[1]));};
 double orig=level(original[4]),mid=level(tapered[4]),full=level(uniform[4]);
 check(std::fabs(mid-(orig+full)*.5)<.15,"intermediate frame blends partial levels in dB");
 check(tapered[4]!=tapered[6]&&tapered[4]!=uniform[4],"falloff creates motion across the range");
 TableFrames replay=original;applyBrushTable(replay,r,6,brush,1);check(replay==tapered,"frozen-baseline replay is deterministic");
 TableHistory history;int f=6;history.push(original,f,"BRUSH FALLOFF");TableFrames edited=tapered;
 check(history.undoDepth()==1&&history.undo(edited,f)&&edited==original&&history.redo(edited,f)&&edited==tapered,"one undo/redo restores whole tapered gesture");
 Preset p;p.voice.osc1Shape=kCustomShape;p.tables[0]=tapered;Preset q;
 check(q.parse(p.serialize())&&q.tables[0]==tapered,"painted falloff survives preset round-trip");
 puts(bad?"TAPER42 FAILED":"ALL TAPER42 TESTS PASSED");return bad?1:0;
}
