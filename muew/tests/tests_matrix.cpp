// tests_matrix.cpp - 0.8.0: LFO 3/4, ENV 3, tempo sync, and the editable
// 16-slot mod matrix model (add/reuse/remove, destination changes keep the
// relative amount, drag-to-assign knob destinations, knob mod rings) plus
// preset round trips of the new fields.
#include "../src/au_params.h"
#include "../src/ui_model.h"
#include <cmath>
#include <cstdio>
#include <vector>

using namespace muew;
using S = ModRoute::Source;
using D = ModRoute::Dest;

static int g_fail = 0;
static void check(bool c, const char* name) {
    if (c) printf("ok:   %s\n", name);
    else { printf("FAIL: %s\n", name); ++g_fail; }
}

static std::vector<float> render(const VoiceParams& v, const std::vector<ModRoute>& routes, double bpm = 120,
                                 int frames = 44100) {
    Synth s(4); s.init(44100); s.setTempo(bpm); s.setParams(v, routes); s.setFX(FXParams{});
    s.noteOn(48, 0.9f);
    std::vector<float> l(frames), r(frames);
    s.renderPlanar(l.data(), r.data(), frames);
    return l;
}
// Envelope of the level in 20 ms windows, to find modulation rates.
static std::vector<double> windows(const std::vector<float>& x, int win = 882) {
    std::vector<double> w;
    for (size_t i = 0; i + win <= x.size(); i += win) { double s = 0; for (int k = 0; k < win; ++k) s += x[i + k] * x[i + k]; w.push_back(std::sqrt(s / win)); }
    return w;
}
static int peaks(const std::vector<double>& w) {
    double mean = 0; for (double v : w) mean += v; mean /= w.size();
    int n = 0; bool above = false;
    for (size_t i = 5; i < w.size(); ++i) { bool a = w[i] > mean; if (a && !above) ++n; above = a; }
    return n;
}

int main() {
    VoiceParams v; v.osc1Shape = 2; v.osc2Level = 0.0; v.filterCutoff = 800; v.ampA = 0.001; v.ampS = 1.0;
    std::vector<ModRoute> none;
    auto base = render(v, none);

    // New sources are silent until routed, and audible once routed.
    VoiceParams v2 = v; v2.lfo3Rate = 7; v2.lfo4Shape = 3; v2.env3A = 0.5;
    check(render(v2, none) == base, "LFO 3/4 and ENV 3 settings change nothing without a route");
    for (S src : {S::LFO3, S::LFO4, S::Env3}) {
        auto out = render(v2, {{src, D::FilterCutoff, 2.0}});
        char name[64]; snprintf(name, sizeof name, "%s -> cutoff is audible", ui::sourceName(src));
        check(out != base, name);
    }
    // Tempo sync: LFO 3 at 1/4 is 2 Hz at 120 BPM and 3 Hz at 180 BPM.
    VoiceParams sy = v; sy.lfo3Shape = 0; sy.lfoSync[2] = 3;
    std::vector<ModRoute> trem{{S::LFO3, D::FilterCutoff, 3.0}};
    int p120 = peaks(windows(render(sy, trem, 120, 88200))), p180 = peaks(windows(render(sy, trem, 180, 88200)));
    printf("      LFO 3 at 1/4: %d cycles in 2 s at 120 BPM, %d at 180 BPM\n", p120, p180);
    check(p120 >= 3 && p120 <= 5 && p180 >= 5 && p180 <= 7, "synced LFO follows the host tempo");
    VoiceParams fr = sy; fr.lfoSync[2] = 0; fr.lfo3Rate = 2.0;
    check(render(fr, trem, 120) == render(fr, trem, 180), "a free-running LFO ignores tempo");
    check(std::fabs(lfoHz(1.0, 4, 120) - 4.0) < 1e-12 && std::fabs(lfoHz(1.0, 6, 90) - 2.25) < 1e-12 && lfoHz(3.3, 0, 140) == 3.3,
          "sync divisions (1/8 at 120 = 4 Hz, 1/4T at 90 = 2.25 Hz, free = Hz)");

    // Matrix model.
    std::vector<ModRoute> r;
    check(ui::addRoute(r, S::LFO3, D::FilterCutoff) == 0 && std::fabs(r[0].amount - 1.25) < 1e-12, "add route with a quarter-scale amount");
    check(ui::addRoute(r, S::LFO3, D::FilterCutoff) == 0 && r.size() == 1, "same source and destination reuses the slot");
    for (int i = 1; i < kMaxRoutes; ++i) ui::addRoute(r, ui::matrixSources()[i % 12], ui::matrixDests()[i % 16]);
    int full = ui::addRoute(r, S::Env3, D::DistDrive);
    check((int)r.size() <= kMaxRoutes && (r.size() < (size_t)kMaxRoutes || full == -1), "matrix holds at most 16 routes");
    ModRoute m{S::LFO1, D::FilterCutoff, 2.5};
    ui::setRouteDest(m, D::Osc1Pitch);
    check(std::fabs(m.amount - 12.0) < 1e-12 && ui::routeAmountReadout(m) == "+12.00 st", "changing destination keeps the relative amount");
    ui::setRouteDisplayAmount(m, -2);
    check(m.amount == -24.0, "amount clamps to full scale");
    size_t before = r.size();
    check(ui::removeRoute(r, 0) && r.size() == before - 1 && !ui::removeRoute(r, 99), "remove route");
    check(ui::knobDest(ui::Cutoff) == (int)D::FilterCutoff && ui::knobDest(ui::Width) == (int)D::UnisonWidth
          && ui::knobDest(ui::Attack) == -1, "knob drop targets");
    std::vector<ModRoute> two{{S::LFO1, D::FilterCutoff, 2.5}, {S::Env3, D::FilterCutoff, -1.25}};
    check(std::fabs(ui::knobModDepth(two, ui::Cutoff) - 0.25) < 1e-12 && ui::knobModDepth(two, ui::WarpA) == 0.0, "knob mod ring depth sums its routes");
    check(ui::matrixSources().size() == 15 && ui::matrixDests().size() == 23, "every source and destination is assignable");
    check(std::string(ui::sourceBadge(S::Env3)) == "ENV3" && std::string(ui::syncName(8)) == "1/4D", "badge and sync names");

    // Presets.
    Preset p = factoryPresets()[3];
    p.voice.lfo3Rate = 3.5; p.voice.lfo4Shape = 2; p.voice.lfoSync[0] = 4; p.voice.lfoSync[3] = 9;
    p.voice.env3A = 0.2; p.voice.env3S = 0.5;
    for (int i = 0; i < 6; ++i) ui::addRoute(p.routes, ui::matrixSources()[i], ui::matrixDests()[i]);
    Preset q; check(q.parse(p.serialize()) && q == p, "LFO 3/4, sync, ENV 3 and 16-slot routes survive a round trip");
    std::string plain = factoryPresets()[7].serialize();
    check(plain.find("lfo34") == std::string::npos && plain.find("sync ") == std::string::npos && plain.find("env3") == std::string::npos,
          "presets without the new modulators write no new lines");
    Preset bad; check(bad.parse("muew-preset 2\nroute 42 2 1\nroute 0 99 1\nroute 11 10 0.5\n") && bad.routes.size() == 1,
                      "routes naming unknown sources or destinations are skipped");

    if (g_fail) { printf("%d MATRIX TEST(S) FAILED\n", g_fail); return 1; }
    printf("ALL MATRIX TESTS PASSED\n");
    return 0;
}
