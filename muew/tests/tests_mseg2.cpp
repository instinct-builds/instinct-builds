// tests_mseg2.cpp - 0.17.0 MSEG 2, segment curves, loop modes, synced length, editor model.
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

static std::vector<float> render(const Preset& p, int n, int offAt = -1, double bpm = 120) {
    Synth s; s.init(44100); s.setTempo(bpm); s.setParams(p.voice, p.routes); s.setFX(p.fx); s.setTables(p.tables[0], p.tables[1]);
    std::vector<float> L(n), R(n); s.noteOn(48, 0.9f);
    if (offAt < 0) s.renderPlanar(L.data(), R.data(), n);
    else { s.renderPlanar(L.data(), R.data(), offAt); s.noteOff(48); s.renderPlanar(L.data() + offAt, R.data() + offAt, n - offAt); }
    return L;
}
static bool same(const std::vector<float>& a, const std::vector<float>& b) { for (size_t i = 0; i < a.size(); ++i) if (a[i] != b[i]) return false; return true; }
static double dist(const std::vector<float>& a, const std::vector<float>& b) { double d = 0; for (size_t i = 0; i < a.size(); ++i) d += std::fabs(a[i] - b[i]); return d / a.size(); }
// Run an MSEG and return its value at sample n.
static std::vector<double> runMseg(MSEG& m, int n, int releaseAt = -1) {
    std::vector<double> v(n); m.reset();
    for (int i = 0; i < n; ++i) { if (i == releaseAt) m.release(); v[i] = m.process(); }
    return v;
}

