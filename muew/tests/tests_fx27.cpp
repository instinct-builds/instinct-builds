// tests_fx27.cpp - 0.27.0 FX depth: HYPER / DIMENSION and FILTER FX units.
// Width and decorrelation, detune modulation, filter response per mode,
// tempo-synced sweep locking to the host bar, preset round-trip, older
// 8-unit fxorder lines, panel model rows, and factory sounds untouched.
#include "../src/preset.h"
#include "../src/factory_bank.h"
#include "../src/ui_model.h"
#include "../src/synth.h"
#include <cmath>
#include <cstdio>
#include <random>
#include <vector>

using namespace muew;
static int g_fail = 0;
static void check(bool c, const std::string& n) { printf("%s %s\n", c ? "ok:  " : "FAIL:", n.c_str()); if (!c) ++g_fail; }
using D = ModRoute::Dest;
using S = ModRoute::Source;

struct Stereo { std::vector<float> l, r; };
static std::vector<float> noise(int n, unsigned seed = 7) {
    std::mt19937 g(seed); std::uniform_real_distribution<float> u(-0.5f, 0.5f);
    std::vector<float> v(n); for (auto& x : v) x = u(g); return v;
}
static std::vector<float> sine(int n, double hz, double sr = 44100) {
    std::vector<float> v(n); for (int i = 0; i < n; ++i) v[i] = (float)(0.5 * std::sin(2 * M_PI * hz * i / sr)); return v;
}
static Stereo run(FXChain& c, const std::vector<float>& mono) {
    Stereo s{std::vector<float>(mono.size()), std::vector<float>(mono.size())};
    for (size_t i = 0; i < mono.size(); ++i) { float l = mono[i], r = mono[i]; c.process(l, r); s.l[i] = l; s.r[i] = r; }
    return s;
}
static double rms(const std::vector<float>& v, size_t from = 0) {
    double s = 0; for (size_t i = from; i < v.size(); ++i) s += (double)v[i] * v[i]; return std::sqrt(s / std::max<size_t>(1, v.size() - from));
}
static double corr(const std::vector<float>& a, const std::vector<float>& b, size_t from) {
    double ab = 0, aa = 0, bb = 0;
    for (size_t i = from; i < a.size(); ++i) { ab += a[i] * b[i]; aa += a[i] * a[i]; bb += b[i] * b[i]; }
    return ab / std::sqrt(aa * bb + 1e-30);
}
static bool finite(const Stereo& s) { for (size_t i = 0; i < s.l.size(); ++i) if (!std::isfinite(s.l[i]) || !std::isfinite(s.r[i])) return false; return true; }
static double gainAt(const FilterFxParams& p, double hz) {
    FXChain c; c.init(44100); FXParams f; f.filter = p; f.filter.enabled = true; c.set(f);
    auto in = sine(22050, hz); auto o = run(c, in);
    return rms(o.l, 11025) / rms(in, 11025);
}
static std::vector<float> renderPreset(const Preset& p, int n) {
    Synth s; s.init(44100); s.setTempo(120); s.setParams(p.voice, p.routes); s.setFX(p.fx); s.setTables(p.tables[0], p.tables[1]);
    std::vector<float> L(n), R(n); s.noteOn(48, 0.9f); s.renderPlanar(L.data(), R.data(), n);
    L.insert(L.end(), R.begin(), R.end()); return L;
}

