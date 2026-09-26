#include "../src/route_range_trace.h"
#include "../src/synth.h"
#include <cstdio>
#include <vector>
using namespace muew;
static int fails=0;
static void ck(bool b,const char* m){printf("%s %s\n",b?"ok:":"FAIL:",m);fails+=!b;}
static void play(Synth& s,int n){std::vector<float> l(n),r(n);s.renderPlanar(l.data(),r.data(),n);}
int main(){
    using S=ModRoute::Source;using D=ModRoute::Dest;
    Synth s(4);s.init(44100);VoiceParams p;p.ampA=.001;p.ampS=1;p.lfo1Rate=200;
    std::vector<ModRoute> r{{S::LFO1,D::FilterCutoff,2.5}};
    s.setParams(p,r);s.noteOn(60,1);play(s,4096);
    ck(s.routeMin(0)<-.1f&&s.routeMax(0)>.1f,"one real voice block retains both LFO polarities");
    ck(s.routeMeter(0)>=s.routeMin(0)&&s.routeMeter(0)<=s.routeMax(0),"old signed peak stays inside the range");
    ck(s.routeMin(-1)==0&&s.routeMax(kMaxRoutes)==0,"invalid slots are zero");
    s.setParams(p,{});play(s,128);ck(s.routeMin(0)==0&&s.routeMax(0)==0,"deleted route clears extrema");
    FXParams fx;fx.lfo[0].rateHz=100; s.setFX(fx);
    s.setParams(p,{{S::FxLfo1,D::DistDrive,.8}});play(s,4096);
    ck(s.routeMin(0)<-.1f&&s.routeMax(0)>.1f,"FX rack block-rate LFO captures both signs");
    s.setParams(p,{{S::Macro1,D::DistDrive,-.5}});p.macros[0]=1;s.setParams(p,{{S::Macro1,D::DistDrive,-.5}});play(s,512);
    ck(s.routeMin(0)<-.49f&&s.routeMax(0)==0,"static FX route keeps its negative sign");
    RouteRangeTrace t;t.clear();float lo[kMaxRoutes]{},hi[kMaxRoutes]{};lo[0]=-.7f;hi[0]=.6f;
    t.update(lo,hi,kMaxRoutes,0);ck(t.low[0]==-.7f&&t.high[0]==.6f,"both sides displayed together");
    lo[0]=hi[0]=0;for(int i=0;i<3;++i)t.update(lo,hi,kMaxRoutes,.1);
    ck(t.low[0]<0&&t.high[0]>0,"range persists briefly across quiet polls");
    for(int i=0;i<7;++i)t.update(lo,hi,kMaxRoutes,.1);
    ck(t.low[0]==0&&t.high[0]==0,"range expires without a sticky trail");
    lo[0]=NAN;hi[0]=INFINITY;t.update(lo,hi,kMaxRoutes,.02);
    ck(t.low[0]==0&&t.high[0]==0,"nonfinite input is ignored");
    lo[0]=-.5f;hi[0]=.5f;t.update(lo,hi,kMaxRoutes,.02);t.clear();
    ck(t.low[0]==0&&t.high[0]==0,"preset/route change clears history");
    printf("%s 0.59.0 route range tests\n",fails?"FAIL":"ALL PASSED");return fails?1:0;
}
