// 0.20.0: WAV/AIFF decode, pitch detection, pitch-synchronous import, spectral morph.
#include "../src/table_import.h"
#include "../src/preset.h"
#include <cstdio>
#include <cmath>
using namespace muew;
static int g_fail = 0;
static void check(bool ok, const char* what) { printf("%s %s\n", ok ? "ok  " : "FAIL", what); if (!ok) g_fail = 1; }

// Band-limited saw whose brightness rises over the file: harmonic k weighted by
// 1/k up to a cutoff that sweeps 2 -> 40 harmonics.
static std::vector<float> sweepSaw(double hz, double secs, double rate) {
    size_t n = (size_t)(secs * rate);
    std::vector<float> x(n);
    double ph = 0;
    for (size_t i = 0; i < n; ++i) {
        double prog = (double)i / n, nh = 2 + 38 * prog, s = 0;
        for (int k = 1; k <= 40; ++k) { double w = std::clamp(nh - k + 1, 0.0, 1.0); if (w > 0) s += w * std::sin(ph * k) / k; }
        x[i] = (float)(0.5 * s);
        ph += 2 * M_PI * hz / rate;
    }
    return x;
}
static void putBE(std::vector<unsigned char>& d, uint32_t v, int n) { for (int i = n - 1; i >= 0; --i) d.push_back((v >> (8 * i)) & 255); }
static std::vector<unsigned char> aiff16(const std::vector<float>& x, double rate) {
    std::vector<unsigned char> d;
    auto tag = [&](const char* t) { d.insert(d.end(), t, t + 4); };
    uint32_t bytes = (uint32_t)x.size() * 2;
    tag("FORM"); putBE(d, 4 + 26 + 16 + bytes, 4); tag("AIFF");
    tag("COMM"); putBE(d, 18, 4); putBE(d, 1, 2); putBE(d, (uint32_t)x.size(), 4); putBE(d, 16, 2);
    int e; double m = std::frexp(rate, &e); // rate = m * 2^e, m in [0.5,1)
    uint64_t mant = (uint64_t)std::ldexp(m, 64);
    putBE(d, (uint32_t)(e - 1 + 16383), 2); putBE(d, (uint32_t)(mant >> 32), 4); putBE(d, (uint32_t)mant, 4);
    tag("SSND"); putBE(d, 8 + bytes, 4); putBE(d, 0, 4); putBE(d, 0, 4);
    for (float v : x) putBE(d, (uint16_t)(int16_t)std::lround(std::clamp(v, -1.0f, 1.0f) * 32767), 2);
    return d;
}
static std::vector<unsigned char> wav16(const std::vector<float>& x, int rate, int ch = 1) {
    std::vector<unsigned char> d;
    auto p32 = [&](uint32_t v) { for (int i = 0; i < 4; ++i) d.push_back((v >> (8 * i)) & 255); };
    auto p16 = [&](uint16_t v) { d.push_back(v & 255); d.push_back(v >> 8); };
    auto tag = [&](const char* t) { d.insert(d.end(), t, t + 4); };
    uint32_t bytes = (uint32_t)(x.size() * 2 * ch);
    tag("RIFF"); p32(36 + bytes); tag("WAVE"); tag("fmt "); p32(16); p16(1); p16(ch); p32(rate); p32(rate * 2 * ch); p16(2 * ch); p16(16);
    tag("data"); p32(bytes);
    for (float v : x) for (int c = 0; c < ch; ++c) p16((uint16_t)(int16_t)std::lround(std::clamp(v, -1.0f, 1.0f) * 32767));
    return d;
}
static double hiShare(const Frame& f) { // energy share above harmonic 8
    auto s = frameSpectrum(f); double lo = 0, hi = 0;
    for (int k = 1; k < kFrameSize / 2; ++k) (k <= 8 ? lo : hi) += std::norm(s[k]);
    return hi / (lo + hi + 1e-12);
}

