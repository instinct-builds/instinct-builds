#include "../src/output_meter.h"
#include "../src/output_meter_display.h"
#include "../src/synth.h"
#include "../src/factory_bank.h"
#include "../src/au_params.h"
#include <cmath>
#include <cstdio>
#include <cstring>
#include <vector>
using namespace muew;
static int bad=0;
static void ck(bool yes,const char*label){std::printf("%s %s\n",yes?"ok:":"FAIL:",label);bad+=!yes;}
int main(){
 OutputMeter m;m.sample(.4f,-.6f,std::tanh(.64f),std::tanh(-.96f));
 ck(std::fabs(m.drive-.96f)<1e-6&&m.right>m.left&&!m.softSaturating(),"stereo post-master peaks and pre-master drive distinct");
 m.sample(1.1f,0,std::tanh(1.76f),0);ck(m.softSaturating()&&m.left<1,"soft saturation does not imply hard clipped output");
 OutputMeter n;n.sample(0,.3f,0,std::tanh(.48f));m.merge(n);ck(m.right>0&&m.drive>=1.76f,"segment merge preserves stereo and hottest drive");
 m.clear();ck(!m.softSaturating()&&m.left==0&&m.right==0,"block meter reset");
 OutputMeterDisplay d;d.update(.8,.3,1.2,0);ck(d.saturated()&&d.left==.8f&&d.right==.3f,"UI SAT indicates only strong pre-master drive");
 d.update(0,0,0,.1);ck(d.saturated()&&d.left>0&&d.left<.8f,"short soft-saturation linger and peak decay");
 d.update(0,0,0,.1);ck(!d.saturated(),"SAT clears after linger");
 d.update(NAN,INFINITY,-INFINITY,.1);ck(std::isfinite(d.left)&&std::isfinite(d.right)&&!d.saturated(),"invalid meter values cannot light SAT");
 bool bank=true;for(const auto& p:factoryPresets())bank &= p.voice.noiseBurstAttack==0&&p.voice.noiseBurstCurve==0;
 ck(bank&&factoryPresets().size()==108&&params::Count==40,"factory presets and 40 AU IDs stable");
 VoiceParams v;v.ampA=.001;v.ampS=1;v.noiseWidth=.8;v.noiseLevel=.25;
 Synth a,b;a.init(44100);b.init(44100);a.setParams(v,{});b.setParams(v,{});a.noteOn(60,1);b.noteOn(60,1);
 std::vector<float> la(4096),ra(4096),lb(4096),rb(4096);
 a.renderPlanar(la.data(),ra.data(),4096);b.renderPlanar(lb.data(),rb.data(),4096);
 ck(la==lb&&ra==rb,"output instrumentation leaves sound deterministic");
 float peakL=0,peakR=0;for(int i=0;i<4096;++i){peakL=std::max(peakL,std::fabs(la[i]));peakR=std::max(peakR,std::fabs(ra[i]));}
 ck(a.outputMeter().left==peakL&&a.outputMeter().right==peakR,"reported stereo peaks match actual post-master buffers");
 a.renderPlanar(la.data(),ra.data(),0);ck(a.outputMeter().left==0&&a.outputMeter().right==0,"zero-length block clears stale peaks");
 std::printf("%s output58 tests\n",bad?"FAIL":"ALL PASSED");return bad?1:0;
}
