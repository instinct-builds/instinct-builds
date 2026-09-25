#pragma once
// MUEW 0.40.0: 127 addressable harmonics in four legible 32-bin pages.
#include "partial_edit.h"
#include <algorithm>
#include <cmath>
#include <complex>
namespace muew {
constexpr int kEditablePartials = kFrameSize / 2 - 1;
constexpr int kPartialPageSize = 32;
inline int partialPageStart(int page) { return std::clamp(page, 0, 3) * kPartialPageSize + 1; }
inline int partialPageEnd(int page) { return std::min(kEditablePartials, partialPageStart(page) + kPartialPageSize - 1); }
inline int partialPageFor(int harmonic) { return std::clamp((harmonic - 1) / kPartialPageSize, 0, 3); }

// Explicitly add a silent harmonic at -24 dB relative to the frame's strongest
// existing partial. Pure silence has no reference level and stays silent.
// One selected partial, no synthesized DC or Nyquist; sine phase is predictable.
inline bool seedPartial(Frame& f, int harmonic, double relativeDb = -24.0) {
    if (f.size() != kFrameSize || harmonic < 1 || harmonic > kEditablePartials || !std::isfinite(relativeDb)) return false;
    auto s = frameSpectrum(f);
    double peak = 0;
    for (int k = 1; k <= kEditablePartials; ++k) peak = std::max(peak, std::abs(s[k]));
    if (peak < 1e-12 || std::abs(s[harmonic]) >= peak * 1e-7) return false;
    s[harmonic] = std::complex<double>(0, -peak * std::pow(10.0, std::clamp(relativeDb, -60.0, -6.0) / 20.0));
    s[kFrameSize - harmonic] = std::conj(s[harmonic]); s[0] = 0; s[kFrameSize/2] = 0;
    fft(s, true);
    Frame next(kFrameSize); float mx = 0;
    for (int i = 0; i < kFrameSize; ++i) { next[i] = (float)s[i].real(); mx = std::max(mx, std::fabs(next[i])); }
    if (mx > 0) for (float& x : next) x /= mx;
    f = std::move(next); return true;
}
inline bool seedPartialRange(TableFrames& t, const FrameRange& range, int harmonic) {
    if (!range.active((int)t.size())) return false;
    bool changed = false;
    for (int i = range.first((int)t.size()); i <= range.last((int)t.size()); ++i) changed |= seedPartial(t[i], harmonic);
    return changed;
}
} // namespace muew
