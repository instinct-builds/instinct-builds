// MUEW 0.30.0 Engine HQ: oscillator oversampling (global QUALITY), HQ render
// mode for offline bounces, engine latency and the voice meter counters.
#include "../src/preset.h"
#include "../src/factory_bank.h"
#include "../src/synth.h"
#include <cmath>
#include <cstdio>
#include <memory>
#include <sstream>
#include <string>
#include <vector>
using namespace muew;

static int g_fail = 0;
static void check(bool c, const std::string& n) { printf("%s %s\n", c ? "ok:  " : "FAIL:", n.c_str()); if (!c) ++g_fail; }
static double bin(const std::vector<float>& x, size_t a, size_t n, double hz) {
    double re = 0, im = 0;
    for (size_t i = 0; i < n; ++i) {
        const double w = 0.5 - 0.5 * std::cos(2 * M_PI * i / (n - 1)), ph = 2 * M_PI * hz * (a + i) / 44100.0;
        re += w * x[a + i] * std::cos(ph); im += w * x[a + i] * std::sin(ph);
    }
    return 2.0 * std::sqrt(re * re + im * im) / (0.5 * n);
}
static Preset bare(int warpMode, double warp) {
    Preset p = factoryPresets()[2]; // Init Saw
    p.routes.clear();
    p.voice.osc2Level = 0.0; p.voice.osc1Unison = 1; p.voice.osc2Unison = 1;
    p.voice.osc1WarpMode = warpMode; p.voice.osc1Warp = warp;
    p.voice.filterCutoff = 20000; p.voice.filterReso = 0.1;
    p.voice.ampA = 0.001; p.voice.ampS = 1.0;
    p.fx = FXParams{};
    return p;
}
static std::vector<float> renderNote(const Preset& p, int note, int frames, bool renderHQ = false) {
    auto s = std::make_unique<Synth>();
    s->init(44100); s->setRenderHQ(renderHQ);
    s->setTables(p.tables[0], p.tables[1]); s->setParams(p.voice, p.routes); s->setFX(p.fx);
    std::vector<float> L(frames), R(frames);
    s->noteOn(note, 0.8f);
    s->renderPlanar(L.data(), R.data(), frames);
    return L;
}
// Sum of the aliased images of harmonics 15..29 (they fold back below Nyquist) relative to the fundamental.
static double aliasRatio(const std::vector<float>& x, double f) {
    const size_t a = 4096, n = 32768;
    double al = 0;
    for (int k = 15; k <= 29; ++k) { double h = std::fmod(k * f, 44100.0); if (h > 22050) h = 44100 - h; al += bin(x, a, n, h); }
    double e = 0; for (size_t i = a; i < a + n; ++i) e += (double)x[i] * x[i];
    return al / std::sqrt(e / n); // relative to the note's RMS level
}
static double rmsOf(const std::vector<float>& x, size_t a, size_t n) { double e = 0; for (size_t i = a; i < a + n; ++i) e += (double)x[i] * x[i]; return std::sqrt(e / n); }

