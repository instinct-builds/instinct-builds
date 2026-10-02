// 0.95.0 LEVEL A destination: oscillator A gain offset around unity.
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
static double rms(const VoiceParams& vp, const std::vector<ModRoute>& routes) {
    Wavetable wt; Voice v; v.init(44100, &wt); v.setParams(vp, routes); v.noteOn(60, 1.0f);
    double e = 0; for (int i = 0; i < 8820; ++i) { float l, r; v.processStereo(l, r); if (i > 2205) e += (double)l * l + (double)r * r; }
    return std::sqrt(e);
}
int main() {
    ck((int)D::Osc1Level == 40 && params::Count == 40 && ui::matrixDests().size() == 41 && ui::matrixDests()[40] == D::Osc1Level &&
       std::string(ui::destName(D::Osc1Level)) == "LEVEL A", "destination 40 appended, AU IDs unchanged, label visible");
    VoiceParams vp; vp.osc2Level = 0.0; vp.macros[0] = 1.0;
    const double base = rms(vp, {}), mute = rms(vp, {{S::Macro1, D::Osc1Level, -1.0}}), half = rms(vp, {{S::Macro1, D::Osc1Level, -0.5}}), up = rms(vp, {{S::Macro1, D::Osc1Level, 0.5}});
    ck(base > 0.1, "baseline sounds");
    ck(mute < base * 1e-6, "-1 mutes oscillator A");
    ck(std::fabs(half / base - 0.5) < 1e-3, "-0.5 halves oscillator A");
    ck(std::fabs(up / base - 1.5) < 1e-3, "+0.5 is 1.5x");
    ck(std::fabs(rms(vp, {{S::Macro1, D::Osc1Level, 3.0}}) / base - 1.5) < 1e-3, "boost clamps at 1.5x");
    ck(rms(vp, {{S::Macro1, D::Osc1Level, 0.0}}) == base, "zero amount is exactly the baseline");
    VoiceParams m0 = vp; m0.macros[0] = 0.0;
    ck(rms(m0, {{S::Macro1, D::Osc1Level, -1.0}}) == base, "a source at zero leaves the level alone");
    { Wavetable wt; Voice v; v.init(44100, &wt); v.setParams(vp, {{S::Macro1, D::Osc1Level, -0.5}}); v.noteOn(60, 1.0f);
      for (int i = 0; i < 1000; ++i) { float l, r; v.processStereo(l, r); }
      ck(std::fabs(v.routeMin(0) + 0.5f) < 1e-3f, "matrix meter shows the level offset on the unit scale"); }
    Preset p; p.routes = {{S::Velocity, D::Osc1Level, -0.5}};
    auto text = p.serialize(); Preset q;
    ck(q.parse(text) && q == p && text.find("route 2 40 -0.5") != std::string::npos, "route round-trips as numeric ID 40");
    Preset junk; junk.routes = {{S::Macro1, (D)41, 1.0}};
    Preset b2; ck(!b2.parse(junk.serialize()) || b2.routes.empty(), "unknown destination 41 is still refused");
    bool factories = factoryPresets().size() == 108;
    for (const auto& f : factoryPresets()) for (const auto& r : f.routes) factories &= (int)r.dest < 40;
    ck(factories, "all 108 factory presets predate destination 40");
    printf("%s\n", failures ? "LEVEL A 95 FAILED" : "ALL LEVEL A 95 TESTS PASSED"); return failures ? 1 : 0;
}
