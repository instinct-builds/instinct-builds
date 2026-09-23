// tests_unison_fx.cpp - 0.7.0: unison stacks (stereo spread, loudness,
// detune, width), the new FX rack stages (distortion, EQ, compressor), the
// macro -> drive route, preset round trips of the new fields, and the new
// factory sounds.
#include "../src/au_params.h"
#include "../src/ui_model.h"
#include <cmath>
#include <cstdio>
#include <vector>

using namespace muew;

static int g_fail = 0;
static void check(bool c, const char* name) {
    if (c) printf("ok:   %s\n", name);
    else { printf("FAIL: %s\n", name); ++g_fail; }
}

struct Out { std::vector<float> l, r; };
static Out render(const VoiceParams& v, const std::vector<ModRoute>& routes, const FXParams& fx, int note = 48,
                  int frames = 22050) {
    Synth s(4); s.init(44100); s.setParams(v, routes); s.setFX(fx);
    s.noteOn(note, 0.9f);
    Out o; o.l.resize(frames); o.r.resize(frames);
    s.renderPlanar(o.l.data(), o.r.data(), frames);
    return o;
}
static double rms(const std::vector<float>& x, size_t from = 2205) {
    double s = 0; for (size_t i = from; i < x.size(); ++i) s += x[i] * x[i];
    return std::sqrt(s / (x.size() - from));
}
static double corr(const Out& o) {
    double a = 0, b = 0, c = 0;
    for (size_t i = 2205; i < o.l.size(); ++i) { a += o.l[i] * o.l[i]; b += o.r[i] * o.r[i]; c += o.l[i] * o.r[i]; }
    return c / std::sqrt(a * b + 1e-30);
}
static double peak(const std::vector<float>& x) { double p = 0; for (float v : x) p = std::max(p, (double)std::fabs(v)); return p; }

static void fxRun(FXParams fx, std::vector<float>& l, std::vector<float>& r) {
    FXChain c; c.init(44100); c.set(fx);
    for (size_t i = 0; i < l.size(); ++i) c.process(l[i], r[i]);
}
static std::vector<float> sine(double hz, double amp, int n = 44100) {
    std::vector<float> v(n); for (int i = 0; i < n; ++i) v[i] = (float)(amp * std::sin(2 * M_PI * hz * i / 44100.0)); return v;
}

