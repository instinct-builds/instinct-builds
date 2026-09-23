// tests_routecurve.cpp - 0.16.0 matrix route curves and aux sources.
#include "../src/preset.h"
#include "../src/factory_bank.h"
#include "../src/ui_model.h"
#include <cmath>
#include <cstdio>
#include <vector>

using namespace muew;
static int g_fail = 0;
static void check(bool c, const std::string& n) { printf("%s %s\n", c ? "ok:  " : "FAIL:", n.c_str()); if (!c) ++g_fail; }
using D = ModRoute::Dest;
using S = ModRoute::Source;

static std::vector<float> render(const Preset& p, int n, float vel = 0.9f) {
    Synth s; s.init(44100); s.setParams(p.voice, p.routes); s.setFX(p.fx); s.setTables(p.tables[0], p.tables[1]);
    std::vector<float> L(n), R(n); s.noteOn(48, vel); s.renderPlanar(L.data(), R.data(), n); return L;
}
static bool same(const std::vector<float>& a, const std::vector<float>& b) { for (size_t i = 0; i < a.size(); ++i) if (a[i] != b[i]) return false; return true; }
static double dist(const std::vector<float>& a, const std::vector<float>& b) { double d = 0; for (size_t i = 0; i < a.size(); ++i) d += std::fabs(a[i] - b[i]); return d / a.size(); }

