// tests_lfox.cpp - 0.18.0 drawn LFO shapes, start phase, delay/rise, free-run.
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

int main() {
    // LFO unit: custom table, start phase, delay/rise.
    {
        LFO l; l.setSampleRate(1000); l.setRate(1);
        float tab[LFO::kTable + 1];
        for (int k = 0; k <= LFO::kTable; ++k) tab[k] = k < LFO::kTable / 2 ? 1.0f : -1.0f;
        l.setCustom(tab); l.reset();
        float a = l.process(); for (int i = 0; i < 499; ++i) l.process(); float b = l.process();
        check(a == 1.0f && b == -1.0f, "custom table plays one drawn cycle per period");
        l.setCustom(nullptr); l.setStartPhase(0.25); l.reset();
        check(std::fabs(l.process() - 1.0f) < 1e-6, "start phase 0.25 starts a sine at its peak");
        l.setStartPhase(0.25); l.setFade(100, 100); l.reset();
        std::vector<float> v(400); for (auto& x : v) x = l.process();
        bool silent = true; for (int i = 0; i < 100; ++i) silent &= v[i] == 0.0f;
        check(silent, "delay holds the LFO at zero");
        check(std::fabs(v[150]) > 0.3 * std::fabs(std::sin(2 * M_PI * (0.25 + 150 / 1000.0))) && std::fabs(v[150]) < 0.7 * std::fabs(std::sin(2 * M_PI * (0.25 + 150 / 1000.0))),
              "rise fades it in halfway at mid-rise");
        check(std::fabs(v[300] - std::sin(2 * M_PI * (0.25 + 300 / 1000.0))) < 1e-4, "full level after delay + rise");
    }
    // Factory presets: extras stay default, serialize without new lines, and defaults render identically.
    {
        int extra = 0;
        for (const auto& p : factoryPresets()) { auto t = p.serialize(); if (t.find("\nlfox ") != std::string::npos || t.find("\nlfopts ") != std::string::npos) ++extra; }
        check(extra == 0, "no factory preset writes lfox/lfopts lines");
    }
    // Round trip.
    {
        Preset p = factoryPresets()[2];
        p.voice.lfoCustom[2] = true; p.voice.lfoPhase[2] = 0.5; p.voice.lfoDelay[2] = 0.2; p.voice.lfoRise[2] = 0.3; p.voice.lfoFree[1] = true;
        p.voice.lfoPoints[2] = {{0, -1, 0}, {0.1, 1, -0.6}, {0.6, 0.2, 0.4}, {1, -1, 0}};
        Preset q; bool ok = q.parse(p.serialize());
        check(ok && q == p && q.serialize() == p.serialize(), "lfox/lfopts round-trip exactly");
        Preset r; r.parse(p.serialize() + "lfox 9 1 0 0 0 0\nlfopts 1 3 0 0 0\n");
        check(r == p, "malformed lfox/lfopts lines are ignored");
    }
    // Engine: custom LFO on cutoff differs from the built-in shape; turning custom off restores it bit for bit.
    {
        Preset p = factoryPresets()[2];
        p.voice.filterCutoff = 600; p.voice.lfo1Rate = 3; p.routes = {{S::LFO1, D::FilterCutoff, 3.0}};
        auto base = render(p, 44100);
        Preset c = p; c.voice.lfoCustom[0] = true; c.voice.lfoPoints[0] = {{0, 1, 0}, {0.05, -1, 0.7}, {1, 1, 0}};
        auto cu = render(c, 44100);
        check(!same(base, cu), "drawn LFO 1 shape changes the sound");
        Preset d = c; d.voice.lfoCustom[0] = false;
        check(same(base, render(d, 44100)), "custom off: identical to the built-in shape");
        Preset e = p; e.voice.lfoDelay[0] = 0.25;
        auto de = render(e, 44100);
        Preset flat = p; flat.routes.clear();
        auto fl = render(flat, 11000);
        bool eq = true; for (int i = 0; i < 11000; ++i) eq &= std::fabs(de[i] - fl[i]) < 1e-6f;
        check(eq, "0.25 s delay: the first 0.25 s sounds like no LFO route");
    }
    // Free-run: two notes started at different times share the LFO phase when free, not when retriggered.
    {
        for (int f = 0; f < 2; ++f) {
            VoiceParams vp; vp.lfo1Rate = 1.0; vp.lfoFree[0] = f;
            Wavetable wt; Voice a, b; a.init(44100, &wt); b.init(44100, &wt);
            a.setParams(vp, {}); b.setParams(vp, {});
            a.setClock(0); a.noteOn(60, 1); b.setClock(11025); b.noteOn(60, 1);
            // after starting b at clock 11025, a has run 11025 samples
            for (int i = 0; i < 11025; ++i) a.lfo(0).process();
            double pa = a.lfo(0).phase(), pb = b.lfo(0).phase();
            if (f) check(std::fabs(pa - pb) < 1e-3, "free-run: a note starting later joins the running phase");
            else check(std::fabs(pb) < 1e-9 && std::fabs(pa - 0.25) < 1e-3, "retrigger: each note restarts at the start phase");
        }
    }
    // UI model: shape cycle through CUSTOM, editor view edits the LFO's points, readouts.
    {
        VoiceParams v;
        ui::setLfoShapeIndex(v, 2, 4);
        check(v.lfoCustom[2] && ui::lfoShapeIndex(v, 2) == 4 && std::string(ui::lfoShapeIndexName(4)) == "CUSTOM", "SHAPE cycles into CUSTOM");
        ui::setLfoShapeIndex(v, 2, 5);
        check(!v.lfoCustom[2] && v.lfo3Shape == 0, "and wraps back to SINE");
        auto mv = ui::editView(v, 4);
        int i = ui::msegInsert(mv, 0.5, 0.5);
        check(i == 2 && v.lfoPoints[2].size() == 5 && mv.mode() == 0, "editor view 4 inserts into LFO 3's points, no loop span");
        check(ui::lfoPhaseReadout(0.25) == "90\u00B0" && ui::lfoFadeReadout(0) == "OFF" && ui::lfoFadeReadout(0.25) == "250 ms", "phase/fade readouts");
        check(ui::fadeFrom01(0) == 0 && std::fabs(ui::fadeFrom01(ui::fadeTo01(0.3)) - 0.3) < 1e-9 && std::fabs(ui::fadeFrom01(1) - 8) < 1e-9, "fade drag mapping");
    }
    printf(g_fail ? "FAILED %d\n" : "ALL PASS\n", g_fail);
    return g_fail ? 1 : 0;
}
