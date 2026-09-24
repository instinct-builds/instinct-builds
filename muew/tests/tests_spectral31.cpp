// MUEW 0.31.0 Spectral Wavetables: texture resynthesis of unpitched audio and
// the SPECTRAL page's whole-table processes (FORMANT, STRETCH, TILT, ODD/EVEN).
#include "../src/table_import.h"
#include "../src/spectral_process.h"
#include "../src/synth.h"
#include "../src/factory_bank.h"
#include <memory>
#include <cmath>
#include <cstdio>
#include <string>
#include <vector>
using namespace muew;

static int g_fail = 0;
static void check(bool c, const std::string& n) { printf("%s %s\n", c ? "ok:  " : "FAIL:", n.c_str()); if (!c) ++g_fail; }
static std::vector<unsigned char> wav16(const std::vector<float>& x, int rate) {
    std::vector<unsigned char> d;
    auto p32 = [&](uint32_t v) { for (int i = 0; i < 4; ++i) d.push_back((v >> (8 * i)) & 255); };
    auto p16 = [&](uint16_t v) { d.push_back(v & 255); d.push_back(v >> 8); };
    auto tag = [&](const char* t) { d.insert(d.end(), t, t + 4); };
    uint32_t bytes = (uint32_t)(x.size() * 2);
    tag("RIFF"); p32(36 + bytes); tag("WAVE"); tag("fmt "); p32(16); p16(1); p16(1); p32(rate); p32(rate * 2); p16(2); p16(16);
    tag("data"); p32(bytes);
    for (float v : x) p16((uint16_t)(int16_t)std::lround(std::clamp(v, -1.0f, 1.0f) * 32767));
    return d;
}
static double corr(const Frame& a, const Frame& b) { double ab = 0, aa = 0, bb = 0; for (int i = 0; i < kFrameSize; ++i) { ab += a[i] * b[i]; aa += a[i] * a[i]; bb += b[i] * b[i]; } return ab / std::sqrt(aa * bb + 1e-12); }
static double partial(const Frame& f, int k) { return std::abs(frameSpectrum(f)[k]); }

