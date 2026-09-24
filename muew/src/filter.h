#pragma once
#include <cmath>
#include <algorithm>
#include <vector>

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

// 0.22.0: 2x oversampling around the nonlinear parts (DRIVE, the ladder).
// 31-tap windowed-sinc halfband: up() turns one sample into two, down()
// turns two back into one. Stopband beyond ~0.29 of the 2x rate is < -70 dB.
class Halfband2x {
public:
    static constexpr int kTaps = 31;
    Halfband2x() {
        const int c = kTaps / 2;
        double sum = 0;
        for (int n = 0; n < kTaps; ++n) {
            const int m = n - c;
            const double sinc = m == 0 ? 0.5 : std::sin(M_PI * 0.5 * m) / (M_PI * m);
            const double w = 0.42 - 0.5 * std::cos(2 * M_PI * n / (kTaps - 1)) + 0.08 * std::cos(4 * M_PI * n / (kTaps - 1));
            h_[n] = sinc * w; sum += h_[n];
        }
        for (double& v : h_) v /= sum; // unity DC gain
    }
    void reset() { std::fill(up_, up_ + 2 * kTaps, 0.0); std::fill(dn_, dn_ + 2 * kTaps, 0.0); upPos_ = dnPos_ = 0; }
    void copyStateFrom(const Halfband2x& o) { std::copy(o.up_, o.up_ + 2 * kTaps, up_); std::copy(o.dn_, o.dn_ + 2 * kTaps, dn_); upPos_ = o.upPos_; dnPos_ = o.dnPos_; }
    inline void up(double x, double& a, double& b) { push(up_, upPos_, 2.0 * x); a = conv(up_, upPos_); push(up_, upPos_, 0.0); b = conv(up_, upPos_); }
    // down() keeps the phase that makes up() + down() a whole-sample delay: exactly kLatency samples at 1x.
    inline double down(double a, double b) { push(dn_, dnPos_, a); const double y = conv(dn_, dnPos_); push(dn_, dnPos_, b); return y; }
    static constexpr int kLatency = kTaps / 2; // 15
private:
    // Each history is stored twice in a row so the convolution reads one contiguous window.
    static inline void push(double* buf, int& pos, double v) { pos = (pos + 1) % kTaps; buf[pos] = v; buf[pos + kTaps] = v; }
    inline double conv(const double* buf, int pos) const { // newest sample is buf[pos]; h is symmetric
        const double* w = buf + pos + 1; double acc = 0;
        for (int n = 0; n < kTaps; ++n) acc += h_[n] * w[n];
        return acc;
    }
    double h_[kTaps];
    double up_[2 * kTaps] = {}, dn_[2 * kTaps] = {};
    int upPos_ = 0, dnPos_ = 0;
};

// 0.22.0: short fixed delay used to line dry/parallel paths up with an oversampled filter.
class AlignDelay {
public:
    inline float process(float x, int d) { buf_[pos_] = x; const float y = buf_[(pos_ - d + kN) & (kN - 1)]; pos_ = (pos_ + 1) & (kN - 1); return y; }
    void reset() { std::fill(buf_, buf_ + kN, 0.0f); pos_ = 0; }
private:
    static constexpr int kN = 64;
    float buf_[kN] = {};
    int pos_ = 0;
};

// 0.21.0 filter 1: the SVF modes (0-4, unchanged) plus appended models:
// 5 LADDER 24 dB (four TPT one-poles with saturating global feedback),
// 6 COMB + and 7 COMB - (fractional-delay feedback comb tuned to the cutoff),
// 8 MORPH (SVF low -> band -> high by the morph amount). DRIVE (0..1)
// saturates the input; at 0 the SVF modes run exactly as before.
constexpr int kFilterModes = 9;
class Filter1 {
public:
    void setSampleRate(double sr) { sr_ = sr; svf_.setSampleRate(sr); buf_.assign((size_t)(sr / 20.0) + 8, 0.0); pos_ = 0; }
    void setMode(int m) { mode_ = std::clamp(m, 0, kFilterModes - 1); if (mode_ < 5) svf_.setMode(static_cast<SVFilter::Mode>(mode_)); updateOs(); }
    int mode() const { return mode_; }
    void setDrive(double d) { drive_ = std::clamp(d, 0.0, 1.0); pre_ = 1.0 + 7.0 * drive_; post_ = 1.0 / std::sqrt(pre_); }
    // 0.22.0: the owner asks for 2x oversampling while DRIVE is in use (set or routed);
    // LADDER 24 always runs at 2x. Off, the SVF modes are exactly the 0.21.0 path.
    void setOversample(bool on) { osReq_ = on; updateOs(); }
    bool oversampled() const { return os_; }
    int latency() const { return os_ ? Halfband2x::kLatency : 0; } // samples at 1x
    void setMorph(double m) { morph_ = std::clamp(m, 0.0, 1.0); }

