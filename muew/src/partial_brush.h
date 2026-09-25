#pragma once
// MUEW 0.41.0: one gesture's absolute dB targets, replayed from its original
// table on each mouse move so a brush never compounds gain accidentally.
#include "partial_view.h"
#include <array>
#include <limits>
namespace muew {
struct PartialBrush {
    std::array<double, kEditablePartials + 1> targetDb{};
    PartialBrush() { clear(); }
    void clear() { targetDb.fill(std::numeric_limits<double>::quiet_NaN()); }
    bool hasEdits() const { for (int h = 1; h <= kEditablePartials; ++h) if (std::isfinite(targetDb[h])) return true; return false; }
    void paint(int harmonic, double db) {
        if (harmonic >= 1 && harmonic <= kEditablePartials && std::isfinite(db))
            targetDb[harmonic] = std::clamp(db, -48.0, 12.0);
    }
    // Fill bars skipped by a fast mouse movement; a page switch is handled
    // separately by the UI and never invents bins between distant pages.
    void line(int a, double da, int b, double db) {
        if (a < 1 || b < 1 || a > kEditablePartials || b > kEditablePartials) return;
        if (a == b) { paint(b, db); return; }
        const int lo = std::min(a, b), hi = std::max(a, b);
        for (int h = lo; h <= hi; ++h) paint(h, da + (db - da) * (h - a) / (double)(b - a));
    }
};
// A full edge taper is zero at both ends, one at the central frame(s).
// Zero taper keeps the original uniform range behavior.
inline double brushRangeStrength(int index, const FrameRange& range, int count, double taper) {
    if (!range.active(count) || !range.contains(index, count)) return 1.0;
    const int a = range.first(count), b = range.last(count), n = b - a + 1;
    if (n < 3) return 1.0;
    const double midpoint = (n - 1) / 2.0;
    const double edgeDistance = std::max(0.0, std::abs(index - a - midpoint) - (n % 2 == 0 ? 0.5 : 0.0));
    const double radius = midpoint - (n % 2 == 0 ? 0.5 : 0.0);
    return 1.0 - std::clamp(taper, 0.0, 1.0) * std::clamp(edgeDistance / radius, 0.0, 1.0);
}
inline bool applyBrushFrame(Frame& f, const PartialBrush& brush, double strength = 1.0) {
    if (f.size() != kFrameSize || !brush.hasEdits() || strength <= 0) return false;
    strength = std::clamp(strength, 0.0, 1.0);
    auto s = frameSpectrum(f);
    double peak = 0;
    for (int h = 1; h <= kEditablePartials; ++h) peak = std::max(peak, std::abs(s[h]));
    if (peak < 1e-12) return false;
    bool changed = false;
    for (int h = 1; h <= kEditablePartials; ++h) {
        if (!std::isfinite(brush.targetDb[h])) continue;
        const double mag = std::abs(s[h]);
        if (mag < peak * 1e-7) continue; // CREATE remains explicit for numerical FFT dust
        const double target = mag * std::pow((peak * std::pow(10.0, brush.targetDb[h] / 20.0)) / mag, strength);
        if (std::fabs(target - mag) < peak * 1e-6) continue;
        s[h] *= target / mag; s[kFrameSize - h] = std::conj(s[h]); changed = true;
    }
    if (!changed) return false;
    s[0] = 0; s[kFrameSize / 2] = 0; fft(s, true);
    Frame out(kFrameSize); float mx = 0;
    for (int i = 0; i < kFrameSize; ++i) { out[i] = (float)s[i].real(); mx = std::max(mx, std::fabs(out[i])); }
    if (mx > 0) for (auto& x : out) x /= mx;
    f = std::move(out); return true;
}
inline bool applyBrushTable(TableFrames& t, const FrameRange& range, int selected, const PartialBrush& brush, double taper = 0.0) {
    if (t.empty()) return false;
    int a = range.active((int)t.size()) ? range.first((int)t.size()) : std::clamp(selected, 0, (int)t.size() - 1);
    int b = range.active((int)t.size()) ? range.last((int)t.size()) : a;
    bool changed = false;
    for (int i = a; i <= b; ++i) changed |= applyBrushFrame(t[i], brush, brushRangeStrength(i, range, (int)t.size(), taper));
    return changed;
}
} // namespace muew
