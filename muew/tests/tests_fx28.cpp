// tests_fx28.cpp - 0.28.0 Space + Dynamics: HALL / PLATE reverb modes and the
// MULTIBAND compressor mode. Decay time, pre-delay, width, low cut, stability;
// band split transparency, downward and upward action, noise floor, trims;
// preset lines, clamping, panel rows, AU parameters, factory sounds untouched.
#include "../src/preset.h"
#include "../src/factory_bank.h"
#include "../src/ui_model.h"
#include "../src/au_params.h"
#include <cmath>
#include <cstdio>
#include <random>
#include <vector>

using namespace muew;
static int g_fail = 0;
static void check(bool c, const std::string& n) { printf("%s %s\n", c ? "ok:  " : "FAIL:", n.c_str()); if (!c) ++g_fail; }
struct St { std::vector<float> l, r; };
static St run(FXChain& c, const std::vector<float>& L, const std::vector<float>& R) {
    St o{L, R}; for (size_t i = 0; i < L.size(); ++i) c.process(o.l[i], o.r[i]); return o;
}
static double rms(const std::vector<float>& v, size_t a, size_t b) { double s = 0; for (size_t i = a; i < b; ++i) s += (double)v[i] * v[i]; return std::sqrt(s / (b - a)); }
static bool finite(const St& s) { for (size_t i = 0; i < s.l.size(); ++i) if (!std::isfinite(s.l[i]) || !std::isfinite(s.r[i])) return false; return true; }
static std::vector<float> noise(int n, float a, unsigned seed) { std::mt19937 g(seed); std::uniform_real_distribution<float> u(-a, a); std::vector<float> v(n); for (auto& x : v) x = u(g); return v; }
static std::vector<float> sine(int n, double hz, double a) { std::vector<float> v(n); for (int i = 0; i < n; ++i) v[i] = (float)(a * std::sin(2 * M_PI * hz * i / 44100.0)); return v; }
static FXChain chain(const FXParams& f) { FXChain c; c.init(44100); c.set(f); return c; }
// Time (s) for the wet tail of an impulse burst to fall 30 dB (x2 = RT60 estimate).
static double t30(const ReverbParams& rp) {
    FXParams f; f.reverb = rp; f.reverb.enabled = true; f.reverb.mix = 1.0; FXChain c = chain(f);
    const int n = 44100 * 8; std::vector<float> L(n, 0.0f), R(n, 0.0f);
    for (int i = 0; i < 882; ++i) L[i] = R[i] = (float)(0.5 * std::sin(2 * M_PI * 500.0 * i / 44100.0)); // 500 Hz burst: above the damping, below the low cut
    St o = run(c, L, R);
    const int w = 2205; double ref = 0; int refAt = 0;
    for (int b = 0; b + w < n; b += w) { double e = rms(o.l, b, b + w); if (e > ref) { ref = e; refAt = b; } }
    for (int b = refAt; b + w < n; b += w) if (rms(o.l, b, b + w) < ref * 0.0316) return (b - refAt) / 44100.0;
    return 99;
}

