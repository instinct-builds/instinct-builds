#pragma once
#include "voice.h"
#include <algorithm>
#include <array>
#include <cmath>

namespace muew {
// Display-only history of actual signed per-render extrema. A short window
// makes both sides of a bipolar route visible without changing the held pip.
struct RouteRangeTrace {
    static constexpr double kWindowSeconds = .48;
    static constexpr int kSamples = 24;
    struct Sample {
        std::array<float, kMaxRoutes> lo{}, hi{};
        double age = kWindowSeconds;
    };
    std::array<Sample, kSamples> samples{};
    std::array<float, kMaxRoutes> low{}, high{};
    int next = 0;
    void clear() { samples = {}; for (auto& s : samples) s.age = kWindowSeconds; low.fill(0); high.fill(0); next = 0; }
    void update(const float* minima, const float* maxima, int n, double elapsed) {
        const double dt = std::clamp(std::isfinite(elapsed) ? elapsed : 0.0, 0.0, .1);
        for (auto& s : samples) s.age = std::min(kWindowSeconds, s.age + dt);
        Sample& s = samples[next]; s.age = 0;
        for (int i = 0; i < kMaxRoutes; ++i) {
            const float a = minima && i < n && std::isfinite(minima[i]) ? minima[i] : 0;
            const float b = maxima && i < n && std::isfinite(maxima[i]) ? maxima[i] : 0;
            s.lo[i] = std::clamp(std::min(a, b), -1.0f, 1.0f);
            s.hi[i] = std::clamp(std::max(a, b), -1.0f, 1.0f);
        }
        next = (next + 1) % kSamples;
        low.fill(0); high.fill(0);
        for (const auto& e : samples) if (e.age < kWindowSeconds)
            for (int i = 0; i < kMaxRoutes; ++i) {
                low[i] = std::min(low[i], e.lo[i]); high[i] = std::max(high[i], e.hi[i]);
            }
    }
};
} // namespace muew
