// 0.73.0: phaser L/R phase spread, exact legacy default, state and UI model.
#include "../src/preset.h"
#include "../src/factory_bank.h"
#include "../src/ui_model.h"
#include <cmath>
#include <cstdio>
#include <vector>
using namespace muew;
static int failures=0;
static void check(bool ok,const char* name){printf("%s %s\n",ok?"ok:  ":"FAIL:",name);failures+=!ok;}
static std::vector<float> render(PhaserParams p,double sr,int n,bool right){
    Phaser ph;ph.init(sr);ph.set(p);std::vector<float> out(n);
    for(int i=0;i<n;++i){float l=(float)(.4*std::sin(2*M_PI*220*i/sr)),r=l;ph.process(l,r);out[i]=right?r:l;}
    return out;
}
// Old 0.72 right-channel signal path kept independently to catch a shifted default.
static std::vector<float> legacyRight(PhaserParams p,double sr,int n){
    double phase=0,s[6]={},last=0;std::vector<float> out(n);
    for(int i=0;i<n;++i){
        double in=(float)(.4*std::sin(2*M_PI*220*i/sr));
        double lfo=.5+.5*std::sin(2*M_PI*(phase+.25));
        double hz=180*std::pow(25.0,p.depth*lfo);
        double t=std::tan(M_PI*std::min(hz,sr*.45)/sr),a=(t-1)/(t+1);
        double x=in-p.feedback*std::tanh(last);
        for(int k=0;k<6;++k){double y=a*x+s[k];s[k]=x-a*y;if(std::fabs(s[k])<1e-20)s[k]=0;x=y;}
        last=x;x*=1-.25*p.feedback;
        double comp=1/std::sqrt((1-p.mix)*(1-p.mix)+p.mix*p.mix);
        out[i]=(float)(((1-p.mix)*in+p.mix*x)*comp);
        phase+=std::clamp(p.rateHz,.02,8.0)/sr;phase-=std::floor(phase);
    }
    return out;
}
int main(){
    PhaserParams p;p.enabled=true;p.rateHz=1.2;p.depth=.9;p.feedback=.6;p.mix=.75;
    for(double sr:{22050.,44100.,48000.,96000.}){
        auto l=render(p,sr,(int)sr,true),r=render(p,sr,(int)sr,false);
        bool finite=true;double difference=0;
        for(size_t i=0;i<l.size();++i){finite&=std::isfinite(l[i])&&std::isfinite(r[i]);difference+=std::fabs(l[i]-r[i]);}
        check(finite,"phaser remains finite across sample rates");
        check(difference/sr>.001,"legacy quarter-cycle produces stereo motion");
    }
    check(render(p,44100,44100,true)==legacyRight(p,44100,44100),"default right output exactly matches legacy quarter-cycle path");
    auto left=render(p,44100,44100,false),quarter=render(p,44100,44100,true);
    p.spread=0;auto zeroL=render(p,44100,44100,false),zeroR=render(p,44100,44100,true);
    check(zeroL==zeroR&&zeroL==left,"zero spread aligns both channels without moving left");
    p.spread=1;auto wideL=render(p,44100,44100,false),wideR=render(p,44100,44100,true);
    check(wideL==left&&wideR!=quarter&&wideR!=zeroR,"full spread moves only right channel to half-cycle");
    Preset original=factoryPresets()[7];auto old=original.serialize();Preset loaded;
    check(old.find("phaserspread ")==std::string::npos&&loaded.parse(old)&&loaded.fx.phaser.spread==.5&&loaded.serialize()==old,
          "legacy factory text omits extension and round-trips exactly");
    original.fx.phaser.spread=.78;const auto text=original.serialize();Preset again;
    check(again.parse(text)&&again==original&&again.serialize()==text&&text.find("phaserspread 0.78")!=std::string::npos,
          "edited spread round-trips via optional extension line");
    Preset legacyFx;legacyFx.parse(old+"phaser 1 1.2 0.9 0.6 0.75\n");
    check(legacyFx.fx.phaser.spread==.5&&legacyFx.serialize().find("phaserspread ")==std::string::npos,
          "old phaser line inherits quarter-cycle spread without rewriting");
    Preset bounded;bounded.parse(old+"phaserspread -2\n");check(bounded.fx.phaser.spread==0,"spread below zero clamps");
    Preset invalid;invalid.parse(old+"phaserspread nan\n");check(invalid.fx.phaser.spread==.5,"nonfinite spread keeps legacy default");
    FXParams f;check(ui::fxControlCount(FxPhaser)==5&&ui::fxDefault(FxPhaser,4)==.5,"fifth phaser row defaults to 50%");
    ui::fxSet(f,FxPhaser,4,.78);check(f.phaser.spread==.78&&f.phaser.mix==.5&&f.phaser.depth==.7,
          "SPREAD row changes only phaser phase");
    puts(failures?"PHASER SPREAD TESTS FAILED":"ALL PHASER SPREAD TESTS PASSED");return failures?1:0;
}
