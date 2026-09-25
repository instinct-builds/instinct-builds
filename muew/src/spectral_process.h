#pragma once
// 0.31.0 Spectral Wavetables: whole-table spectral processes for the WT
// editor's SPECTRAL page, applied to every frame's harmonic spectrum
// (partials 1..127 of a 256-sample frame), then re-normalized.
//  - FORMANT: moves the spectral envelope up or down (+-24 semitones) while
//    the partials stay on their harmonic slots, so the pitch does not move.
//  - STRETCH: remaps partial k to k^(1+s) (s -0.5..0.5), splitting its energy
//    between the two nearest harmonic slots - a brighter/sparser or darker/
//    denser spread that stays periodic.
//  - TILT: dB per octave (-12..12) around the fundamental.
//  - ODD/EVEN: -1 = odd partials only (hollow) .. +1 = even partials only (octave-up).
#include "custom_table.h"
#include <algorithm>
#include <cmath>
#include <complex>
#include <vector>

namespace muew {

struct SpectralProcess {
    double formantSt = 0.0; // -24..24 semitones
    double stretch = 0.0;   // -0.5..0.5
    double tiltDb = 0.0;    // -12..12 dB / octave
    double oddEven = 0.0;   // -1..1
    bool isIdentity() const { return formantSt == 0.0 && stretch == 0.0 && tiltDb == 0.0 && oddEven == 0.0; }
    bool operator==(const SpectralProcess& o) const { return formantSt == o.formantSt && stretch == o.stretch && tiltDb == o.tiltDb && oddEven == o.oddEven; }
    bool operator!=(const SpectralProcess& o) const { return !(*this == o); }
};

inline Frame processFrame(const Frame& f, const SpectralProcess& sp) {
    if (sp.isIdentity()) return f;
    constexpr int H = kFrameSize / 2; // partials 1..H-1
    auto s = frameSpectrum(f);
    std::vector<double> mag(H, 0.0), ph(H, -M_PI / 2);
    for (int k = 1; k < H; ++k) { mag[k] = std::abs(s[k]); if (mag[k] > 1e-12) ph[k] = std::arg(s[k]); }
    // Envelope sampled at a fractional partial number (linear between partials).
    auto env = [&](const std::vector<double>& m, double k) {
        if (k < 1.0) return m[1]; // below the fundamental: hold it, so the pitch never drops out
        const int i = (int)std::floor(k); if (i >= H - 1) return i == H - 1 ? m[H - 1] : 0.0;
        const double t = k - i; return m[i] + t * (m[i + 1] - m[i]);
    };
    std::vector<double> m = mag;
    if (sp.formantSt != 0.0) {
        const double r = std::pow(2.0, std::clamp(sp.formantSt, -24.0, 24.0) / 12.0);
        for (int k = 1; k < H; ++k) m[k] = env(mag, k / r);
    }
    if (sp.stretch != 0.0) {
        const double e = 1.0 + std::clamp(sp.stretch, -0.5, 0.5);
        std::vector<double> pw(H, 0.0); // energy, so a split partial keeps its power
        for (int k = 1; k < H; ++k) {
            const double j = std::pow((double)k, e); const int a = (int)std::floor(j); const double t = j - a;
            if (a >= 1 && a < H) pw[a] += m[k] * m[k] * (1.0 - t);
            if (a + 1 >= 1 && a + 1 < H) pw[a + 1] += m[k] * m[k] * t;
        }
        for (int k = 1; k < H; ++k) m[k] = std::sqrt(pw[k]);
    }
    if (sp.tiltDb != 0.0) {
        const double t = std::clamp(sp.tiltDb, -12.0, 12.0);
        for (int k = 1; k < H; ++k) m[k] *= std::pow(10.0, t * std::log2((double)k) / 20.0);
    }
    if (sp.oddEven != 0.0) {
        const double b = std::clamp(sp.oddEven, -1.0, 1.0);
        const double odd = std::min(1.0, 1.0 - b), even = std::min(1.0, 1.0 + b);
        for (int k = 1; k < H; ++k) m[k] *= (k % 2) ? odd : even;
    }
    std::vector<std::complex<double>> out(kFrameSize);
    for (int k = 1; k < H; ++k) { out[k] = std::polar(m[k], ph[k]); out[kFrameSize - k] = std::conj(out[k]); }
    fft(out, true);
    Frame g(kFrameSize);
    for (int i = 0; i < kFrameSize; ++i) g[i] = (float)out[i].real();
    normalizeFrame(g);
    return g;
}

inline TableFrames processTable(const TableFrames& t, const SpectralProcess& sp) {
    TableFrames out; out.reserve(t.size());
    for (const auto& f : t) out.push_back(processFrame(f, sp));
    return out;
}

// Spectral centroid in partials (1 = all energy in the fundamental): tests and the SPECTRAL page readout.
inline double frameCentroid(const Frame& f) {
    auto s = frameSpectrum(f); double num = 0, den = 0;
    for (int k = 1; k < kFrameSize / 2; ++k) { const double p = std::norm(s[k]); num += k * p; den += p; }
    return den > 0 ? num / den : 0.0;
}

} // namespace muew
