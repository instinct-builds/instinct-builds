// tests_usertable.cpp - 0.9.0 user wavetables: frame math (harmonic
// resampling, harmonic editing, strokes, morph fill), playback through the
// oscillator with WT POS and its mod destinations, preset round trips, and
// WAV import/export.
#include "../src/preset.h"
#include "../src/factory_bank.h"
#include "../src/ui_model.h"
#include <chrono>
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
static Frame sineFrame(int h = 1) { Frame f(kFrameSize); for (int i = 0; i < kFrameSize; ++i) f[i] = (float)std::sin(2 * M_PI * h * i / kFrameSize); return f; }
static std::vector<float> render(const Preset& p, int frames = 22050, int note = 57) {
    Synth s(4); s.init(44100); s.setTables(p.tables[0], p.tables[1]); s.setParams(p.voice, p.routes); s.setFX(p.fx);
    s.noteOn(note, 0.9f);
    std::vector<float> l(frames), r(frames);
    s.renderPlanar(l.data(), r.data(), frames);
    return l;
}
// Share of energy above the fundamental (0 = pure sine), from a DFT of the
// steady part at the known note frequency.
static double brightness(const std::vector<float>& x, double hz) {
    double e1 = 0, eh = 0;
    for (int h = 1; h <= 20; ++h) {
        double re = 0, im = 0;
        for (size_t i = 8000; i < x.size(); ++i) { double ph = 2 * M_PI * hz * h * i / 44100.0; re += x[i] * std::cos(ph); im += x[i] * std::sin(ph); }
        (h == 1 ? e1 : eh) += re * re + im * im;
    }
    return eh / (e1 + eh + 1e-12);
}
static double corr(const std::vector<float>& a, const std::vector<float>& b) {
    double ab = 0, aa = 0, bb = 0;
    for (size_t i = 0; i < a.size() && i < b.size(); ++i) { ab += a[i] * b[i]; aa += a[i] * a[i]; bb += b[i] * b[i]; }
    return ab / std::sqrt(aa * bb + 1e-12);
}

