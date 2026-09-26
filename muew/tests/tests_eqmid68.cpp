// 0.68.0: sweepable EQ middle bell, neutral response, reset and legacy state.
#include "../src/preset.h"
#include "../src/factory_bank.h"
#include "../src/ui_model.h"
#include <cmath>
#include <cstdio>
#include <string>
using namespace muew;
static int bad=0;
static void check(bool yes,const char* s){printf("%s %s\n",yes?"ok:  ":"FAIL:",s);bad+=!yes;}
int main(){
    EQParams p; p.enabled=true; p.midDb=9;
    EQ3 eq; eq.init(44100); eq.set(p);
    const double baseline=eq.responseDb(1200);
    check(std::fabs(baseline-9)<.05,"middle bell gain at legacy 1.2 kHz");
    p.midHz=3500; eq.set(p);
    check(std::fabs(eq.responseDb(3500)-9)<.05 && eq.responseDb(1200)<baseline-1,
          "middle center moves without changing its gain");
    const double shoulder=eq.responseDb(1800);
    p.midQ=4; eq.set(p);
    check(eq.responseDb(1800)<shoulder-1 && std::fabs(eq.responseDb(3500)-9)<.05,
          "higher Q narrows shoulders while center remains fixed");
    EQParams neutral=p;neutral.midDb=0;eq.set(neutral);
    check(std::fabs(eq.responseDb(3500))<1e-7 && std::fabs(eq.responseDb(900))<1e-7,
          "neutral gain is flat for every center and Q");
    p.midDb=-9;eq.set(p);
    check(std::fabs(eq.responseDb(3500)+9)<.05,"negative gain cuts at swept center");
    bool finite=true;
    for(double sr:{22050.,44100.,48000.,96000.}){
        EQ3 band;band.init(sr);
        for(double hz:{200.,1200.,3500.,8000.}) for(double q:{.3,.9,8.}){
            p.midHz=hz;p.midQ=q;p.midDb=12;band.set(p);
            for(int n=0;n<10000;++n){float l=n==0?1.f:0.f,r=l;band.process(l,r);finite&=std::isfinite(l)&&std::isfinite(r)&&std::fabs(l)<10;}
            finite&=std::isfinite(band.responseDb(std::min(hz,sr*.45)));
        }
    }
    check(finite,"bounded finite response at 22.05/44.1/48/96 kHz and Q/frequency extremes");
    p=EQParams{};p.enabled=true;p.midDb=7;p.midHz=5200;p.midQ=3;
    EQ3 reset;reset.init(44100);reset.set(p);
    for(int n=0;n<400;++n){float l=n==0?1.f:0.f,r=l;reset.process(l,r);}
    reset.init(44100);reset.set(p);
    EQ3 fresh;fresh.init(44100);fresh.set(p);
    bool same=true;
    for(int n=0;n<400;++n){float l=n==0?1.f:0.f,r=l,a=l,b=r;reset.process(l,r);fresh.process(a,b);same &= l==a&&r==b;}
    check(same,"host Reset clears EQ memories and reapplies swept bell");
    p.midHz=1200;p.midQ=.9;
    EQ3 baselineEq;baselineEq.init(44100);baselineEq.set(p);
    EQ3 legacy;legacy.init(44100);legacy.set(p);
    bool identical=true;
    for(int n=0;n<1000;++n){float a=(n%17)/17.f,b=a,c=a,d=b;baselineEq.process(a,b);legacy.process(c,d);identical &= a==c&&b==d;}
    check(identical,"legacy center/Q render bytes identical");
    Preset factory=factoryPresets()[7];
    check(factory.serialize().find("eqmid ")==std::string::npos,"factory state omits new line");
    factory.fx.eq.midHz=3500;factory.fx.eq.midQ=2.4;
    std::string line=factory.serialize();Preset copy;
    check(copy.parse(line)&&copy==factory&&copy.serialize()==line&&line.find("eqmid 3500 2.4")!=std::string::npos,
          "new bell state round-trips in preset and AU state");
    Preset clamp;clamp.parse(factoryPresets()[7].serialize()+"eqmid 90000 -2\n");
    check(clamp.fx.eq.midHz==8000&&clamp.fx.eq.midQ==.3,"out-of-range settings clamp");
    Preset invalid;invalid.parse(factoryPresets()[7].serialize()+"eqmid nan inf\n");
    check(invalid.fx.eq.midHz==1200&&invalid.fx.eq.midQ==.9,"invalid state leaves defaults");
    FXParams f;
    check(ui::fxControlCount(FxEQ)==5&&ui::fxGet(f,FxEQ,3)==1200&&ui::fxGet(f,FxEQ,4)==.9,
          "five EQ rows include MID FREQ and MID Q");
    ui::fxSet(f,FxEQ,3,3500);ui::fxSet(f,FxEQ,4,2.4);
    check(f.eq.midHz==3500&&f.eq.midQ==2.4&&f.eq.lowDb==0&&f.eq.highDb==0,
          "EQ rows touch only middle bell settings");
    printf("%s\n",bad?"EQ MID TESTS FAILED":"ALL EQ MID TESTS PASSED");return bad?1:0;
}