int main() {
    const int note = 90; const double f = 440.0 * std::pow(2.0, (note - 69) / 12.0);
    // ---- Oscillator oversampling ----
    {
        Preset st = bare(1, 0.6); // SYNC: hard phase resets alias
        Preset hq = st; hq.voice.oscQuality = 1;
        const auto a = renderNote(st, note, 40000), b = renderNote(hq, note, 40000);
        const double ra = aliasRatio(a, f), rb = aliasRatio(b, f);
        printf("      SYNC 0.6 (5x) at %.0f Hz: aliasing %.5f STANDARD -> %.5f HQ\n", f, ra, rb);
        check(rb < ra / 8, "QUALITY HQ cuts oscillator SYNC aliasing by more than 8x");
        const double fa = bin(a, 4096, 32768, 5 * f), fb = bin(b, 4096, 32768, 5 * f);
        printf("      synced tone (5f) %.4f -> %.4f\n", fa, fb);
        check(std::fabs(20 * std::log10(fb / fa)) < 0.5, "HQ keeps the synced tone's level (within 0.5 dB); only the aliases go");
        Preset fm = bare(6, 0.8); Preset fmh = fm; fmh.voice.oscQuality = 1; // FOLD
        const double fa2 = aliasRatio(renderNote(fm, note, 40000), f), fb2 = aliasRatio(renderNote(fmh, note, 40000), f);
        printf("      FOLD 0.8: aliasing %.5f -> %.5f\n", fa2, fb2);
        check(fb2 < fa2 / 4, "QUALITY HQ cuts FOLD warp aliasing by more than 4x");
        Preset plain = bare(0, 0.0), plainHQ = plain; plainHQ.voice.oscQuality = 1;
        const auto p0 = renderNote(plain, 60, 20000), p1 = renderNote(plainHQ, 60, 20000);
        const double g0 = bin(p0, 4096, 8192, 261.6255653), g1 = bin(p1, 4096, 8192, 261.6255653);
        check(std::fabs(20 * std::log10(g1 / g0)) < 0.1, "an unwarped saw sounds the same in HQ (within 0.1 dB)");
    }
    // ---- Unison and FM stacks in HQ ----
    {
        Preset p = factoryPresets()[2]; p.voice.oscQuality = 1; p.voice.osc1Unison = 7; p.voice.osc2Unison = 3; p.voice.uniWidth = 0.8;
        p.voice.osc1Warp2Mode = 7; p.voice.osc1Warp2 = 0.5; // FM B
        auto s = std::make_unique<Synth>(); s->init(44100); s->setParams(p.voice, p.routes); s->setFX(p.fx);
        std::vector<float> L(4096), R(4096); s->noteOn(60, 0.8f); s->noteOn(67, 0.8f); s->renderPlanar(L.data(), R.data(), 4096);
        bool finite = true; double e = 0, side = 0; for (int i = 0; i < 4096; ++i) { finite &= std::isfinite(L[i]) && std::isfinite(R[i]); e += L[i] * L[i]; side += (L[i] - R[i]) * (L[i] - R[i]); }
        check(finite && e > 1.0 && side > 0.01, "HQ unison stacks with FM B render finite, audible and stereo");
        check(s->activeVoiceCount() == 2 && s->maxVoices() == 16, "voice meter counts: 2 of 16 voices active");
    }
    // ---- Latency and HQ render ----
    {
        Synth s; s.init(44100);
        Preset p = factoryPresets()[2];
        s.setParams(p.voice, p.routes); s.setFX(p.fx);
        check(s.latencySamples() == 0.0 && !s.oscHQ(), "STANDARD adds no latency");
        VoiceParams v = p.voice; v.oscQuality = 1; s.setParams(v, p.routes);
        check(s.latencySamples() == 7.5 && s.oscHQ(), "oscillator HQ reports 7.5 samples");
        FXParams fx = p.fx; fx.dist.enabled = true; fx.dist.mode = 1; fx.dist.quality = 1; s.setFX(fx);
        check(s.latencySamples() == 30.0, "oscillator HQ + HQ distortion report 30 samples");
        fx.dist.mode = 2; s.setFX(fx);
        check(s.latencySamples() == 7.5, "BITCRUSH adds no latency (it never oversamples)");
        s.setParams(p.voice, p.routes); fx.dist.mode = 1; fx.dist.quality = 0; s.setFX(fx);
        check(s.latencySamples() == 0.0, "STANDARD distortion adds no latency");
        s.setRenderHQ(true);
        check(s.oscHQ() && s.fx().latencySamples() == 22.5 && s.latencySamples() == 30.0, "HQ render forces oscillator and distortion HQ");
        s.init(44100);
        check(s.renderHQ() && s.oscHQ(), "HQ render survives a host Reset");
        s.setRenderHQ(false);
        check(!s.oscHQ() && s.latencySamples() == 0.0, "leaving HQ render restores STANDARD");
        // A realtime HQ render sounds like the offline one.
        Preset d = bare(1, 0.6); d.fx.dist.enabled = true; d.fx.dist.mode = 1; d.fx.dist.drive = 0.6;
        Preset dh = d; dh.voice.oscQuality = 1; dh.fx.dist.quality = 1;
        const auto off = renderNote(d, note, 12000, true), live = renderNote(dh, note, 12000, false);
        double diff = 0; for (size_t i = 0; i < off.size(); ++i) diff = std::max(diff, (double)std::fabs(off[i] - live[i]));
        check(diff < 1e-6, "an offline HQ render equals QUALITY HQ + DIST HQ played live");
    }
    // ---- Reset consistency in HQ ----
    {
        Preset p = factoryPresets()[34]; p.voice.oscQuality = 1;
        auto s = std::make_unique<Synth>();
        std::vector<double> e;
        for (int k = 0; k < 3; ++k) {
            s->init(44100); s->setTables(p.tables[0], p.tables[1]); s->setParams(p.voice, p.routes); s->setFX(p.fx);
            std::vector<float> L(8192), R(8192); s->noteOn(72, 0.8f); s->renderPlanar(L.data(), R.data(), 8192); s->noteOff(72);
            double m = 0; for (float x : L) m += x * x; e.push_back(m);
        }
        check(e[0] == e[1] && e[1] == e[2], "HQ notes after a Reset render identically");
    }
    // ---- Preset line ----
    {
        Preset p = factoryPresets()[5]; p.voice.oscQuality = 1;
        const std::string t = p.serialize();
        check(t.find("\noscq 1\n") != std::string::npos, "HQ writes an `oscq 1` line");
        Preset q; check(q.parse(t) && q.voice.oscQuality == 1 && q == p, "oscq round-trips");
        const std::string t0 = factoryPresets()[5].serialize();
        check(t0.find("oscq") == std::string::npos, "STANDARD writes no oscq line (0.29 presets stay byte-identical)");
        bool allStd = true; for (const auto& fp : factoryPresets()) allStd &= fp.voice.oscQuality == 0;
        check(allStd, "factory presets stay STANDARD");
    }
    if (g_fail) { printf("%d FAILED\n", g_fail); return 1; }
    printf("ALL HQ30 TESTS PASSED\n");
}
