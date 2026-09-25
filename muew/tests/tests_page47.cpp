#include "../src/spectral_clipboard.h"
#include "../src/table_history.h"
#include "../src/preset.h"
#include <cstdio>
#include <cmath>
using namespace muew;
static int bad=0;static void ck(bool a,const char*s){printf("%s %s\n",a?"ok:  ":"FAIL:",s);bad+=!a;}
int main(){
 ck(partialPageStart(0)==1&&partialPageEnd(0)==32&&partialPageStart(1)==33&&partialPageEnd(1)==64&&partialPageEnd(3)==127,
    "four pages cover H1-H127 with a clipped final page");
 ck(spanPageHandoffEnd(28,1)==33&&spanPageHandoffEnd(28,3)==97&&
    spanPageHandoffEnd(98,2)==96&&spanPageHandoffEnd(98,0)==32,
    "handoff chooses first next-page or last previous-page bin from anchor");
 ck(spanPageHandoffEnd(127,3)==127&&spanPageHandoffEnd(1,0)==32,
    "handoff never selects nonexistent H128");
 Frame src=shapeFrame(2), dest=shapeFrame(2);gainPartial(src,29,-20);gainPartial(src,35,12);
 SpectralClipboard clip;ck(clip.capture(src,0),"captures cross-page source spectrum");
 clip.span(28,spanPageHandoffEnd(28,1));
 ck(clip.firstH==28&&clip.lastH==33&&clip.includes(32)&&clip.includes(33),"handoff keeps anchor while crossing H32/H33");
 clip.span(28,38);clip.feather=2;
 ck(clip.weight(27)==2.0/3&&clip.weight(39)==2.0/3&&clip.weight(41)==0,
    "page-spanning selection preserves feather on both edges");
 clip.reverse=true;ck(clip.sourceRatio(28)==clip.ratio[38]&&clip.sourceRatio(38)==clip.ratio[28],
    "REVERSE reflects across the full page-spanning selection");
 TableFrames frames(16,dest),original=frames;FrameRange range{3,12};
 ck(applySpectralProfileTable(frames,range,7,clip,.9,1,false),"cross-page span transfers into tapered frame range");
 ck(frames[0]==original[0]&&frames[3]==original[3]&&frames[12]==original[12]&&frames[7]!=original[7],
    "outside frames and EDGE endpoints stay untouched");
 TableHistory hist;int f=7;hist.push(original,f,"PROFILE RANGE");auto edited=frames;
 ck(hist.undoDepth()==1&&hist.undo(frames,f)&&frames==original&&hist.redo(frames,f)&&frames==edited,
    "cross-page paste remains a single undo step");
 Preset p;p.voice.osc1Shape=kCustomShape;p.tables[0]=edited;Preset q;
 ck(q.parse(p.serialize())&&q.tables[0]==edited,"result saves in existing preset format");
 puts(bad?"PAGE47 FAILED":"ALL PAGE47 TESTS PASSED");return bad?1:0;
}
