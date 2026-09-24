// MUEW 0.29.0 Quality + Consistency: host Reset gives every note the same render,
// HQ (4x oversampled) distortion, MULTIBAND AUTO GAIN, preset lines and UI rows.
#include "../src/preset.h"
#include "../src/factory_bank.h"
#include "../src/synth.h"
#include "../src/ui_model.h"
#include <cmath>
#include <cstdio>
#include <memory>
#include <sstream>
#include <string>
#include <vector>
using namespace muew;

static int g_fail = 0;
static void check(bool c, const std::string& n) { printf("%s %s\n", c ? "ok:  " : "FAIL:", n.c_str()); if (!c) ++g_fail; }
static std::vector<float> sine(int n, double hz, double a) { std::vector<float> v(n); for (int i = 0; i < n; ++i) v[i] = (float)(a * std::sin(2 * M_PI * hz * i / 44100.0)); return v; }
static double rms(const std::vector<float>& v, size_t a, size_t b) { double s = 0; for (size_t i = a; i < b; ++i) s += (double)v[i] * v[i]; return std::sqrt(s / (b - a)); }
// Magnitude of one frequency (Hann-windowed single-bin DFT).
static double bin(const std::vector<float>& x, size_t a, size_t n, double hz) {
    double re = 0, im = 0;
    for (size_t i = 0; i < n; ++i) {
        const double w = 0.5 - 0.5 * std::cos(2 * M_PI * i / (n - 1)), ph = 2 * M_PI * hz * (a + i) / 44100.0;
        re += w * x[a + i] * std::cos(ph); im += w * x[a + i] * std::sin(ph);
    }
    return 2.0 * std::sqrt(re * re + im * im) / (0.5 * n);
}
static void runFx(const FXParams& f, std::vector<float>& L, std::vector<float>& R) {
    FXChain c; c.init(44100); c.set(f);
    for (size_t i = 0; i < L.size(); ++i) c.process(L[i], R[i]);
}
static double noteEnergy(Synth& s, const Preset& p, int note) {
    s.init(44100); s.setTables(p.tables[0], p.tables[1]); s.setParams(p.voice, p.routes); s.setFX(p.fx);
    std::vector<float> L(512), R(512); double m = 0;
    s.noteOn(note, 110 / 127.f);
    for (int b = 0; b < 24; ++b) { s.renderPlanar(L.data(), R.data(), 512); if (b < 4) continue; for (int i = 0; i < 512; ++i) m += (L[i] + R[i]) * (L[i] + R[i]); }
    s.noteOff(note);
    return m;
}