int main() {
    check((int)S::MSEG2 == 14 && kModSources == 15, "MSEG 2 is appended as source 14");
    check(ui::matrixSources().size() == 15 && ui::matrixSources()[7] == S::MSEG2 && std::string(ui::sourceBadge(S::MSEG2)) == "MS2"
          && std::string(ui::sourceName(S::MSEG2)) == "MSEG 2", "MSEG 2 badge sits next to MSEG 1");

    // Segment curves.
    MSEG m; m.setSampleRate(1000); m.setRate(1.0);
    m.setPoints({{0, 0}, {1, 1}});
    check(m.valueAt(0.5) == 0.5, "straight segment unchanged");
    m.setPoints({{0, 0, 1.0}, {1, 1}});
    check(std::fabs(m.valueAt(0.5) - 0.0625) < 1e-12, "EXP segment: slow start");
    m.setPoints({{0, 1, -1.0}, {1, -1}});
    check(std::fabs(m.valueAt(0.5) - (1 - 2 * 0.9375)) < 1e-12, "LOG falling segment: fast start");

    // Loop modes.
    m.setPoints({{0, 0}, {0.25, 1}, {0.5, -1}, {1, 0}});
    m.setLoop(1, 2, true); m.setFreeLoop(false);
    auto sus = runMseg(m, 3000, 1000);
    m.setFreeLoop(true);
    auto fr = runMseg(m, 3000, 1000);
    check(sus[2999] == 0.0f && fr[2999] != 0.0f, "SUSTAIN runs out after release, LOOP keeps cycling");
    bool looped = true; for (int i = 600; i < 1000; ++i) if (std::fabs(sus[i] - sus[i - 250]) > 0.02) looped = false;
    check(looped, "loop span 1..2 repeats every 0.25 of the length");

    // Editor model.
    VoiceParams v;
    auto mv = ui::msegView(v, 1);
    int i = ui::msegInsert(mv, 0.3, 0.5);
    check(i == 2 && v.mseg2Points.size() == 5 && v.mseg2Points[2].time == 0.3, "insert lands in time order");
    check(ui::msegInsert(mv, 0.0, 0.1) == -1 && ui::msegInsert(mv, 0.3, 0.1) == -1, "no insert on the ends or an existing time");
    ui::msegSetLoop(mv, 0, 2); ui::msegSetLoop(mv, 1, 3);
    check(v.mseg2LoopStart == 2 && v.mseg2LoopEnd == 3, "loop edges set by point index");
    ui::msegInsert(mv, 0.1, 0.0);
    check(v.mseg2LoopStart == 3 && v.mseg2LoopEnd == 4, "insert before the loop shifts both edges");
    ui::msegDelete(mv, 3);
    check(v.mseg2LoopStart == 3 && mv.loopEndIndex() == 3 + 1 && v.mseg2Points.size() == 5, "deleting a loop point keeps start < end");
    check(!ui::msegDelete(mv, 0) && !ui::msegDelete(mv, (int)v.mseg2Points.size() - 1), "end points can't be deleted");
    ui::msegMove(mv, 1, 0.99, 3.0);
    check(v.mseg2Points[1].value == 1.0 && v.mseg2Points[1].time < v.mseg2Points[2].time, "move clamps value and stays between neighbours");
    ui::msegMove(mv, 0, 0.5, -0.4);
    check(v.mseg2Points[0].time == 0.0 && v.mseg2Points[0].value == -0.4, "first point keeps time 0");
    check(ui::msegSnap(0.3, 2) == 0.25 && ui::msegSnap(0.3, 0) == 0.3, "grid snap");
    mv.setMode(2); check(v.mseg2Mode == 2 && mv.mode() == 2, "MSEG 2 mode");
    auto m1 = ui::msegView(v, 0); m1.setMode(1);
    check(v.mseg1Loop && !v.mseg1FreeLoop && m1.mode() == 1, "MSEG 1 SUSTAIN = its original loop flag");
    v.mseg2Sync = 3; check(ui::msegLengthReadout(mv) == "1/4", "synced length readout");

    // Serialization.
    bool clean = true;
    for (const auto& p : factoryPresets()) { auto t = p.serialize(); if (t.find("\nmseg2 ") != std::string::npos || t.find("\nmsegx") != std::string::npos || t.find("\nmsegcurve") != std::string::npos) clean = false; }
    check(clean, "factory sounds write no MSEG editor lines");
    Preset p = factoryPresets()[7];
    p.voice.mseg2Points = {{0, 0, 0.5}, {0.2, 1, -0.3}, {0.6, 0.2}, {1, 0}};
    p.voice.mseg2Mode = 2; p.voice.mseg2Sync = 4; p.voice.mseg2LoopStart = 0; p.voice.mseg2LoopEnd = 2; p.voice.mseg2Seconds = 0.5;
    p.voice.mseg1Points[1].curve = 0.7; p.voice.mseg1Sync = 3; p.voice.mseg1FreeLoop = true; p.voice.mseg1Loop = true;
    p.routes.push_back({S::MSEG2, D::FilterCutoff, 2.0});
    std::string t = p.serialize(); Preset q;
    check(q.parse(t) && q == p && q.serialize() == t, "MSEG 2, curves, sync and loop round-trip");
    Preset d2 = p; d2.voice.mseg2Points[2].curve = 0.1;
    check(!(d2 == p), "segment curve is part of equality");
    Preset bad; bad.parse(factoryPresets()[7].serialize() + "mseg2 99 40 9 -4 70 3 0 0 0 0.5 5 9 1 0 0\nmsegcurve 2 0.5 0.5\n");
    check(bad.voice.mseg2Seconds == 8.0 && bad.voice.mseg2Sync == kSyncCount - 1 && bad.voice.mseg2Mode == 2 && bad.voice.mseg2LoopStart == 0
          && bad.voice.mseg2Points[1].value == 1 && bad.voice.mseg2Points[1].curve == 1 && bad.voice.mseg1Points[0].curve == 0,
          "out-of-range MSEG values clamp; a curve-count mismatch is ignored");
    Preset trunc; trunc.parse(factoryPresets()[7].serialize() + "mseg2 1 0 1 1 -1 4 0 0 0 0.5\n");
    check(trunc.voice.mseg2Mode == 0 && trunc.voice.mseg2Points.size() == 4, "a truncated mseg2 line keeps the defaults");

    // Engine.
    Preset base = factoryPresets()[2];
    base.routes.clear(); base.voice.filterCutoff = 500; base.voice.filterReso = 2.0;
    auto a = render(base, 22050);
    Preset shaped = base; shaped.voice.mseg2Points = {{0, 1}, {1, -1}}; shaped.voice.mseg2Mode = 2; // no route
    check(same(render(shaped, 22050), a), "MSEG 2 without a route leaves the sound bit-exact");
    Preset r2 = shaped; r2.routes.push_back({S::MSEG2, D::FilterCutoff, 2.0});
    auto b = render(r2, 22050);
    check(dist(a, b) > 1e-3, "MSEG 2 -> cutoff changes the sound");
    Preset curved = r2; curved.voice.mseg2Points[0].curve = 0.9;
    check(dist(render(curved, 22050), b) > 1e-4, "a segment curve changes the sweep");
    Preset aux = base; aux.routes = {{S::LFO1, D::FilterCutoff, 2.0}}; aux.routes[0].aux = (int)S::MSEG2;
    aux.voice.mseg2Points = {{0, -1}, {1, -1}}; // bipolar -1 = aux level 0
    Preset noRoute = base; noRoute.routes = {{S::LFO1, D::FilterCutoff, 0.0}};
    check(same(render(aux, 22050), render(noRoute, 22050)), "MSEG 2 aux at -1 (level 0) mutes its route");
    Preset sy = r2; sy.voice.mseg2Sync = 3; sy.voice.mseg2Mode = 0;
    Preset sec = r2; sec.voice.mseg2Seconds = 0.5; sec.voice.mseg2Mode = 0;
    check(same(render(sy, 22050, -1, 120), render(sec, 22050, -1, 120)), "1/4 sync at 120 BPM = 0.5 s length");
    Preset one = r2; one.voice.mseg2Mode = 0; one.voice.mseg2LoopStart = 0; Preset lp = one; lp.voice.mseg2Mode = 2;
    check(dist(render(one, 44100 * 2), render(lp, 44100 * 2)) > 1e-4, "LOOP differs from ONE-SHOT after the first cycle");
    Preset legacy = base; legacy.voice.mseg1Loop = true; legacy.routes = {{S::MSEG1, D::FilterCutoff, 2.0}};
    Preset legacyX = legacy; legacyX.voice.mseg1LoopStart = 1; legacyX.voice.mseg1LoopEnd = (int)legacy.voice.mseg1Points.size() - 1;
    check(same(render(legacy, 44100, 22050), render(legacyX, 44100, 22050)), "MSEG 1 loop defaults match the old point 1..last loop");

    printf(g_fail ? "%d MSEG TEST(S) FAILED\n" : "ALL MSEG TESTS PASSED\n", g_fail);
    return g_fail ? 1 : 0;
}
