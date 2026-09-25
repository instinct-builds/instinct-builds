// MUEW 0.35.0 Live Morph View: the engine's per-oscillator morph meter that
// the SPEC preview, the MORPH row and the main OSC display follow.
#include "../src/ui_model.h"
#include "../src/factory_bank.h"
#include <cmath>
#include <cstdio>
#include <string>
#include <vector>
using namespace muew;

static int g_fail = 0;
static void check(bool c, const std::string& n) { printf("%s %s\n", c ? "ok:  " : "FAIL:", n.c_str()); if (!c) ++g_fail; }

int main() {
    Preset p; p.info.name = "Live"; TableFrames t; for (int f = 0; f < 4; ++f) t.push_back(shapeFrame(2));
    p.tables[0] = t; p.voice.osc1Shape = kCustomShape; p.voice.osc2Level = 0;
    SpectralProcess sp; sp.tiltDb = -9;
    ui::setSpecMorphTarget(p, 0, sp);
    p.voice.osc1SpecMorph = 0.2; p.voice.macros[1] = 0.5;
    Synth s; s.init(44100); s.setTables(p.tables[0], p.tables[1]); s.setParams(p.voice, p.routes);
    std::vector<float> L(512), R(512);
    check(s.specMorphMeter(0) == -1.0f && s.specMorphMeter(1) == -1.0f, "the meter reads -1 while nothing sounds");
    s.noteOn(48, 0.8f); s.noteOn(55, 0.8f); s.renderPlanar(L.data(), R.data(), 512);
    printf("meter A %.3f, B %.3f\n", s.specMorphMeter(0), s.specMorphMeter(1));
    check(std::fabs(s.specMorphMeter(0) - 0.7f) < 1e-4f, "OSC A meters 70%: 20% amount plus WARP 50%");
    check(s.specMorphMeter(1) == 0.0f, "OSC B, with no morph, meters 0 while voices sound");
    check(std::fabs(ui::specMorphLevel(p, 0) - 0.7) < 1e-9, "the settled level the editor falls back to agrees with the engine");
    // An LFO driver makes the meter move.
    Preset q = p; ui::stepMorphDriver(q, 0, 1); q.voice.lfo1Rate = 4; q.voice.osc1SpecMorph = 0.5;
    Synth s2; s2.init(44100); s2.setTables(q.tables[0], q.tables[1]); s2.setParams(q.voice, q.routes);
    s2.noteOn(60, 0.8f);
    float lo = 2, hi = -2;
    for (int b = 0; b < 100; ++b) { s2.renderPlanar(L.data(), R.data(), 512); const float m = s2.specMorphMeter(0); lo = std::min(lo, m); hi = std::max(hi, m); }
    printf("LFO 1 driver: meter %.3f .. %.3f\n", lo, hi);
    check(lo < 0.15f && hi > 0.85f && lo >= 0.0f && hi <= 1.0f, "an LFO 1 driver sweeps the meter across nearly the whole 0-100% range");
    // Released voices stop metering.
    s.noteOff(48); s.noteOff(55);
    for (int b = 0; b < 400 && s.specMorphMeter(0) >= 0; ++b) s.renderPlanar(L.data(), R.data(), 512);
    check(s.specMorphMeter(0) == -1.0f, "once the release ends the meter returns to -1");
    // Factory sounds: meters report 0 on presets without a morph and render unchanged.
    const Preset& f = factoryPresets()[7];
    Synth s3; s3.init(44100); s3.setTables(f.tables[0], f.tables[1]); s3.setParams(f.voice, f.routes); s3.noteOn(60, 0.8f); s3.renderPlanar(L.data(), R.data(), 512);
    check(s3.specMorphMeter(0) == 0.0f && s3.specMorphMeter(1) == 0.0f, "a factory preset without a morph meters 0");
    printf(g_fail ? "\n%d FAILED\n" : "\nall live35 tests passed\n", g_fail);
    return g_fail ? 1 : 0;
}
