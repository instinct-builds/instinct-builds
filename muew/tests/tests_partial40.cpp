#include "../src/partial_view.h"
#include "../src/table_history.h"
#include "../src/preset.h"
#include <cstdio>
#include <cmath>
using namespace muew;
static int bad=0;
static void check(bool b,const char* s){printf("%s %s\n",b?"ok:  ":"FAIL:",s);bad+=!b;}
int main(){
    check(partialPageStart(0)==1&&partialPageEnd(0)==32&&partialPageStart(3)==97&&partialPageEnd(3)==127,"four pages address exactly harmonics 1-127");
    check(partialPageFor(1)==0&&partialPageFor(64)==1&&partialPageFor(127)==3,"harmonic selection maps into pages");
    Frame sine=shapeFrame(0),original=sine;
    check(partialLevelDb(sine,127)==-90,"high partial initially silent");
    check(seedPartial(sine,127),"explicitly seed harmonic 127");
    double newDb=partialLevelDb(sine,127);
    check(std::fabs(newDb+24)<.1,"seed uses a controlled -24 dB reference");
    auto a=frameSpectrum(original),b=frameSpectrum(sine);
    double ratio=std::abs(b[1])/std::abs(a[1]);
    check(std::abs(b[1]-a[1]*ratio)<.001&&std::fabs(b[127].real())<.001,"seed preserves old harmonic phase and adds sine-phase high partial");
    check(!seedPartial(sine,127),"a populated harmonic is not silently overwritten");
    Frame quiet(kFrameSize,0);
    check(!seedPartial(quiet,127)&&quiet==Frame(kFrameSize,0),"all-silent frame has no reference and stays silent");
    check(!seedPartial(sine,0)&&!seedPartial(sine,128),"DC and Nyquist cannot be created");
    TableFrames t(4,original),prior=t;FrameRange range{1,2};TableHistory h;int frame=1;
    TableFrames staged=t;check(seedPartialRange(staged,range,127),"range can seed only silent bins");
    h.push(t,frame,"CREATE RANGE");t=staged;
    check(t[0]==prior[0]&&t[3]==prior[3]&&t[1]!=prior[1]&&t[2]!=prior[2],"range creation leaves outside frames intact");
    check(h.undoDepth()==1&&h.undo(t,frame)&&t==prior&&h.redo(t,frame)&&t==staged,"creation is one undoable batch");
    Preset p;p.voice.osc1Shape=kCustomShape;p.tables[0]=t;Preset q;
    check(q.parse(p.serialize())&&q.tables[0]==t,"new high partial persists in preset state");
    puts(bad?"PARTIAL40 FAILED":"ALL PARTIAL40 TESTS PASSED");return bad?1:0;
}