int main() {
    // ---- Reverb modes ----
    {
        ReverbParams h; h.mode = 1; h.decay = 0.6; h.damping = 0.2; h.preDelayMs = 0; h.lowCutHz = 20;
        const double rtSet = SpaceReverb::rt60(1, 0.6), rt = 2 * t30(h);
        check(rt > rtSet * 0.5 && rt < rtSet * 1.6, "HALL tail follows its RT60: set " + std::to_string(rtSet) + " s, measured ~" + std::to_string(rt) + " s");
        ReverbParams hl = h; hl.decay = 0.9; ReverbParams hs = h; hs.decay = 0.2;
        check(t30(hl) > t30(h) * 1.5 && t30(hs) < t30(h), "DECAY lengthens the HALL tail");
        ReverbParams pl = h; pl.mode = 2;
        check(t30(pl) < t30(h), "PLATE at the same DECAY is shorter than HALL");
        check(std::fabs(SpaceReverb::rt60(1, 0.0) - 0.8) < 1e-9 && std::fabs(SpaceReverb::rt60(1, 0.97) - 12.0) < 1e-9
              && std::fabs(SpaceReverb::rt60(2, 0.97) - 6.0) < 1e-9, "DECAY maps to HALL 0.8-12 s and PLATE 0.5-6 s");
        // Pre-delay: the first wet energy arrives after it.
        auto firstWet = [&](double preMs) {
            FXParams f; f.reverb = h; f.reverb.enabled = true; f.reverb.mix = 1.0; f.reverb.preDelayMs = preMs; FXChain c = chain(f);
            std::vector<float> L(22050, 0.0f), R(22050, 0.0f); L[0] = R[0] = 1.0f;
            St o = run(c, L, R);
            for (int i = 0; i < 22050; ++i) if (std::fabs(o.l[i]) > 1e-4) return i;
            return -1;
        };
        const int a0 = firstWet(0), a1 = firstWet(100);
        check(a1 - a0 > 4300 && a1 - a0 < 4520, "PRE-DELAY 100 ms delays the tail by ~4410 samples (" + std::to_string(a1 - a0) + ")");
        // Width: 0 collapses the wet signal to mono; 1 is decorrelated.
        auto sideRatio = [&](double width) {
            FXParams f; f.reverb = h; f.reverb.enabled = true; f.reverb.mix = 1.0; f.reverb.width = width; FXChain c = chain(f);
            auto in = noise(44100, 0.3f, 3); St o = run(c, in, in);
            double s = 0, m = 0; for (int i = 22050; i < 44100; ++i) { double d = o.l[i] - o.r[i], p = o.l[i] + o.r[i]; s += d * d; m += p * p; }
            return s / m;
        };
        check(sideRatio(0.0) < 1e-9 && sideRatio(1.0) > 0.2, "WIDTH 0 is mono, WIDTH 1 is wide");
        // Low cut: a 60 Hz tone loses much more wet level with LOW CUT at 600 Hz.
        auto lowLevel = [&](double lc) {
            FXParams f; f.reverb = h; f.reverb.enabled = true; f.reverb.mix = 1.0; f.reverb.lowCutHz = lc; FXChain c = chain(f);
            auto in = sine(44100, 60, 0.3); St o = run(c, in, in); return rms(o.l, 22050, 44100);
        };
        check(lowLevel(600) < lowLevel(20) * 0.3, "LOW CUT removes low end from the tail");
        // Stability at the extremes, both modes.
        bool ok = true;
        for (int m : {1, 2}) {
            FXParams f; f.reverb = ReverbParams{true, 0.97, 0.0, 1.0, m, 250, 1.0, 1.0, 20}; FXChain c = chain(f);
            auto in = noise(44100 * 4, 1.0f, 9); St o = run(c, in, in);
            ok = ok && finite(o) && rms(o.l, 44100 * 3, 44100 * 4) < 4.0;
        }
        check(ok, "HALL and PLATE stay finite and bounded at max decay, no damping, loud noise");
        // CLASSIC ignores the space rows.
        FXParams c0; c0.reverb.enabled = true; FXParams c1 = c0; c1.reverb.preDelayMs = 200; c1.reverb.size = 0.1; c1.reverb.width = 0.2; c1.reverb.lowCutHz = 900;
        auto in = noise(8000, 0.4f, 5); FXChain k0 = chain(c0), k1 = chain(c1);
        check(run(k0, in, in).l == run(k1, in, in).l, "CLASSIC ignores PRE-DELAY, SIZE, WIDTH and LOW CUT");
        // Decay macro offset still reaches HALL.
        FXParams fm; fm.reverb = h; fm.reverb.enabled = true; FXChain cm = chain(fm); FXChain::Mod md; md.reverbDecay = 0.3; cm.setMod(md);
        check(cm.reverb().space().rt60() > SpaceReverb::rt60(1, 0.6) * 1.5, "the REV DECAY route lengthens the HALL tail");
    }
    // ---- Multiband ----
    {
        auto in = noise(44100, 0.3f, 11);
        FXParams t; t.comp.enabled = true; t.comp.mode = 1; t.comp.amount = 0.0; t.comp.upward = 0.0;
        FXChain c = chain(t); St o = run(c, in, in);
        double err = 0; for (int i = 0; i < 44100; ++i) err = std::max(err, (double)std::fabs(o.l[i] - in[i]));
        check(err < 1e-5, "at zero depth the three bands sum back to the input (max error " + std::to_string(err) + ")");
        auto level = [&](double amp, double amount, double upward, double lowDb = 0) {
            FXParams f; f.comp.enabled = true; f.comp.mode = 1; f.comp.amount = amount; f.comp.upward = upward; f.comp.lowDb = lowDb;
            FXChain k = chain(f); auto s = sine(44100, 1000, amp); St r = run(k, s, s); return rms(r.l, 22050, 44100) / rms(s, 22050, 44100);
        };
        check(level(0.9, 0.8, 0.0) < 0.5, "loud material is pushed down: gain " + std::to_string(level(0.9, 0.8, 0.0)));
        check(level(0.003, 0.8, 1.0) > 2.0, "quiet material (-50 dBFS) is lifted by UPWARD: gain " + std::to_string(level(0.003, 0.8, 1.0)));
        check(std::fabs(level(0.003, 0.8, 0.0) - 1.0) < 0.05, "UPWARD 0 leaves quiet material alone");
        check(std::fabs(level(0.0001, 0.8, 1.0) - 1.0) < 0.05, "the noise floor (-80 dBFS) is not raised");
        auto lowTrim = [&](double db) {
            FXParams f; f.comp.enabled = true; f.comp.mode = 1; f.comp.amount = 0.0; f.comp.upward = 0.0; f.comp.lowDb = db;
            FXChain k = chain(f); auto s = sine(44100, 25, 0.3); St r = run(k, s, s); return rms(r.l, 22050, 44100) / rms(s, 22050, 44100);
        };
        check(std::fabs(20 * std::log10(lowTrim(6.0)) - 6.0) < 1.5 && std::fabs(20 * std::log10(lowTrim(-6.0)) + 6.0) < 1.5, "LOW trims the low band (25 Hz: " + std::to_string(20 * std::log10(lowTrim(6.0))) + " dB)");
        FXParams dm; dm.comp.enabled = true; dm.comp.mode = 1; dm.comp.amount = 1.0; dm.comp.upward = 1.0; dm.comp.mix = 0.0;
        FXChain kd = chain(dm); St dr = run(kd, in, in);
        check(dr.l == in, "MIX 0 is dry");
        const auto& mb = kd.params().comp; (void)mb;
        MultibandComp m; m.init(44100); CompressorParams cp; cp.mode = 1; cp.amount = 0.6; cp.upward = 0.5; m.set(cp);
        check(m.staticGainDb(0) < -5 && m.staticGainDb(-60) > 2 && m.staticGainDb(-25) == 0.0 && m.staticGainDb(-100) == 0.0, "static curve: down above, up below, flat between, off at the floor");
        FXParams o1; o1.comp.enabled = true; FXParams o2 = o1; o2.comp.upward = 0.9; o2.comp.speed = 0.1; o2.comp.midDb = 5; o2.comp.mix = 0.3;
        FXChain j1 = chain(o1), j2 = chain(o2);
        check(run(j1, in, in).l == run(j2, in, in).l, "ONE-KNOB ignores the MULTIBAND rows");
        FXParams hot; hot.comp = CompressorParams{true, 1.0, 1, 1.0, 1.0, 12, 12, 12, 1.0}; FXChain kh = chain(hot);
        auto big = noise(44100, 1.0f, 2); St bo = run(kh, big, big);
        check(finite(bo) && rms(bo.l, 0, 44100) < 4.0, "extreme MULTIBAND settings stay finite");
    }
    // ---- Presets, panel, parameters ----
    {
        Preset p = factoryPresets()[7];
        p.fx.reverb.mode = 2; p.fx.reverb.preDelayMs = 35; p.fx.reverb.size = 0.8; p.fx.reverb.width = 0.7; p.fx.reverb.lowCutHz = 250;
        p.fx.comp.mode = 1; p.fx.comp.upward = 0.6; p.fx.comp.speed = 0.7; p.fx.comp.lowDb = 2; p.fx.comp.midDb = -1.5; p.fx.comp.highDb = 3; p.fx.comp.mix = 0.8;
        const std::string t = p.serialize();
        Preset q; const bool ok = q.parse(t);
        check(ok && q == p && q.serialize() == t, "reverbx and compx round-trip");
        check(t.find("\nreverbx 2 35 0.8 0.7 250\n") != std::string::npos && t.find("\ncompx 1 0.6 0.7 2 -1.5 3 0.8\n") != std::string::npos, "saved as reverbx / compx lines");
        Preset r = q; r.fx.reverb.size = 0.81; check(!(r == q), "a reverb change makes presets differ");
        Preset c; c.parse(factoryPresets()[7].serialize() + "reverbx 7 999 5 -2 5\ncompx 4 9 -1 50 -50 0 3\n");
        check(c.fx.reverb.mode == 2 && c.fx.reverb.preDelayMs == 250 && c.fx.reverb.size == 1 && c.fx.reverb.width == 0 && c.fx.reverb.lowCutHz == 20
              && c.fx.comp.mode == 1 && c.fx.comp.upward == 1 && c.fx.comp.speed == 0 && c.fx.comp.lowDb == 12 && c.fx.comp.midDb == -12 && c.fx.comp.mix == 1,
              "out-of-range values clamp on load");
        bool clean = true;
        for (const auto& fp : factoryPresets()) { const std::string s = fp.serialize(); if (s.find("\nreverbx ") != std::string::npos || s.find("\ncompx ") != std::string::npos) clean = false; }
        check(clean, "no factory sound writes the new lines");
        FXParams f;
        check(ui::fxControlCount(FxReverb) == 8 && ui::fxControlCount(FxComp) == 8, "reverb and compressor pages list 8 rows");
        check(ui::fxValueText(f, FxReverb, 0) == "CLASSIC" && ui::fxRowInactive(f, FxReverb, 3) && !ui::fxRowInactive(f, FxReverb, 1)
              && ui::fxRowInactive(f, FxComp, 2) && !ui::fxRowInactive(f, FxComp, 1), "CLASSIC / ONE-KNOB grey out the new rows");
        ui::fxSet(f, FxReverb, 0, 1); ui::fxSet(f, FxReverb, 3, 80); ui::fxSet(f, FxComp, 0, 1);
        check(f.reverb.mode == 1 && ui::fxValueText(f, FxReverb, 0) == "HALL" && ui::fxValueText(f, FxReverb, 3) == "80.0 ms" && !ui::fxRowInactive(f, FxReverb, 3)
              && ui::fxValueText(f, FxComp, 0) == "MULTIBAND" && !ui::fxRowInactive(f, FxComp, 4), "mode rows switch on the new rows");
        check(std::string(ui::fxChoiceName(FxReverb, 2)) == "PLATE" && std::string(ui::fxChoiceName(FxComp, 0)) == "ONE-KNOB" && std::string(ui::fxChoiceName(FxDist, 1)) == "FOLD",
              "segmented choice labels per unit");
        Preset a = factoryPresets()[3];
        params::set(a, params::ReverbSize, 25); params::set(a, params::CompUpward, 70);
        check(std::fabs(a.fx.reverb.size - 0.25) < 1e-12 && std::fabs(a.fx.comp.upward - 0.7) < 1e-12 && params::def(params::ReverbSize).unit == params::Percent,
              "AU parameters 36 Reverb Size and 37 Multiband Upward map to the sound");
    }
    if (g_fail) { printf("%d FX28 TEST(S) FAILED\n", g_fail); return 1; }
    printf("ALL FX28 TESTS PASSED\n");
    return 0;
}
