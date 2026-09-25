#include "../src/spectral_clipboard.h"
#include "../src/table_history.h"
#include "../src/preset.h"
#include <cmath>
#include <cstdio>
using namespace muew;
static int fail=0;static void ck(bool a,const char*s){printf("%s %s\n",a?"ok:  ":"FAIL:",s);fail+=!a;}
int main(){
 SpectralClipboard c;Frame source=shapeFrame(2), destination=shapeFrame(2);
 gainPartial(source,4,-18);gainPartial(source,8,9);
 ck(c.capture(source,0),"captures original profile");c.span(4,16);c.feather=3;
 ck(c.weight(4)==1&&c.weight(16)==1&&c.weight(3)==.75&&c.weight(2)==.5&&c.weight(1)==.25&&
    c.weight(17)==.75&&c.weight(18)==.5&&c.weight(19)==.25&&c.weight(20)==0,
    "three-bin feather ramps symmetrically beyond span, exact interior");
 SpectralClipboard hard=c;hard.feather=0;ck(hard.weight(3)==0&&hard.weight(4)==1&&hard.weight(17)==0,"zero feather is hard span");
 Frame feathered=destination,hardFrame=destination;
 ck(applySpectralProfile(feathered,c,1)&&applySpectralProfile(hardFrame,hard,1),"both soft and hard span transfers work");
 auto a=frameSpectrum(destination),b=frameSpectrum(feathered),d=frameSpectrum(hardFrame);
 double old4=std::abs(a[4])/std::abs(a[1]),soft4=std::abs(b[4])/std::abs(b[1]),hard4=std::abs(d[4])/std::abs(d[1]);
 ck(std::fabs(soft4-hard4)<.01&&std::fabs(soft4-old4)>.01,"selected span keeps full-strength transfer");
 bool outside=true;const double scale=std::abs(b[1])/std::abs(a[1]);for(int h=20;h<=kEditablePartials;++h)
   outside &= std::abs(b[h]-a[h]*scale)<.003*std::max(1.0,std::abs(b[h]));
 ck(outside,"harmonics outside feather and span preserve relative magnitude and phase");
 // Use a source with changes in bins 17 and 18 to prove the right ramp is not a no-op.
 Frame source2=shapeFrame(2);gainPartial(source2,17,12);gainPartial(source2,18,-10);SpectralClipboard right;
 right.capture(source2,0);right.span(4,16);right.feather=3;
 Frame soft=destination,full=destination;applySpectralProfile(soft,right,1);right.span(17,18);right.feather=0;applySpectralProfile(full,right,1);
 auto sf=frameSpectrum(soft),ff=frameSpectrum(full),orig=frameSpectrum(destination);
 double ds=20*std::log10(std::abs(sf[17])/std::abs(sf[1]))-20*std::log10(std::abs(orig[17])/std::abs(orig[1]));
 double df=20*std::log10(std::abs(ff[17])/std::abs(ff[1]))-20*std::log10(std::abs(orig[17])/std::abs(orig[1]));
 ck(std::fabs(ds-df*.75)<.15,"first feather bin receives exactly 75 percent dB transfer");
 ck(std::fabs(std::remainder(std::arg(sf[17])-std::arg(orig[17]),2*M_PI))<.001,"feather keeps destination phase");
 TableFrames table(16,destination),baseline=table;FrameRange r{3,12};
 ck(applySpectralProfileTable(table,r,7,right,.8,1,false),"range transfer with feather and EDGE works");
 bool edges=true;for(int i=0;i<16;++i)if(i<3||i>12||i==3||i==12)edges &= table[i]==baseline[i];
 ck(edges&&table[7]!=baseline[7],"frame boundaries are bit-identical, center altered");
 TableHistory hist;int frame=7;hist.push(baseline,frame,"PROFILE FEATHER RANGE");auto changed=table;
 ck(hist.undoDepth()==1&&hist.undo(table,frame)&&table==baseline&&hist.redo(table,frame)&&table==changed,"one undo/redo covers feathered paste");
 Frame sine=shapeFrame(0);ck(!applySpectralProfile(sine,c,1,false),"silent bins stay silent with SEED off");
 ck(applySpectralProfile(sine,c,1,true),"SEED explicitly creates selected and feather bins");
 Preset p;p.voice.osc1Shape=kCustomShape;p.tables[0]=table;Preset q;ck(q.parse(p.serialize())&&q.tables[0]==table,"result survives preset state");
 puts(fail?"FEATHER45 FAILED":"ALL FEATHER45 TESTS PASSED");return fail?1:0;
}
