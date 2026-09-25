#pragma once
// MUEW 0.43.0: transfer a frame's relative partial magnitudes while keeping
// each destination partial's phase. Empty bins stay empty unless CREATE is on.
#include "partial_brush.h"
#include <array>
namespace muew {
struct SpectralClipboard {
    std::array<double, kEditablePartials + 1> ratio{};
    bool valid = false;
    int sourceFrame = -1;
    int firstH = 1, lastH = kEditablePartials;
    void span(int a, int b) {
        firstH = std::clamp(std::min(a, b), 1, kEditablePartials);
        lastH = std::clamp(std::max(a, b), 1, kEditablePartials);
    }
    bool includes(int h) const { return h >= firstH && h <= lastH; }
    bool capture(const Frame& f, int frame = -1) {
        if (f.size() != kFrameSize) return false;
        const auto s = frameSpectrum(f);
        double peak = 0;
        for (int h = 1; h <= kEditablePartials; ++h) peak = std::max(peak, std::abs(s[h]));
        if (peak < 1e-12) return false;
        for (int h = 1; h <= kEditablePartials; ++h)
            ratio[h] = std::abs(s[h]) >= peak * 1e-7 ? std::abs(s[h]) / peak : 0;
        valid = true; sourceFrame = frame; return true;
    }
    void clear() { valid = false; sourceFrame = -1; firstH = 1; lastH = kEditablePartials; ratio.fill(0); }
};
inline bool applySpectralProfile(Frame& f, const SpectralClipboard& copy, double strength = 1,
                                 bool createSilent = false) {
    if (f.size() != kFrameSize || !copy.valid || strength <= 0) return false;
    const auto original = frameSpectrum(f);
    auto s = original;
    double peak = 0;
    for (int h = 1; h <= kEditablePartials; ++h) peak = std::max(peak, std::abs(s[h]));
    if (peak < 1e-12) return false;
    strength = std::clamp(strength, 0.0, 1.0);
    bool changed = false;
    for (int h = 1; h <= kEditablePartials; ++h) {
        if (!copy.includes(h)) continue;
        double old = std::abs(original[h]), target = peak * copy.ratio[h];
        if (old < peak * 1e-7 && !createSilent) continue;
        if (target < peak * 1e-7) target = 0;
        double desired = 0;
        if (old >= peak * 1e-7 && target >= peak * 1e-7) {
            // dB interpolation keeps the profile's relative gain audible through the blend.
            desired = old * std::pow(target / old, strength);
        } else if (old >= peak * 1e-7) desired = old * (1 - strength);
        else if (createSilent) desired = target * strength;
        if (std::abs(desired - old) < peak * 1e-6) continue;
        const std::complex<double> phase = old >= peak * 1e-7 ? original[h] / old
            : std::complex<double>(0, -1); // predictable phase only for an explicitly created bin
        s[h] = phase * desired; s[kFrameSize - h] = std::conj(s[h]); changed = true;
    }
    if (!changed) return false;
    s[0] = 0; s[kFrameSize / 2] = 0; fft(s, true);
    Frame next(kFrameSize); float mx = 0;
    for (int i = 0; i < kFrameSize; ++i) { next[i] = (float)s[i].real(); mx = std::max(mx, std::fabs(next[i])); }
    if (mx > 0) for (auto& x : next) x /= mx;
    if (next == f) return false;
    f = std::move(next); return true;
}
inline bool applySpectralProfileTable(TableFrames& table, const FrameRange& range, int selected,
                                      const SpectralClipboard& copy, double blend,
                                      double taper = 0, bool createSilent = false) {
    if (table.empty() || !copy.valid) return false;
    const int a = range.active((int)table.size()) ? range.first((int)table.size()) : std::clamp(selected, 0, (int)table.size()-1);
    const int b = range.active((int)table.size()) ? range.last((int)table.size()) : a;
    bool changed = false;
    for (int i = a; i <= b; ++i)
        changed |= applySpectralProfile(table[i], copy,
            std::clamp(blend, 0.0, 1.0) * brushRangeStrength(i, range, (int)table.size(), taper), createSilent);
    return changed;
}
} // namespace muew
