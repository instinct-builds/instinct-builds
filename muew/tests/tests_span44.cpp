#include "../src/spectral_clipboard.h"
#include "../src/table_history.h"
#include "../src/preset.h"
#include <cmath>
#include <cstdio>
using namespace muew;
static int bad=0;static void ck(bool a,const char*s){printf("%s %s\n",a?"ok:  ":"FAIL:",s);bad+=!a;}
int main(){
 SpectralClipboard c;Frame src=shapeFrame(2), dest=shapeFrame(2);gainPartial(src,4,-18);gainPartial(src,8,9);
 ck(c.capture(src,0),"copied source profile");c.span(4,8);
 auto original=frameSpectrum(dest);Frame changed=dest;
 ck(applySpectralProfile(changed,c,.75),"partial-span transfer changes destination");
 auto after=frameSpectrum(changed);double scale=std::abs(after[1])/std::abs(original[1]);bool untouched=true;
 for(int h=1;h<=kEditablePartials;++h)if(!c.includes(h))untouched &= std::abs(after[h]-original[h]*scale)<.003*std::max(1.0,std::abs(after[h]));
 ck(untouched,"all non-selected harmonic bins preserve phase and relative magnitude");
 ck(std::abs(after[4])/std::abs(after[1])!=std::abs(original[4])/std::abs(original[1]),"H4 changes inside selected span");
 TableFrames table(16,dest),before=table;FrameRange r{3,12};
 ck(applySpectralProfileTable(table,r,7,c,.75,1,false),"span transfer applies across frame range");
 bool isolated=true;for(int i=0;i<16;++i)if(i<3||i>12||i==3||i==12)isolated &= table[i]==before[i];
 ck(isolated&&table[7]!=before[7],"outside and EDGE endpoints remain bit-identical");
 TableHistory hist;int f=7;hist.push(before,f,"PROFILE SPAN RANGE");TableFrames result=table;
 ck(hist.undoDepth()==1&&hist.undo(table,f)&&table==before&&hist.redo(table,f)&&table==result,"single undo/redo covers selected-span range");
 Frame sine=shapeFrame(0);ck(!applySpectralProfile(sine,c,1,false),"SEED off prevents creation in silent span bins");
 ck(applySpectralProfile(sine,c,1,true),"explicit SEED creates copied silent-bin profile");
 Preset p;p.voice.osc1Shape=kCustomShape;p.tables[0]=result;Preset q;
 ck(q.parse(p.serialize())&&q.tables[0]==result,"span result survives preset state");
 puts(bad?"SPAN44 FAILED":"ALL SPAN44 TESTS PASSED");return bad?1:0;
}