int main() {
    const double rate = 48000, hz = 146.83; // period 326.9 samples: not a 2048 layout
    auto x = sweepSaw(hz, 1.5, rate);
    {
        std::vector<float> m; double r = 0;
        check(decodeAudio(aiff16(x, rate), m, r) && m.size() == x.size() && std::fabs(r - rate) < 1e-6, "AIFF 16-bit decodes with its 80-bit sample rate");
        double err = 0; for (size_t i = 0; i < m.size(); i += 97) err = std::max(err, (double)std::fabs(m[i] - x[i]));
        check(err < 1e-4, "AIFF samples decode big-endian");
        check(decodeAudio(wav16(x, 44100, 2), m, r) && m.size() == x.size() && r == 44100, "stereo WAV decodes to mono with its rate");
        check(!decodeAudio(std::vector<unsigned char>(64, 7), m, r), "junk decodes to nothing");
    }
    {
        double P = detectPeriod(x, 20000, 4000, rate);
        check(std::fabs(P - rate / hz) < 0.2, "YIN period is within 0.2 samples of 326.9");
        std::vector<float> noise(20000); unsigned s = 1; for (auto& v : noise) { s = s * 1664525u + 1013904223u; v = (float)((s >> 8) / 8388608.0 - 1.0); }
        check(detectPeriod(noise, 0, 4000, rate) == 0, "white noise reads as unpitched");
    }
    {
        ImportInfo info;
        auto t = importAudio(aiff16(x, rate), &info);
        check(info.pitched && t.size() == 64 && info.frames == 64, "pitched AIFF imports as 64 pitch-synchronous frames");
        check(hiShare(t[63]) > hiShare(t[48]) && hiShare(t[48]) > hiShare(t[32]) + 0.005 && hiShare(t[32]) > hiShare(t[16]) + 0.01 && hiShare(t[16]) > hiShare(t[0]) + 0.01, "frames follow the brightness sweep");
        bool aligned = true, dc = true, norm = true;
        for (const auto& f : t) {
            auto s = frameSpectrum(f);
            if (std::fabs(std::remainder(std::arg(s[1]) + M_PI / 2, 2 * M_PI)) > 1e-3) aligned = false;
            double mean = 0, pk = 0; for (float v : f) { mean += v; pk = std::max(pk, (double)std::fabs(v)); }
            if (std::fabs(mean / kFrameSize) > 1e-4) dc = false;
            if (std::fabs(pk - 1) > 1e-4) norm = false;
        }
        check(aligned, "every frame's fundamental is phase-aligned");
        check(dc && norm, "frames are DC-free and peak-normalized");
        // Neighbouring aligned frames correlate strongly (no cancellation on crossfade).
        double worst = 1;
        for (int i = 0; i + 1 < 64; ++i) {
            double ab = 0, aa = 0, bb = 0;
            for (int k = 0; k < kFrameSize; ++k) { ab += t[i][k] * t[i + 1][k]; aa += t[i][k] * t[i][k]; bb += t[i + 1][k] * t[i + 1][k]; }
            worst = std::min(worst, ab / std::sqrt(aa * bb));
        }
        check(worst > 0.9, "neighbouring frames correlate above 0.9");
        auto few = importAudio(wav16(std::vector<float>(x.begin(), x.begin() + 1600), 48000), &info);
        check(info.pitched && few.size() == 2, "a short pitched clip keeps only whole interior cycles");
        auto cap = importAudio(aiff16(x, rate), &info, 12);
        check(cap.size() == 12, "import honours a smaller frame cap");
    }
    {   // 2048-sample layout keeps the 0.9.0 per-cycle import
        std::vector<float> lay(2048 * 3);
        for (int c = 0; c < 3; ++c) for (int i = 0; i < 2048; ++i) lay[c * 2048 + i] = (float)std::sin(2 * M_PI * (c + 1) * i / 2048.0) * 0.8f;
        ImportInfo info;
        auto t = importAudio(wav16(lay, 44100), &info);
        auto old = importWav(wav16(lay, 44100));
        bool same = t.size() == 3 && old.size() == 3;
        for (int c = 0; c < 3 && same; ++c) for (int i = 0; i < kFrameSize; ++i) if (std::fabs(t[c][i] - old[c][i]) > 2e-3) { same = false; break; }
        check(info.layout2048 && same, "2048-sample wavetable files import exactly like 0.9.0");
    }
    {   // spectral morph
        Frame a(kFrameSize), b(kFrameSize);
        for (int i = 0; i < kFrameSize; ++i) { a[i] = (float)std::sin(2 * M_PI * i / kFrameSize); b[i] = -a[i]; }
        auto m = spectralMorph({a, b}, 3);
        double pk = 0; for (float v : m[1]) pk = std::max(pk, (double)std::fabs(v));
        auto mid = frameSpectrum(m[1]);
        check(m.size() == 3 && m[0] == a && m[2] == b, "spectral morph keeps the key frames at the ends");
        check(pk > 0.99 && std::abs(mid[1]) > 100, "phase-opposed keys morph through a full-level frame (a crossfade would be silent)");
        Frame c = shapeFrame(2), s = shapeFrame(0);
        auto m16 = spectralMorph({s, c}, 16);
        double prev = -1; bool mono = true;
        for (const auto& f : m16) { double h = hiShare(f); if (h < prev - 1e-6) mono = false; prev = h; }
        check(m16.size() == 16 && mono, "SINE -> SAW morph brightens monotonically over 16 frames");
        auto three = spectralMorph({s, c, s}, 5);
        check(three.size() == 5 && three[2] == c && three[4] == s, "three keys land on frames 1, 3 and 5");
        check(morphTarget(2) == 8 && morphTarget(8) == 16 && morphTarget(40) == 64 && morphTarget(64) == 64, "MORPH targets 8/16/32/64");
    }
    {   // presets carry up to 64 frames now
        Preset p; p.tables[0] = TableFrames(64, shapeFrame(1));
        Preset q; check(q.parse(p.serialize()) && q.tables[0].size() == 64, "a 64-frame table survives preset save and load");
    }
    printf(g_fail ? "FAILED\n" : "ALL PASS\n");
    return g_fail;
}
