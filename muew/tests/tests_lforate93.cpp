// 0.93.0 LFO RATE destinations: octave-exponential, cycle-free by construction.
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
// Phase of LFO `n` after `samples` samples of a held note.
static double phaseAfter(VoiceParams vp, const std::vector<ModRoute>& routes, int n, int samples, float vel = 1.0f, double bpm = 120.0) {
    Wavetable wt; Voice v; v.init(44100, &wt); v.setTempo(bpm); v.setParams(vp, routes); v.noteOn(60, vel);
    for (int i = 0; i < samples; ++i) { float l, r; v.processStereo(l, r); }
    return v.lfo(n).phase();
}
static double wrap(double x) { return x - std::floor(x); }
int main() {
    ck((int)D::Lfo1Rate == 33 && (int)D::Lfo4Rate == 36 && params::Count == 40 &&
       ui::matrixDests().size() == 41 && ui::matrixDests()[32] == D::NoiseColor && ui::matrixDests()[36] == D::Lfo4Rate &&
       std::string(ui::destName(D::Lfo3Rate)) == "LFO3 RATE", "destinations 33-36 appended, AU IDs unchanged, labels visible");
    ck(ui::routeScale(D::Lfo1Rate) == 4.0, "full scale is four octaves");
    VoiceParams vp; vp.lfo2Rate = 1.0; vp.macros[0] = 1.0;
    const int N = 11025; // a quarter second
    ck(std::fabs(phaseAfter(vp, {}, 1, N) - 0.25) < 1e-3, "baseline: 1 Hz for 0.25 s is phase 0.25");
    ck(std::fabs(phaseAfter(vp, {{S::Macro1, D::Lfo2Rate, 1.0}}, 1, N) - 0.5) < 1e-3, "+1 octave doubles the rate");
    ck(std::fabs(phaseAfter(vp, {{S::Macro1, D::Lfo2Rate, -1.0}}, 1, N) - 0.125) < 1e-3, "-1 octave halves the rate");
    ck(std::fabs(phaseAfter(vp, {{S::Macro1, D::Lfo2Rate, 0.0}}, 1, N) - phaseAfter(vp, {}, 1, N)) == 0.0, "zero amount is exactly the baseline");
    VoiceParams mac0 = vp; mac0.macros[0] = 0.0;
    ck(std::fabs(phaseAfter(mac0, {{S::Macro1, D::Lfo2Rate, 3.0}}, 1, N) - 0.25) < 1e-6, "a source at zero leaves the rate alone");
    ck(std::fabs(phaseAfter(vp, {{S::Velocity, D::Lfo2Rate, 1.0}}, 1, N, 1.0f) - 0.5) < 1e-3 &&
       std::fabs(phaseAfter(vp, {{S::Velocity, D::Lfo2Rate, 1.0}}, 1, N, 0.5f) - 0.25 * std::pow(2.0, 0.5)) < 1e-3, "velocity scales the rate per note");
    ck(std::fabs(phaseAfter(vp, {{S::Macro1, D::Lfo2Rate, 1.0}}, 0, N) - wrap(vp.lfo1Rate * 0.25)) < 1e-3, "other LFOs keep their own rate");
    ModRoute self{S::LFO2, D::Lfo2Rate, 1.0}, higher{S::LFO3, D::Lfo2Rate, 1.0}, lower{S::LFO1, D::Lfo2Rate, 1.0}, back{S::LFO2, D::Lfo1Rate, 1.0};
    ck(!ui::routeActive(self) && !ui::routeActive(higher) && !ui::routeActive(back) && ui::routeActive(lower), "only a lower-numbered LFO may drive an LFO rate");
    ck(std::string(ui::routeAmountReadout(self)) == "LOWER LFO ONLY" && std::string(ui::routeAmountReadout(lower)) == "+1.00 oct", "readouts say why and show octaves");
    const double base = phaseAfter(vp, {}, 1, N);
    ck(phaseAfter(vp, {self}, 1, N) == base && phaseAfter(vp, {higher}, 1, N) == base, "invalid routes are ignored by the voice, sample-identically");
    ck(std::fabs(phaseAfter(vp, {lower}, 1, N) - base) > 1e-4, "a lower LFO does modulate the rate");
    VoiceParams sy = vp; sy.lfoSync[1] = 3; // 1/4 at 120 bpm = 2 Hz
    ck(std::fabs(phaseAfter(sy, {}, 1, N) - 0.5) < 1e-3 && std::fabs(phaseAfter(sy, {{S::Macro1, D::Lfo2Rate, -1.0}}, 1, N) - 0.25) < 1e-3, "synced LFOs follow the same octave scaling");
    double ph = phaseAfter(vp, {{S::Macro1, D::Lfo2Rate, 40.0}}, 1, N);
    ck(std::isfinite(ph) && ph >= 0.0 && ph < 1.0, "extreme amounts stay finite and clamped");
    { Wavetable wt; Voice v; v.init(44100, &wt); v.setParams(vp, {{S::Macro1, D::Lfo2Rate, 1.0}}); v.noteOn(60, 1.0f);
      for (int i = 0; i < 2000; ++i) { float l, r; v.processStereo(l, r); }
      ck(std::fabs(v.routeMax(0) - 0.25f) < 1e-3f, "matrix meter reports the octave contribution on the four-octave scale"); }
    { Wavetable wt; Voice v; v.init(44100, &wt); v.setParams(vp, {{S::Macro1, D::Lfo2Rate, 1.0}}); v.noteOn(60, 1.0f);
      for (int i = 0; i < 1000; ++i) { float l, r; v.processStereo(l, r); }
      v.setParams(vp, {}); const double p0 = v.lfo(1).phase();
      for (int i = 0; i < N; ++i) { float l, r; v.processStereo(l, r); }
      ck(std::fabs(wrap(v.lfo(1).phase() - p0) - 0.25) < 1e-3, "clearing the routes returns the LFO to its base rate"); }
    Preset p; p.voice.lfo2Rate = 1.0;
    p.routes = {{S::Macro1, D::Lfo2Rate, 1.0}, {S::LFO1, D::Lfo4Rate, -0.5}, {S::Keytrack, D::Lfo1Rate, 0.75}};
    auto text = p.serialize(); Preset q;
    ck(q.parse(text) && q == p && text.find(" 34 ") != std::string::npos, "routes round-trip with numeric IDs 33-36");
    Preset junk; junk.routes = {{S::Macro1, (D)41, 1.0}};
    Preset back2; ck(!back2.parse(junk.serialize()) || back2.routes.empty(), "unknown destination 41 is still refused");
    bool factories = factoryPresets().size() == 108;
    for (const auto& f : factoryPresets()) for (const auto& r : f.routes) factories &= (int)r.dest < 33;
    ck(factories, "all 108 factory presets predate destination 33");
    printf("%s\n", failures ? "LFO RATE 93 FAILED" : "ALL LFO RATE 93 TESTS PASSED"); return failures ? 1 : 0;
}
