#pragma once
#include "voice.h"
#include <algorithm>
#include <array>
#include <cmath>

namespace muew {
// Editor-only ballistics: the engine's signed route reading is never altered.
// Hold a peak for 180 ms, then fade over 420 ms; a stronger opposite-polarity
// hit takes over immediately. The editable amount bar is a separate control.
struct RouteMeterHold {
    static constexpr double kHoldSeconds = .18;
    static constexpr double kFadeSeconds = .42;
    std::array<float, kMaxRoutes> value{};
    std::array<double, kMaxRoutes> age{};
    void clear() { value.fill(0); age.fill(0); }
    void update(const float* input, int n, double elapsed) {
        const double dt = std::clamp(elapsed, 0.0, .1);
        for (int i = 0; i < kMaxRoutes; ++i) {
            float x = input && i < n && std::isfinite(input[i]) ? std::clamp(input[i], -1.0f, 1.0f) : 0.0f;
            float& held = value[i]; double& t = age[i];
            if (std::fabs(x) > std::fabs(held) + .005f) { held = x; t = 0; continue; }
            const double oldAge = t; t += dt;
            if (t > kHoldSeconds && held != 0) {
                const double active = std::max(0.0, t - std::max(oldAge, kHoldSeconds));
                const double fade = std::min(1.0, active / kFadeSeconds);
                held = (float)(held * (1.0 - fade));
                if (std::fabs(held) < .004f) { held = 0; t = 0; }
            }
        }
    }
};
} // namespace muew
