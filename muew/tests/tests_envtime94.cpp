// 0.94.0 envelope TIME destinations: octave scaling of attack, decay and release.
#include "../src/preset.h"
#include "../src/factory_bank.h"
#include "../src/synth.h"
#include "../src/ui_model.h"
#include "../src/au_params.h"
#include <cmath>
#include <cstdio>
#include <vector>
using namespace muew;
static int failures = 0;
static void ck(bool ok, const char* msg) { printf("%s %s\n", ok ? "ok:" : "FAIL:", msg); failures += !ok; }
using D = ModRoute::Dest;
using S = ModRoute::Source;
static VoiceParams base() {
    VoiceParams vp; vp.ampA = 0.1; vp.ampD = 0.2; vp.ampS = 0.5; vp.ampR = 0.2; vp.macros[0] = 1.0;
    vp.modA = 0.1; vp.modD = 0.2; vp.modS = 0.5; vp.modR = 0.2; vp.env3A = 0.1; vp.env3D = 0.2; vp.env3S = 0.5; vp.env3R = 0.2;
    return vp;
}
static double levelAfter(const VoiceParams& vp, const std::vector<ModRoute>& routes, int env, int samples, bool release = false, int relSamples = 0) {
    Wavetable wt; Voice v; v.init(44100, &wt); v.setParams(vp, routes); v.noteOn(60, 1.0f);
    for (int i = 0; i < samples; ++i) { float l, r; v.processStereo(l, r); }
    if (release) { v.noteOff(); for (int i = 0; i < relSamples; ++i) { float l, r; v.processStereo(l, r); } }
    return v.envelope(env).level();
}
int main() {
    ck((int)D::AmpEnvTime == 37 && (int)D::Env3Time == 39 && params::Count == 40 && ui::matrixDests().size() == 41 &&
       ui::matrixDests()[39] == D::Env3Time && std::string(ui::destName(D::ModEnvTime)) == "MOD ENV TIME", "destinations 37-39 appended, AU IDs unchanged, labels visible");
    ck(ui::routeScale(D::AmpEnvTime) == 4.0, "full scale is four octaves");
    const int N = 2205; // 50 ms: halfway up a 100 ms attack
    for (int e = 0; e < 3; ++e) {
        const D d = (D)(37 + e);
        const VoiceParams vp = base();
        const double l0 = levelAfter(vp, {}, e, N), lp = levelAfter(vp, {{S::Macro1, d, 1.0}}, e, N), lm = levelAfter(vp, {{S::Macro1, d, -1.0}}, e, N);
        ck(std::fabs(l0 - 0.5) < 0.01 && std::fabs(lp - 0.25) < 0.01 && lm > 0.95 && lm <= 1.0, "+1 oct halves the attack slope, -1 oct doubles it");
    }
    { const VoiceParams vp = base();
      const double r0 = levelAfter(vp, {}, 1, 88200, true, 4410), rp = levelAfter(vp, {{S::Macro1, D::ModEnvTime, 1.0}}, 1, 88200, true, 4410);
      ck(rp > r0, "a longer time stretches release too"); }
    { const VoiceParams vp = base();
      ck(levelAfter(vp, {{S::Macro1, D::AmpEnvTime, 0.0}}, 0, N) == levelAfter(vp, {}, 0, N), "zero amount is exactly the baseline");
      VoiceParams m0 = vp; m0.macros[0] = 0.0;
      ck(levelAfter(m0, {{S::Macro1, D::AmpEnvTime, 3.0}}, 0, N) == levelAfter(vp, {}, 0, N), "a source at zero leaves the time alone"); }
    ModRoute selfMod{S::ModEnv, D::ModEnvTime, 1.0}, selfE3{S::Env3, D::Env3Time, 1.0}, crossOk{S::ModEnv, D::Env3Time, 1.0}, ampFromMod{S::ModEnv, D::AmpEnvTime, 1.0};
    ck(!ui::routeActive(selfMod) && !ui::routeActive(selfE3) && ui::routeActive(crossOk) && ui::routeActive(ampFromMod), "an envelope cannot drive its own time");
    ck(std::string(ui::routeAmountReadout(selfMod)) == "NOT ITSELF" && std::string(ui::routeAmountReadout(crossOk)) == "+1.00 oct", "readouts say why and show octaves");
    { const VoiceParams vp = base();
      ck(levelAfter(vp, {selfMod}, 1, N) == levelAfter(vp, {}, 1, N), "invalid routes are ignored, sample-identically"); }
    { const VoiceParams vp = base(); const double x = levelAfter(vp, {{S::Macro1, D::AmpEnvTime, 40.0}}, 0, N);
      ck(std::isfinite(x) && x > 0.0 && x < 0.1, "extreme amounts stay finite (time scale clamps at 16x)"); }
    { Wavetable wt; Voice v; v.init(44100, &wt); v.setParams(base(), {{S::Macro1, D::AmpEnvTime, 1.0}}); v.noteOn(60, 1.0f);
      for (int i = 0; i < 1000; ++i) { float l, r; v.processStereo(l, r); }
      ck(std::fabs(v.routeMax(0) - 0.25f) < 1e-3f, "matrix meter reports octaves on the four-octave scale"); }
    { Wavetable wt; Voice v; v.init(44100, &wt); v.setParams(base(), {{S::Macro1, D::AmpEnvTime, 1.0}}); v.noteOn(60, 1.0f);
      for (int i = 0; i < 500; ++i) { float l, r; v.processStereo(l, r); }
      v.setParams(base(), {}); float l, r; v.processStereo(l, r); const double a0 = v.envelope(0).level(); v.processStereo(l, r);
      ck(std::fabs((v.envelope(0).level() - a0) - 1.0 / (0.1 * 44100)) < 1e-7, "clearing the routes restores the base time"); }
    Preset p; p.routes = {{S::Macro1, D::AmpEnvTime, 1.0}, {S::Velocity, D::ModEnvTime, -0.5}, {S::LFO1, D::Env3Time, 0.75}};
    auto text = p.serialize(); Preset q;
    ck(q.parse(text) && q == p && text.find(" 37 ") != std::string::npos, "routes round-trip with numeric IDs 37-39");
    Preset junk; junk.routes = {{S::Macro1, (D)41, 1.0}};
    Preset b2; ck(!b2.parse(junk.serialize()) || b2.routes.empty(), "unknown destination 41 is still refused");
    bool factories = factoryPresets().size() == 108;
    for (const auto& f : factoryPresets()) for (const auto& r : f.routes) factories &= (int)r.dest < 37;
    ck(factories, "all 108 factory presets predate destination 37");
    printf("%s\n", failures ? "ENV TIME 94 FAILED" : "ALL ENV TIME 94 TESTS PASSED"); return failures ? 1 : 0;
}
