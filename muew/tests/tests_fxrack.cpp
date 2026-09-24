// tests_fxrack.cpp - 0.13.0 FX rack depth: phaser and flanger units, a
// reorderable chain saved with the sound, and factory sounds left untouched.
#include "../src/preset.h"
#include "../src/factory_bank.h"
#include "../src/au_params.h"
#include <cmath>
#include <cstdio>
#include <vector>

using namespace muew;
static int g_fail = 0;
static void check(bool c, const std::string& n) { printf("%s %s\n", c ? "ok:  " : "FAIL:", n.c_str()); if (!c) ++g_fail; }

static std::vector<float> noise(int n) {
    std::vector<float> v(n); uint32_t s = 12345;
    for (auto& x : v) { s = s * 1664525u + 1013904223u; x = ((s >> 9) / 4194304.0f - 1.0f) * 0.5f; }
    return v;
}
// Runs a mono signal through a chain; returns the left output.
static std::vector<float> run(const FXParams& p, const std::vector<float>& in) {
    FXChain c; c.init(44100); c.set(p);
    std::vector<float> out(in.size());
    for (size_t i = 0; i < in.size(); ++i) { float l = in[i], r = in[i]; c.process(l, r); out[i] = l; }
    return out;
}
static double rms(const std::vector<float>& v, size_t from = 0) {
    double s = 0; for (size_t i = from; i < v.size(); ++i) s += (double)v[i] * v[i];
    return std::sqrt(s / std::max<size_t>(1, v.size() - from));
}
static bool finite(const std::vector<float>& v) { for (float x : v) if (!std::isfinite(x)) return false; return true; }
static std::string orderText(const FxOrder& o) { std::string s; for (int i = 0; i < kFxUnits; ++i) s += std::to_string(o.slot[i]); return s; }