int main() {
    // ---- Texture resynthesis ----
    {
        // One second of noise whose low-pass closes from bright to dark.
        std::vector<float> x(44100); unsigned s = 7; double y = 0;
        for (size_t i = 0; i < x.size(); ++i) {
            s = s * 1664525u + 1013904223u; const double n = (s >> 8) / 8388608.0 - 1.0;
            const double a = 0.9 - 0.88 * i / x.size(); // one-pole coefficient: open -> closed
            y += a * (n - y); x[i] = (float)(0.8 * y / std::sqrt(a));
        }
        ImportInfo inf; TableFrames t = importAudio(wav16(x, 44100), &inf);
        printf("      texture: %d frames, centroid first %.1f last %.1f\n", inf.frames, frameCentroid(t.front()), frameCentroid(t.back()));
        check(inf.texture && !inf.pitched && inf.frames >= 16 && inf.frames <= kMaxFrames, "long unpitched audio imports as a texture table (16+ frames)");
        check(frameCentroid(t.front()) > 2.0 * frameCentroid(t.back()), "the table follows the file: bright frames first, dark frames last");
        double worst = 1; for (size_t k = 1; k < t.size(); ++k) worst = std::min(worst, corr(t[k - 1], t[k]));
        printf("      neighbour correlation min %.3f\n", worst);
        check(worst > 0.6, "neighbouring texture frames share phases, so WT POS sweeps morph instead of flickering");
        bool norm = true; for (const auto& f : t) { float pk = 0; double m = 0; for (float v : f) { pk = std::max(pk, std::fabs(v)); m += v; } norm &= std::fabs(pk - 1.0f) < 1e-4 && std::fabs(m) < 1e-3; }
        check(norm, "texture frames are normalized and DC-free");
        std::vector<float> shortNoise(x.begin(), x.begin() + 6000);
        ImportInfo si; TableFrames st = importAudio(wav16(shortNoise, 44100), &si);
        check(!si.texture && st.size() == 1, "short unpitched audio still imports one cycle (0.20 behaviour)");
        std::vector<float> tone(22050); for (size_t i = 0; i < tone.size(); ++i) tone[i] = (float)(0.7 * std::sin(2 * M_PI * 220.0 * i / 44100.0) + 0.2 * std::sin(2 * M_PI * 660.0 * i / 44100.0));
        ImportInfo ti; importAudio(wav16(tone, 44100), &ti);
        check(ti.pitched && !ti.texture, "pitched audio keeps the pitch-synchronous import");
    }
    // ---- Spectral processes ----
    {
        Frame saw = shapeFrame(2);
        const double c0 = frameCentroid(saw);
        // A vowel-like frame: partials under one resonance at partial 8.
        Frame vow(kFrameSize, 0.0f);
        for (int k = 1; k < 60; ++k) { const double a = std::exp(-0.5 * std::pow((k - 8) / 2.5, 2)) + 0.02 / k; for (int i = 0; i < kFrameSize; ++i) vow[i] += (float)(a * std::sin(2 * M_PI * k * i / kFrameSize)); }
        normalizeFrame(vow);
        auto peak = [&](const Frame& f) { int b = 1; double m = 0; for (int k = 1; k < 64; ++k) if (partial(f, k) > m) { m = partial(f, k); b = k; } return b; };
        check(processFrame(saw, SpectralProcess{}) == saw, "an untouched SPECTRAL page leaves frames bit-identical");
        SpectralProcess up; up.formantSt = 12; SpectralProcess dn; dn.formantSt = -12;
        const Frame fu = processFrame(vow, up), fd = processFrame(vow, dn);
        printf("      formant peak at partial %d, +12 -> %d, -12 -> %d\n", peak(vow), peak(fu), peak(fd));
        check(peak(vow) == 8 && peak(fu) == 16 && peak(fd) == 4, "FORMANT moves the resonance an octave up (partial 16) and down (partial 4)");
        check(partial(fu, 1) > 0 && partial(fd, 1) > 0, "FORMANT keeps the fundamental: the pitch does not move");
        SpectralProcess sp; sp.stretch = 0.3; SpectralProcess sq; sq.stretch = -0.3;
        check(frameCentroid(processFrame(saw, sp)) > c0 && frameCentroid(processFrame(saw, sq)) < c0, "STRETCH spreads partials up (+) or packs them down (-)");
        SpectralProcess tl; tl.tiltDb = -6; SpectralProcess th; th.tiltDb = 6;
        check(frameCentroid(processFrame(saw, tl)) < c0 && frameCentroid(processFrame(saw, th)) > c0, "TILT darkens (-dB/oct) and brightens (+dB/oct)");
        SpectralProcess odd; odd.oddEven = -1; SpectralProcess even; even.oddEven = 1;
        const Frame fo = processFrame(saw, odd), fe = processFrame(saw, even);
        double eo = 0, ee = 0; for (int k = 2; k < 40; k += 2) eo += partial(fo, k); for (int k = 1; k < 40; k += 2) ee += partial(fe, k);
        check(eo < 1e-6 * partial(fo, 1) && ee < 1e-6 * partial(fe, 2), "ODD/EVEN -1 keeps odd partials only, +1 even only");
        TableFrames tab{saw, shapeFrame(2), shapeFrame(3)};
        SpectralProcess all; all.formantSt = 5; all.stretch = 0.1; all.tiltDb = -3; all.oddEven = 0.3;
        const TableFrames pt = processTable(tab, all);
        bool ok = pt.size() == tab.size();
        for (const auto& f : pt) { float pk = 0; bool fin = true; for (float v : f) { pk = std::max(pk, std::fabs(v)); fin &= std::isfinite(v); } ok &= fin && std::fabs(pk - 1.0f) < 1e-4; }
        check(ok, "processTable keeps the frame count, finite and normalized");
    }
    // ---- HQ sub / noise alignment (0.30.0 known limit 1) ----
    {
        auto render = [&](int q, double sub, double noise) {
            Preset p = factoryPresets()[2]; p.routes.clear(); p.fx = FXParams{};
            p.voice.osc1Shape = 0; p.voice.osc2Level = 0; p.voice.osc1Unison = 1; p.voice.osc2Unison = 1;
            p.voice.filterCutoff = 20000; p.voice.filterReso = 0.1; p.voice.ampA = 0.001; p.voice.ampS = 1;
            p.voice.subLevel = sub; p.voice.noiseLevel = noise; p.voice.oscQuality = q;
            auto sy = std::make_unique<Synth>(); sy->init(44100); sy->setParams(p.voice, p.routes); sy->setFX(p.fx);
            std::vector<float> L(16384), R(16384); sy->noteOn(60, 0.8f); sy->renderPlanar(L.data(), R.data(), 16384); return L;
        };
        auto resid = [&](const std::vector<float>& hq, const std::vector<float>& st) { // HQ vs STANDARD delayed 7.5 samples
            double e = 0, r = 0; for (size_t i = 4096; i < hq.size(); ++i) { const double d = 0.5 * (st[i - 7] + st[i - 8]); e += (hq[i] - d) * (hq[i] - d); r += d * d; } return std::sqrt(e / r);
        };
        const double withSub = resid(render(1, 1.0, 0.0), render(0, 1.0, 0.0)), oscOnly = resid(render(1, 0.0, 0.0), render(0, 0.0, 0.0));
        printf("      HQ vs STANDARD+7.5: osc only %.4f, osc + sub %.4f\n", oscOnly, withSub);
        check(withSub < 0.01 && oscOnly < 0.01, "in HQ the sub oscillator lines up with the main oscillators (both 7.5 samples late)");
        const auto nz = render(1, 0.0, 0.5); bool fin = true; for (float v : nz) fin &= std::isfinite(v);
        check(fin, "HQ noise renders finite");
    }
    if (g_fail) { printf("%d FAILED\n", g_fail); return 1; }
    printf("ALL SPECTRAL31 TESTS PASSED\n");
}
