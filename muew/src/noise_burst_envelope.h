#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>
namespace muew {
// A burst's duration is total time, including its optional attack. Zero
// duration bypasses this envelope exactly, preserving sustained noise.
inline float noiseBurstGain(uint64_t sample, uint64_t length, double attack, double curve) {
    if (!length) return 1.0f;
    if (sample >= length) return 0.0f;
    const double t = (double)sample / length;
    const double a = std::clamp(attack, 0.0, 0.8);
    if (a > 0.0 && t < a) return (float)(t / a);
    const double decay = std::clamp((t - a) / (1.0 - a), 0.0, 1.0);
    if (curve == 0.0) return (float)(1.0 - decay); // old 0.55.0 operation
    return (float)std::pow(1.0 - decay, std::exp2(-2.0 * std::clamp(curve, -1.0, 1.0)));
}
}
