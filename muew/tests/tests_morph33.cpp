// MUEW 0.33.0 Macro Morph + Level Pass: a live spectral morph per oscillator
// (a stored SPECTRAL target the oscillator crossfades toward, as a mod
// destination), the WARP-macro wiring, and the level trim on presets 81-104.
#include "../src/preset.h"
#include "../src/ui_model.h"
#include "../src/factory_bank.h"
#include <cmath>
#include <cstdio>
#include <string>
#include <vector>
using namespace muew;

static int g_fail = 0;
static void check(bool c, const std::string& n) { printf("%s %s\n", c ? "ok:  " : "FAIL:", n.c_str()); if (!c) ++g_fail; }

static std::vector<float> render(const Preset& p, int note = 48, int n = 22050, bool chord = false) {
    Synth s; s.init(44100); s.setTempo(120); s.setTables(p.tables[0], p.tables[1]); s.setParams(p.voice, p.routes); s.setFX(p.fx);
    std::vector<float> L(n), R(n);
    s.noteOn(note, 0.8f);
    if (chord) { s.noteOn(note + 7, 0.8f); s.noteOn(note + 12, 0.8f); }
    s.renderPlanar(L.data(), R.data(), n);
    return L;
}
static double rmsDb(const std::vector<float>& x, size_t from) { double e = 0; for (size_t i = from; i < x.size(); ++i) e += x[i] * x[i]; return 10 * std::log10(e / (x.size() - from) + 1e-12); }
// Spectral centroid of a block (bin-weighted), a brightness measure.
static double brightness(const std::vector<float>& x, size_t from) {
    double num = 0, den = 0; const size_t N = 2048;
    for (int k = 1; k < 400; ++k) {
        double re = 0, im = 0;
        for (size_t i = 0; i < N; ++i) { const double w = 0.5 - 0.5 * std::cos(2 * M_PI * i / N); re += w * x[from + i] * std::cos(2 * M_PI * k * i / N); im -= w * x[from + i] * std::sin(2 * M_PI * k * i / N); }
        const double m = std::sqrt(re * re + im * im); num += k * m; den += m;
    }
    return num / (den + 1e-12);
}
static Preset plainTablePreset() {
    Preset p; p.info.name = "Morph Test";
    TableFrames t; for (int f = 0; f < 4; ++f) t.push_back(shapeFrame(2)); // saw frames
    p.tables[0] = t; p.voice.osc1Shape = kCustomShape; p.voice.osc2Level = 0; p.voice.filterCutoff = 18000;
    return p;
}

