// MUEW 0.36.0 Morph Everywhere: per-voice morph values the ghost traces, the
// MORPH row ticks and the mod-matrix row meter follow, on both oscillators.
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
    Preset p; p.info.name = "Ghosts"; TableFrames t; for (int f = 0; f < 4; ++f) t.push_back(shapeFrame(2));
    p.tables[0] = t; p.tables[1] = t; p.voice.osc1Shape = kCustomShape; p.voice.osc2Shape = kCustomShape;
    SpectralProcess sp; sp.tiltDb = -9;
    ui::setSpecMorphTarget(p, 0, sp); ui::setSpecMorphTarget(p, 1, sp);
    p.voice.osc1SpecMorph = 0.2; p.voice.osc2SpecMorph = 0.45;
    ModRoute vr; vr.source = ModRoute::Source::Velocity; vr.dest = ModRoute::Dest::Osc1SpecMorph; vr.amount = 0.6;
    p.routes.insert(p.routes.begin(), vr);
    Synth s; s.init(44100); s.setTables(p.tables[0], p.tables[1]); s.setParams(p.voice, p.routes);
    std::vector<float> L(512), R(512);
    float va[8], vb[8];
    check(s.specMorphVoices(0, va, 8) == 0, "no voices report while nothing sounds");
    s.noteOn(48, 0.25f); s.noteOn(55, 0.55f); s.noteOn(60, 0.95f); s.renderPlanar(L.data(), R.data(), 512);
    const int na = s.specMorphVoices(0, va, 8), nb = s.specMorphVoices(1, vb, 8);
    printf("A: %d voices %.3f %.3f %.3f; B: %d voices %.3f\n", na, va[0], va[1], va[2], nb, vb[0]);
    check(na == 3 && nb == 3, "three held voices report on both oscillators");
    check(std::fabs(va[0] - 0.77f) < 1e-3f && std::fabs(va[1] - 0.53f) < 1e-3f && std::fabs(va[2] - 0.35f) < 1e-3f, "OSC A's velocity route spreads the voices: 77, 53, 35%, highest first");
    check(std::fabs(va[0] - s.specMorphMeter(0)) < 1e-6f, "the first entry is the meter the displays show");
    check(std::fabs(vb[0] - 0.45f) < 1e-4f && std::fabs(vb[2] - 0.45f) < 1e-4f, "OSC B, with no per-voice source, holds 45% on every voice");
    float cap[2]; check(s.specMorphVoices(0, cap, 2) == 2 && cap[0] == va[0], "the list respects its size cap");
    for (int i = 0; i < 8; ++i) s.noteOn(62 + i, 0.5f);
    s.renderPlanar(L.data(), R.data(), 512);
    check(s.specMorphVoices(0, va, 8) == 8, "a big chord reports its 8 highest voices");
    // Factory sounds render unchanged and report 0 on every voice.
    const Preset& f = factoryPresets()[7];
    Synth s3; s3.init(44100); s3.setTables(f.tables[0], f.tables[1]); s3.setParams(f.voice, f.routes); s3.noteOn(60, 0.8f); s3.noteOn(64, 0.3f); s3.renderPlanar(L.data(), R.data(), 512);
    const int nf = s3.specMorphVoices(0, va, 8);
    check(nf == 2 && va[0] == 0.0f && va[1] == 0.0f, "a factory preset without a morph reports 0 per voice");
    printf(g_fail ? "\n%d FAILED\n" : "\nall live36 tests passed\n", g_fail);
    return g_fail ? 1 : 0;
}