int main() {
    // Order model.
    FxOrder o;
    check(o.isDefault() && orderText(o) == "0123456789", "default chain is the 0.7.0 order with the later units appended");
    check(o.move(4, 0) && orderText(o) == "4012356789", "moving REVERB to the front shifts the others right");
    check(o.move(0, 9) && orderText(o) == "0123567894", "moving it to the end shifts the others left");
    check(!o.move(3, 3) && !o.move(-1, 2) && !o.move(2, 10), "no-op and out-of-range moves are refused");
    check(o.slotOf(FxReverb) == 9 && o.slotOf(FxDist) == 0, "slotOf finds units");
    int dup[kFxUnits] = {0, 0, 1, 2, 3, 4, 5, 6, 7, 8};
    FxOrder keep; check(!keep.assign(dup, kFxUnits) && keep.isDefault(), "a duplicate unit is rejected");

    // Factory sounds: no new lines, round-trip unchanged.
    bool clean = true, rt = true;
    for (const auto& p : factoryPresets()) {
        std::string t = p.serialize();
        if (t.find("\nphaser ") != std::string::npos || t.find("\nflanger ") != std::string::npos || t.find("\nfxorder") != std::string::npos) clean = false;
        Preset q; if (!q.parse(t) || !(q == p) || q.serialize() != t) rt = false;
        if (!p.fx.order.isDefault() || p.fx.phaser.enabled || p.fx.flanger.enabled) clean = false;
    }
    check(clean, "no factory sound writes phaser, flanger or fxorder lines");
    check(rt, "every factory sound round-trips byte-identical");

    // Round-trip of the new state.
    Preset p = factoryPresets()[7];
    p.fx.phaser = PhaserParams{true, 1.5, 0.8, 0.7, 0.6};
    p.fx.flanger = FlangerParams{true, 0.1, 0.4, 0.3, 0.45};
    p.fx.order.move(p.fx.order.slotOf(FxPhaser), 0); p.fx.order.move(p.fx.order.slotOf(FxReverb), 2);
    std::string t = p.serialize();
    Preset q; bool ok = q.parse(t);
    check(ok && q == p && q.serialize() == t, "phaser, flanger and chain order round-trip");
    check(t.find("fxorder phaser dist reverb chorus delay comp eq flanger") != std::string::npos, "chain order is saved as unit names");
    Preset bad; bad.parse(t + "fxorder dist dist chorus delay comp reverb eq phaser\n");
    check(bad.fx.order == p.fx.order, "a damaged fxorder line keeps the last good order");
    Preset bad2; bad2.parse(factoryPresets()[7].serialize() + "fxorder dist chorus warp delay comp reverb eq phaser\n");
    check(bad2.fx.order.isDefault(), "an unknown unit name keeps the default order");
    Preset bad3; bad3.parse(factoryPresets()[7].serialize() + "phaser 1 99 5 3 -2\n");
    check(bad3.fx.phaser.rateHz == 8.0 && bad3.fx.phaser.depth == 1.0 && bad3.fx.phaser.feedback == 0.9 && bad3.fx.phaser.mix == 0.0,
          "out-of-range phaser values are clamped");

    // AU parameters 28 and 29.
    Preset a = factoryPresets()[7];
    params::set(a, params::PhaserMix, 35); params::set(a, params::FlangerMix, 80);
    check(std::fabs(a.fx.phaser.mix - 0.35) < 1e-9 && std::fabs(a.fx.flanger.mix - 0.8) < 1e-9, "PhaserMix/FlangerMix map to the unit mixes");
    check(std::string(params::def(params::PhaserMix).name) == "Phaser Mix" && std::string(params::def(params::FlangerMix).name) == "Flanger Mix", "parameter names");

    // DSP: off units are exact pass-through; default order equals the old fixed order.
    auto in = noise(44100 * 2);
    FXParams off;
    auto dry = run(off, in);
    bool same = true; for (size_t i = 0; i < in.size(); ++i) if (dry[i] != in[i]) same = false;
    check(same, "an all-off rack is bit-exact pass-through");

    FXParams ph; ph.phaser = PhaserParams{true, 0.5, 0.8, 0.6, 0.5};
    auto phOut = run(ph, in);
    double diff = 0; for (size_t i = 0; i < in.size(); ++i) diff += std::fabs(phOut[i] - in[i]);
    check(finite(phOut) && diff / in.size() > 0.02 && rms(phOut, 4410) < rms(in) * 1.6, "phaser colours noise and stays level");
    FXParams fl; fl.flanger = FlangerParams{true, 0.3, 0.8, 0.6, 0.5};
    auto flOut = run(fl, in);
    diff = 0; for (size_t i = 0; i < in.size(); ++i) diff += std::fabs(flOut[i] - in[i]);
    check(finite(flOut) && diff / in.size() > 0.02 && rms(flOut, 4410) < rms(in) * 1.8, "flanger colours noise and stays level");

    // Stability at maximum feedback over 20 s of a loud square.
    std::vector<float> sq(44100 * 20);
    for (size_t i = 0; i < sq.size(); ++i) sq[i] = ((i / 100) % 2) ? 0.9f : -0.9f;
    FXParams hot; hot.phaser = PhaserParams{true, 8, 1, 0.9, 1}; hot.flanger = FlangerParams{true, 8, 1, 0.9, 1};
    auto hotOut = run(hot, sq);
    double pk = 0; for (float x : hotOut) pk = std::max(pk, (double)std::fabs(x));
    check(finite(hotOut) && pk < 4.0, "phaser + flanger at full feedback stay bounded (peak " + std::to_string(pk) + ")");

    // Order matters: distortion before vs after the reverb.
    FXParams d1; d1.dist.enabled = true; d1.dist.drive = 0.9; d1.reverb.enabled = true; d1.reverb.mix = 0.5;
    FXParams d2 = d1; d2.order.move(d2.order.slotOf(FxReverb), 0);
    auto o1 = run(d1, in), o2 = run(d2, in);
    diff = 0; for (size_t i = 0; i < in.size(); ++i) diff += std::fabs(o1[i] - o2[i]);
    check(diff / in.size() > 1e-3, "moving the reverb ahead of the distortion changes the sound");
    // Moving an off unit changes nothing.
    FXParams d3 = d1; d3.order.move(d3.order.slotOf(FxPhaser), 0);
    auto o3 = run(d3, in);
    same = true; for (size_t i = 0; i < in.size(); ++i) if (o3[i] != o1[i]) same = false;
    check(same, "moving an off unit leaves the output bit-exact");

    printf(g_fail ? "%d FX RACK TEST(S) FAILED\n" : "ALL FX RACK TESTS PASSED\n", g_fail);
    return g_fail ? 1 : 0;
}
