#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>
#include "tempo_sync.h"
namespace muew {
// A sync value of zero preserves the free 5-500 ms duration. When a host
// supplies no usable tempo, synced bursts use 120 BPM, never the last tempo
// seen from an earlier host/playback session.
inline uint64_t noiseBurstSamples(double freeSeconds, int division, double bpm, double sampleRate) {
    const double beats = syncBeats(division);
    if (!(sampleRate > 0.0) || !std::isfinite(sampleRate)) return 0;
    if (beats > 0.0) {
        const double tempo = std::isfinite(bpm) && bpm >= 20.0 && bpm < 999.0 ? bpm : 120.0;
        return (uint64_t)std::ceil(beats * 60.0 / tempo * sampleRate);
    }
    return freeSeconds > 0.0 ? (uint64_t)std::ceil(std::clamp(freeSeconds, 0.005, 0.5) * sampleRate) : 0;
}

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