int main() {
    // Frame math.
    auto up = upsampleFrame(sineFrame());
    double err = 0; for (int i = 0; i < Wavetable::kTableSize; ++i) err = std::max(err, std::fabs(up[i] - std::sin(2 * M_PI * i / Wavetable::kTableSize)));
    check(err < 1e-4, "a 256-sample frame upsamples to 2048 without changing its shape");
    Frame f = sineFrame();
    setFrameHarmonic(f, 3, 0.5);
    auto hs = frameHarmonics(f, 8);
    printf("      harmonics after setting H3=0.5: %.3f %.3f %.3f %.3f\n", hs[0], hs[1], hs[2], hs[3]);
    check(std::fabs(hs[0] - 1) < 1e-6 && hs[1] < 1e-6 && std::fabs(hs[2] - 0.5) < 1e-6, "harmonic slider edits one partial");
    Frame s(kFrameSize, 0.0f);
    drawStroke(s, 10, -1, 20, 1);
    check(s[10] == -1 && s[20] == 1 && std::fabs(s[15]) < 1e-6 && s[9] == 0 && s[21] == 0, "freehand stroke fills the gap between mouse points");
    TableFrames t{sineFrame(), Frame(kFrameSize, 0.0f), Frame(kFrameSize, 0.0f), shapeFrame(3)};
    morphFill(t);
    check(std::fabs(t[1][64] - (2.0 / 3 * t[0][64] + 1.0 / 3 * t[3][64])) < 1e-5, "morph fill crossfades between the first and last frames");

    // Playback.
    Preset base = factoryPresets()[0];
    base.routes.clear(); base.fx = FXParams{}; base.voice.osc2Level = 0; base.voice.filterCutoff = 18000; base.voice.filterReso = 0.7;
    base.voice.osc1Shape = 2;
    auto saw = render(base);
    Preset user = base; user.voice.osc1Shape = kCustomShape; user.tables[0] = {shapeFrame(2)};
    auto usaw = render(user);
    printf("      user table of a saw vs built-in saw: correlation %.4f\n", corr(saw, usaw));
    check(corr(saw, usaw) > 0.97, "a user table plays like the shape it was drawn from");
    Preset wt = user; wt.tables[0] = {sineFrame(), shapeFrame(3)};
    Preset p0 = wt, p1 = wt; p1.voice.osc1WtPos = 1.0;
    double b0 = brightness(render(p0), 220), b1 = brightness(render(p1), 220);
    printf("      WT POS 0 brightness %.4f, WT POS 1 brightness %.4f\n", b0, b1);
    check(b0 < 0.01 && b1 > 0.1, "WT POS moves from the sine frame to the square frame");
    Preset lfo = p0; lfo.voice.lfo1Rate = 5; lfo.voice.lfo1Shape = 0; lfo.routes = {{S::LFO1, D::Osc1WtPos, 1.0}};
    check(render(lfo) != render(p0), "LFO -> WT POS A is audible");
    Preset none = base; none.voice.osc1Shape = kCustomShape;
    check(corr(render(none), saw) > 0.97, "USER shape without a table falls back to the saw");
    Preset b = base; b.voice.osc2Level = 0.8; b.voice.osc2Shape = kCustomShape; b.voice.osc2Detune = 0; b.tables[1] = {sineFrame(), shapeFrame(3)};
    Preset b1p = b; b1p.voice.osc2WtPos = 1; b1p.routes = {};
    check(render(b) != render(b1p), "oscillator B has its own table and WT POS");
    Preset uni = wt; uni.voice.osc1Unison = 7; uni.routes = {{S::LFO2, D::Osc1WtPos, 0.8}};
    auto t0 = std::chrono::steady_clock::now();
    { Synth sy(16); sy.init(44100); sy.setTables(uni.tables[0], uni.tables[1]); sy.setParams(uni.voice, uni.routes);
      for (int n = 0; n < 8; ++n) sy.noteOn(48 + n * 3, 0.8f);
      std::vector<float> l(44100), r(44100); sy.renderPlanar(l.data(), r.data(), 44100); }
    double ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
    printf("      8 notes x 7-voice unison on a morphing user table: 1 s of audio in %.0f ms\n", ms);
    check(ms < 1000, "user tables render faster than real time");
    // Existing sounds: setting empty tables changes nothing.
    { const Preset& fp = factoryPresets()[12];
      Synth a(4), c(4); a.init(44100); c.init(44100); a.setParams(fp.voice, fp.routes); c.setTables({}, {}); c.setParams(fp.voice, fp.routes);
      a.setFX(fp.fx); c.setFX(fp.fx); a.noteOn(60, .9f); c.noteOn(60, .9f);
      std::vector<float> l1(8192), r1(8192), l2(8192), r2(8192); a.renderPlanar(l1.data(), r1.data(), 8192); c.renderPlanar(l2.data(), r2.data(), 8192);
      check(l1 == l2 && r1 == r2, "presets without user tables render bit-identical"); }

    // Presets.
    Preset rt = factoryPresets()[5]; rt.voice.osc1Shape = kCustomShape; rt.voice.osc2WtPos = 0.35;
    rt.tables[0] = {sineFrame(), shapeFrame(1), shapeFrame(3)}; rt.tables[1] = {shapeFrame(4)};
    Preset q; check(q.parse(rt.serialize()) && q == rt && q.serialize() == rt.serialize(), "user tables and WT POS survive a preset round trip exactly");
    check(factoryPresets()[7].serialize().find("wt1") == std::string::npos, "presets without user tables write no table lines");
    std::string txt = rt.serialize(); size_t at = txt.find("wt1 3 ");
    std::string cut = txt.substr(0, at) + "wt1 3 0.5 0.25\n" + txt.substr(txt.find('\n', at) + 1);
    Preset dmg; check(dmg.parse(cut) && dmg.tables[0].empty() && dmg.tables[1].size() == 1, "a truncated table line loads as no table");

    // WAV.
    TableFrames three{sineFrame(), shapeFrame(2), shapeFrame(3)};
    auto wav = exportWav(three);
    check(wav.size() == 44 + 3 * 2048 * 4, "export writes one 2048-sample float cycle per frame");
    auto back = importWav(wav);
    double werr = 0;
    for (size_t k = 0; k < back.size() && k < 3; ++k) for (int i = 0; i < kFrameSize; ++i) {
        Frame ref = three[k]; normalizeFrame(ref); werr = std::max(werr, (double)std::fabs(back[k][i] - ref[i])); }
    printf("      WAV round trip: %zu frames, max error %.3f\n", back.size(), werr);
    check(back.size() == 3 && werr < 0.01, "import reads a 2048-per-cycle wavetable back as frames");
    // A 600-sample 16-bit stereo single cycle.
    std::vector<unsigned char> w16;
    auto p32 = [&](uint32_t v) { for (int i = 0; i < 4; ++i) w16.push_back((v >> (8 * i)) & 255); };
    auto p16 = [&](uint16_t v) { w16.push_back(v & 255); w16.push_back(v >> 8); };
    auto tag = [&](const char* s4) { w16.insert(w16.end(), s4, s4 + 4); };
    tag("RIFF"); p32(36 + 600 * 4); tag("WAVE"); tag("fmt "); p32(16); p16(1); p16(2); p32(44100); p32(44100 * 4); p16(4); p16(16); tag("data"); p32(600 * 4);
    for (int i = 0; i < 600; ++i) { int16_t v = (int16_t)(20000 * std::sin(2 * M_PI * i / 600)); p16((uint16_t)v); p16((uint16_t)v); }
    auto single = importWav(w16);
    Frame sref = sineFrame();
    check(single.size() == 1 && corr(single[0], sref) > 0.999,
          "a 16-bit stereo single cycle imports as one frame");
    check(importWav(std::vector<unsigned char>(100, 0)).empty(), "a non-WAV file imports nothing");

    // UI model.
    check(std::string(ui::shapeName(kCustomShape)) == "USER" && std::string(ui::destName(D::Osc2WtPos)) == "WT POS B", "USER shape and WT POS names");

    {
        TableFrames two = {shapeFrame(0), shapeFrame(3)};
        auto w0 = ui::waveformUser(two, 0.0, 0, 0.0, 240), w1 = ui::waveformUser(two, 1.0, 0, 0.0, 240);
        double d = 0, pk = 0; for (int i = 0; i < 240; ++i) { d = std::max(d, (double)std::fabs(w0[i] - w1[i])); pk = std::max(pk, (double)std::fabs(w0[i])); }
        check(pk > 0.5 && d > 0.2, "display preview follows the table position");
    }
    if (g_fail) { printf("%d USER TABLE TEST(S) FAILED\n", g_fail); return 1; }
    printf("ALL USER TABLE TESTS PASSED\n");
    return 0;
}
