#pragma once
#include <vector>
#include <cmath>
#include <cstdint>

namespace muew {

// Band-limited wavetable: one mipmap level per octave, each level additively
// synthesized with harmonics limited below that octave's Nyquist. All tables
// are generated mathematically in code; no sampled or third-party content.
class Wavetable {
public:
    static constexpr int kTableSize = 2048;
    static constexpr int kNumLevels = 11; // covers ~20 Hz .. 20 kHz

    enum class Shape { Sine, Triangle, Saw, Square, Pulse25, Count };

    Wavetable() { buildAll(); }

    // shape index 0..Shape::Count-1, level 0..kNumLevels-1, phase 0..1
    inline float sample(int shape, int level, double phase) const {
        const auto& t = tables_[shape][level];
        double pos = phase * kTableSize;
        int i0 = static_cast<int>(pos) & (kTableSize - 1);
        int i1 = (i0 + 1) & (kTableSize - 1);
        float frac = static_cast<float>(pos - std::floor(pos));
        return t[i0] + frac * (t[i1] - t[i0]);
    }

    // Fractional-level sample for smooth pitch sweeps.
    inline float sampleFractional(int shape, double level, double phase) const {
        if (level < 0) level = 0;
        int l0 = static_cast<int>(level);
        int l1 = l0 + 1 >= kNumLevels ? kNumLevels - 1 : l0 + 1;
        float f = static_cast<float>(level - l0);
        return sample(shape, l0, phase) * (1.0f - f) + sample(shape, l1, phase) * f;
    }

    // Registers an editor-built table (mipmap levels from wavetable_editor.h)
    // as an extra shape slot. Returns its shape index (>= (int)Shape::Count).
    int addCustomTable(std::vector<std::vector<float>> levels) {
        if ((int)levels.size() != kNumLevels) return -1;
        tables_.push_back(std::move(levels));
        return static_cast<int>(tables_.size()) - 1;
    }

    int shapeCount() const { return static_cast<int>(tables_.size()); }

    // Mipmap level for a frequency: higher freq -> higher level -> fewer harmonics.
    static double levelForFrequency(double freq, double sampleRate) {
        if (freq < 1.0) freq = 1.0;
        // Level 0 covers up to sr/2^kNumLevels; each level doubles the band.
        double nyquist = sampleRate * 0.5;
        double ratio = nyquist / freq;          // harmonics available
        double level = kNumLevels - std::log2(ratio > 1.0 ? ratio : 1.0) - 1.0;
        return level < 0.0 ? 0.0 : (level > kNumLevels - 1 ? kNumLevels - 1 : level);
    }

private:
    std::vector<std::vector<std::vector<float>>> tables_; // [shape][level][sample]

    void buildAll() {
        tables_.resize(static_cast<int>(Shape::Count));
        for (int s = 0; s < static_cast<int>(Shape::Count); ++s) {
            tables_[s].resize(kNumLevels);
            for (int lvl = 0; lvl < kNumLevels; ++lvl)
                tables_[s][lvl] = buildLevel(static_cast<Shape>(s), lvl);
        }
    }

    static std::vector<float> buildLevel(Shape shape, int level) {
        std::vector<float> t(kTableSize, 0.0f);
        // Level 0 (lowest octave) is the most harmonically rich.
        int maxHarmonic = 1 << (kNumLevels - 1 - level);
        if (maxHarmonic > kTableSize / 2) maxHarmonic = kTableSize / 2;
        for (int i = 0; i < kTableSize; ++i) {
            double ph = static_cast<double>(i) / kTableSize;
            double v = 0.0;
            switch (shape) {
            case Shape::Sine:
                v = std::sin(2.0 * M_PI * ph);
                break;
            case Shape::Triangle:
                for (int h = 1; h <= maxHarmonic; h += 2) {
                    double sign = ((h - 1) / 2) % 2 == 0 ? 1.0 : -1.0;
                    v += sign * std::sin(2.0 * M_PI * h * ph) / (h * h);
                }
                v *= 8.0 / (M_PI * M_PI);
                break;
            case Shape::Saw:
                for (int h = 1; h <= maxHarmonic; ++h)
                    v += std::sin(2.0 * M_PI * h * ph) / h;
                v *= 2.0 / M_PI;
                break;
            case Shape::Square:
                for (int h = 1; h <= maxHarmonic; h += 2)
                    v += std::sin(2.0 * M_PI * h * ph) / h;
                v *= 4.0 / M_PI;
                break;
            case Shape::Pulse25: {
                // 25% pulse via additive Fourier series with phase-shifted partials.
                const double duty = 0.25;
                for (int h = 1; h <= maxHarmonic; ++h)
                    v += (2.0 / (M_PI * h)) * std::sin(M_PI * h * duty)
                       * std::cos(2.0 * M_PI * h * (ph - duty * 0.5));
                break;
            }
            default: break;
            }
            t[i] = static_cast<float>(v);
        }
        // Normalize peak to ~1.
        float peak = 0.0f;
        for (float x : t) peak = std::max(peak, std::fabs(x));
        if (peak > 0.0f) for (auto& x : t) x /= peak;
        return t;
    }
};

} // namespace muew