int main() {
    VoiceParams v; v.osc1Shape = 2; v.osc2Level = 0.0; v.filterCutoff = 12000; v.ampA = 0.001; v.ampS = 1.0;
    std::vector<ModRoute> none;
    FXParams dry;

    // --- unison
    Out mono = render(v, none, dry);
    check(corr(mono) > 0.99999 && mono.l == mono.r, "one voice per oscillator is mono (classic path)");
    VoiceParams u = v; u.osc1Unison = 7; u.osc1UniDetune = 0.3; u.uniWidth = 1.0;
    Out stack = render(u, none, dry);
    printf("      7-voice stack: corr %.3f, rms %.3f vs single %.3f\n", corr(stack), rms(stack.l), rms(mono.l));
    check(corr(stack) < 0.9, "a 7-voice stack at full width is stereo");
    check(rms(stack.l) > rms(mono.l) * 0.5 && rms(stack.l) < rms(mono.l) * 2.0, "stack loudness stays close to one oscillator");
    VoiceParams narrow = u; narrow.uniWidth = 0.0;
    Out n0 = render(narrow, none, dry);
    check(n0.l == n0.r, "width 0 collapses the stack to mono");
    VoiceParams tight = u; tight.osc1UniDetune = 0.0; tight.uniWidth = 0.0;
    Out t0 = render(tight, none, dry);
    check(rms(t0.l) > 0.0 && t0.l != n0.l, "detune changes the stack");
    // Detune modulation and width modulation are live destinations.
    std::vector<ModRoute> spread{{ModRoute::Source::Macro4, ModRoute::Dest::Osc1Unison, 0.5},
                                 {ModRoute::Source::Macro4, ModRoute::Dest::UnisonWidth, -1.0}};
    VoiceParams m = u; Out m0 = render(m, spread, dry);
    m.macros[3] = 1.0; Out m1 = render(m, spread, dry);
    check(m0.l == stack.l, "unison routes add nothing with the macro at 0");
    check(m1.l == m1.r, "a macro can modulate width down to mono");
    VoiceParams bad = u; bad.osc1Unison = 99; bad.osc2Unison = -3;
    Out b = render(bad, none, dry);
    check(std::isfinite(rms(b.l)) && peak(b.l) < 1.0, "out-of-range voice counts are clamped");
    check(ui::unisonReadout(u, 0) == "7 VOICES" && ui::unisonReadout(v, 1) == "1 VOICE", "unison readout text");
    auto offs = ui::unisonOffsets(u, 0);
    check(offs.size() == 7 && std::fabs(offs.front() + 0.3) < 1e-12 && std::fabs(offs[3]) < 1e-12, "unison display offsets are symmetric");

    // --- FX rack
    {
        auto l = sine(220, 0.5), r = l, l0 = l, r0 = r;
        FXParams off; off.dist.drive = 0.9; off.eq.lowDb = 12; off.comp.amount = 1.0; // settings, but all disabled
        fxRun(off, l, r);
        check(l == l0 && r == r0, "disabled distortion/EQ/compressor pass audio untouched");
    }
    for (int mode = 0; mode < 3; ++mode) {
        auto l = sine(220, 0.8), r = l, l0 = l;
        FXParams f; f.dist.enabled = true; f.dist.mode = mode; f.dist.drive = 0.7;
        fxRun(f, l, r);
        double diff = 0; for (size_t i = 0; i < l.size(); ++i) diff += std::fabs(l[i] - l0[i]);
        bool ok = peak(l) <= 1.0 && diff > 100.0;
        printf("      %s: peak %.3f, rms %.3f\n", ui::distModeName(mode), peak(l), rms(l));
        check(ok, mode == 0 ? "soft clip shapes and stays bounded" : mode == 1 ? "fold shapes and stays bounded" : "bitcrush shapes and stays bounded");
    }
    {
        auto l = sine(220, 0.8), r = l; FXParams f; f.dist.enabled = true; f.dist.mode = 2; f.dist.drive = 1.0; fxRun(f, l, r);
        int distinct = 0; std::vector<float> seen;
        for (float x : l) { bool found = false; for (float y : seen) if (y == x) { found = true; break; } if (!found && seen.size() < 64) seen.push_back(x); }
        distinct = (int)seen.size();
        printf("      bitcrush at full drive: %d distinct levels\n", distinct);
        check(distinct <= 16, "bitcrush at full drive quantizes to a few levels");
    }
    {
        auto lo = sine(80, 0.1), hi = sine(9000, 0.1);
        auto lo2 = lo, lr = lo, hi2 = hi, hr = hi;
        FXParams f; f.eq.enabled = true; f.eq.lowDb = 12; f.eq.highDb = -12;
        fxRun(f, lo2, lr); fxRun(f, hi2, hr);
        double gl = 20 * std::log10(rms(lo2, 4410) / rms(lo, 4410)), gh = 20 * std::log10(rms(hi2, 4410) / rms(hi, 4410));
        printf("      EQ: 80 Hz %+.1f dB, 9 kHz %+.1f dB\n", gl, gh);
        check(gl > 9 && gh < -9, "EQ shelves boost lows and cut highs by about 12 dB");
        auto mid = sine(1000, 0.1), m2 = mid, mr = mid; FXParams flat; flat.eq.enabled = true; fxRun(flat, m2, mr);
        double dmax = 0; for (size_t i = 0; i < mid.size(); ++i) dmax = std::max(dmax, (double)std::fabs(m2[i] - mid[i]));
        check(dmax < 1e-5, "a flat EQ is transparent");
    }
    {
        // Loud then quiet: the compressor narrows the level difference.
        std::vector<float> l(44100);
        for (int i = 0; i < 44100; ++i) l[i] = (float)((i < 22050 ? 0.9 : 0.1) * std::sin(2 * M_PI * 200 * i / 44100.0));
        auto r = l, c = l, cr = l;
        FXParams f; f.comp.enabled = true; f.comp.amount = 0.8; fxRun(f, c, cr);
        auto seg = [](const std::vector<float>& x, int a, int b) { double s = 0; for (int i = a; i < b; ++i) s += x[i] * x[i]; return std::sqrt(s / (b - a)); };
        double before = seg(l, 8000, 22000) / seg(l, 30000, 44000), after = seg(c, 8000, 22000) / seg(c, 30000, 44000);
        printf("      compressor: loud/quiet ratio %.2f -> %.2f\n", before, after);
        check(after < before * 0.6, "compressor reduces dynamic range");
        check(peak(c) < 1.5 && c == cr, "compressor is stereo-linked and bounded");
    }
    {
        // Macro -> drive (FX are global, so the synth applies macro routes to the rack).
        VoiceParams dv = v; FXParams f; f.dist.enabled = true; f.dist.mode = 0; f.dist.drive = 0.0;
        std::vector<ModRoute> r{{ModRoute::Source::Macro2, ModRoute::Dest::DistDrive, 1.0}};
        Out d0 = render(dv, r, f); dv.macros[1] = 1.0; Out d1 = render(dv, r, f);
        check(d0.l != d1.l, "a macro drives the distortion");
    }

    // --- presets
    {
        Preset p = factoryPresets()[0];
        p.voice.osc1Unison = 6; p.voice.osc2Unison = 3; p.voice.osc1UniDetune = 0.41; p.voice.uniWidth = 0.33; p.voice.uniBlend = 0.2;
        p.fx.dist = {true, 1, 0.66, 0.5}; p.fx.eq = {true, -3, 4.5, 2}; p.fx.comp = {true, 0.72};
        Preset q; check(q.parse(p.serialize()) && q == p, "unison and new FX survive a preset round trip");
        Preset plain = factoryPresets()[7];
        std::string text = plain.serialize();
        check(text.find("unison") == std::string::npos && text.find("dist ") == std::string::npos
              && text.find("comp ") == std::string::npos, "presets without the new features write no new lines");
        params::set(p, params::UnisonDetuneB, 80); params::set(p, params::DistDrive, 25); params::set(p, params::CompAmount, 10);
        check(std::fabs(p.voice.osc2UniDetune - 0.8) < 1e-12 && std::fabs(p.fx.dist.drive - 0.25) < 1e-12
              && std::fabs(p.fx.comp.amount - 0.1) < 1e-12, "AU params 17, 19, 20 reach the sound");
    }
    int stacks = 0, driven = 0, compressed = 0;
    for (int i = 30; i < kFactoryPresetCount; ++i) {
        const Preset& p = factoryPresets()[i];
        if (p.voice.osc1Unison > 1 || p.voice.osc2Unison > 1) ++stacks;
        if (p.fx.dist.enabled) ++driven;
        if (p.fx.comp.enabled) ++compressed;
        bool bass = p.info.category == "Bass";
        Synth s(8); s.init(44100); s.setParams(p.voice, p.routes); s.setFX(p.fx);
        if (bass) s.noteOn(36, 0.9f); else { s.noteOn(60, 0.85f); s.noteOn(67, 0.8f); }
        std::vector<float> l(44100), r(44100);
        s.renderPlanar(l.data(), r.data(), 44100);
        double pk = std::max(peak(l), peak(r)), level = rms(l);
        bool ok = std::isfinite(level) && level > 0.02 && pk < 1.0;
        char name[96]; snprintf(name, sizeof name, "%s renders (peak %.2f, rms %.3f)", p.info.name.c_str(), pk, level);
        check(ok, name);
    }
    check(kFactoryPresetCount == 38 && factoryPresets()[29].info.name == "Laser Drop", "bank appended: 38 presets, 0-29 unchanged");
    check(stacks >= 6 && driven >= 4 && compressed >= 6, "new sounds use unison, distortion and compression");

    if (g_fail) { printf("%d UNISON/FX TEST(S) FAILED\n", g_fail); return 1; }
    printf("ALL UNISON/FX TESTS PASSED\n");
    return 0;
}
