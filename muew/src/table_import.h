#pragma once
// 0.20.0 wavetable import and spectral morph.
//  - decodeAudio: PCM/float WAV and AIFF/AIFC (NONE, sowt, fl32) to mono.
//  - detectPeriod: YIN-style cumulative-mean-normalized difference, so pitched
//    audio of any length and pitch can be sliced one cycle at a time.
//  - importAudio: 2048-sample wavetable layouts keep the 0.9.0 per-cycle
//    import; pitched audio is sliced pitch-synchronously into up to 64 frames
//    spread over the file, each band-limited to 256 samples, DC-free,
//    normalized and phase-aligned on the fundamental so frames crossfade
//    without cancelling. Anything else is a single cycle, as before.
//  - spectralMorph: rebuilds a table as N frames by interpolating each
//    harmonic's magnitude and phase between the key frames.
#include "custom_table.h"
#include <algorithm>
#include <cmath>
#include <complex>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

namespace muew {

// Mono samples plus sample rate; returns false when the file is not a supported format.
inline bool decodeAudio(const std::vector<unsigned char>& d, std::vector<float>& mono, double& rate) {
    mono.clear(); rate = 44100;
    if (d.size() < 12) return false;
    const std::string riff(d.begin(), d.begin() + 4), kind(d.begin() + 8, d.begin() + 12);
    auto le16 = [&](size_t o) { return (unsigned)d[o] | ((unsigned)d[o + 1] << 8); };
    auto le32 = [&](size_t o) { return le16(o) | (le16(o + 2) << 16); };
    auto be16 = [&](size_t o) { return ((unsigned)d[o] << 8) | (unsigned)d[o + 1]; };
    auto be32 = [&](size_t o) { return (be16(o) << 16) | be16(o + 2); };
    int fmt = 0, ch = 0, bits = 0; size_t data = 0, dataLen = 0; bool big = false;
    if (riff == "RIFF" && kind == "WAVE") {
        for (size_t o = 12; o + 8 <= d.size();) {
            std::string id(d.begin() + o, d.begin() + o + 4);
            size_t len = le32(o + 4);
            if (id == "fmt " && o + 24 <= d.size()) {
                fmt = (int)le16(o + 8); ch = (int)le16(o + 10); rate = le32(o + 12); bits = (int)le16(o + 22);
                if (fmt == 0xFFFE && o + 34 <= d.size()) fmt = (int)le16(o + 32);
            } else if (id == "data") { data = o + 8; dataLen = std::min(len, d.size() - data); }
            o += 8 + len + (len & 1);
        }
    } else if (riff == "FORM" && (kind == "AIFF" || kind == "AIFC")) {
        big = true; fmt = 1;
        for (size_t o = 12; o + 8 <= d.size();) {
            std::string id(d.begin() + o, d.begin() + o + 4);
            size_t len = be32(o + 4);
            if (id == "COMM" && o + 26 <= d.size()) {
                ch = (int)be16(o + 8); bits = (int)be16(o + 14);
                // 80-bit extended sample rate
                int ex = (int)(be16(o + 16) & 0x7FFF) - 16383;
                uint64_t mant = 0; for (int i = 0; i < 8; ++i) mant = (mant << 8) | d[o + 18 + i];
                rate = std::ldexp((double)mant, ex - 63);
                if (kind == "AIFC" && o + 30 <= d.size()) {
                    std::string comp(d.begin() + o + 26, d.begin() + o + 30);
                    if (comp == "sowt") big = false;
                    else if (comp == "fl32" || comp == "FL32") fmt = 3;
                    else if (comp != "NONE") return false;
                }
            } else if (id == "SSND" && o + 16 <= d.size()) {
                size_t off = be32(o + 8);
                data = o + 16 + off; dataLen = data < d.size() ? std::min(len - 8 - off, d.size() - data) : 0;
            }
            o += 8 + len + (len & 1);
        }
    } else return false;
    if (!data || ch < 1 || !(fmt == 1 || fmt == 3) || !(bits == 8 || bits == 16 || bits == 24 || bits == 32)) return false;
    if (fmt == 3 && bits != 32) return false;
    if (!(rate > 1000 && rate < 1e6)) rate = 44100;
    const int bps = bits / 8;
    const size_t n = dataLen / (size_t)(bps * ch);
    if (n < 8) return false;
    mono.resize(n);
    for (size_t i = 0; i < n; ++i) {
        double acc = 0;
        for (int c = 0; c < ch; ++c) {
            const size_t o = data + (i * ch + c) * bps;
            uint32_t u = 0;
            for (int b = 0; b < bps; ++b) u |= (uint32_t)d[o + (big ? bps - 1 - b : b)] << (8 * b);
            double v;
            if (fmt == 3) { float fv; std::memcpy(&fv, &u, 4); v = std::isfinite(fv) ? fv : 0.0; }
            else if (bits == 8) v = big ? (int8_t)u / 128.0 : ((int)u - 128) / 128.0; // WAV 8-bit is unsigned
            else { int sh = 32 - bits; v = (double)((int32_t)(u << sh) >> sh) / std::ldexp(1.0, bits - 1); }
            acc += v;
        }
        mono[i] = (float)(acc / ch);
    }
    return true;
}

// Fundamental period in samples (fractional) of x[start, start+win), or 0 when unpitched.
inline double detectPeriod(const std::vector<float>& x, size_t start, size_t win, double rate) {
    const int minP = std::max(8, (int)(rate / 2000.0)), maxP = (int)std::min<double>(rate / 30.0, win / 2.0);
    if (start + win > x.size() || maxP <= minP + 2) return 0;
    std::vector<double> dd(maxP + 2, 0.0);
    const size_t W = win - maxP - 1;
    for (int tau = 1; tau <= maxP + 1; ++tau) {
        double s = 0;
        for (size_t i = 0; i < W; ++i) { double e = (double)x[start + i] - x[start + i + tau]; s += e * e; }
        dd[tau] = s;
    }
    std::vector<double> cm(maxP + 2, 1.0);
    double run = 0;
    for (int tau = 1; tau <= maxP + 1; ++tau) { run += dd[tau]; cm[tau] = run > 0 ? dd[tau] * tau / run : 1.0; }
    int best = 0;
    for (int tau = minP; tau <= maxP; ++tau)
        if (cm[tau] < 0.15) { while (tau + 1 <= maxP && cm[tau + 1] < cm[tau]) ++tau; best = tau; break; }
    if (!best) { // no dip under the threshold: take the global minimum if it is clearly periodic
        double m = 1e9; for (int tau = minP; tau <= maxP; ++tau) if (cm[tau] < m) { m = cm[tau]; best = tau; }
        if (m > 0.3) return 0;
    }
    const double a = cm[best - 1], b = cm[best], c = cm[best + 1], den = a - 2 * b + c; // parabolic refine
    return best + (std::fabs(den) > 1e-12 ? 0.5 * (a - c) / den : 0.0);
}

// One cycle starting at fractional sample s with fractional period P -> a 256-sample band-limited frame.
inline Frame frameFromCycle(const std::vector<float>& x, double s, double P) {
    const int M = 2048; // resample the cycle to M points (cubic), then keep 127 harmonics
    std::vector<std::complex<double>> big(M);
    auto at = [&](double pos) {
        long i = (long)std::floor(pos); double t = pos - i;
        auto g = [&](long k) { k = std::clamp<long>(k, 0, (long)x.size() - 1); return (double)x[k]; };
        double y0 = g(i - 1), y1 = g(i), y2 = g(i + 1), y3 = g(i + 2);
        return y1 + 0.5 * t * (y2 - y0 + t * (2 * y0 - 5 * y1 + 4 * y2 - y3 + t * (3 * (y1 - y2) + y3 - y0)));
    };
    for (int i = 0; i < M; ++i) big[i] = {at(s + P * i / M), 0.0};
    fft(big, false);
    std::vector<std::complex<double>> spec(kFrameSize);
    const double g = (double)kFrameSize / M;
    for (int k = 1; k < kFrameSize / 2; ++k) { spec[k] = big[k] * g; spec[kFrameSize - k] = std::conj(spec[k]); }
    fft(spec, true);
    Frame f(kFrameSize);
    for (int i = 0; i < kFrameSize; ++i) f[i] = (float)spec[i].real();
    normalizeFrame(f);
    return f;
}

// Rotates a frame in time so its fundamental starts at phase `phi` (sine phase 0 by default).
inline void alignFundamental(Frame& f, double phi = -M_PI / 2) {
    auto s = frameSpectrum(f);
    if (std::abs(s[1]) < 1e-9) return;
    const double shift = phi - std::arg(s[1]);
    for (int k = 1; k < kFrameSize / 2; ++k) { s[k] *= std::polar(1.0, shift * k); s[kFrameSize - k] = std::conj(s[k]); }
    s[0] = 0; s[kFrameSize / 2] = 0;
    fft(s, true);
    for (int i = 0; i < kFrameSize; ++i) f[i] = (float)s[i].real();
    normalizeFrame(f);
}

struct ImportInfo { int frames = 0; double period = 0; bool pitched = false; bool layout2048 = false; };

inline TableFrames importAudio(const std::vector<unsigned char>& d, ImportInfo* info = nullptr, int maxFrames = kMaxFrames) {
    std::vector<float> x; double rate = 44100;
    if (!decodeAudio(d, x, rate)) return {};
    ImportInfo inf;
    TableFrames out;
    const size_t C = Wavetable::kTableSize;
    maxFrames = std::clamp(maxFrames, 1, kMaxFrames);
    if (x.size() >= C && x.size() % C == 0) { // wavetable layout: one frame per 2048-sample cycle (0.9.0 behaviour)
        inf.layout2048 = true;
        const size_t cycles = x.size() / C;
        const int keep = (int)std::min<size_t>(cycles, maxFrames);
        for (int k = 0; k < keep; ++k) {
            size_t c = keep == 1 ? 0 : (size_t)std::llround((double)k * (cycles - 1) / (keep - 1));
            out.push_back(frameFromCycle(x, (double)(c * C), (double)C));
        }
    } else {
        const size_t win = std::min<size_t>(x.size(), (size_t)(rate * 0.08) + 64);
        // Skip a quiet or noisy attack: find the first window that is clearly pitched.
        double P = 0; size_t first = 0;
        for (size_t s = 0; s + win <= x.size() && s < x.size() / 2; s += win / 2) {
            P = detectPeriod(x, s, win, rate);
            if (P > 0) { first = s; break; }
        }
        const double cycles = P > 0 ? (double)(x.size() - first) / P : 0;
        if (P > 0 && cycles >= 3) {
            inf.pitched = true; inf.period = P;
            const int keep = std::min(maxFrames, std::max(1, (int)std::floor(cycles) - 2));
            const double span = x.size() - first - 2 * P;
            for (int k = 0; k < keep; ++k) {
                double s = first + (keep == 1 ? 0 : span * k / (keep - 1));
                // local period: re-detect around s when there is room, else keep the global one
                double lp = P;
                if (s + win <= x.size()) { double q = detectPeriod(x, (size_t)s, win, rate); if (q > 0 && std::fabs(q - P) < 0.25 * P) lp = q; }
                Frame f = frameFromCycle(x, s, lp);
                alignFundamental(f);
                out.push_back(f);
            }
        } else {
            out.push_back(frameFromCycle(x, 0, (double)std::min<size_t>(x.size(), 8192)));
        }
    }
    inf.frames = (int)out.size();
    if (info) *info = inf;
    return out;
}

// N frames from the key frames spread evenly over the table: each harmonic's
// magnitude is interpolated linearly and its phase along the shorter arc, so
// frames never thin out mid-morph the way a plain crossfade does.
inline TableFrames spectralMorph(const TableFrames& keys, int N) {
    N = std::clamp(N, 1, kMaxFrames);
    if (keys.empty()) return {};
    if (keys.size() == 1) return TableFrames(N, keys[0]);
    std::vector<std::vector<std::complex<double>>> sp;
    for (const auto& f : keys) sp.push_back(frameSpectrum(f));
    const int K = (int)keys.size();
    TableFrames out;
    for (int j = 0; j < N; ++j) {
        const double pos = N == 1 ? 0 : (double)j * (K - 1) / (N - 1);
        const int a = std::min((int)pos, K - 2);
        const double t = pos - a;
        if (t < 1e-12) { out.push_back(keys[a]); continue; }
        if (t > 1 - 1e-12) { out.push_back(keys[a + 1]); continue; }
        std::vector<std::complex<double>> s(kFrameSize);
        for (int k = 1; k < kFrameSize / 2; ++k) {
            const auto& A = sp[a][k]; const auto& B = sp[a + 1][k];
            const double m = (1 - t) * std::abs(A) + t * std::abs(B);
            double pa = std::arg(A), pb = std::arg(B);
            if (std::abs(A) < 1e-9) pa = pb;
            if (std::abs(B) < 1e-9) pb = pa;
            double dp = std::remainder(pb - pa, 2 * M_PI);
            s[k] = std::polar(m, pa + t * dp);
            s[kFrameSize - k] = std::conj(s[k]);
        }
        fft(s, true);
        Frame f(kFrameSize);
        for (int i = 0; i < kFrameSize; ++i) f[i] = (float)s[i].real();
        normalizeFrame(f);
        out.push_back(f);
    }
    return out;
}

// MORPH button target: the next of 8/16/32/64 above the current count (64 re-spreads).
inline int morphTarget(int n) { for (int t : {8, 16, 32, 64}) if (t > n) return t; return kMaxFrames; }

} // namespace muew
