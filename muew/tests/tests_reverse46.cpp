#include "../src/spectral_clipboard.h"
#include "../src/table_history.h"
#include "../src/preset.h"
#include <cmath>
#include <cstdio>
using namespace muew;
static int fail=0;static void ck(bool a,const char*s){printf("%s %s\n",a?"ok:  ":"FAIL:",s);fail+=!a;}
int main(){
 Frame src=shapeFrame(2),dest=shapeFrame(2);
 gainPartial(src,4,-18);gainPartial(src,16,11);gainPartial(src,17,8);
 SpectralClipboard c;ck(c.capture(src,0),"capture profile");c.span(4,16);c.feather=3;c.reverse=true;
 ck(c.sourceRatio(4)==c.ratio[16]&&c.sourceRatio(16)==c.ratio[4]&&
    c.sourceRatio(8)==c.ratio[12]&&c.sourceRatio(3)==c.ratio[3]&&c.sourceRatio(17)==c.ratio[17],
    "selected span reflects exactly, feather uses original adjacent ratios");
 ck(c.weight(4)==1&&c.weight(16)==1&&c.weight(3)==.75&&c.weight(17)==.75&&c.weight(20)==0,
    "feathering and span weight are independent of polarity");
 Frame reversed=dest,normal=dest;ck(applySpectralProfile(reversed,c,.75),"reverse changes sound");
 c.reverse=false;ck(applySpectralProfile(normal,c,.75),"normal changes sound");
 auto rs=frameSpectrum(reversed),ns=frameSpectrum(normal),ds=frameSpectrum(dest);
 ck(reversed!=normal&&std::abs(rs[4]/rs[1])>std::abs(ns[4]/ns[1])&&
    std::abs(rs[16]/rs[1])<std::abs(ns[16]/ns[1]),"reverse audibly swaps low/high shape inside span");
 ck(std::fabs(std::remainder(std::arg(rs[4])-std::arg(ds[4]),2*M_PI))<.001,
    "reverse retains destination phase");
 ck(std::fabs(std::abs(rs[17]/rs[1])-std::abs(ns[17]/ns[1]))<.002,
    "outside feather bin sees identical untouched source ratio in both polarities");
 const double scale=std::abs(rs[1])/std::abs(ds[1]);bool outside=true;
 for(int h=20;h<=kEditablePartials;++h)
   outside &= std::abs(rs[h]-ds[h]*scale)<.003*std::max(1.0,std::abs(rs[h]));
 ck(outside,"beyond feather, original magnitude and phase survive");
 c.reverse=true;TableFrames table(16,dest),before=table;FrameRange range{3,12};
 ck(applySpectralProfileTable(table,range,7,c,.75,1,false),"reverse paste with EDGE changes range");
 ck(table[3]==before[3]&&table[12]==before[12]&&table[7]!=before[7]&&table[2]==before[2],
    "range endpoints and outside are untouched");
 TableHistory hist;int frame=7;hist.push(before,frame,"PROFILE RANGE");auto changed=table;
 ck(hist.undoDepth()==1&&hist.undo(table,frame)&&table==before&&hist.redo(table,frame)&&table==changed,
    "one undo/redo covers reverse paste");
 Frame sine=shapeFrame(0);ck(!applySpectralProfile(sine,c,1,false),"SEED off does not create silent bins");
 ck(applySpectralProfile(sine,c,1,true),"SEED on explicitly creates silent bins");
 Preset p;p.voice.osc1Shape=kCustomShape;p.tables[0]=table;Preset q;
 ck(q.parse(p.serialize())&&q.tables[0]==table,"reverse result survives preset roundtrip without new preset field");
 c.capture(src,0);ck(!c.reverse&&c.feather==0&&c.firstH==1&&c.lastH==kEditablePartials,"COPY resets ephemeral polarity and selection");
 c.reverse=true;c.clear();ck(!c.reverse&&!c.valid,"CLEAR resets polarity");
 puts(fail?"REVERSE46 FAILED":"ALL REVERSE46 TESTS PASSED");return fail?1:0;
}