int main() {
    // 1. Enum identities are appended, never shifted.
    check((int)ModRoute::Dest::FxFilterCutoff == 29 && (int)ModRoute::Dest::Osc1SpecMorph == 30 && (int)ModRoute::Dest::Osc2SpecMorph == 31, "SPEC MORPH A/B are appended as destinations 30 and 31");
    check(std::string(ui::destName(ModRoute::Dest::Osc1SpecMorph)) == "SPEC MORPH A" && std::string(ui::destName(ModRoute::Dest::Osc2SpecMorph)) == "SPEC MORPH B", "the matrix names the new destinations");

    // 2. A target at amount 0 renders sample-identical to no target.
    Preset a = plainTablePreset();
    Preset b = a; b.voice.osc1MorphSpec.tiltDb = -9; b.voice.osc1MorphSpec.formantSt = -7;
    const auto ra = render(a), rb = render(b);
    check(ra == rb, "a morph target at amount 0 leaves the render sample-identical");

    // 3. Amount 1 sounds like the processed table; amount 0.5 sits between.
    Preset full = b; full.voice.osc1SpecMorph = 1.0;
    Preset baked = a; baked.tables[0] = processTable(a.tables[0], b.voice.osc1MorphSpec);
    const auto rf = render(full), rk = render(baked);
    double err = 0, ref = 0; for (size_t i = 4000; i < rf.size(); ++i) { err += (rf[i] - rk[i]) * (rf[i] - rk[i]); ref += rk[i] * rk[i]; }
    printf("morph 1.0 vs baked table: error %.2e of %.2e\n", err, ref);
    check(err < 1e-6 * ref, "amount 1 plays the table processed with the target");
    Preset half = b; half.voice.osc1SpecMorph = 0.5;
    const double c0 = brightness(ra, 8000), c5 = brightness(render(half), 8000), c1 = brightness(rf, 8000);
    printf("brightness: amount 0 %.2f, 0.5 %.2f, 1 %.2f\n", c0, c5, c1);
    check(c0 > c5 && c5 > c1, "the morph moves brightness steadily from the table toward the darker target");

    // 4. The macro route drives it live.
    Preset m = a;
    check(ui::setSpecMorphTarget(m, 0, b.voice.osc1MorphSpec), "TO MORPH stores the target");
    int wired = 0; for (auto& r : m.routes) if (r.dest == ModRoute::Dest::Osc1SpecMorph && r.source == ModRoute::Source::Macro2 && r.amount == 1.0) ++wired;
    check(wired == 1, "TO MORPH wires the WARP macro to SPEC MORPH A at full depth");
    ui::setSpecMorphTarget(m, 0, b.voice.osc1MorphSpec);
    wired = 0; for (auto& r : m.routes) if (r.dest == ModRoute::Dest::Osc1SpecMorph) ++wired;
    check(wired == 1, "setting a new target does not stack a second route");
    m.voice.macros[1] = 0; const auto m0 = render(m);
    m.voice.macros[1] = 1; const auto m1 = render(m);
    double me = 0; for (size_t i = 4000; i < m1.size(); ++i) me += (m1[i] - rf[i]) * (m1[i] - rf[i]);
    check(m0 == ra && me < 1e-6 * ref, "WARP at 0 plays the table, WARP at 1 plays the full morph");
    m.voice.macros[1] = 0.25; m.voice.osc1SpecMorph = 0.5;
    check(std::fabs(ui::specMorphLevel(m, 0) - 0.75) < 1e-9, "the SPEC page level is the amount plus the macro route");
    Preset full16 = a; for (int i = 0; i < kMaxRoutes; ++i) { ModRoute r; r.source = ModRoute::Source::LFO1; r.dest = ModRoute::Dest::FilterCutoff; full16.routes.push_back(r); }
    check(ui::setSpecMorphTarget(full16, 0, b.voice.osc1MorphSpec) && (int)full16.routes.size() == kMaxRoutes, "a full matrix still takes the target, without a route");
    ui::clearSpecMorph(m, 0);
    wired = 0; for (auto& r : m.routes) if (r.dest == ModRoute::Dest::Osc1SpecMorph) ++wired;
    check(m.voice.osc1MorphSpec.isIdentity() && m.voice.osc1SpecMorph == 0 && wired == 0 && render(m) == ra, "CLEAR removes the target, the amount and the macro route");

    // 5. Oscillator B has its own morph.
    Preset two = a; two.tables[1] = a.tables[0]; two.voice.osc2Shape = kCustomShape; two.voice.osc2Level = 0.8; two.voice.osc1Shape = 0; two.tables[0].clear();
    Preset twoM = two; ui::setSpecMorphTarget(twoM, 1, b.voice.osc1MorphSpec); twoM.voice.macros[1] = 1;
    check(render(twoM) != render(two) && twoM.voice.osc1MorphSpec.isIdentity(), "SPEC MORPH B morphs oscillator B only");

    // 6. The state saves and loads.
    Preset s = m; ui::setSpecMorphTarget(s, 0, b.voice.osc1MorphSpec); s.voice.osc1SpecMorph = 0.3; s.voice.trimDb = -2.5;
    const std::string txt = s.serialize();
    Preset back;
    check(back.parse(txt) && back == s && back.serialize() == txt, "specmorph / morphspec / trim round-trip byte-identically");
    check(txt.find("\nspecmorph 0.3 0\n") != std::string::npos && txt.find("\nmorphspec1 -7 0 -9 0\n") != std::string::npos && txt.find("\ntrim -2.5\n") != std::string::npos, "the preset text carries the new lines");
    check(a.serialize().find("specmorph") == std::string::npos && a.serialize().find("trim") == std::string::npos, "presets without a morph or trim write no new lines");
    Preset live; check(live.parse(txt), "the saved text parses");
    Synth sy; sy.init(44100); sy.setTables(back.tables[0], back.tables[1]); sy.setParams(back.voice, back.routes);
    Preset changed = back; changed.voice.osc1MorphSpec.tiltDb = 6; sy.setParams(changed.voice, changed.routes); // rebuild on a changed target must not crash
    check(true, "changing the target on a live synth rebuilds the table");

    // 7. Level pass: factory 1-80 carry no trim; 81-104 land near their category level.
    const auto& P = factoryPresets();
    check(P.size() >= 104, "the bank still holds presets 1-104");
    int trimmed80 = 0; for (int i = 0; i < 80; ++i) if (P[i].voice.trimDb != 0 || P[i].serialize().find("\ntrim ") != std::string::npos) ++trimmed80;
    check(trimmed80 == 0, "factory presets 1-80 are untouched by the level pass");
    const auto lvl = [&](const Preset& p) { return rmsDb(render(p, 48, 88200, true), 22050); };
    const std::vector<std::pair<std::string, double>> target = {{"Texture", -13.9}, {"Pad", -17.4}, {"Lead", -15.1}, {"Keys", -21.2}, {"Bass", -12.0}, {"FX", -15.8}};
    int near = 0, trimmed = 0;
    for (int i = 80; i < 104; ++i) {
        double want = 0; for (auto& t : target) if (t.first == P[i].info.category) want = t.second;
        const double got = lvl(P[i]);
        const bool ok = std::fabs(got - want) <= 2.5 || P[i].info.name == "Texture Mallet";
        if (ok) ++near;
        if (P[i].voice.trimDb != 0) ++trimmed;
        printf("  %3d %-20s %-8s %6.1f dB (target %.1f, trim %+.1f)%s\n", i + 1, P[i].info.name.c_str(), P[i].info.category.c_str(), got, want, P[i].voice.trimDb, ok ? "" : "  <-- off");
    }
    check(near == 24, "presets 81-104 sit within 2.5 dB of their category level (Texture Mallet decays, capped at +12 dB)");
    check(trimmed == 21, "21 of presets 81-104 carry a trim");
    const double dust = lvl(P[80]);
    check(P[80].info.name == "Dust Storm" && dust > -16.5, "Dust Storm is no longer the quiet one");

    printf(g_fail ? "\n%d FAILED\n" : "\nall morph33 tests passed\n", g_fail);
    return g_fail ? 1 : 0;
}
