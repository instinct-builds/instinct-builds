#include "../src/spectral_clipboard.h"
#include "../src/table_history.h"
#include "../src/preset.h"
#include <cmath>
#include <cstdio>
using namespace muew;
static int failures=0;
static void check(bool ok,const char* label){printf("%s %s\n",ok?"ok:  ":"FAIL:",label);failures+=!ok;}
int main(){
 SpectralClipboard clip;Frame source=shapeFrame(2), dest=shapeFrame(2);gainPartial(dest,4,-12);gainPartial(dest,8,6);
 check(clip.capture(source,5)&&clip.valid&&clip.sourceFrame==5,"copies source frame profile");
 auto srcSpec=frameSpectrum(source), old=frameSpectrum(dest);
 double peak=0;for(int h=1;h<=kEditablePartials;++h)peak=std::max(peak,std::abs(old[h]));
 Frame pasted=dest;check(applySpectralProfile(pasted,clip),"paste changes destination");auto ps=frameSpectrum(pasted);
 double newPeak=0;for(int h=1;h<=kEditablePartials;++h)newPeak=std::max(newPeak,std::abs(ps[h]));
 check(std::abs(ps[1])>0&&std::fabs(std::remainder(std::arg(ps[1])-std::arg(old[1]),2*M_PI))<.001,"destination phase survives paste");
 bool levels=true;for(int h=1;h<=12;++h)if(std::abs(old[h])>peak*1e-7&&clip.ratio[h]>1e-7)levels &= std::fabs(std::abs(ps[h])/std::abs(ps[1])-clip.ratio[h]/clip.ratio[1])<.02;
 check(levels,"copied magnitude ratios land on existing bins");
 Frame sine=shapeFrame(0);Frame noCreate=sine;
 check(!applySpectralProfile(noCreate,clip,1,false)&&noCreate==sine,"silent destination bins remain silent by default");
 check(applySpectralProfile(noCreate,clip,1,true)&&std::abs(frameSpectrum(noCreate)[4])>1,"explicit CREATE permits new harmonics");
 Frame half=dest;check(applySpectralProfile(half,clip,.5),"blend changes frame");
 auto mid=frameSpectrum(half);bool dB=true;for(int h=1;h<=8;++h){double a=std::abs(old[h]);if(a>peak*1e-7&&clip.ratio[h]>1e-7){double t=peak*clip.ratio[h];dB &= std::fabs(20*std::log10(std::abs(mid[h])/std::abs(mid[1]))-20*std::log10(std::sqrt(a*t)/std::sqrt(std::abs(old[1])*peak*clip.ratio[1])))<.2;}}
 check(dB,"half blend interpolates existing partials in dB");
 TableFrames table(16,dest),base=table;FrameRange range{3,12};
 check(applySpectralProfileTable(table,range,7,clip,1,1),"range paste with EDGE falloff changes table");
 bool isolated=true;for(int i=0;i<16;++i)if(i<3||i>12||i==3||i==12)isolated &= table[i]==base[i];
 check(isolated&&table[7]!=base[7],"outside and edge frames bit-identical, center changed");
 TableFrames replay=base;applySpectralProfileTable(replay,range,7,clip,1,1);check(replay==table,"deterministic profile replay");
 TableHistory history;int frame=7;history.push(base,frame,"PROFILE RANGE");
 check(history.undoDepth()==1&&history.undo(table,frame)&&table==base&&history.redo(table,frame)&&table==replay,"one undo/redo for range paste");
 Preset preset;preset.voice.osc1Shape=kCustomShape;preset.tables[0]=table;Preset loaded;check(loaded.parse(preset.serialize())&&loaded.tables[0]==table,"profile result survives preset round-trip");
 SpectralClipboard spanClip=clip;spanClip.span(4,8);Frame spanDest=dest;
 check(applySpectralProfile(spanDest,spanClip,1),"selected harmonic span changes frame");
 auto spanSpec=frameSpectrum(spanDest);auto baseSpec=frameSpectrum(dest);
 double ratio=std::abs(spanSpec[1])/std::abs(baseSpec[1]);bool outsideRatios=true;
 for(int h=1;h<=kEditablePartials;++h)if(h<4||h>8)
   outsideRatios &= std::abs(spanSpec[h]-baseSpec[h]*ratio)<.003*std::max(1.0,std::abs(spanSpec[h]));
 check(outsideRatios,"unselected harmonic ratios and phases remain unchanged");
 check(spanClip.includes(4)&&spanClip.includes(8)&&!spanClip.includes(3)&&!spanClip.includes(9),"span bounds are inclusive");
 spanClip.span(100,97);check(spanClip.firstH==97&&spanClip.lastH==100,"reverse drag resolves to ascending span");
 spanClip.clear();check(spanClip.firstH==1&&spanClip.lastH==127,"clipboard reset restores full span");
 puts(failures?"CLIP43 FAILED":"ALL CLIP43 TESTS PASSED");return failures?1:0;
}
