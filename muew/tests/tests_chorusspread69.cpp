// 0.69.0: chorus L/R phase spread, default parity, state and reset.
#include "../src/preset.h"
#include "../src/factory_bank.h"
#include "../src/ui_model.h"
#include <cmath>
#include <cstdio>
#include <string>
#include <vector>
using namespace muew;
static int bad=0;
static void check(bool yes,const char* s){printf("%s %s\n",yes?"ok:  ":"FAIL:",s);bad+=!yes;}
static std::vector<float> render(ChorusParams p,double sr,int n,bool left){
    Chorus c;c.init(sr);c.set(p);std::vector<float> out(n);
    for(int i=0;i<n;++i){float l=std::sin(2*M_PI*220*i/sr)*.4f,r=l;c.process(l,r);out[i]=left?l:r;}
    return out;
}
int main(){
    ChorusParams p;p.enabled=true;p.mix=1;p.depthMs=12;p.rateHz=1.2;
    for(double sr:{22050.,44100.,48000.,96000.}){
        auto l=render(p,sr,(int)sr,true),r=render(p,sr,(int)sr,false);
        bool finite=true;double d=0;
        for(size_t i=0;i<l.size();++i){finite &= std::isfinite(l[i])&&std::isfinite(r[i]);d+=std::fabs(l[i]-r[i]);}
        check(finite,"stereo chorus finite across sample rates");
        check(d/sr>1e-3,"legacy 90-degree L/R taps retain stereo motion");
    }
    const auto left=render(p,44100,44100,true),legacy=render(p,44100,44100,false);
    p.spread=0;
    const auto monoL=render(p,44100,44100,true),monoR=render(p,44100,44100,false);
    check(monoL==monoR,"spread zero locks L/R motion on identical input");
    check(monoL==left,"spread never changes left tap");
    p.spread=1;
    const auto wideL=render(p,44100,44100,true),wideR=render(p,44100,44100,false);
    check(wideL==left&&wideR!=legacy&&wideR!=monoR,"180-degree setting moves only right tap");
    p.spread=.5;
    check(render(p,44100,44100,false)==legacy,"default 90-degree setting is byte-identical");
    Chorus reset;reset.init(44100);reset.set(p);
    for(int i=0;i<1200;++i){float l=.1f,r=l;reset.process(l,r);}
    // The FXChain Reset reconstructs the unit, not a second call to Chorus::init.
    FXChain chain;chain.init(44100);FXParams fx;fx.chorus=p;chain.set(fx);
    for(int i=0;i<1200;++i){float l=.1f,r=l;chain.process(l,r);}
    chain.init(44100); FXChain fresh;fresh.init(44100);fresh.set(fx);
    bool equal=true;
    for(int i=0;i<2000;++i){float l=i?0:1,r=l,a=l,b=r;chain.process(l,r);fresh.process(a,b);equal &= l==a&&r==b;}
    check(equal,"host Reset clears chorus buffers and LFO phase");
    Preset original=factoryPresets()[7];
    check(original.serialize().find("chorusspread ")==std::string::npos,"old factory preset omits spread line");
    original.fx.chorus.spread=.78;const std::string text=original.serialize();Preset copy;
    check(copy.parse(text)&&copy==original&&copy.serialize()==text&&text.find("chorusspread 0.78")!=std::string::npos,
          "new spread round-trips through AU/preset text");
    Preset bounded;bounded.parse(factoryPresets()[7].serialize()+"chorusspread -2\n");
    check(bounded.fx.chorus.spread==0,"spread below zero clamps");
    Preset invalid;invalid.parse(factoryPresets()[7].serialize()+"chorusspread nan\n");
    check(invalid.fx.chorus.spread==.5,"nonfinite value leaves legacy default");
    FXParams f;
    check(ui::fxControlCount(FxChorus)==5&&ui::fxGet(f,FxChorus,4)==.5,"fifth chorus row has 90-degree default");
    ui::fxSet(f,FxChorus,4,.75);
    check(f.chorus.spread==.75&&f.chorus.depthMs==6&&f.chorus.mix==.35,"SPREAD row edits only phase");
    printf("%s\n",bad?"CHORUS SPREAD TESTS FAILED":"ALL CHORUS SPREAD TESTS PASSED");return bad?1:0;
}