    void set(double cutoffHz, double resonanceQ) {
        if (mode_ < 5 || mode_ == 8) { svf_.set(cutoffHz, resonanceQ); return; }
        cutoffHz = std::clamp(cutoffHz, 20.0, sr_ * 0.45);
        const double q = std::clamp(resonanceQ, 0.5, 20.0);
        if (mode_ == 5) {
            const double g = std::tan(M_PI * cutoffHz / (os_ ? 2.0 * sr_ : sr_));
            G_ = g / (1.0 + g);
            k_ = 3.96 * (1.0 - std::exp(-(q - 0.5) / 2.5));
        } else {
            delay_ = std::clamp(sr_ / cutoffHz, 2.0, (double)buf_.size() - 4);
            fb_ = (mode_ == 6 ? 1.0 : -1.0) * (0.25 + 0.7 * std::clamp((q - 0.5) / 8.0, 0.0, 1.0));
        }
    }

    inline double shape(double x) const { return drive_ > 0 ? std::tanh(x * pre_) * post_ * 1.2 : x; }
    inline double ladder(double x) { // zero-delay linear estimate of the output, tanh on the loop input
        const double b = 1.0 - G_;
        const double G2 = G_ * G_, G4 = G2 * G2;
        const double S = G2 * G_ * b * s_[0] + G2 * b * s_[1] + G_ * b * s_[2] + b * s_[3];
        const double y4 = (G4 * x + S) / (1.0 + k_ * G4);
        double u = std::tanh((x * (1.0 + 0.5 * k_) - k_ * y4) * 0.8) / 0.8;
        for (int i = 0; i < 4; ++i) { const double v = (u - s_[i]) * G_; const double y = v + s_[i]; s_[i] = y + v; u = y; }
        return u;
    }
    inline float process(float in) {
        if (os_) { // 0.22.0: drive (and the whole ladder) at 2x
            double a, b; hb_.up(in, a, b);
            a = shape(a); b = shape(b);
            if (mode_ == 5) { a = ladder(a); b = ladder(b); return static_cast<float>(hb_.down(a, b)); }
            return linear(hb_.down(a, b));
        }
        double x = in;
        if (drive_ > 0) x = shape(x);
        if (mode_ == 5) return static_cast<float>(ladder(x));
        return linear(x);
    }
    inline float linear(double x) {
        switch (mode_) {
        case 6: case 7: { // comb: y = x + fb * y[n - D]
            const int nb = (int)buf_.size();
            double rp = pos_ - delay_; if (rp < 0) rp += nb;
            const int i0 = (int)rp; const double fr = rp - i0;
            const double d = buf_[i0] + fr * (buf_[(i0 + 1) % nb] - buf_[i0]);
            const double y = x + fb_ * d;
            buf_[(int)pos_] = std::clamp(y, -4.0, 4.0);
            pos_ += 1; if (pos_ >= nb) pos_ = 0;
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
    void reset() { svf_.reset(); hb_.reset(); for (double& v : s_) v = 0; std::fill(buf_.begin(), buf_.end(), 0.0); pos_ = 0; }
    void copyStateFrom(const Filter1& o) {
        svf_.copyStateFrom(o.svf_);
        if (os_ && o.os_) hb_.copyStateFrom(o.hb_);
        if (mode_ == 5) for (int i = 0; i < 4; ++i) s_[i] = o.s_[i];
        // comb lines are not copied (64 KB a sample in mono); a width change starts the right comb cold
    }

private:
    void updateOs() { const bool on = osReq_ || mode_ == 5; if (on != os_) { os_ = on; hb_.reset(); } }
    SVFilter svf_;
    Halfband2x hb_;
    bool osReq_ = false, os_ = false;
    int mode_ = 0;
    double sr_ = 44100.0, drive_ = 0.0, pre_ = 1.0, post_ = 1.0, morph_ = 0.0;
    double G_ = 0.1, k_ = 0.0, s_[4] = {0, 0, 0, 0};
    std::vector<double> buf_ = std::vector<double>(44100 / 20 + 8, 0.0); // comb line: 20 Hz at the sample rate (0.22.0: sized by rate)
    double pos_ = 0, delay_ = 100, fb_ = 0.5;
};

} // namespace muew
