#pragma once
#include <cmath>
#include <algorithm>

namespace muew {

// TPT (topology-preserving transform) state-variable filter.
// Unconditionally stable across the full cutoff/resonance range, unlike the
// naive Chamberlin form. Modes: LP/BP/HP/Notch/Peak, 12 dB/oct.
class SVFilter {
public:
    enum class Mode { Lowpass, Bandpass, Highpass, Notch, Peak };

    void setSampleRate(double sr) { sr_ = sr; }
    void setMode(Mode m) { mode_ = m; }

    // cutoffHz 20..sr*0.45, resonanceQ 0.5..20
    void set(double cutoffHz, double resonanceQ) {
        cutoffHz = std::clamp(cutoffHz, 20.0, sr_ * 0.45);
        resonanceQ = std::clamp(resonanceQ, 0.5, 20.0);
        g_ = std::tan(M_PI * cutoffHz / sr_);
        k_ = 1.0 / resonanceQ;
        a1_ = 1.0 / (1.0 + g_ * (g_ + k_));
        a2_ = g_ * a1_;
        a3_ = g_ * a2_;
    }

    inline float process(float in) {
        double v3 = in - ic2_;
        double v1 = a1_ * ic1_ + a2_ * v3;
        double v2 = ic2_ + a2_ * ic1_ + a3_ * v3;
        ic1_ = 2.0 * v1 - ic1_;
        ic2_ = 2.0 * v2 - ic2_;
        double low = v2, band = v1, high = in - k_ * v1 - v2;
        switch (mode_) {
        case Mode::Lowpass:  return static_cast<float>(low);
        case Mode::Bandpass: return static_cast<float>(band);
        case Mode::Highpass: return static_cast<float>(high);
        case Mode::Notch:    return static_cast<float>(low + high);
        case Mode::Peak:     return static_cast<float>(low - high);
        }
        return in;
    }

    void reset() { ic1_ = ic2_ = 0.0; }

private:
    double sr_ = 44100.0;
    double g_ = 0.1, k_ = 1.0;
    double a1_ = 0.0, a2_ = 0.0, a3_ = 0.0;
    double ic1_ = 0.0, ic2_ = 0.0;
    Mode mode_ = Mode::Lowpass;
};

} // namespace muew
