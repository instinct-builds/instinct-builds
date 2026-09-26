#include "../src/preset.h"
#include "../src/factory_bank.h"
#include "../src/au_params.h"
#include <cstdio>
#include <cmath>
#include <vector>
using namespace muew;
static int failures=0;
static void ck(bool b,const char* m){printf("%s %s\n",b?"ok:":"FAIL:",m);failures+=!b;}
struct Stereo{std::vector<float> l,r;};
static Stereo render(VoiceParams p,float velocity,int n=12000){
    Synth s;s.init(48000);s.setParams(p,{});s.noteOn(60,velocity);
    Stereo x;x.l.resize(n);x.r.resize(n);s.renderPlanar(x.l.data(),x.r.data(),n);return x;
}
static double layer(const std::vector<float>& full,const std::vector<float>& bed){
    double sum=0;for(size_t i=250;i<1500;++i){double x=full[i]-bed[i];sum+=x*x;}
    return std::sqrt(sum/1250);
}
int main(){
    Preset p,q;p.voice.noiseBurst=.125;p.voice.noiseBurstVelocity=.65;
    auto text=p.serialize();ck(text.find("\nnoiseb 0.125\nnoisebvel 0.65\n")!=std::string::npos,"optional velocity depth follows burst shape");
    ck(q.parse(text)&&q==p,"velocity depth round trips without a new format");
    Preset old;old.voice.noiseBurst=.125;auto legacy=old.serialize();
    ck(legacy.find("noisebvel")==std::string::npos&&q.parse(legacy)&&q.voice.noiseBurstVelocity==0,"old preset is static and omits velocity line");
    ck(q.parse(legacy+"noisebvel -1\n")&&q.voice.noiseBurstVelocity==0&&q.parse(legacy+"noisebvel 2\n")&&q.voice.noiseBurstVelocity==1,"velocity depth clamps 0..1");
    ck(q.parse(legacy+"noisebvel nan\n")&&q.voice.noiseBurstVelocity==0,"nonfinite depth ignored");
    for(int hq=0;hq<2;++hq)for(int mode=0;mode<4;++mode){
        VoiceParams v;v.noiseLevel=.35;v.noiseWidth=.8;v.noiseCharacter=mode;
        v.noiseColor=.7;v.noiseBurst=.125;v.oscQuality=hq;v.ampA=.001;v.ampS=1;
        auto legacySound=render(v,.25f);
        v.noiseBurstVelocity=1;auto hard=render(v,1.f);
        v.noiseBurstVelocity=0;auto hardLegacy=render(v,1.f);
        ck(hard.l==hardLegacy.l&&hard.r==hardLegacy.r,"hard strike unchanged with depth on (stereo/HQ)");
        v.noiseBurstVelocity=1;auto soft=render(v,.25f);
        VoiceParams noNoise=v;noNoise.noiseLevel=0;auto bed=render(noNoise,.25f);
        double leftBase=layer(legacySound.l,bed.l),rightBase=layer(legacySound.r,bed.r);
        double leftSoft=layer(soft.l,bed.l),rightSoft=layer(soft.r,bed.r);
        ck(leftBase>1e-5&&rightBase>1e-5&&leftSoft/leftBase>.20&&leftSoft/leftBase<.31&&
           rightSoft/rightBase>.20&&rightSoft/rightBase<.31,"soft hit attenuates burst-only contribution in both channels/HQ");
        v.noiseBurstVelocity=.5;auto mid=render(v,.25f);
        ck(layer(mid.l,bed.l)>leftSoft&&layer(mid.l,bed.l)<leftBase&&
           layer(mid.r,bed.r)>rightSoft&&layer(mid.r,bed.r)<rightBase,"half depth sits between static and full response");
        v.noiseBurst=0;v.noiseBurstVelocity=1;auto sustained=render(v,.25f);
        v.noiseBurstVelocity=0;auto sustainedLegacy=render(v,.25f);
        ck(sustained.l==sustainedLegacy.l&&sustained.r==sustainedLegacy.r,"BURST OFF ignores velocity depth bit-for-bit");
    }
    bool factory=true;for(const auto& f:factoryPresets())factory &= f.voice.noiseBurstVelocity==0&&f.serialize().find("noisebvel ")==std::string::npos;
    ck(factory&&factoryPresets().size()==108&&params::Count==40,"factory renders and AU ID count untouched");
    printf("%s noise burst63 tests\n",failures?"FAIL":"ALL PASSED");return failures?1:0;
}
