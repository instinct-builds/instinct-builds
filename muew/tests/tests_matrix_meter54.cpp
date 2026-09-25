// 0.54.0: meters observe route contributions without changing the sound.
#include "../src/ui_model.h"
#include <cstdio>
#include <cmath>
#include <vector>
using namespace muew;
using S = ModRoute::Source;
using D = ModRoute::Dest;
static int failures=0;
static void check(bool ok, const char* msg) { printf("%s: %s\n", ok?"ok":"FAIL", msg); failures += !ok; }
static void play(Synth& s, int frames=512) {
    std::vector<float> l(frames),r(frames);
    s.renderPlanar(l.data(),r.data(),frames);
}
int main() {
    Synth s(4); s.init(44100);
    VoiceParams p; p.ampA=.001; p.ampR=.001; p.ampS=1; p.noiseLevel=.3; p.noiseCharacter=1; p.macros[0]=.6; p.macros[1]=.5;
    std::vector<ModRoute> routes{{S::Macro1,D::FilterCutoff,2.5,0,(int)S::Macro2},
                                  {S::LFO1,D::NoiseColor,.8},
                                  {S::Macro1,D::DistDrive,-.7}};
    s.setParams(p,routes);
    check(std::fabs(s.routeMeter(2)+.42f)<.00001f, "FX macro route is globally active without notes");
    check(s.routeMeter(0)==0 && s.routeMeter(1)==0, "voice routes idle without notes");
    s.noteOn(60,1); play(s);
    check(std::fabs(s.routeMeter(0)-.15f)<.0001f, "per-voice macro times AUX normalized to destination scale");
    check(std::fabs(s.routeMeter(1))>.03f && std::fabs(s.routeMeter(1))<=.8f, "LFO activity follows rendered noise color contribution");
    check(s.routeMeter(2)<-.419f, "FX macro route preserves signed level");
    check(s.routeMeter(16)==0 && s.routeMeter(-1)==0, "out-of-range slots are silent");
    // A short block near one LFO phase differs from a later block.
    s.setParams(p,routes); play(s,64); const float first=s.routeMeter(1);
    play(s,4096); const float later=s.routeMeter(1);
    check(std::fabs(later-first)>.002f, "LFO meter changes after next render block");
    s.allNotesOff(); play(s,44100);
    check(s.activeVoiceCount()==0 && s.routeMeter(0)==0 && s.routeMeter(1)==0 && s.routeMeter(2)<-.419f,
          "voice rows clear after release, global FX remains metered");
    // Rack LFO routes remain active independently of polyphony, and the
    // route index survives the voice/global split in a mixed matrix.
    FXParams fx; fx.lfo[0].rateHz=2; fx.lfo[0].shape=0; s.setFX(fx);
    std::vector<ModRoute> rack{{S::Velocity,D::FilterCutoff,2.5},
                                {S::FxLfo1,D::DistDrive,.8},
                                {S::LFO1,D::DistDrive,.9}}; // incompatible voice -> FX
    s.setParams(p,rack); play(s,512);
    check(s.routeMeter(0)==0 && std::fabs(s.routeMeter(1))>.001f && s.routeMeter(2)==0,
          "rack LFO runs without voices while unsupported FX source stays dark");
    const float rackFirst=s.routeMeter(1); play(s,4096);
    check(std::fabs(s.routeMeter(1)-rackFirst)>.01f, "FX LFO activity updates at rack block rate");
    s.setParams(p,{}); play(s,64);
    check(s.routeMeter(0)==0 && s.routeMeter(1)==0 && s.routeMeter(2)==0, "removing routes clears stale meters");
    Synth a(4),b(4); a.init(44100); b.init(44100); a.setParams(p,routes); b.setParams(p,routes);
    a.noteOn(60,1); b.noteOn(60,1);
    std::vector<float> al(2048),ar(2048),bl(2048),br(2048);
    a.renderPlanar(al.data(),ar.data(),2048); b.renderPlanar(bl.data(),br.data(),2048);
    check(al==bl && ar==br, "meter inspection leaves audio bit-identical");
    printf("%s matrix metering tests\n", failures?"FAIL":"ALL PASSED");
    return failures?1:0;
}
