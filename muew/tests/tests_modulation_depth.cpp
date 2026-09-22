#include "../src/synth.h"
#include "../src/mseg.h"
#include <cmath>
#include <cstdio>
#include <vector>
using namespace muew;
static int fail=0; static void check(bool c,const char* m){std::printf("%s: %s\n",c?"ok  ":"FAIL",m);if(!c)++fail;}
static double diff(const std::vector<float>& a,const std::vector<float>& b){double d=0;for(size_t i=0;i<a.size();++i)d+=std::fabs(a[i]-b[i]);return d;}
int main(){
 Wavetable wt; Oscillator a,b; for(auto* o:{&a,&b}){o->setSampleRate(48000);o->setTable(&wt);o->setFrequency(220);o->setShape(2);} b.setWarp(Oscillator::WarpMode::Sync,.72);
 std::vector<float>x(2048),y(2048);for(int i=0;i<2048;++i){x[i]=a.process();y[i]=b.process();} check(diff(x,y)>100,"sync warp materially changes the wavetable tone");
 for(int mode=0;mode<=6;++mode){Oscillator o;o.setSampleRate(48000);o.setTable(&wt);o.setFrequency(18000);o.setShape(2);o.setWarp((Oscillator::WarpMode)mode,.9);bool finite=true;float pk=0;for(int i=0;i<4096;++i){float z=o.process();finite&=std::isfinite(z);pk=std::max(pk,std::fabs(z));}check(finite&&pk<=1.01f,"warp mode stays finite and bounded");}
 MSEG m;m.setSampleRate(100);m.setRate(1);m.setPoints({{0,0},{.25,1},{.5,-1},{1,0}});m.reset();check(std::fabs(m.valueAt(.25)-1)<1e-6,"MSEG hits authored control point");check(std::fabs(m.valueAt(.375))<1e-6,"MSEG interpolates segments");
 Synth dry,mod;dry.init(48000);mod.init(48000);VoiceParams p;p.osc2Level=0;p.osc1Shape=2;p.osc1WarpMode=(int)Oscillator::WarpMode::BendPlus;p.mseg1Seconds=.15;dry.setParams(p,{});mod.setParams(p,{{ModRoute::Source::MSEG1,ModRoute::Dest::Osc1Warp,.9}});dry.noteOn(52,.9);mod.noteOn(52,.9);std::vector<float>d(4096),e(4096);dry.render(d.data(),d.size());mod.render(e.data(),e.size());check(diff(d,e)>50,"MSEG route drives oscillator warp per sample");
 std::puts(fail?"MODULATION DEPTH TESTS FAILED":"ALL MODULATION DEPTH TESTS PASSED");return fail?1:0;
}
