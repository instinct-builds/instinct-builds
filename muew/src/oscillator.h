#pragma once
#include "wavetable.h"
#include <algorithm>
#include <cmath>

namespace muew {

// Band-limited wavetable oscillator with original phase-warp algorithms.
class Oscillator {
public:
    enum class WarpMode { Off, Sync, BendPlus, BendMinus, PWM, Quantize, Fold };

    void setSampleRate(double sr) { sr_ = sr; }
    void setFrequency(double hz) { freq_ = hz; }
    void setDetuneSemitones(double st) { detune_ = st; }
    void setShape(int shape) { shape_ = shape; }
    void setWarp(WarpMode mode, double amount) { warpMode_ = mode; warp_ = std::clamp(amount, 0.0, 1.0); }
    void setPhase(double p) { phase_ = p - std::floor(p); }
    void reset() { phase_ = 0.0; }

    inline float process() {
        const double hz = freq_ * std::pow(2.0, detune_ / 12.0);
        return processAt(hz, Wavetable::levelForFrequency(hz, sr_));
    }

    // Same output as process() for a precomputed frequency and mip level;
    // unison stacks share one level and pitch computation per sample.
    inline float processAt(double hz, double level) {
        const double p = warpedPhase(phase_);
        float out = table_->sampleFractional(shape_, level, p);
        if (warpMode_ == WarpMode::Fold && warp_ > 0.0) {
            const double drive = 1.0 + warp_ * 7.0;
            double x = out * drive;
            x = std::fmod(x + 1.0, 4.0); if (x < 0.0) x += 4.0;
            out = static_cast<float>((x <= 2.0 ? x : 4.0 - x) - 1.0);
        }
        phase_ += hz / sr_; phase_ -= std::floor(phase_);
        return out;
    }

    void setTable(const Wavetable* t) { table_ = t; }
    double frequency() const { return freq_; }
    double phase() const { return phase_; }

private:
    double warpedPhase(double p) const {
        switch (warpMode_) {
        case WarpMode::Sync: return std::fmod(p * (1.0 + std::floor(warp_ * 7.0)), 1.0);
        case WarpMode::BendPlus: return std::pow(p, 1.0 + warp_ * 5.0);
        case WarpMode::BendMinus: return 1.0 - std::pow(1.0 - p, 1.0 + warp_ * 5.0);
        case WarpMode::PWM: {
            const double split = 0.5 + warp_ * 0.45;
            return p < split ? 0.5 * p / split : 0.5 + 0.5 * (p - split) / (1.0 - split);
        }
        case WarpMode::Quantize: {
            const double steps = 64.0 - std::floor(warp_ * 60.0);
            return std::floor(p * steps) / steps;
        }
        case WarpMode::Off: case WarpMode::Fold: default: return p;
        }
    }

    const Wavetable* table_ = nullptr;
    double sr_ = 44100.0, freq_ = 440.0, detune_ = 0.0, phase_ = 0.0, warp_ = 0.0;
    int shape_ = 0;
    WarpMode warpMode_ = WarpMode::Off;
};

} // namespace muew
