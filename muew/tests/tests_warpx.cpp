// tests_warpx.cpp - 0.19.0 second warp slot, FM B / AM B / WINDOW / REMAP warps, appended destinations.
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
static std::vector<float> render(const Preset& p, int n) {
    Synth s; s.init(44100); s.setTempo(120); s.setParams(p.voice, p.routes); s.setFX(p.fx);
    std::vector<float> L(n), R(n); s.noteOn(48, 0.9f); s.renderPlanar(L.data(), R.data(), n);
    return L;
}
static bool same(const std::vector<float>& a, const std::vector<float>& b) { for (size_t i = 0; i < a.size(); ++i) if (a[i] != b[i]) return false; return true; }
static double dist(const std::vector<float>& a, const std::vector<float>& b) { double d = 0; for (size_t i = 0; i < a.size(); ++i) d += std::fabs(a[i] - b[i]); return d / a.size(); }

int main() {
    check((int)D::Osc1Warp2 == 21 && (int)D::Osc2Warp2 == 22 && (int)D::FxChorusDepth == 20, "destinations appended after FX CHORUS DEPTH");
    check(!ui::isFxDest(D::Osc1Warp2) && !ui::isFxDest(D::Osc2Warp2) && ui::isFxDest(D::FxChorusDepth), "WARP 2 destinations are voice destinations");
    check(std::string(ui::destName(D::Osc1Warp2)) == "WARP 2 A" && std::string(ui::warpName(10)) == "REMAP" && std::string(ui::warpName(7)) == "FM B", "names");
    {
        int extra = 0;
        for (const auto& p : factoryPresets()) { auto t = p.serialize(); if (t.find("\nwarpx ") != std::string::npos || t.find("\nremap ") != std::string::npos) ++extra; }
        check(extra == 0, "no factory preset writes warpx/remap lines");
    }
    {
        Preset p = factoryPresets()[2];
        p.voice.osc1Warp2Mode = 10; p.voice.osc1Warp2 = 0.7; p.voice.osc2Warp2Mode = 7; p.voice.osc2Warp2 = 0.4;
        p.voice.remapPoints[0] = {{0, -1, 0}, {0.3, 0.6, -0.5}, {1, 1, 0}};
        p.routes.push_back({S::LFO1, D::Osc1Warp2, 0.3});
        Preset q; bool ok = q.parse(p.serialize());
        check(ok && q == p && q.serialize() == p.serialize(), "warpx/remap lines and WARP 2 routes round-trip exactly");
        Preset r; r.parse(p.serialize() + "warpx 1 nan 2 0\nremap 5 2 0 0 0 1 1 0\n");
        check(r == p, "malformed warpx/remap lines are ignored");
    }
    Preset base = factoryPresets()[2];
    base.voice.osc2Level = 0.0; base.routes.clear(); base.voice.filterCutoff = 12000;
    const auto dry = render(base, 8192);
    {
        Preset pu = base; pu.voice.osc1Shape = 4; // PULSE runs the DC blocker either way, so only the warp differs
        Preset p = pu; p.voice.osc1Warp2Mode = 10; p.voice.osc1Warp2 = 1.0; // identity curve
        check(dist(render(pu, 8192), render(p, 8192)) < 1e-3, "REMAP with the default straight curve leaves the wave (almost) untouched");
        p = base; p.voice.osc1Warp2Mode = 10; p.voice.osc1Warp2 = 1.0;
        p.voice.remapPoints[0] = {{0, -1, 0}, {0.5, 0.6, 0.6}, {1, 1, 0}};
        check(dist(dry, render(p, 8192)) > 0.01, "a drawn REMAP curve reshapes the wave");
        Preset z = p; z.voice.osc1Warp2 = 0;
        check(dist(dry, render(z, 8192)) < 1e-3, "REMAP at amount 0 is dry");
    }
    {
        Preset p = base; p.voice.osc1Warp2Mode = 7; p.voice.osc1Warp2 = 0.6; // FM from B, B silent in the mix
        check(dist(dry, render(p, 8192)) > 0.01, "FM B modulates A even with oscillator B's level at 0");
        Preset a = base; a.voice.osc1Warp2Mode = 8; a.voice.osc1Warp2 = 1.0;
        check(dist(dry, render(a, 8192)) > 0.01, "AM B changes the wave");
        Preset w = base; w.voice.osc1Warp2Mode = 9; w.voice.osc1Warp2 = 0.5;
        check(dist(dry, render(w, 8192)) > 0.01, "WINDOW changes the wave");
        Preset s1 = base; s1.voice.osc1WarpMode = 1; s1.voice.osc1Warp = 0.5;
        Preset s2 = s1; s2.voice.osc1Warp2Mode = 2; s2.voice.osc1Warp2 = 0.6;
        check(dist(render(s1, 8192), render(s2, 8192)) > 0.01, "slot 2 runs after slot 1 (SYNC then BEND+)");
        Preset off = s1; off.voice.osc1Warp2Mode = 0; off.voice.osc1Warp2 = 0.9;
        check(same(render(s1, 8192), render(off, 8192)), "slot 2 OFF: identical to one slot, whatever its amount");
    }
    {
        Preset p = base; p.voice.osc1Warp2Mode = 3; p.voice.osc1Warp2 = 0.0;
        Preset m = p; m.routes = {{S::Macro1, D::Osc1Warp2, 0.8}}; m.voice.macros[0] = 1.0;
        check(dist(render(p, 8192), render(m, 8192)) > 0.01, "a macro route into WARP 2 A moves the second slot");
    }
    {
        Wavetable wt;
        VoiceParams v; v.osc1Warp2Mode = 10; v.osc1Warp2 = 1.0; v.remapPoints[0] = {{0, -1, 0}, {0.5, 0.6, 0.6}, {1, 1, 0}};
        auto x = ui::warpExtras(v, 0);
        auto a = ui::waveform(wt, 2, 0, 0, 240), b = ui::waveform(wt, 2, 0, 0, 240, &x);
        check(dist(a, b) > 0.01, "oscillator display shows the second slot and REMAP curve");
    }
    {
        VoiceParams v;
        ui::stepWarpMode(v, 0, 1, -1);
        check(v.osc1Warp2Mode == 10 && ui::usesRemap(v, 0) && !ui::usesRemap(v, 1), "slot 2 steps back from CLEAN to REMAP");
        ui::stepWarpMode(v, 1, 0, 1);
        check(v.osc2WarpMode == 1 && ui::warpMode(v, 1, 0) == 1, "slot 1 steps forward");
        auto mv = ui::editView(v, 6);
        int i = ui::msegInsert(mv, 0.5, 0.6);
        check(i == 1 && v.remapPoints[0].size() == 3 && mv.mode() == 0 && *mv.sync == 0, "editor view 6 edits oscillator A's REMAP curve");
    }
    printf(g_fail ? "FAILED %d\n" : "ALL PASS\n", g_fail);
    return g_fail ? 1 : 0;
}
