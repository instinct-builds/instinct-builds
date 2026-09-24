// tests_fxdetail.cpp - 0.14.0 FX detail editor: every unit control readable
// and writable through the panel model, tempo-synced delay, and macro routes
// into the new FX destinations. Factory sounds stay untouched.
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

// Renders an impulse train through a synth-less FX chain; returns the left channel.
static std::vector<float> clicks(FXChain& c, int n, int every) {
    std::vector<float> out(n);
    for (int i = 0; i < n; ++i) { float l = (i % every == 0) ? 0.8f : 0.0f, r = l; c.process(l, r); out[i] = l; }
    return out;
}
static int firstEcho(const std::vector<float>& v, int from) {
    for (int i = from; i < (int)v.size(); ++i) if (std::fabs(v[i]) > 0.01f) return i;
    return -1;
}

int main() {
    // Panel model: counts, titles, every row round-trips through fxSet/fxGet.
    const int counts[kFxUnits] = {4, 4, 6, 8, 8, 3, 4, 4, 4, 8};
    bool cnt = true; for (int u = 0; u < kFxUnits; ++u) cnt = cnt && ui::fxControlCount(u) == counts[u] && *ui::fxUnitTitle(u);
    check(cnt, "every unit lists its controls (dist 3, chorus 4, delay 6, comp 1, reverb 3, eq 3, phaser 4, flanger 4)");
    bool rt = true, clampOk = true, normOk = true;
    for (int u = 0; u < kFxUnits; ++u)
        for (int i = 0; i < ui::fxControlCount(u); ++i) {
            const auto& c = ui::fxControls(u)[i];
            FXParams f;
            double mid = c.fmt == ui::FmtChoice ? std::round((c.lo + c.hi) / 2) : ui::fxFromNorm(c, 0.37);
            ui::fxSet(f, u, i, mid);
            if (std::fabs(ui::fxGet(f, u, i) - mid) > 1e-9) rt = false;
            ui::fxSet(f, u, i, c.hi + 100); if (ui::fxGet(f, u, i) != c.hi) clampOk = false;
            ui::fxSet(f, u, i, c.lo - 100); if (ui::fxGet(f, u, i) != c.lo) clampOk = false;
            if (c.fmt != ui::FmtChoice && std::fabs(ui::fxNorm(c, ui::fxFromNorm(c, 0.61)) - 0.61) > 1e-9) normOk = false;
            // Writing one row leaves every other row of every unit alone.
            FXParams g, h; ui::fxSet(g, u, i, mid);
            for (int u2 = 0; u2 < kFxUnits; ++u2) for (int i2 = 0; i2 < ui::fxControlCount(u2); ++i2)
                if ((u2 != u || i2 != i) && ui::fxGet(g, u2, i2) != ui::fxGet(h, u2, i2)) rt = false;
        }
    check(rt, "every detail row writes only its own field and reads back");
    check(clampOk, "detail rows clamp to their ranges");
    check(normOk, "slider position maps back to the same value (linear and log rows)");
    FXParams f;
    check(ui::fxValueText(f, FxDelay, 0) == "280 ms" && ui::fxValueText(f, FxDelay, 1) == "FREE", "delay rows read 280 ms / FREE by default");
    ui::fxSet(f, FxDelay, 1, 4);
    check(ui::fxValueText(f, FxDelay, 1) == "1/8" && ui::fxValueText(f, FxDelay, 0) == "TEMPO" && ui::fxRowInactive(f, FxDelay, 0),
          "a synced side shows its division and its TIME row follows the tempo");
    check(ui::fxValueText(f, FxDist, 0) == "SOFT CLIP" && ui::fxValueText(f, FxEQ, 1) == "+0.0 dB" && ui::fxValueText(f, FxPhaser, 0) == "0.40 Hz",
          "value text for choice, dB and Hz rows");

    // Tempo-synced delay: 1/8 at 120 BPM = 250 ms, at 90 BPM = 333 ms.
    FXParams d; d.delay.enabled = true; d.delay.mix = 0.5; d.delay.feedback = 0; d.delay.syncL = 4; d.delay.syncR = 3;
    FXChain c; c.init(44100); c.set(d);
    auto o = clicks(c, 44100, 44100);
    int e1 = firstEcho(o, 10);
    check(std::abs(e1 - 11025) <= 2, "1/8 sync at 120 BPM echoes after 250 ms (" + std::to_string(e1) + " samples)");
    FXChain c2; c2.init(44100); c2.setTempo(90); c2.set(d);
    auto o2 = clicks(c2, 44100, 44100);
    int e2 = firstEcho(o2, 10);
    check(std::abs(e2 - 14700) <= 2, "1/8 sync at 90 BPM echoes after 333 ms (" + std::to_string(e2) + " samples)");
    check(std::fabs(c2.delay().timeR() - 60.0 / 90.0) < 1e-9, "the right side follows 1/4 at 90 BPM");
    FXParams slow = d; slow.delay.syncL = 9; // 2/1 = 8 beats: capped at the 2 s line
    FXChain c3; c3.init(44100); c3.setTempo(60); c3.set(slow);
    check(c3.delay().timeL() <= 1.99, "a long division at a slow tempo is capped at the delay line");

    // Preset: delaysync line only when set; round-trips; damaged values clamp.
    Preset p = factoryPresets()[7];
    check(p.serialize().find("delaysync") == std::string::npos, "factory sounds write no delaysync line");
    p.fx.delay.syncL = 4; p.fx.delay.syncR = 6;
    std::string t = p.serialize(); Preset q;
    check(q.parse(t) && q == p && q.serialize() == t && t.find("delaysync 4 6") != std::string::npos, "delay sync round-trips");
    Preset bad; bad.parse(factoryPresets()[7].serialize() + "delaysync 99 -3\n");
    check(bad.fx.delay.syncL == kSyncCount - 1 && bad.fx.delay.syncR == 0, "out-of-range sync values clamp");

    // New destinations: appended after Filter2Cutoff, parse, names, macros only.
    check((int)D::FxDelayFeedback == 16 && (int)D::FxChorusDepth == 20, "FX destinations are appended (16-20)");
    Preset m = factoryPresets()[7];
    m.routes.push_back({S::Macro1, D::FxReverbDecay, 0.3});
    m.routes.push_back({S::LFO1, D::FxPhaserDepth, 0.5});
    Preset m2; m2.parse(m.serialize());
    check(m2 == m, "routes into FX destinations survive save and load");
    check(std::string(ui::destName(D::FxDelayFeedback)) == "DELAY FB" && std::string(ui::destName(D::FxChorusDepth)) == "CH DEPTH", "destination names");
    check(ui::routeAmountReadout(m.routes.back()) == "GLOBAL ONLY" && ui::routeAmountReadout(m.routes[m.routes.size() - 2]) == "+30%",
          "a non-macro source on an FX destination says so");

    // Engine: macro routes move the FX; zero macro leaves the output bit-exact.
    auto render = [](const Preset& s, int n) {
        Synth y; y.init(44100); y.setParams(s.voice, s.routes); y.setFX(s.fx);
        std::vector<float> L(n), R(n); y.noteOn(48, 0.9f); y.renderPlanar(L.data(), R.data(), n); return L;
    };
    Preset base = factoryPresets()[7];
    base.fx.delay.enabled = true; base.fx.reverb.enabled = true; base.fx.phaser.enabled = true; base.fx.flanger.enabled = true; base.fx.chorus.enabled = true;
    Preset routed = base;
    for (D dd : {D::FxDelayFeedback, D::FxReverbDecay, D::FxPhaserDepth, D::FxFlangerDepth, D::FxChorusDepth}) routed.routes.push_back({S::Macro2, dd, 0.3});
    auto a = render(base, 44100), b = render(routed, 44100);
    bool same = true; for (size_t i = 0; i < a.size(); ++i) if (a[i] != b[i]) same = false;
    check(same, "routes with the macro at 0 leave the sound bit-exact");
    routed.voice.macros[1] = 1.0; base.voice.macros[1] = 1.0;
    a = render(base, 44100); b = render(routed, 44100);
    double diff = 0; for (size_t i = 0; i < a.size(); ++i) diff += std::fabs(a[i] - b[i]);
    check(diff / a.size() > 1e-4, "turning the macro up moves the FX");
    FXChain rc; rc.init(44100); FXParams rp; rp.reverb.decay = 0.5; rc.set(rp);
    FXChain::Mod mod; mod.reverbDecay = 0.3; rc.setMod(mod);
    check(std::fabs(rc.reverb().decay() - 0.8f) < 1e-6, "reverb decay offset adds to the base value");
    rc.set(rp);
    check(std::fabs(rc.reverb().decay() - 0.8f) < 1e-6, "a new FX setting keeps the macro offset");

    printf(g_fail ? "%d FX DETAIL TEST(S) FAILED\n" : "ALL FX DETAIL TESTS PASSED\n", g_fail);
    return g_fail ? 1 : 0;
}
