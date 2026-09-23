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

    // 0.21.0: all three responses at once (same state update as process()).
    inline void processAll(float in, double& low, double& band, double& high) {
        double v3 = in - ic2_;
        double v1 = a1_ * ic1_ + a2_ * v3;
        double v2 = ic2_ + a2_ * ic1_ + a3_ * v3;
        ic1_ = 2.0 * v1 - ic1_;
        ic2_ = 2.0 * v2 - ic2_;
        low = v2; band = v1; high = in - k_ * v1 - v2;
    }
    double k() const { return k_; }

    void reset() { ic1_ = ic2_ = 0.0; }
    void copyStateFrom(const SVFilter& o) { ic1_ = o.ic1_; ic2_ = o.ic2_; }

private:
    double sr_ = 44100.0;
    double g_ = 0.1, k_ = 1.0;
    double a1_ = 0.0, a2_ = 0.0, a3_ = 0.0;
    double ic1_ = 0.0, ic2_ = 0.0;
    Mode mode_ = Mode::Lowpass;
};

// 0.21.0 filter 1: the SVF modes (0-4, unchanged) plus appended models:
// 5 LADDER 24 dB (four TPT one-poles with saturating global feedback),
// 6 COMB + and 7 COMB - (fractional-delay feedback comb tuned to the cutoff),
// 8 MORPH (SVF low -> band -> high by the morph amount). DRIVE (0..1)
// saturates the input; at 0 the SVF modes run exactly as before.
constexpr int kFilterModes = 9;
class Filter1 {
public:
    void setSampleRate(double sr) { sr_ = sr; svf_.setSampleRate(sr); }
    void setMode(int m) { mode_ = std::clamp(m, 0, kFilterModes - 1); if (mode_ < 5) svf_.setMode(static_cast<SVFilter::Mode>(mode_)); }
    int mode() const { return mode_; }
    void setDrive(double d) { drive_ = std::clamp(d, 0.0, 1.0); pre_ = 1.0 + 7.0 * drive_; post_ = 1.0 / std::sqrt(pre_); }
    void setMorph(double m) { morph_ = std::clamp(m, 0.0, 1.0); }

    void set(double cutoffHz, double resonanceQ) {
        if (mode_ < 5 || mode_ == 8) { svf_.set(cutoffHz, resonanceQ); return; }
        cutoffHz = std::clamp(cutoffHz, 20.0, sr_ * 0.45);
        const double q = std::clamp(resonanceQ, 0.5, 20.0);
        if (mode_ == 5) {
            const double g = std::tan(M_PI * cutoffHz / sr_);
            G_ = g / (1.0 + g);
            k_ = 3.96 * (1.0 - std::exp(-(q - 0.5) / 2.5));
        } else {
            delay_ = std::clamp(sr_ / cutoffHz, 2.0, (double)kCombMax - 4);
            fb_ = (mode_ == 6 ? 1.0 : -1.0) * (0.25 + 0.7 * std::clamp((q - 0.5) / 8.0, 0.0, 1.0));
        }
    }

    inline float process(float in) {
        double x = in;
        if (drive_ > 0) x = std::tanh(x * pre_) * post_ * 1.2;
        switch (mode_) {
        case 5: { // ladder: zero-delay linear estimate of the output, tanh on the loop input
            const double b = 1.0 - G_;
            const double G2 = G_ * G_, G4 = G2 * G2;
            const double S = G2 * G_ * b * s_[0] + G2 * b * s_[1] + G_ * b * s_[2] + b * s_[3];
            const double y4 = (G4 * x + S) / (1.0 + k_ * G4);
            double u = std::tanh((x * (1.0 + 0.5 * k_) - k_ * y4) * 0.8) / 0.8;
            for (int i = 0; i < 4; ++i) { const double v = (u - s_[i]) * G_; const double y = v + s_[i]; s_[i] = y + v; u = y; }
            return static_cast<float>(u);
        }
        case 6: case 7: { // comb: y = x + fb * y[n - D]
            double rp = pos_ - delay_; if (rp < 0) rp += kCombMax;
            const int i0 = (int)rp; const double fr = rp - i0;
            const double d = buf_[i0] + fr * (buf_[(i0 + 1) % kCombMax] - buf_[i0]);
            const double y = x + fb_ * d;
            buf_[(int)pos_] = std::clamp(y, -4.0, 4.0);
            pos_ += 1; if (pos_ >= kCombMax) pos_ = 0;
            return static_cast<float>(y * (1.0 - std::fabs(fb_)) * 1.6);
        }
        case 8: {
            double lo, bp, hi; svf_.processAll((float)x, lo, bp, hi);
            bp *= svf_.k(); // unity-peak band pass
            const double m = morph_ * 2.0;
            return static_cast<float>(m < 1.0 ? lo + (bp - lo) * m : bp + (hi - bp) * (m - 1.0));
        }
        default: return svf_.process((float)x);
        }
    }
    void reset() { svf_.reset(); for (double& v : s_) v = 0; std::fill(buf_, buf_ + kCombMax, 0.0); pos_ = 0; }
    void copyStateFrom(const Filter1& o) {
        svf_.copyStateFrom(o.svf_);
        if (mode_ == 5) for (int i = 0; i < 4; ++i) s_[i] = o.s_[i];
        // comb lines are not copied (64 KB a sample in mono); a width change starts the right comb cold
    }

private:
    static constexpr int kCombMax = 8192; // 20 Hz at 96 kHz fits
    SVFilter svf_;
    int mode_ = 0;
    double sr_ = 44100.0, drive_ = 0.0, pre_ = 1.0, post_ = 1.0, morph_ = 0.0;
    double G_ = 0.1, k_ = 0.0, s_[4] = {0, 0, 0, 0};
    double buf_[kCombMax] = {};
    double pos_ = 0, delay_ = 100, fb_ = 0.5;
};

} // namespace muew
