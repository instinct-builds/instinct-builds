// MUEW 0.34.0 Morph Lanes: morph drivers (the MORPH row's source chip), SPEC
// MORPH A/B as AU parameters 38/39, and four appended morph presets 105-108.
#include "../src/au_params.h"
#include "../src/ui_model.h"
#include "../src/factory_bank.h"
#include <cmath>
#include <cstdio>
#include <set>
#include <string>
#include <vector>
using namespace muew;

static int g_fail = 0;
static void check(bool c, const std::string& n) { printf("%s %s\n", c ? "ok:  " : "FAIL:", n.c_str()); if (!c) ++g_fail; }
static std::vector<float> render(const Preset& p, int n = 44100) {
    Synth s; s.init(44100); s.setTempo(120); s.setTables(p.tables[0], p.tables[1]); s.setParams(p.voice, p.routes); s.setFX(p.fx);
    std::vector<float> L(n), R(n);
    s.noteOn(48, 0.8f); s.noteOn(55, 0.8f); s.noteOn(60, 0.8f);
    s.renderPlanar(L.data(), R.data(), n);
    return L;
}
static double rel(const std::vector<float>& a, const std::vector<float>& b, size_t from, size_t to) {
    double d = 0, r = 0; for (size_t k = from; k < to; ++k) { d += (a[k] - b[k]) * (a[k] - b[k]); r += b[k] * b[k]; } return d / (r + 1e-12);
}
static double rmsDb(const std::vector<float>& x, size_t from) { double e = 0; for (size_t i = from; i < x.size(); ++i) e += x[i] * x[i]; return 10 * std::log10(e / (x.size() - from) + 1e-12); }