int main() {
    const int N = 44100;
    // ---- HYPER / DIMENSION ----
    {
        auto in = noise(N);
        FXChain off; off.init(44100); FXParams f0; off.set(f0);
        auto dry = run(off, in);
        check(dry.l == in && dry.r == in, "HYPER off by default leaves the signal bit-exact");
        FXChain c; c.init(44100); FXParams f; f.hyper = HyperParams{true, 0.35, 0.6, 0.5, 1.0}; c.set(f);
        auto o = run(c, in);
        const double cr = corr(o.l, o.r, 4410);
        check(finite(o) && cr < 0.6, "HYPER spreads a mono input: L/R correlation " + std::to_string(cr));
        const double lv = rms(o.l, 4410) / rms(in, 4410);
        check(lv > 0.5 && lv < 1.6, "HYPER keeps the level near unity: " + std::to_string(lv));
        // Dimension adds width on top of the voices.
        FXChain c2; c2.init(44100); FXParams f2 = f; f2.hyper.dimension = 0.0; c2.set(f2);
        auto o2 = run(c2, in);
        check(o2.l != o.l, "DIMENSION changes the image");
        // Detune: a pure sine picks up sidebands (spectral spread) with detune.
        auto tone = sine(N, 440);
        auto spread = [&](double det) {
            FXChain h; h.init(44100); FXParams p; p.hyper = HyperParams{true, 2.0, det, 0.0, 1.0}; h.set(p);
            auto y = run(h, tone);
            // Envelope ripple of the wet sum = beating between detuned copies.
            double mn = 1e9, mx = 0;
            for (int b = 4; b < 40; ++b) { double e = 0; for (int i = b * 1000; i < b * 1000 + 1000; ++i) e += y.l[i] * y.l[i]; mn = std::min(mn, e); mx = std::max(mx, e); }
            return mx / (mn + 1e-12);
        };
        const double s0 = spread(0.0), s1 = spread(1.0);
        check(s1 > s0 * 1.05, "more DETUNE means more beating (" + std::to_string(s0) + " -> " + std::to_string(s1) + ")");
        // Macro route into HY DETUNE moves the output; macro 0 is bit-exact.
        FXChain m0; m0.init(44100); m0.set(f); FXChain::Mod md; m0.setMod(md);
        check(run(m0, in).l == o.l, "a zero HY DETUNE offset changes nothing");
        FXChain m1; m1.init(44100); FXParams fl = f; fl.hyper.detune = 0.1; m1.set(fl); md.hyperDetune = 0.8; m1.setMod(md);
        FXChain m2; m2.init(44100); m2.set(fl);
        check(run(m1, tone).l != run(m2, tone).l, "a HY DETUNE offset moves the detune");
    }
    // ---- FILTER FX ----
    {
        FilterFxParams p; p.cutoffHz = 1000; p.reso = 0.1; p.mix = 1.0;
        p.mode = 0; const double lpLo = gainAt(p, 200), lpHi = gainAt(p, 6000);
        check(lpLo > 0.8 && lpHi < 0.1, "LOW PASS passes 200 Hz and cuts 6 kHz");
        p.mode = 2; const double hpLo = gainAt(p, 200), hpHi = gainAt(p, 6000);
        check(hpLo < 0.1 && hpHi > 0.8, "HIGH PASS cuts 200 Hz and passes 6 kHz");
        p.mode = 1; const double bpC = gainAt(p, 1000), bpLo = gainAt(p, 100);
        check(bpC > bpLo * 4, "BAND PASS peaks at the cutoff");
        p.mode = 3; const double nC = gainAt(p, 1000), nLo = gainAt(p, 150);
        check(nC < 0.2 && nLo > 0.8, "NOTCH removes the cutoff and keeps the rest");
        p.mode = 0; p.reso = 0.9; const double res = gainAt(p, 1000);
        check(res > 3.0, "RESONANCE boosts the cutoff: x" + std::to_string(res));
        p.reso = 0.1; p.mix = 0.0;
        check(std::fabs(gainAt(p, 6000) - 1.0) < 0.01, "MIX 0 is dry");
        // Macro route: +1 = +4 octaves on the cutoff.
        FXChain c; c.init(44100); FXParams f; f.filter.enabled = true; f.filter.cutoffHz = 500; c.set(f);
        FXChain::Mod md; md.filterCutoff = 0.5; c.setMod(md);
        check(std::fabs(c.filterFx().cutoffNow() - 2000.0) < 1.0, "FX CUTOFF offset 0.5 moves the cutoff two octaves up");
        // Sweep: the LFO moves the cutoff over time.
        FXChain w; w.init(44100); FXParams fw; fw.filter.enabled = true; fw.filter.cutoffHz = 800; fw.filter.lfoDepth = 0.5; fw.filter.lfoRateHz = 2; w.set(fw);
        double lo = 1e9, hi = 0; float l = 0, r = 0;
        for (int i = 0; i < N; ++i) { l = r = 0; w.process(l, r); if (i % 100 == 0) { lo = std::min(lo, w.filterFx().cutoffNow()); hi = std::max(hi, w.filterFx().cutoffNow()); } }
        check(hi / lo > 12.0, "SWEEP 50% moves the cutoff about +-2 octaves");
        check(std::fabs(w.filterFx().cutoffNow(0) - w.filterFx().cutoffNow(1)) > 1.0, "the right channel sweep runs ahead of the left");
        // Tempo sync: 1/4 at 120 BPM = 2 Hz; host beat locks the phase.
        FXChain t; t.init(44100); t.setTempo(120); FXParams ft = fw; ft.filter.lfoSync = 1; t.set(ft);
        int quarter = -1; for (int i = 1; i < kSyncCount; ++i) if (std::fabs(syncBeats(i) - 1.0) < 1e-9) quarter = i;
        ft.filter.lfoSync = quarter; t.set(ft);
        check(quarter > 0 && std::fabs(t.filterFx().lfoHz() - 2.0) < 1e-9, "a 1/4 synced sweep runs at 2 Hz at 120 BPM");
        t.lockLfos(8.25);
        check(std::fabs(t.filterFx().lfoPhase() - 0.25) < 1e-9, "the host beat locks the synced sweep phase");
        FXChain fr; fr.init(44100); fr.set(fw); fr.lockLfos(8.25);
        check(fr.filterFx().lfoPhase() == 0.0, "a free sweep ignores the host beat");
        // Stability: max resonance + drive on loud noise.
        FXChain hot; hot.init(44100); FXParams fh; fh.filter = FilterFxParams{true, 4, 18000, 1.0, 1.0, 20, 0, 1.0, 1.0}; hot.set(fh);
        auto big = noise(N); for (auto& x : big) x *= 3.0f;
        auto ho = run(hot, big);
        check(finite(ho) && rms(ho.l) < 20.0, "extreme FILTER FX settings stay finite");
    }
    // ---- Presets ----
    {
        Preset p = factoryPresets()[7];
        p.fx.hyper = HyperParams{true, 1.2, 0.7, 0.25, 0.6};
        p.fx.filter = FilterFxParams{true, 1, 900, 0.55, 0.2, 3.0, 2, 0.4, 0.8};
        p.fx.order.move(p.fx.order.slotOf(FxFilter), 0);
        p.routes.push_back({S::Macro2, D::FxFilterCutoff, 0.5});
        p.routes.push_back({S::Macro3, D::FxHyperDetune, 0.3});
        const std::string t = p.serialize();
        Preset q; const bool ok = q.parse(t);
        check(ok && q == p && q.serialize() == t, "HYPER, FILTER FX, order and routes round-trip");
        check(t.find("\nhyper 1 ") != std::string::npos && t.find("\nfilterfx 1 1 ") != std::string::npos, "units are saved as hyper/filterfx lines");
        Preset r = q; r.fx.filter.cutoffHz = 901;
        check(!(r == q), "a FILTER FX change makes presets differ");
        // Older 8-unit fxorder line.
        Preset old; old.parse(factoryPresets()[7].serialize() + "fxorder phaser dist reverb chorus delay comp eq flanger\n");
        const int want[kFxUnits] = {FxPhaser, FxDist, FxReverb, FxChorus, FxDelay, FxComp, FxEQ, FxFlanger, FxHyper, FxFilter};
        bool same = true; for (int i = 0; i < kFxUnits; ++i) same = same && old.fx.order.slot[i] == want[i];
        check(same, "an older 8-unit fxorder line loads with the new units at the end");
        Preset clamp; clamp.parse(factoryPresets()[7].serialize() + "filterfx 1 9 99999 5 -1 100 99 7 2\nhyper 1 50 9 -3 4\n");
        check(clamp.fx.filter.mode == 4 && clamp.fx.filter.cutoffHz == 18000 && clamp.fx.filter.reso == 1 && clamp.fx.filter.drive == 0
              && clamp.fx.filter.lfoRateHz == 20 && clamp.fx.filter.lfoSync == kSyncCount - 1 && clamp.fx.hyper.rateHz == 5 && clamp.fx.hyper.dimension == 0,
              "out-of-range values clamp on load");
        bool clean = true;
        for (const auto& fp : factoryPresets()) {
            const std::string s = fp.serialize();
            if (s.find("\nhyper ") != std::string::npos || s.find("\nfilterfx ") != std::string::npos || fp.fx.hyper.enabled || fp.fx.filter.enabled) clean = false;
        }
        check(clean, "no factory sound turns on or writes the new units");
        // Enabling a unit changes the render; the dry render is unaffected by the new code path.
        Preset a = factoryPresets()[3]; Preset b = a; b.fx.hyper.enabled = true; b.fx.hyper.mix = 0.7;
        Preset c = a; c.fx.filter.enabled = true; c.fx.filter.cutoffHz = 600;
        const auto ra = renderPreset(a, 22050);
        check(renderPreset(b, 22050) != ra && renderPreset(c, 22050) != ra, "turning on HYPER or FILTER FX changes a preset's sound");
    }
    // ---- Panel model ----
    {
        check(ui::fxControlCount(FxHyper) == 4 && ui::fxControlCount(FxFilter) == 8
              && std::string(ui::fxUnitTitle(FxHyper)) == "HYPER / DIMENSION" && std::string(ui::fxUnitTitle(FxFilter)) == "FILTER FX", "panel rows and titles");
        FXParams f;
        ui::fxSet(f, FxFilter, 0, 2.4); ui::fxSet(f, FxFilter, 1, 99999); ui::fxSet(f, FxFilter, 6, 3);
        check(f.filter.mode == 2 && f.filter.cutoffHz == 18000 && f.filter.lfoSync == 3 && ui::fxRowInactive(f, FxFilter, 5), "FILTER FX rows write through and clamp");
        check(ui::fxValueText(f, FxFilter, 0) == "HIGH PASS" && ui::fxValueText(f, FxFilter, 1) == "18.00 kHz" && ui::fxValueText(f, FxFilter, 5) == "TEMPO", "FILTER FX value text");
        ui::fxSet(f, FxHyper, 1, 0.75);
        check(f.hyper.detune == 0.75 && ui::fxValueText(f, FxHyper, 1) == "75%", "HYPER rows write through");
        check((int)D::FxHyperDetune == 28 && (int)D::FxFilterCutoff == 29 && ui::isFxDest(D::FxHyperDetune) && ui::isFxDest(D::FxFilterCutoff)
              && std::string(ui::destName(D::FxHyperDetune)) == "HY DETUNE" && std::string(ui::destName(D::FxFilterCutoff)) == "FX CUTOFF", "new destinations are appended and global");
        check(ui::fxUnitDest(FxHyper) == (int)D::FxHyperDetune && ui::fxUnitDest(FxFilter) == (int)D::FxFilterCutoff, "each unit has a mod destination");
    }
    if (g_fail) { printf("%d FX27 TEST(S) FAILED\n", g_fail); return 1; }
    printf("ALL FX27 TESTS PASSED\n");
    return 0;
}
