#include "../src/partial_edit.h"
#include "../src/table_history.h"
#include "../src/preset.h"
#include "../src/factory_bank.h"
#include <cstdio>
#include <cmath>
using namespace muew;
static int bad=0;
static void check(bool b,const char* n){printf("%s %s\n", b?"ok:  ":"FAIL:",n);bad+=!b;}
int main(){
    Frame f=shapeFrame(2), orig=f;
    double db=partialLevelDb(f,4);check(db<0 && db>-60,"fourth partial has a measurable level");
    check(gainPartial(f,4,6),"partial gain changes frame");
    auto a=frameSpectrum(orig), b=frameSpectrum(f);
    double k=std::abs(b[1])/std::abs(a[1]), ratio=std::abs(b[4])/std::abs(a[4])/k;
    bool other=true;for(int i=1;i<80;++i)if(i!=4)other &= std::abs(b[i]-a[i]*k)<.003*std::max(1.0,std::abs(b[i]));
    check(std::fabs(ratio-std::pow(10.0,6.0/20))<.01 && other,"+6 dB boosts only partial four relative to other partials");
    check(std::fabs(std::remainder(std::arg(b[4])-std::arg(a[4]),2*M_PI))<.001,"partial phase is preserved");
    check(gainPartial(f,4,-6),"attenuation works");
    check(std::fabs(partialLevelDb(f,4)-db)<.05,"opposite gains restore relative partial level");
    Frame zero(kFrameSize,0);check(!gainPartial(zero,4,6)&&zero==Frame(kFrameSize,0),"silence stays silent");
    check(!gainPartial(f,0,6)&&!gainPartial(f,128,6)&&!gainPartial(f,4,0),"invalid/identity gain consumes no edit");
    TableFrames t(5,orig), prior=t; FrameRange r{1,3};TableHistory h;int sel=2;
    TableFrames next=t;check(gainPartialRange(next,r,4,-6),"batch gain edits a range");
    h.push(t,sel,"PARTIAL RANGE");t=next;
    check(t[0]==prior[0]&&t[4]==prior[4]&&t[1]!=prior[1]&&t[2]!=prior[2]&&t[3]!=prior[3],"only selected frames change");
    check(h.undoDepth()==1&&h.undo(t,sel)&&t==prior&&h.redo(t,sel)&&t==next,"single undo/redo covers the range");
    Preset p;p.tables[0]=t;p.voice.osc1Shape=kCustomShape;Preset q;
    check(q.parse(p.serialize())&&q.tables[0]==t,"preset state preserves spectral edits");
    puts(bad?"PARTIAL39 FAILED":"ALL PARTIAL39 TESTS PASSED");return bad?1:0;
}