int main() {
    // The curve itself.
    check(routeCurve(0.37, 0.0) == 0.37 && routeCurve(-0.8, 0.0) == -0.8, "curve 0 is the identity, bit-exact");
    check(std::fabs(routeCurve(0.5, 1.0) - 0.0625) < 1e-12 && std::fabs(routeCurve(0.5, -1.0) - 0.9375) < 1e-12, "EXP 100% = x^4, LOG 100% = 1-(1-x)^4");
    check(routeCurve(-0.5, 1.0) == -routeCurve(0.5, 1.0) && routeCurve(1.0, 0.7) == 1.0 && routeCurve(0.0, -0.7) == 0.0, "symmetric for bipolar, ends fixed");
    bool mono = true; double prev = -1;
    for (int i = 0; i <= 100; ++i) { double y = routeCurve(i / 100.0, 0.6); if (y < prev) mono = false; prev = y; }
    check(mono, "curves are monotonic");
    check(auxLevel((int)S::LFO1, -1) == 0 && auxLevel((int)S::LFO1, 1) == 1 && auxLevel((int)S::Velocity, 0.4) == 0.4, "aux levels: bipolar maps -1..1 to 0..1");

    // Readouts and reachability.
    check(ui::curveReadout(0) == "LINEAR" && ui::curveReadout(0.5) == "EXP 50%" && ui::curveReadout(-0.25) == "LOG 25%", "curve readouts");
    check(ui::clampCurve(0.01) == 0.0 && ui::clampCurve(1.7) == 1.0, "curve drag snaps to linear and clamps");
    ModRoute vr{S::LFO1, D::FilterCutoff, 1.0}; vr.aux = (int)S::Velocity;
    ModRoute fr{S::Macro1, D::FxDelayFeedback, 0.5}; fr.aux = (int)S::FxLfo1;
    ModRoute bad1 = vr; bad1.aux = (int)S::FxLfo2;
    ModRoute bad2 = fr; bad2.aux = (int)S::Velocity;
    check(ui::auxActive(vr) && ui::auxActive(fr) && !ui::auxActive(bad1) && !ui::auxActive(bad2), "aux reachability: voice aux on voice routes, global aux on FX routes");

    // Serialization.
    bool clean = true;
    for (const auto& p : factoryPresets()) { auto t = p.serialize(); if (t.find(" curve ") != std::string::npos || t.find(" aux ") != std::string::npos) clean = false; }
    check(clean, "factory sounds write no curve/aux suffix");
    Preset p = factoryPresets()[7];
    p.routes.push_back(vr); p.routes.back().curve = 0.4;
    p.routes.push_back(fr);
    std::string t = p.serialize(); Preset q;
    check(q.parse(t) && q == p && q.serialize() == t && t.find("route 0 2 1 curve 0.4 aux 2\n") != std::string::npos, "curve and aux round-trip");
    Preset bad; bad.parse(factoryPresets()[7].serialize() + "route 0 2 1 curve 9 aux 44\nroute 3 2 1 aux -3 curve -0.5\nroute 3 2 1 bogus 4 curve 0.5\n");
    auto& br = bad.routes;
    check(br.size() >= 3 && br[br.size() - 3].curve == 1.0 && br[br.size() - 3].aux == -1 && br[br.size() - 2].aux == -1 && br[br.size() - 2].curve == -0.5
          && br.back().curve == 0.0, "out-of-range curve/aux clamp or drop; unknown keys stop the suffix");
    Preset diff = p; diff.routes.back().aux = (int)S::FxLfo2;
    check(!(diff == p), "aux is part of preset equality");

    // Engine: defaults bit-exact, curve and aux change the sound.
    Preset base = factoryPresets()[2];
    base.routes = {{S::LFO2, D::FilterCutoff, 2.0}};
    base.voice.lfo2Rate = 3.0;
    auto a = render(base, 22050);
    Preset curved = base; curved.routes[0].curve = 0.8;
    auto c = render(curved, 22050);
    check(dist(a, c) > 1e-3, "an EXP curve on LFO 2 -> cutoff changes the sound");
    Preset auxd = base; auxd.routes[0].aux = (int)S::Velocity;
    auto hi = render(auxd, 22050, 1.0f), lo = render(auxd, 22050, 0.2f);
    Preset velFull = base;
    check(same(render(velFull, 22050, 1.0f), hi), "velocity aux at full velocity equals no aux");
    check(dist(hi, lo) > 1e-3, "velocity aux scales the route by how hard the note is played");
    Preset rackAuxOnVoice = base; rackAuxOnVoice.routes[0].aux = (int)S::FxLfo1;
    check(same(render(rackAuxOnVoice, 22050), a), "a rack LFO aux on a voice route is ignored");

    // FX routes: macro curve, macro aux (static), rack-LFO aux (moving).
    Preset fx = factoryPresets()[2];
    fx.fx.delay.enabled = true; fx.fx.delay.feedback = 0.3;
    fx.voice.macros[0] = 0.5; fx.voice.macros[1] = 0.25;
    fx.routes = {{S::Macro1, D::FxDelayFeedback, 0.4}};
    auto feedback = [](const Preset& pr, int steps) {
        Synth s; s.init(44100); s.setParams(pr.voice, pr.routes); s.setFX(pr.fx);
        double lo = 9, hi = -9;
        for (int i = 0; i < steps; ++i) { float l = 0, r = 0; s.fx().process(l, r); double f = s.fx().delay().feedback(); lo = std::min(lo, f); hi = std::max(hi, f); }
        return std::make_pair(lo, hi);
    };
    auto f0 = feedback(fx, 64);
    check(std::fabs(f0.first - 0.5) < 1e-9 && f0.first == f0.second, "macro 50% x 0.4 adds 0.2 feedback (baseline)");
    Preset fc = fx; fc.routes[0].curve = 1.0;
    check(std::fabs(feedback(fc, 64).first - (0.3 + 0.0625 * 0.4)) < 1e-9, "EXP curve on a macro FX route: 0.5^4 x 0.4");
    Preset fa = fx; fa.routes[0].aux = (int)S::Macro2;
    check(std::fabs(feedback(fa, 64).first - (0.3 + 0.5 * 0.25 * 0.4)) < 1e-9, "Macro 2 aux scales the FX route statically");
    Preset fl = fx; fl.routes[0].aux = (int)S::FxLfo1; fl.fx.lfo[0] = RackLfoParams{2.0, 3, 0};
    auto f3 = feedback(fl, 44100);
    check(std::fabs(f3.first - 0.3) < 1e-9 && std::fabs(f3.second - 0.5) < 1e-9, "FX LFO 1 aux gates the macro route between 0 and full");
    Preset fv = fx; fv.routes[0].aux = (int)S::Velocity;
    check(std::fabs(feedback(fv, 64).first - 0.5) < 1e-9, "a voice aux on an FX route is ignored");
    Preset lc = fx; lc.routes = {{S::FxLfo1, D::FxDelayFeedback, 0.2}}; lc.routes[0].curve = 1.0; lc.fx.lfo[0] = RackLfoParams{1.0, 3, 0};
    auto f5 = feedback(lc, 44100);
    check(std::fabs(f5.first - 0.1) < 1e-9 && std::fabs(f5.second - 0.5) < 1e-9, "curve on a square FX LFO keeps its +/-1 swing");

    printf(g_fail ? "%d ROUTE CURVE TEST(S) FAILED\n" : "ALL ROUTE CURVE TESTS PASSED\n", g_fail);
    return g_fail ? 1 : 0;
}
