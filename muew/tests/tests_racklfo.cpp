// tests_racklfo.cpp - 0.15.0 rack LFOs: two global LFOs as matrix sources
// for the FX destinations; saved with the sound; factory sounds untouched.
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

static std::vector<float> render(const Preset& p, int n, double bpm = 120) {
    Synth s; s.init(44100); s.setTempo(bpm); s.setParams(p.voice, p.routes); s.setFX(p.fx); s.setTables(p.tables[0], p.tables[1]);
    std::vector<float> L(n), R(n); s.noteOn(48, 0.9f); s.renderPlanar(L.data(), R.data(), n); return L;
}

int main() {
    check((int)S::FxLfo1 == 12 && (int)S::FxLfo2 == 13, "rack LFO sources are appended (12, 13)");
    check(ui::matrixSources().size() == 15 && std::string(ui::sourceBadge(S::FxLfo1)) == "FXL1" && std::string(ui::sourceName(S::FxLfo2)) == "FX LFO 2",
          "both rack LFOs are in the source badges");

    // Readouts: where a route does something.
    check(ui::routeAmountReadout({S::FxLfo1, D::FxFlangerDepth, 0.5}) == "+50%", "rack LFO -> FX destination shows its amount");
    check(ui::routeAmountReadout({S::FxLfo1, D::FilterCutoff, 1.0}) == "FX DESTS ONLY", "rack LFO -> voice destination says FX only");
    check(ui::routeAmountReadout({S::LFO2, D::FxDelayFeedback, 0.5}) == "GLOBAL ONLY", "voice LFO -> FX destination says global only");
    check(ui::fxUnitDest(FxFlanger) == (int)D::FxFlangerDepth && ui::fxUnitDest(FxComp) == -1, "rack cards know their drop destination");

    DelayParams dl; dl.timeLSec = 0.3; dl.timeRSec = 0.45;
    check(ui::delayCardReadout(dl) == "300 / 450 ms", "free DELAY card shows ms");
    dl.syncL = 3; dl.syncR = 5;
    check(ui::delayCardReadout(dl) == std::string(ui::syncName(3)) + " / " + ui::syncName(5), "synced DELAY card shows note divisions");
    dl.syncR = 0;
    check(ui::delayCardReadout(dl) == std::string(ui::syncName(3)) + " / 450ms", "mixed DELAY card shows each side");

    // Serialization.
    bool clean = true;
    for (const auto& p : factoryPresets()) if (p.serialize().find("\nfxlfo") != std::string::npos) clean = false;
    check(clean, "factory sounds write no fxlfo line");
    Preset p = factoryPresets()[7];
    p.fx.lfo[0] = RackLfoParams{3.5, 1, 0}; p.fx.lfo[1] = RackLfoParams{0.5, 3, 5};
    p.routes.push_back({S::FxLfo2, D::FxDelayFeedback, 0.3});
    std::string t = p.serialize(); Preset q;
    check(q.parse(t) && q == p && q.serialize() == t && t.find("fxlfo 3.5 1 0 0.5 3 5") != std::string::npos, "rack LFOs and their routes round-trip");
    Preset bad; bad.parse(factoryPresets()[7].serialize() + "fxlfo 99 7 -2 0.001 -1 44\n");
    check(bad.fx.lfo[0].rateHz == 20 && bad.fx.lfo[0].shape == 3 && bad.fx.lfo[0].sync == 0 && bad.fx.lfo[1].rateHz == 0.02 && bad.fx.lfo[1].sync == kSyncCount - 1,
          "out-of-range rack LFO values clamp");
    Preset trunc; trunc.parse(factoryPresets()[7].serialize() + "fxlfo 2 1\n");
    check(trunc.fx.lfo[0] == RackLfoParams{} && trunc.fx.lfo[1] == RackLfoParams{}, "a truncated fxlfo line keeps the defaults");

    // Engine: byte-identical without routes; LFO route moves the flanger over time.
    Preset base = factoryPresets()[2]; // Init Saw
    base.fx.flanger = FlangerParams{true, 0.25, 0.1, 0.6, 0.5};
    Preset lfoOnly = base; lfoOnly.fx.lfo[0] = RackLfoParams{4, 2, 0};   // LFO settings alone change nothing
    auto a = render(base, 44100), b = render(lfoOnly, 44100);
    bool same = true; for (size_t i = 0; i < a.size(); ++i) if (a[i] != b[i]) same = false;
    check(same, "rack LFO settings without a route leave the sound bit-exact");
    Preset voiceLfo = base; voiceLfo.routes.push_back({S::FxLfo1, D::FilterCutoff, 2.0}); // ignored by the voices
    auto c = render(voiceLfo, 44100);
    same = true; for (size_t i = 0; i < a.size(); ++i) if (a[i] != c[i]) same = false;
    check(same, "a rack LFO routed to a voice destination changes nothing");
    Preset routed = base; routed.fx.lfo[0] = RackLfoParams{2, 0, 0}; routed.routes.push_back({S::FxLfo1, D::FxFlangerDepth, 0.8});
    auto d = render(routed, 44100);
    double diff = 0; for (size_t i = 0; i < a.size(); ++i) diff += std::fabs(a[i] - d[i]);
    check(diff / a.size() > 1e-3, "FX LFO 1 -> FL DEPTH changes the sound");

    // The LFO itself: shapes, sync, block modulation.
    check(std::fabs(rackLfoValue(0, 0.25) - 1) < 1e-12 && rackLfoValue(1, 0.5) == 1 && rackLfoValue(2, 0.0) == -1 && rackLfoValue(3, 0.75) == -1,
          "sine / triangle / saw / square values");
    FXChain ch; ch.init(44100); FXParams fp; fp.lfo[1].sync = 3; ch.set(fp); ch.setTempo(90);
    check(std::fabs(ch.rackLfoHz(1) - 1.5) < 1e-12, "1/4 sync at 90 BPM cycles at 1.5 Hz");
    fp.lfo[0] = RackLfoParams{1.0, 3, 0}; fp.reverb.decay = 0.5; ch.set(fp);
    ch.setLfoRoutes(FXChain::Mod{}, {{0, FXChain::kRevDecay, 0.2}});
    double lo = 1, hi = 0;
    for (int i = 0; i < 44100; ++i) { float l = 0, r = 0; ch.process(l, r); lo = std::min(lo, (double)ch.reverb().decay()); hi = std::max(hi, (double)ch.reverb().decay()); }
    check(std::fabs(hi - 0.7) < 1e-6 && std::fabs(lo - 0.3) < 1e-6, "a square FX LFO swings reverb decay 0.5 +/- 0.2");
    ch.setLfoRoutes(FXChain::Mod{}, {});
    check(std::fabs(ch.reverb().decay() - 0.5) < 1e-6, "removing the route restores the static value");

    printf(g_fail ? "%d RACK LFO TEST(S) FAILED\n" : "ALL RACK LFO TESTS PASSED\n", g_fail);
    return g_fail ? 1 : 0;
}
