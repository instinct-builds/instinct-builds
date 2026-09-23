// tests_layers.cpp - 0.10.0 sub oscillator, noise and filter 2 (LP/BP/HP,
// comb, formant; serial and parallel), their mod destinations, AU
// parameters and preset round trips.
#include "../src/preset.h"
#include "../src/factory_bank.h"
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
static std::vector<float> render(const Preset& p, int frames = 22050, int note = 57) {
    Synth s(4); s.init(44100); s.setTables(p.tables[0], p.tables[1]); s.setParams(p.voice, p.routes); s.setFX(p.fx);
    s.noteOn(note, 0.9f);
    std::vector<float> l(frames), r(frames);
    s.renderPlanar(l.data(), r.data(), frames);
    return l;
}
static double band(const std::vector<float>& x, double hz) { // DFT magnitude^2 at hz over the steady part
    double re = 0, im = 0;
    for (size_t i = 8000; i < x.size(); ++i) { double ph = 2 * M_PI * hz * i / 44100.0; re += x[i] * std::cos(ph); im += x[i] * std::sin(ph); }
    return re * re + im * im;
}
static double rms(const std::vector<float>& x) { double e = 0; for (size_t i = 8000; i < x.size(); ++i) e += x[i] * x[i]; return std::sqrt(e / (x.size() - 8000)); }
static bool finite(const std::vector<float>& x) { for (float v : x) if (!std::isfinite(v) || std::fabs(v) > 4) return false; return true; }
static double maxDiff(const std::vector<float>& a, const std::vector<float>& b) { double d = 0; for (size_t i = 0; i < a.size(); ++i) d = std::max(d, (double)std::fabs(a[i] - b[i])); return d; }

