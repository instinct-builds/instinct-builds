#pragma once
// User wavetables (0.9.0). A table is 1-64 (1-16 before 0.20.0) key frames of 256 samples each,
// drawn or built from harmonics in the editor, or imported from a WAV. For
// playback each frame is band-limited into the same per-octave mipmaps as the
// built-in shapes, and the WT POS control (0..1) crossfades through frames.
#include "wavetable_editor.h"
#include <algorithm>
#include <cmath>
#include <complex>
#include <cstdint>
#include <cstring>
#include <string>
#include <memory>
#include <vector>

namespace muew {

constexpr int kFrameSize = 256;
constexpr int kMaxFrames = 64; // 16 until 0.19.0; 0.20.0 import + morph fill up to 64
constexpr int kCustomShape = 5; // osc shape index that plays the oscillator's own table
using Frame = std::vector<float>;
using TableFrames = std::vector<Frame>; // empty = no table

// Harmonic spectrum (bins 0..kFrameSize/2-1) of a 256-sample frame.
inline std::vector<std::complex<double>> frameSpectrum(const Frame& f) {
    std::vector<std::complex<double>> s(kFrameSize);
    for (int i = 0; i < kFrameSize; ++i) s[i] = {i < (int)f.size() ? (double)f[i] : 0.0, 0.0};
    fft(s, false);
    return s;
}

// A frame resampled to Wavetable::kTableSize by harmonic (zero-padded FFT)
// interpolation, DC removed, so the drawn shape keeps its exact spectrum.
inline std::vector<float> upsampleFrame(const Frame& f) {
    const int N = Wavetable::kTableSize, H = kFrameSize / 2;
    auto s = frameSpectrum(f);
    std::vector<std::complex<double>> big(N);
    const double g = (double)N / kFrameSize;
    for (int k = 1; k < H; ++k) { big[k] = s[k] * g; big[N - k] = s[kFrameSize - k] * g; }
    fft(big, true);
    std::vector<float> out(N);
    for (int i = 0; i < N; ++i) out[i] = (float)big[i].real();
    return out;
}

// Harmonic amplitude 0..1 (relative to the loudest) of partials 1..n.
inline std::vector<double> frameHarmonics(const Frame& f, int n) {
    auto s = frameSpectrum(f);
    std::vector<double> a(n);
    double peak = 0;
    for (int k = 1; k <= n && k < kFrameSize / 2; ++k) { a[k - 1] = std::abs(s[k]); peak = std::max(peak, a[k - 1]); }
    if (peak > 0) for (auto& x : a) x /= peak;
    return a;
}

// Sets partial `h` (1-based) of a frame to amplitude `amp` (0..1 of the
// loudest partial) keeping its phase (sine phase if it was silent), then
// resynthesizes the frame and scales its peak to 1.
inline void setFrameHarmonic(Frame& f, int h, double amp) {
    if (h < 1 || h >= kFrameSize / 2) return;
    auto s = frameSpectrum(f);
    double peak = 0;
    for (int k = 1; k < kFrameSize / 2; ++k) peak = std::max(peak, std::abs(s[k]));
    if (peak <= 0) peak = kFrameSize / 2.0;
    std::complex<double> dir = std::abs(s[h]) > 1e-9 ? s[h] / std::abs(s[h]) : std::complex<double>(0, -1); // sine
    s[h] = dir * (amp * peak);
    s[kFrameSize - h] = std::conj(s[h]);
    s[0] = 0;
    fft(s, true);
    f.assign(kFrameSize, 0.0f);
    float pk = 0;
    for (int i = 0; i < kFrameSize; ++i) { f[i] = (float)s[i].real(); pk = std::max(pk, std::fabs(f[i])); }
    if (pk > 0) for (auto& x : f) x /= pk;
}

// Frame from a built-in shape (0-4), for seeding a new table.
inline Frame shapeFrame(int shape) {
    static const Wavetable w;
    Frame f(kFrameSize);
    int s = std::clamp(shape, 0, (int)Wavetable::Shape::Count - 1);
    for (int i = 0; i < kFrameSize; ++i) f[i] = w.sample(s, 3, (double)i / kFrameSize); // level 3: 128 harmonics
    return f;
}

// Playback form: [frame][level][sample], built once per edit and shared by voices.
class CustomTable {
public:
    explicit CustomTable(const TableFrames& frames) {
        for (const auto& f : frames) levels_.push_back(buildMipmapLevels(upsampleFrame(f)));
        if (levels_.empty()) levels_.push_back(buildMipmapLevels(upsampleFrame(shapeFrame(2))));
    }
    // 0.33.0 live spectral morph: a second table (same frame count) that
    // sample() crossfades toward by `morph`. The frames keep their phases
    // through the spectral process, so the crossfade moves each partial's
    // level from one setting to the other.
    CustomTable(const TableFrames& frames, const TableFrames& morphTarget) : CustomTable(frames) {
        if (morphTarget.size() == frames.size() && !frames.empty())
            for (const auto& f : morphTarget) morph_.push_back(buildMipmapLevels(upsampleFrame(f)));
    }
    bool hasMorph() const { return !morph_.empty(); }
    int frames() const { return (int)levels_.size(); }
    // pos 0..1 across frames, fractional mip level, phase 0..1.
    inline float sample(double pos, double level, double phase) const {
        const int F = (int)levels_.size();
        double fp = std::clamp(pos, 0.0, 1.0) * (F - 1);
        int f0 = (int)fp, f1 = std::min(f0 + 1, F - 1);
        float t = (float)(fp - f0);
        float a = at(levels_, f0, level, phase);
        return t > 0 ? a + t * (at(levels_, f1, level, phase) - a) : a;
    }
    // 0.33.0: with a morph amount above 0 and a morph table, blend toward it.
    inline float sample(double pos, double level, double phase, double morph) const {
        const float a = sample(pos, level, phase);
        if (morph <= 0.0 || morph_.empty()) return a;
        const int F = (int)morph_.size();
        double fp = std::clamp(pos, 0.0, 1.0) * (F - 1);
        int f0 = (int)fp, f1 = std::min(f0 + 1, F - 1);
        float t = (float)(fp - f0);
        float b = at(morph_, f0, level, phase);
        if (t > 0) b += t * (at(morph_, f1, level, phase) - b);
        const float m = (float)std::min(morph, 1.0);
        return a + m * (b - a);
    }

private:
    using Levels = std::vector<std::vector<std::vector<float>>>;
    static inline float at(const Levels& L, int f, double level, double phase) {
        if (level < 0) level = 0;
        int l0 = (int)level, l1 = std::min(l0 + 1, Wavetable::kNumLevels - 1);
        float lf = (float)(level - l0);
        return one(L[f][l0], phase) * (1.0f - lf) + one(L[f][l1], phase) * lf;
    }
    static inline float one(const std::vector<float>& t, double phase) {
        const int N = Wavetable::kTableSize;
        double pos = phase * N;
        int i0 = (int)pos & (N - 1), i1 = (i0 + 1) & (N - 1);
        float fr = (float)(pos - std::floor(pos));
        return t[i0] + fr * (t[i1] - t[i0]);
    }
    Levels levels_, morph_;
};

// ---- table editing (editor model) ----
// Crossfades every frame strictly between the first and last key frames.
inline void morphFill(TableFrames& t) {
    int n = (int)t.size();
    if (n < 3) return;
    for (int i = 1; i < n - 1; ++i) t[i] = WavetableEditor::morph(t[0], t[n - 1], (double)i / (n - 1));
}
inline void smoothFrame(Frame& f, int passes = 1) {
    for (int p = 0; p < passes; ++p) {
        Frame w = f;
        for (int i = 0; i < kFrameSize; ++i)
            f[i] = 0.25f * w[(i + kFrameSize - 1) % kFrameSize] + 0.5f * w[i] + 0.25f * w[(i + 1) % kFrameSize];
    }
}
inline void normalizeFrame(Frame& f) {
    double mean = 0; for (float x : f) mean += x; mean /= kFrameSize;
    float pk = 0; for (auto& x : f) { x -= (float)mean; pk = std::max(pk, std::fabs(x)); }
    if (pk > 0) for (auto& x : f) x /= pk;
}
// Freehand stroke from sample a to b (inclusive), values -1..1, linearly
// interpolated so fast mouse moves leave no gaps.
inline void drawStroke(Frame& f, int a, double va, int b, double vb) {
    if (a > b) { std::swap(a, b); std::swap(va, vb); }
    for (int i = std::max(a, 0); i <= std::min(b, kFrameSize - 1); ++i) {
        double t = b == a ? 1.0 : (double)(i - a) / (b - a);
        f[i] = (float)std::clamp(va + (vb - va) * t, -1.0, 1.0);
    }
}

// ---- WAV import/export ----
// Reads a PCM (16/24/32-bit) or float WAV, mixes to mono, and slices it into
// key frames: files that are a whole number of 2048-sample cycles (the usual
// wavetable layout) give one frame per cycle; anything shorter is one
// single-cycle frame. Each frame is resampled to 256 samples. Longer files
// keep at most kMaxFrames cycles, spread evenly. Returns empty on failure.
inline TableFrames importWav(const std::vector<unsigned char>& d) {
    auto u16 = [&](size_t o) { return (unsigned)d[o] | ((unsigned)d[o + 1] << 8); };
    auto u32 = [&](size_t o) { return u16(o) | (u16(o + 2) << 16); };
    if (d.size() < 44 || std::string(d.begin(), d.begin() + 4) != "RIFF" || std::string(d.begin() + 8, d.begin() + 12) != "WAVE") return {};
    int fmt = 0, ch = 0, bits = 0; size_t data = 0, dataLen = 0;
    for (size_t o = 12; o + 8 <= d.size();) {
        std::string id(d.begin() + o, d.begin() + o + 4);
        size_t len = u32(o + 4);
        if (id == "fmt " && o + 24 <= d.size()) { fmt = (int)u16(o + 8); ch = (int)u16(o + 10); bits = (int)u16(o + 22); if (fmt == 0xFFFE && o + 34 <= d.size()) fmt = (int)u16(o + 32); }
        else if (id == "data") { data = o + 8; dataLen = std::min(len, d.size() - data); }
        o += 8 + len + (len & 1);
    }
    if (!data || ch < 1 || !(fmt == 1 || fmt == 3) || !(bits == 16 || bits == 24 || bits == 32)) return {};
    const int bps = bits / 8;
    size_t frames = dataLen / (size_t)(bps * ch);
    if (frames < 8) return {};
    std::vector<float> mono(frames);
    for (size_t i = 0; i < frames; ++i) {
        double acc = 0;
        for (int c = 0; c < ch; ++c) {
            size_t o = data + (i * ch + c) * bps;
            double v;
            if (fmt == 3 && bits == 32) { uint32_t b = u32(o); float fv; std::memcpy(&fv, &b, 4); v = fv; }
            else if (bits == 16) v = (int16_t)u16(o) / 32768.0;
            else if (bits == 24) { int32_t x = (int32_t)((d[o] << 8) | (d[o + 1] << 16) | (d[o + 2] << 24)) >> 8; v = x / 8388608.0; }
            else v = (int32_t)u32(o) / 2147483648.0;
            acc += v;
        }
        mono[i] = (float)(acc / ch);
    }
    auto resample = [](const float* src, size_t n) { // one cycle of n samples -> 256, band-limited
        // Direct DFT of the cycle's first 127 harmonics, resynthesized at 256
        // points: exact for band-limited cycles, no aliasing for richer ones.
        std::vector<std::complex<double>> spec(kFrameSize);
        const int H = std::min<int>(kFrameSize / 2 - 1, (int)n / 2 - 1);
        for (int k = 1; k <= H; ++k) {
            std::complex<double> acc = 0, w = 1, step = std::polar(1.0, -2 * M_PI * k / (double)n);
            for (size_t i = 0; i < n; ++i) { acc += (double)src[i] * w; w *= step; }
            acc *= (double)kFrameSize / (double)n;
            spec[k] = acc; spec[kFrameSize - k] = std::conj(acc);
        }
        fft(spec, true);
        Frame f(kFrameSize);
        for (int i = 0; i < kFrameSize; ++i) f[i] = (float)spec[i].real();
        normalizeFrame(f);
        return f;
    };
    TableFrames out;
    const size_t C = Wavetable::kTableSize;
    if (frames >= C && frames % C == 0) {
        size_t cycles = frames / C;
        int keep = (int)std::min<size_t>(cycles, kMaxFrames);
        for (int k = 0; k < keep; ++k) {
            size_t c = keep == 1 ? 0 : (size_t)std::llround((double)k * (cycles - 1) / (keep - 1));
            out.push_back(resample(mono.data() + c * C, C));
        }
    } else {
        out.push_back(resample(mono.data(), std::min<size_t>(frames, 8192)));
    }
    return out;
}

// 32-bit float mono WAV, one 2048-sample cycle per frame (the common layout).
inline std::vector<unsigned char> exportWav(const TableFrames& t) {
    std::vector<float> s;
    for (const auto& f : t) { auto u = upsampleFrame(f); float pk = 0; for (float x : u) pk = std::max(pk, std::fabs(x)); for (float x : u) s.push_back(pk > 0 ? x / pk : 0); }
    std::vector<unsigned char> d;
    auto put32 = [&](uint32_t v) { for (int i = 0; i < 4; ++i) d.push_back((v >> (8 * i)) & 255); };
    auto put16 = [&](uint16_t v) { d.push_back(v & 255); d.push_back(v >> 8); };
    auto tag = [&](const char* t4) { d.insert(d.end(), t4, t4 + 4); };
    uint32_t bytes = (uint32_t)(s.size() * 4);
    tag("RIFF"); put32(36 + bytes); tag("WAVE"); tag("fmt "); put32(16); put16(3); put16(1); put32(44100); put32(44100 * 4); put16(4); put16(32);
    tag("data"); put32(bytes);
    for (float x : s) { uint32_t b; std::memcpy(&b, &x, 4); put32(b); }
    return d;
}

} // namespace muew
