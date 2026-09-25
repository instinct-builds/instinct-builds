#include "../src/partial_brush.h"
#include "../src/table_history.h"
#include "../src/preset.h"
#include <cmath>
#include <cstdio>
using namespace muew;
static int bad=0;static void check(bool b,const char* s){printf("%s %s\n",b?"ok:  ":"FAIL:",s);bad+=!b;}
int main(){
 PartialBrush brush;check(!brush.hasEdits(),"fresh brush has no targets");
 brush.line(3,-3,7,-15);check(brush.hasEdits()&&brush.targetDb[3]==-3&&brush.targetDb[5]==-9&&brush.targetDb[7]==-15,"fast gesture interpolates skipped harmonic bins");
 Frame f=shapeFrame(2),before=f;auto orig=frameSpectrum(f);
 check(applyBrushFrame(f,brush),"paint changes a real frame");auto after=frameSpectrum(f);
 double scale=std::abs(after[1])/std::abs(orig[1]);
 check(std::fabs(20*std::log10(std::abs(after[3])/std::abs(after[1]))+3)<.1,"H3 reaches absolute -3 dB relative to original peak");
 check(std::fabs(std::remainder(std::arg(after[7])-std::arg(orig[7]),2*M_PI))<.001,"brush preserves harmonic phase");
 check(std::abs(after[2]-orig[2]*scale)<.003*std::max(1.0,std::abs(after[2])),"unpainted partial remains unchanged relative to base");
 Frame replay=before;applyBrushFrame(replay,brush);check(replay==f,"replay from gesture baseline is deterministic");
 brush.clear();check(!applyBrushFrame(replay,brush),"cleared brush is identity");
 brush.paint(127,8);Frame sine=shapeFrame(0);check(!applyBrushFrame(sine,brush),"silent H127 needs explicit CREATE");
 TableFrames t(5,before),prior=t;FrameRange r{1,3};PartialBrush line;line.line(4,-12,9,-18);
 TableFrames next=t;check(applyBrushTable(next,r,2,line),"range stroke changes table");
 check(next[0]==prior[0]&&next[4]==prior[4]&&next[1]!=prior[1]&&next[3]!=prior[3],"only selected frame range changes");
 TableHistory h;int fr=2;h.push(t,fr,"BRUSH RANGE");t=next;
 check(h.undoDepth()==1&&h.undo(t,fr)&&t==prior&&h.redo(t,fr)&&t==next,"one undo/redo covers the gesture");
 Preset p;p.voice.osc1Shape=kCustomShape;p.tables[0]=t;Preset q;check(q.parse(p.serialize())&&q.tables[0]==t,"painted table survives preset state");
 puts(bad?"BRUSH41 FAILED":"ALL BRUSH41 TESTS PASSED");return bad?1:0;
}