int main() {
    using S = ModRoute::Source; using D = ModRoute::Dest;
    // 1. AU parameters are appended.
    check(params::Count == 40 && params::SpecMorphA == 38 && params::SpecMorphB == 39, "SPEC MORPH A/B are AU parameters 38 and 39");
    check(std::string(params::def(params::SpecMorphA).name) == "Spec Morph A" && params::def(params::SpecMorphB).unit == params::Percent, "the parameters are named and in percent");
    Preset p = factoryPresets()[0];
    params::set(p, params::SpecMorphA, 40); params::set(p, params::SpecMorphB, 150);
    check(p.voice.osc1SpecMorph == 0.4 && p.voice.osc2SpecMorph == 1.0 && params::get(p, params::SpecMorphB) == 100, "parameters 38/39 write the morph amounts, clamped to 0-100%");
    int zeroDefault = 0; for (int i = 0; i < 104; ++i) if (params::get(factoryPresets()[i], params::SpecMorphA) == 0 && params::get(factoryPresets()[i], params::SpecMorphB) == 0) ++zeroDefault;
    check(zeroDefault == 104 && params::defaultValue(params::SpecMorphA) == 0, "presets 1-104 read 0% on the new parameters");

    // 2. The driver chip steps the managed route.
    Preset m; m.info.name = "Lanes"; TableFrames t; for (int f = 0; f < 4; ++f) t.push_back(shapeFrame(2));
    m.tables[0] = t; m.voice.osc1Shape = kCustomShape; m.voice.osc2Level = 0; m.voice.filterCutoff = 18000;
    SpectralProcess sp; sp.tiltDb = -9; sp.formantSt = -7;
    check(!ui::stepMorphDriver(m, 0, 1), "no target, no driver to step");
    ui::setSpecMorphTarget(m, 0, sp);
    const int ri = ui::morphDriverRoute(m, 0);
    check(ri >= 0 && m.routes[ri].source == S::Macro2 && std::string(ui::morphDriverName(m.routes[ri].source)) == "WARP", "a new target starts on the WARP macro");
    check(ui::stepMorphDriver(m, 0, 1) && m.routes[ri].source == S::LFO1 && m.routes[ri].amount == 0.5 && m.voice.osc1SpecMorph == 0.5, "stepping forward reaches LFO 1 at half depth around a 50% amount");
    m.voice.osc1SpecMorph = 0.3; ui::stepMorphDriver(m, 0, 1);
    check(m.routes[ri].source == S::LFO2 && m.voice.osc1SpecMorph == 0.3, "a set amount is kept when stepping between LFOs");
    ui::stepMorphDriver(m, 0, -1); ui::stepMorphDriver(m, 0, -1);
    check(m.routes[ri].source == S::Macro2 && m.routes[ri].amount == 1.0, "stepping back returns to WARP at full depth");
    ui::stepMorphDriver(m, 0, -1);
    check(m.routes[ri].source == S::ModWheel, "stepping back from WARP wraps to the mod wheel");
    std::set<int> seen; for (int i = 0; i < 10; ++i) { ui::stepMorphDriver(m, 0, 1); seen.insert((int)m.routes[ri].source); }
    check(seen.size() == ui::morphDrivers().size() && seen.count((int)S::MSEG1) && seen.count((int)S::MSEG2) && seen.count((int)S::Env3), "the chip cycles all ten drivers, MSEG 1/2 and ENV 3 included");
    // Other routes to the destination are left alone.
    Preset o = m; ModRoute extra; extra.source = S::Velocity; extra.dest = D::Osc1SpecMorph; extra.amount = 0.2; o.routes.insert(o.routes.begin(), extra);
    const int oi = ui::morphDriverRoute(o, 0); ui::stepMorphDriver(o, 0, 1);
    check(o.routes[0].source == S::Velocity && oi == ri + 1, "the chip manages only its own route, not a velocity route to the same place");
    ui::clearSpecMorph(o, 0);
    check(o.routes.size() == m.routes.size() && o.routes[0].source == S::Velocity, "CLEAR removes the driver route and keeps the velocity route");

    // 3. LFO and MSEG drivers move the sound over time.
    Preset lfo = m; while (lfo.routes[ri].source != S::LFO1) ui::stepMorphDriver(lfo, 0, 1);
    lfo.voice.osc1SpecMorph = 0.5; lfo.voice.lfo1Rate = 2;
    Preset still = lfo; still.routes.erase(still.routes.begin() + ri);
    check(rel(render(lfo), render(still), 4410, 44100) > 0.01, "an LFO-driven morph differs from the fixed 50% morph");

    // 4. Presets 105-108.
    const auto& P = factoryPresets();
    check(P.size() == 108, "the bank has 108 presets");
    const char* names[] = {"Vowel Morph Pad", "Breathing Glass", "Morph Lead", "Formant Growl"};
    const S drivers[] = {S::Macro2, S::LFO1, S::MSEG1, S::ModEnv};
    const std::vector<std::pair<std::string, double>> target = {{"Texture", -13.9}, {"Pad", -17.4}, {"Lead", -15.1}, {"Bass", -12.0}};
    const std::set<std::string> chars = {"dark", "bright", "warm", "clean", "soft", "aggressive", "evolving", "wide"};
    for (int k = 0; k < 4; ++k) {
        const Preset& q = P[104 + k];
        const int di = ui::morphDriverRoute(q, 0);
        bool tagged = false; for (const auto& tg : q.info.tags) if (chars.count(tg)) tagged = true;
        int std8 = 0; for (auto& r : q.routes) if ((int)r.source >= 5 && (int)r.source <= 8 && r.dest != D::Osc1SpecMorph) ++std8;
        Preset rt; const std::string txt = q.serialize();
        check(q.info.name == names[k] && !q.voice.osc1MorphSpec.isIdentity() && di >= 0 && q.routes[di].source == drivers[k] && tagged && q.info.description.size() >= 20 && std8 == 8
              && rt.parse(txt) && rt.serialize() == txt, std::string(names[k]) + ": a morph target, its " + ui::morphDriverName(drivers[k]) + " driver, tags, desc, macros and a stable round trip");
        double want = 0; for (auto& tg : target) if (tg.first == q.info.category) want = tg.second;
        const double got = rmsDb(render(q, 88200), 22050);
        printf("  %d %-16s %-8s %6.1f dB (target %.1f)\n", 105 + k, q.info.name.c_str(), q.info.category.c_str(), got, want);
        check(std::fabs(got - want) <= 2.5, std::string(names[k]) + " sits within 2.5 dB of its category level");
    }
    Preset vm = P[104], vm1 = vm; vm1.voice.macros[1] = 1;
    check(rel(render(vm1), render(vm), 4410, 44100) > 0.05, "Vowel Morph Pad: the WARP macro audibly morphs it");
    Preset fg = P[107], fg0 = fg; fg0.voice.osc1MorphSpec = SpectralProcess{};
    check(rel(render(fg, 8820), render(fg0, 8820), 200, 8820) > 0.01, "Formant Growl: the mod envelope snaps the morph on each note");

    printf(g_fail ? "\n%d FAILED\n" : "\nall lanes34 tests passed\n", g_fail);
    return g_fail ? 1 : 0;
}
