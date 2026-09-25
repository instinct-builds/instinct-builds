#pragma once
#include "wavetable.h"
#include "custom_table.h"
#include <algorithm>
#include <cmath>

namespace muew {

// Band-limited wavetable oscillator with original phase-warp algorithms.
class Oscillator {
public:
    // 0.19.0 appends FM from oscillator B, AM from B, WINDOW (windowed
    // continuous sync) and REMAP (phase through a drawn curve). Every mode can
    // sit in either warp slot; slot 2 runs after slot 1.
    enum class WarpMode { Off, Sync, BendPlus, BendMinus, PWM, Quantize, Fold, FmB, AmB, Window, Remap };
    static constexpr int kWarpModes = 11;
    static constexpr int kRemapTable = 512;

    void setSampleRate(double sr) { sr_ = sr; }
    void setFrequency(double hz) { freq_ = hz; }
    void setDetuneSemitones(double st) { detune_ = st; }
    void setShape(int shape) { shape_ = shape; }
    void setWarp(WarpMode mode, double amount) { warpMode_ = mode; warp_ = std::clamp(amount, 0.0, 1.0); }
    void setWarp2(WarpMode mode, double amount) { warpMode2_ = mode; warp2_ = std::clamp(amount, 0.0, 1.0); }
    // Oscillator B's last sample (-1..1) for FM B / AM B, set each sample by the voice.
    void setModInput(float m) { modIn_ = m; }
    // kRemapTable+1 samples of the REMAP curve (-1..1 = phase 0..1); null = identity.
    void setRemap(const float* table) { remap_ = table; }
    float lastOut() const { return last_; }
    void setPhase(double p) { phase_ = p - std::floor(p); }
    void reset() { phase_ = 0.0; }

    inline float process() {
        const double hz = freq_ * std::pow(2.0, detune_ / 12.0);
        return processAt(hz, Wavetable::levelForFrequency(hz, sr_));
    }

    // Same output as process() for a precomputed frequency and mip level;
    // unison stacks share one level and pitch computation per sample.
    inline float processAt(double hz, double level) {
        double p = warpedPhase(warpMode_, warp_, phase_);
        const double p1 = p;
        if (warpMode2_ != WarpMode::Off) p = warpedPhase(warpMode2_, warp2_, p);
        float out = custom_ ? custom_->sample(wtPos_, level, p, specMorph_) : table_->sampleFractional(shape_, level, p);
        out = outputStage(warpMode_, warp_, out, phase_);
        if (warpMode2_ != WarpMode::Off) out = outputStage(warpMode2_, warp2_, out, p1);
        phase_ += hz / sr_; phase_ -= std::floor(phase_);
        last_ = out;
        return out;
    }

    void setTable(const Wavetable* t) { table_ = t; }
    // 0.9.0: play a user table (null = the built-in shape) at frame position 0..1.
    void setCustom(const CustomTable* c) { custom_ = c; }
    void setWtPos(double p) { wtPos_ = p; }
    void setSpecMorph(double m) { specMorph_ = m; } // 0.33.0: 0 = the table, 1 = its morph target
    double frequency() const { return freq_; }
    double phase() const { return phase_; }

private:
    double warpedPhase(WarpMode mode, double warp, double p) const {
        switch (mode) {
        case WarpMode::Sync: return std::fmod(p * (1.0 + std::floor(warp * 7.0)), 1.0);
        case WarpMode::BendPlus: return std::pow(p, 1.0 + warp * 5.0);
        case WarpMode::BendMinus: return 1.0 - std::pow(1.0 - p, 1.0 + warp * 5.0);
        case WarpMode::PWM: {
            const double split = 0.5 + warp * 0.45;
            return p < split ? 0.5 * p / split : 0.5 + 0.5 * (p - split) / (1.0 - split);
        }
        case WarpMode::Quantize: {
            const double steps = 64.0 - std::floor(warp * 60.0);
            return std::floor(p * steps) / steps;
        }
        case WarpMode::FmB: { // phase modulation by B, up to +-1.5 cycles
            const double q = p + warp * 1.5 * modIn_;
            return q - std::floor(q);
        }
        case WarpMode::Window: return std::fmod(p * (1.0 + warp * 7.0), 1.0); // continuous ratio; the window hides the reset
        case WarpMode::Remap: {
            if (!remap_ || warp <= 0.0) return p;
            const double x = std::clamp(p, 0.0, 1.0) * kRemapTable; const int i = std::min((int)x, kRemapTable - 1); const double f = x - i;
            const double q = 0.5 * (1.0 + remap_[i] + (remap_[i + 1] - remap_[i]) * f);
            return std::clamp(p + warp * (q - p), 0.0, 0.999999999);
        }
        case WarpMode::Off: case WarpMode::Fold: case WarpMode::AmB: default: return p;
        }
    }
    // Output-side warps: FOLD, AM B and the WINDOW gain. `ph` is the phase the slot saw.
    float outputStage(WarpMode mode, double warp, float out, double ph) const {
        if (mode == WarpMode::Fold && warp > 0.0) {
            const double drive = 1.0 + warp * 7.0;
            double x = out * drive;
            x = std::fmod(x + 1.0, 4.0); if (x < 0.0) x += 4.0;
            return static_cast<float>((x <= 2.0 ? x : 4.0 - x) - 1.0);
        }
        if (mode == WarpMode::AmB) return static_cast<float>(out * ((1.0 - warp) + warp * modIn_));
        if (mode == WarpMode::Window) {
            const double win = 0.5 - 0.5 * std::cos(2.0 * M_PI * ph), mix = std::min(1.0, warp * 4.0);
            return static_cast<float>(out * (1.0 - mix + mix * win));
        }
        return out;
    }

    const Wavetable* table_ = nullptr;
    const CustomTable* custom_ = nullptr;
    double wtPos_ = 0.0, specMorph_ = 0.0;
    double sr_ = 44100.0, freq_ = 440.0, detune_ = 0.0, phase_ = 0.0, warp_ = 0.0;
    int shape_ = 0;
    WarpMode warpMode_ = WarpMode::Off, warpMode2_ = WarpMode::Off;
    double warp2_ = 0.0;
    float modIn_ = 0.0f, last_ = 0.0f;
    const float* remap_ = nullptr;
};

} // namespace muew