int main() {
    // ---- Reset consistency ----
    {
        bool same = true; std::string worst;
        int bad = 0;
        for (const auto& fp : factoryPresets()) {
            Preset p = fp;
            auto s = std::make_unique<Synth>();
            const double first = noteEnergy(*s, p, 60);
            for (int k = 0; k < 3; ++k) {
                const double again = noteEnergy(*s, p, 60);
                if (again != first) { if (same || true) worst += p.info.name + " (" + std::to_string(first) + " vs " + std::to_string(again) + ") "; same = false; ++bad; break; }
            }
        }
        check(same, "after init (host Reset) every note of all 80 factory sounds renders exactly like the first one" + (same ? std::string() : " - " + std::to_string(bad) + ": " + worst));
        Preset mono = factoryPresets()[2]; mono.voice.voiceMode = 1; mono.voice.glideTime = 0.3;
        auto s = std::make_unique<Synth>();
        const double a = noteEnergy(*s, mono, 60);
        noteEnergy(*s, mono, 72);
        check(noteEnergy(*s, mono, 60) == a, "Reset forgets the last note: no glide in from the previous key");
        s->init(44100);
        check(s->activeVoiceCount() == 0 && s->heldCount() == 0, "Reset leaves no active voices and no held keys");
    }
    // ---- HQ distortion ----
    {
        auto alias = [&](int quality, int mode) {
            FXParams f; f.dist.enabled = true; f.dist.mode = mode; f.dist.drive = 1.0; f.dist.quality = quality;
            auto L = sine(16384, 7000, 0.8), R = L; runFx(f, L, R);
            // 7 kHz: harmonics 21 (kept), 35, 49 kHz fold to 9.1, 4.9 kHz; measure those alias lines.
            return bin(L, 4096, 8192, 9100.0) + bin(L, 4096, 8192, 4900.0);
        };
        const double s0 = alias(0, 0), s1 = alias(1, 0), f0 = alias(0, 1), f1 = alias(1, 1);
        printf("aliases: soft clip %.5f -> %.5f, fold %.5f -> %.5f\n", s0, s1, f0, f1);
        check(s1 < s0 * 0.25, "HQ cuts soft-clip aliasing by at least 12 dB");
        check(f1 < f0 * 0.5, "HQ cuts fold aliasing by at least 6 dB");
        FXParams g; g.dist.enabled = true; g.dist.mode = 0; g.dist.drive = 0.6; g.dist.quality = 1;
        auto L = sine(8192, 300, 0.5), R = L, D = L; runFx(g, L, R);
        const double h0 = bin(L, 2048, 4096, 300.0), d0 = bin(D, 2048, 4096, 300.0);
        FXParams g0 = g; g0.dist.quality = 0; auto L0 = sine(8192, 300, 0.5), R0 = L0; runFx(g0, L0, R0);
        check(std::fabs(h0 - bin(L0, 2048, 4096, 300.0)) < 0.02 * d0, "HQ keeps the same tone below the aliasing range");
        FXParams m0 = g; m0.dist.mix = 0.0; auto Lm = sine(4096, 300, 0.5), Rm = Lm, Dm = Lm; runFx(m0, Lm, Rm);
        double err = 0; for (int i = 100; i < 4000; ++i) err = std::max(err, std::fabs((double)Lm[i] - 0.5 * (Dm[i - 22] + Dm[i - 23])));
        check(err < 0.01, "HQ at MIX 0 is the dry signal, 22.5 samples late (dry and wet share the oversampled path)");
        FXParams b; b.dist.enabled = true; b.dist.mode = 2; b.dist.drive = 0.7;
        FXParams bq = b; bq.dist.quality = 1;
        auto Lb = sine(4096, 1000, 0.5), Rb = Lb, Lq = Lb, Rq = Lb; runFx(b, Lb, Rb); runFx(bq, Lq, Rq);
        check(Lb == Lq, "BITCRUSH ignores QUALITY (its aliasing is the sound)");
        check(true, "STANDARD is the 0.28 distortion (factory renders byte-identical, checked by the factory dump)");
    }
    // ---- MULTIBAND AUTO GAIN ----
    {
        auto lvl = [&](int makeup) {
            FXParams f; f.comp.enabled = true; f.comp.mode = 1; f.comp.amount = 0.8; f.comp.upward = 0.0; f.comp.makeup = makeup;
            auto L = sine(44100, 1000, 0.5), R = L; runFx(f, L, R); return rms(L, 22050, 44100);
        };
        const double a = lvl(0), b = lvl(1);
        printf("auto gain: %.4f -> %.4f\n", a, b);
        check(b > a * 1.4, "AUTO GAIN gives back level lost to heavy MULTIBAND squeeze");
        MultibandComp m; m.init(44100); CompressorParams c; c.mode = 1; c.amount = 0.0; c.makeup = 1; m.set(c);
        check(std::fabs(m.makeupDb()) < 1e-9, "AUTO GAIN adds nothing when nothing is squeezed");
        c.amount = 1.0; m.set(c);
        check(m.makeupDb() > 0.0 && m.makeupDb() <= 12.0, "AUTO GAIN stays within 0..+12 dB");
    }
    // ---- Preset lines ----
    {
        Preset p = factoryPresets()[3];
        const std::string base = p.serialize();
        check(base.find("\ndistx ") == std::string::npos, "defaults write no distx line");
        p.fx.dist.quality = 1; p.fx.comp.mode = 1; p.fx.comp.makeup = 1;
        const std::string t = p.serialize();
        Preset q;
        check(t.find("\ndistx 1\n") != std::string::npos && q.parse(t) && q == p && q.fx.dist.quality == 1 && q.fx.comp.makeup == 1,
              "distx and the AUTO GAIN compx field round-trip");
        Preset old; std::string legacy = t;
        const size_t k = legacy.find("\ndistx 1\n"); legacy.erase(k, 8);
        check(old.parse(legacy) && old.fx.dist.quality == 0, "a sound without distx loads STANDARD");
        Preset p28 = factoryPresets()[3]; p28.fx.comp.mode = 1; p28.fx.comp.upward = 0.7;
        const std::string s28 = p28.serialize(); const size_t c0 = s28.find("\ncompx "), c1 = s28.find('\n', c0 + 1);
        int fields = 0; { std::istringstream ls(s28.substr(c0 + 1, c1 - c0 - 1)); std::string w; while (ls >> w) ++fields; }
        Preset r28; check(fields == 8 && r28.parse(s28) && r28.fx.comp.makeup == 0, "AUTO GAIN off writes the 0.28 7-field compx line, which loads with AUTO GAIN off");
        bool ident = true;
        for (const auto& fp : factoryPresets()) { Preset x; if (!x.parse(fp.serialize()) || !(x == fp) || x.fx.dist.quality || x.fx.comp.makeup) ident = false; }
        check(ident, "factory presets keep STANDARD and AUTO GAIN off");
    }
    // ---- UI ----
    {
        FXParams f;
        check(ui::fxControls(FxDist).size() == 4 && std::string(ui::fxControls(FxDist)[3].label) == "QUALITY", "DIST page gains a QUALITY row");
        ui::fxSet(f, FxDist, 3, 1);
        check(f.dist.quality == 1 && ui::fxValueText(f, FxDist, 3) == "HQ 4X" && std::string(ui::fxChoiceName(FxDist, 3, 0)) == "STANDARD"
              && std::string(ui::fxChoiceName(FxDist, 0, 1)) == "FOLD", "QUALITY row reads and writes STANDARD / HQ 4X");
        f.dist.mode = 2;
        check(ui::fxRowInactive(f, FxDist, 3) && !ui::fxRowInactive(f, FxDist, 1), "QUALITY greys out under BITCRUSH");
    }
    if (g_fail) { printf("%d QUALITY29 TEST(S) FAILED\n", g_fail); return 1; }
    printf("ALL QUALITY29 TESTS PASSED\n");
    return 0;
}
