#pragma once
// MUEW 0.39.0: exact partial gain, preserving the phase and other harmonics.
#include "frame_range.h"
#include <algorithm>
#include <cmath>
#include <complex>
#include <vector>

namespace muew {
inline double partialLevelDb(const Frame& f, int harmonic) {
    if (harmonic < 1 || harmonic >= kFrameSize / 2) return -90;
    auto s = frameSpectrum(f);
    double peak = 0;
    for (int k = 1; k < kFrameSize / 2; ++k) peak = std::max(peak, std::abs(s[k]));
    const double m = std::abs(s[harmonic]);
    return peak > 1e-12 && m > 1e-12 ? std::max(-90.0, 20 * std::log10(m / peak)) : -90.0;
}
// A true gain relative to the current partial. Silent partials stay silent.
// Normalization follows the existing frame editor. Avoid doing any work when
// the edit is an identity so undo history stays meaningful.
inline bool gainPartial(Frame& f, int harmonic, double db) {
    if (f.size() != kFrameSize || harmonic < 1 || harmonic >= kFrameSize / 2 || !std::isfinite(db) || db == 0) return false;
    auto s = frameSpectrum(f);
    if (std::abs(s[harmonic]) < 1e-12) return false;
    const double g = std::pow(10.0, std::clamp(db, -48.0, 24.0) / 20.0);
    s[harmonic] *= g; s[kFrameSize - harmonic] = std::conj(s[harmonic]);
    s[0] = 0; s[kFrameSize / 2] = 0;
    fft(s, true);
    Frame next(kFrameSize); float peak = 0;
    for (int i = 0; i < kFrameSize; ++i) { next[i] = (float)s[i].real(); peak = std::max(peak, std::fabs(next[i])); }
    if (peak > 0) for (float& x : next) x /= peak;
    if (next == f) return false;
    f = std::move(next); return true;
}
inline bool gainPartialRange(TableFrames& table, const FrameRange& r, int harmonic, double db) {
    if (!r.active((int)table.size())) return false;
    bool changed = false;
    for (int i = r.first((int)table.size()); i <= r.last((int)table.size()); ++i)
        changed |= gainPartial(table[i], harmonic, db);
    return changed;
}
} // namespace muew
