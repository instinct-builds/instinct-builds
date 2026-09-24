// arp.h - MUEW's arpeggiator pattern logic (0.25.0). The Synth owns the clock
// and the held-note pool; this file turns a pool into the notes of one step,
// so the engine, the editor's step display and the tests agree.
#pragma once
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>

namespace muew {
namespace arp {

// Append only: values are stored in presets.
enum Mode { Up = 0, Down = 1, UpDown = 2, Order = 3, Random = 4, Chord = 5, kModes = 6 };
inline const char* modeName(int m) {
    static const char* n[kModes] = {"UP", "DOWN", "UP/DN", "ORDER", "RANDOM", "CHORD"};
    return n[std::clamp(m, 0, kModes - 1)];
}

// Step rates, in beats (quarter notes). Append only.
constexpr int kRates = 7;
inline double rateBeats(int r) {
    static const double b[kRates] = {1.0, 0.5, 1.0 / 3.0, 0.25, 1.0 / 6.0, 0.125, 1.0 / 12.0};
    return b[std::clamp(r, 0, kRates - 1)];
}
inline const char* rateName(int r) {
    static const char* n[kRates] = {"1/4", "1/8", "1/8T", "1/16", "1/16T", "1/32", "1/32T"};
    return n[std::clamp(r, 0, kRates - 1)];
}

constexpr int kPool = 32;         // held keys the arp remembers
constexpr int kSeq = kPool * 4 * 2;

// The cycle a pool plays for a mode (not RANDOM / CHORD, which pick per step).
// `pool` is in press order. Returns the cycle length.
inline int sequence(int mode, const int* pool, int count, int octaves, std::array<int, kSeq>& out) {
    count = std::clamp(count, 0, kPool);
    octaves = std::clamp(octaves, 1, 4);
    if (count == 0) return 0;
    int base[kPool];
    std::copy(pool, pool + count, base);
    if (mode != Order) std::sort(base, base + count);
    int n = 0;
    int up[kPool * 4];
    for (int o = 0; o < octaves; ++o)
        for (int i = 0; i < count; ++i) up[n++] = std::min(127, base[i] + 12 * o);
    int m = 0;
    if (mode == Down) { for (int i = n - 1; i >= 0; --i) out[m++] = up[i]; }
    else if (mode == UpDown) {
        for (int i = 0; i < n; ++i) out[m++] = up[i];
        for (int i = n - 2; i >= 1; --i) out[m++] = up[i];
    } else { for (int i = 0; i < n; ++i) out[m++] = up[i]; }
    return m;
}

// Step length in samples: swing lengthens even steps and shortens odd ones
// (0 = straight, 0.5 = 75/25 shuffle), so every pair still takes two steps.
inline double stepLength(double sampleRate, double bpm, int rate, double swing, int step) {
    const double base = sampleRate * 60.0 / std::max(bpm, 1.0) * rateBeats(rate);
    const double s = std::clamp(swing, 0.0, 0.5);
    return (step & 1) ? base * (1.0 - s) : base * (1.0 + s);
}
inline int stepSamples(double sampleRate, double bpm, int rate, double swing, int step) {
    return std::max(1, (int)std::lround(stepLength(sampleRate, bpm, rate, swing, step)));
}
// Whole-sample length of a step that starts at the exact (fractional) time
// `start`: rounding each boundary instead of each length keeps the grid from
// drifting against the host over long passages.
inline int stepSamplesAt(double start, double sampleRate, double bpm, int rate, double swing, int step) {
    const double end = start + stepLength(sampleRate, bpm, rate, swing, step);
    return std::max(1, (int)(std::llround(end) - std::llround(start)));
}

} // namespace arp
} // namespace muew