int main() {
    Preset base = factoryPresets()[0];
    base.routes.clear(); base.fx = FXParams{};
    base.voice.osc1Shape = 0; base.voice.osc2Level = 0; base.voice.filterCutoff = 16000; // a plain sine at A3 (220 Hz)
    base.voice.ampS = 1.0; base.voice.ampA = 0.001;
    const double f0 = 220.0;

    // Sub oscillator: one and two octaves down, three shapes.
    auto dry = render(base);
    Preset sp = base; sp.voice.subLevel = 1.0;
    auto sub1 = render(sp);
    sp.voice.subOctave = 2; auto sub2 = render(sp);
    check(band(sub1, f0 / 2) > 50 * (band(dry, f0 / 2) + 1e-9), "sub level adds a partial one octave below oscillator A");
    check(band(sub2, f0 / 4) > 50 * (band(dry, f0 / 4) + 1e-9), "sub octave 2 lands two octaves below");
    sp.voice.subOctave = 1; sp.voice.subShape = 2; auto subSq = render(sp);
    check(band(subSq, 3 * f0 / 2) > 20 * band(sub1, 3 * f0 / 2), "SQUARE sub has odd harmonics a SINE sub lacks");
    Preset sr = base; sr.routes.push_back({S::Macro1, D::SubLevel, 1.0});
    auto subOff = render(sr); sr.voice.macros[0] = 1.0; auto subMod = render(sr);
    check(maxDiff(subOff, dry) == 0.0 && band(subMod, f0 / 2) > 50 * band(subOff, f0 / 2), "SUB mod destination fades the sub in from 0");

    // Noise: level and tone.
    Preset np = base; np.voice.osc1Shape = 0; np.voice.noiseLevel = 1.0;
    auto white = render(np);
    np.voice.noiseTone = 0.0; auto dark = render(np);
    auto hf = [&](const std::vector<float>& x) { double e = 0; for (double hz = 6000; hz < 12000; hz += 997) e += band(x, hz); return e; };
    printf("      noise rms %.4f dry %.4f hf %.3g vs %.3g\n", rms(white), rms(dry), hf(white), hf(dry));
    check(rms(white) > rms(dry) * 1.05 && hf(white) > 1000 * (hf(dry) + 1e-12), "noise level adds broadband energy");
    check(hf(white) > 20 * hf(dark), "noise TONE 0 is much darker than white");
    check(maxDiff(render(np), dark) == 0.0, "noise is deterministic per note (renders repeat exactly)");

    // Filter 2 on a bright saw.
    Preset fp = base; fp.voice.osc1Shape = 2;
    auto saw = render(fp);
    fp.voice.filter2Type = (int)Filter2Type::Lowpass; fp.voice.filter2Cutoff = 500;
    auto lp = render(fp);
    check(band(lp, 10 * f0) < 0.01 * band(saw, 10 * f0), "filter 2 LOW PASS at 500 Hz removes the 10th harmonic");
    fp.voice.filter2Type = (int)Filter2Type::Highpass; auto hp = render(fp);
    check(band(hp, f0) < 0.05 * band(saw, f0), "filter 2 HIGH PASS removes the fundamental");
    fp.voice.filter2Type = (int)Filter2Type::Comb; fp.voice.filter2Cutoff = 660; fp.voice.filter2Reso = 7.0;
    auto comb = render(fp);
    check(finite(comb) && band(comb, 3 * f0) / band(comb, 2 * f0) > 4 * band(saw, 3 * f0) / band(saw, 2 * f0),
          "COMB tuned to 660 Hz boosts the 3rd harmonic over the 2nd");
    fp.voice.filter2Type = (int)Filter2Type::Formant; fp.voice.filter2Cutoff = 100; auto vA = render(fp);
    fp.voice.filter2Cutoff = 8000; auto vU = render(fp);
    fp.voice.filter2Cutoff = 100 * std::pow(80.0, 0.5); auto vI = render(fp);
    check(finite(vA) && finite(vI) && finite(vU), "FORMANT output stays bounded");
    printf("      formant 880 Hz: U %.3g I %.3g\n", band(vU, 4 * f0), band(vI, 4 * f0));
    check(band(vU, 4 * f0) > 4 * band(vI, 4 * f0), "FORMANT sweeps vowels: U (870 Hz formant) passes 880 Hz, I does not");
    // Serial vs parallel.
    Preset sp2 = base; sp2.voice.osc1Shape = 2; sp2.voice.filterCutoff = 400;
    sp2.voice.filter2Type = (int)Filter2Type::Highpass; sp2.voice.filter2Cutoff = 3000;
    auto ser = render(sp2); sp2.voice.filterRouting = 1; auto par = render(sp2);
    check(rms(par) > 3 * rms(ser), "PARALLEL LP 400 + HP 3k keeps both bands; SERIAL leaves almost nothing");
    Preset fm = base; fm.voice.osc1Shape = 2; fm.voice.filter2Type = 1; fm.voice.filter2Cutoff = 300;
    fm.routes.push_back({S::Macro2, D::Filter2Cutoff, 4.0});
    auto closed = render(fm); fm.voice.macros[1] = 1.0; auto open = render(fm);
    check(band(open, 8 * f0) > 100 * band(closed, 8 * f0), "F2 CUTOFF mod destination opens filter 2 (+4 oct)");
    Preset off = base; off.voice.filter2Cutoff = 300; off.voice.filter2Reso = 5; off.voice.noiseTone = 0.2; off.voice.subOctave = 2;
    check(maxDiff(render(off), dry) == 0.0, "type OFF / level 0 layers leave the sound sample-identical");

    // Presets and AU parameters.
    Preset all = base; all.voice.subLevel = 0.4; all.voice.subOctave = 2; all.voice.subShape = 1; all.voice.noiseLevel = 0.2;
    all.voice.noiseTone = 0.35; all.voice.filter2Type = 5; all.voice.filter2Cutoff = 1234.5; all.voice.filter2Reso = 2.5;
    all.voice.filterRouting = 1; all.routes.push_back({S::LFO3, D::Filter2Cutoff, 1.5});
    Preset back; bool ok = back.parse(all.serialize());
    check(ok && back == all, "sub, noise and filter 2 round-trip through a preset");
    Preset legacy; ok = legacy.parse(base.serialize());
    check(ok && base.serialize().find("filter2") == std::string::npos && legacy.voice.filter2Type == 0, "untouched sounds write no new lines");
    Preset bad; bad.parse("muew-preset 2\nname x\nsub 9 7 9\nnoise -3 5\nfilter2 99 1e9 -4 3\n");
    check(bad.voice.subLevel == 1 && bad.voice.subOctave == 2 && bad.voice.subShape == 2 && bad.voice.noiseLevel == 0
          && bad.voice.filter2Type == 5 && bad.voice.filter2Cutoff == 18000 && bad.voice.filter2Reso == 0.1 && bad.voice.filterRouting == 1,
          "out-of-range values clamp");
    Preset q = base; params::set(q, params::SubLevel, 50); params::set(q, params::Filter2Cutoff, 900); params::set(q, params::NoiseTone, 25);
    check(q.voice.subLevel == 0.5 && q.voice.filter2Cutoff == 900 && q.voice.noiseTone == 0.25 && params::get(q, params::Filter2Reso) == 0.7,
          "AU parameters 23-27 map onto the new fields");
    check(std::string(ui::destName(D::Filter2Cutoff)) == "F2 CUTOFF" && std::string(ui::filter2TypeName(4)) == "COMB"
          && ui::knobPage(ui::Sub) == 1 && ui::knobPage(ui::Cutoff) == 0 && ui::knobPage(ui::WarpA) == -1, "UI names and knob pages");

    if (g_fail) { printf("%d LAYER TEST(S) FAILED\n", g_fail); return 1; }
    printf("ALL LAYER TESTS PASSED\n");
    return 0;
}
