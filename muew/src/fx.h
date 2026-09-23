#pragma once
#include <vector>
#include <cmath>
#include <algorithm>

namespace muew {

// Interpolated circular delay line shared by chorus/delay/reverb.
class DelayLine {
public:
    void resize(int maxSamples) {
        buf_.assign(maxSamples + 1, 0.0f);
        write_ = 0;
    }
    inline void push(float x) {
        buf_[write_] = x;
        write_ = (write_ + 1) % (int)buf_.size();
    }
    // delay in fractional samples
    inline float read(double delay) const {
        double pos = (double)write_ - delay;
        while (pos < 0) pos += buf_.size();
        int i0 = (int)pos % (int)buf_.size();
        int i1 = (i0 + 1) % (int)buf_.size();
        double f = pos - std::floor(pos);
        return buf_[i0] + (float)f * (buf_[i1] - buf_[i0]);
    }
    void clear() { std::fill(buf_.begin(), buf_.end(), 0.0f); }
private:
    std::vector<float> buf_;
    int write_ = 0;
};

struct ChorusParams {
    bool enabled = false;
    double rateHz = 0.6;
    double depthMs = 6.0;
    double baseMs = 15.0;
    double mix = 0.35;
};

// Stereo chorus: two modulated delay taps with quadrature LFOs.
class Chorus {
public:
    void init(double sr) {
        sr_ = sr;
        int maxD = (int)(sr * 0.06) + 4;
        dl_.resize(maxD); dr_.resize(maxD);
    }
    void set(const ChorusParams& p) { p_ = p; }
    inline void process(float& l, float& r) {
        double lfoL = std::sin(2.0 * M_PI * phase_);
        double lfoR = std::sin(2.0 * M_PI * phase_ + M_PI * 0.5);
        phase_ += p_.rateHz / sr_;
        phase_ -= std::floor(phase_);
        double dL = (p_.baseMs + p_.depthMs * (0.5 + 0.5 * lfoL)) * 0.001 * sr_;
        double dR = (p_.baseMs + p_.depthMs * (0.5 + 0.5 * lfoR)) * 0.001 * sr_;
        dl_.push(l); dr_.push(r);
        float wetL = dl_.read(dL), wetR = dr_.read(dR);
        l = (float)((1.0 - p_.mix) * l + p_.mix * wetL);
        r = (float)((1.0 - p_.mix) * r + p_.mix * wetR);
    }
    const ChorusParams& params() const { return p_; }
private:
    double sr_ = 44100.0, phase_ = 0.0;
    ChorusParams p_;
    DelayLine dl_, dr_;
};

struct DelayParams {
    bool enabled = false;
    double timeLSec = 0.28;
    double timeRSec = 0.42;
    double feedback = 0.35;
    double mix = 0.25;
};

// Stereo delay with independent L/R times and feedback.
class StereoDelay {
public:
    void init(double sr) {
        sr_ = sr;
        dl_.resize((int)(sr * 2.0) + 4);
        dr_.resize((int)(sr * 2.0) + 4);
    }
    void set(const DelayParams& p) { p_ = p; }
    inline void process(float& l, float& r) {
        float fbL = dl_.read(p_.timeLSec * sr_);
        float fbR = dr_.read(p_.timeRSec * sr_);
        dl_.push(l + fbR * (float)p_.feedback);   // cross-feedback for a wider tail
        dr_.push(r + fbL * (float)p_.feedback);
        l = (float)((1.0 - p_.mix) * l + p_.mix * fbL);
        r = (float)((1.0 - p_.mix) * r + p_.mix * fbR);
    }
    const DelayParams& params() const { return p_; }
private:
    double sr_ = 44100.0;
    DelayParams p_;
    DelayLine dl_, dr_;
};

struct ReverbParams {
    bool enabled = false;
    double decay = 0.6;   // 0..1 feedback amount
    double damping = 0.4; // 0..1 high-frequency loss
    double mix = 0.3;
};

// Schroeder-style reverb: 4 damped parallel combs into 2 series allpasses,
// per channel, with slightly detuned lengths per side for a stereo field.
class Reverb {
public:
    void init(double sr) {
        sr_ = sr;
        static const int combTun[2][4] = {
            {1116, 1188, 1277, 1356},
            {1139, 1211, 1300, 1379},
        };
        static const int apTun[2][2] = {{556, 441}, {579, 464}};
        for (int ch = 0; ch < 2; ++ch) {
            for (int i = 0; i < 4; ++i) {
                combs_[ch][i].line.resize(combTun[ch][i] + 4);
                combs_[ch][i].length = combTun[ch][i];
            }
            for (int i = 0; i < 2; ++i) {
                aps_[ch][i].line.resize(apTun[ch][i] + 4);
                aps_[ch][i].length = apTun[ch][i];
            }
        }
    }
    void set(const ReverbParams& p) { p_ = p; }

    inline float processOne(int ch, float in) {
        float acc = 0.0f;
        for (auto& c : combs_[ch]) {
            float out = c.line.read(c.length);
            c.store += (out - c.store) * (float)p_.damping; // one-pole lowpass in the feedback path
            c.line.push(in + c.store * (float)p_.decay);
            acc += out;
        }
        for (auto& a : aps_[ch]) {
            float buf = a.line.read(a.length);
            float v = -0.5f * acc + buf;
            a.line.push(acc + buf * 0.5f);
            acc = v;
        }
        return acc * 0.25f;
    }

    inline void process(float& l, float& r) {
        float wetL = processOne(0, l), wetR = processOne(1, r);
        l = (float)((1.0 - p_.mix) * l + p_.mix * wetL);
        r = (float)((1.0 - p_.mix) * r + p_.mix * wetR);
    }
    const ReverbParams& params() const { return p_; }
private:
    struct Comb { DelayLine line; int length = 0; float store = 0.0f; };
    struct AP { DelayLine line; int length = 0; };
    double sr_ = 44100.0;
    ReverbParams p_;
    Comb combs_[2][4];
    AP aps_[2][2];
};

struct DistortionParams {
    bool enabled = false;
    int mode = 0;       // 0 soft clip, 1 fold, 2 bitcrush
    double drive = 0.4; // 0..1
    double mix = 1.0;   // 0..1
};

// Waveshaping distortion. Soft clip is a normalized tanh curve; fold
// reflects the driven signal back into range; bitcrush drops bit depth and
// holds samples (the aliasing is the sound). Output is trimmed as drive
// rises so turning it up changes character more than loudness.
class Distortion {
public:
    void set(const DistortionParams& p) { p_ = p; }
    void setDriveOffset(double d) { driveOffset_ = d; }
    double drive() const { return std::clamp(p_.drive + driveOffset_, 0.0, 1.0); }
    static inline float shape(int mode, double drive, float x) {
        switch (mode) {
        case 1: { // fold
            double v = x * (1.0 + drive * 6.0);
            v = std::fmod(v + 1.0, 4.0); if (v < 0.0) v += 4.0;
            return (float)(((v <= 2.0) ? v : 4.0 - v) - 1.0);
        }
        case 2: { // crush (bit depth only; sample hold lives in process)
            const double levels = std::pow(2.0, 12.0 - drive * 10.0);
            return (float)(std::round(x * levels) / levels);
        }
        default: { // soft clip
            const double g = 1.0 + drive * 24.0;
            return (float)(std::tanh(g * x) / std::tanh(g));
        }
        }
    }
    inline void process(float& l, float& r) {
        const double d = drive();
        float wl, wr;
        if (p_.mode == 2) {
            const int hold = 1 + (int)(d * 15.0);
            if (++holdCount_ >= hold) { holdCount_ = 0; heldL_ = shape(2, d, l); heldR_ = shape(2, d, r); }
            wl = heldL_; wr = heldR_;
        } else {
            wl = shape(p_.mode, d, l); wr = shape(p_.mode, d, r);
        }
        const float trim = (float)(1.0 / (1.0 + d * (p_.mode == 0 ? 1.2 : 0.4)));
        const float m = (float)std::clamp(p_.mix, 0.0, 1.0);
        l = l + m * (wl * trim - l);
        r = r + m * (wr * trim - r);
    }
    const DistortionParams& params() const { return p_; }
private:
    DistortionParams p_;
    double driveOffset_ = 0.0;
    int holdCount_ = 0;
    float heldL_ = 0, heldR_ = 0;
};

// RBJ-cookbook biquad (transposed direct form II).
class Biquad {
public:
    enum Kind { LowShelf, Peak, HighShelf };
    void design(Kind kind, double sr, double hz, double q, double gainDb) {
        const double A = std::pow(10.0, gainDb / 40.0), w = 2.0 * M_PI * hz / sr;
        const double cw = std::cos(w), sw = std::sin(w), alpha = sw / (2.0 * q);
        double b0, b1, b2, a0, a1, a2;
        if (kind == Peak) {
            b0 = 1 + alpha * A; b1 = -2 * cw; b2 = 1 - alpha * A;
            a0 = 1 + alpha / A; a1 = -2 * cw; a2 = 1 - alpha / A;
        } else {
            const double sa = 2.0 * std::sqrt(A) * alpha, s = kind == LowShelf ? 1.0 : -1.0;
            b0 = A * ((A + 1) - s * (A - 1) * cw + sa);
            b1 = s * 2 * A * ((A - 1) - s * (A + 1) * cw);
            b2 = A * ((A + 1) - s * (A - 1) * cw - sa);
            a0 = (A + 1) + s * (A - 1) * cw + sa;
            a1 = -s * 2 * ((A - 1) + s * (A + 1) * cw);
            a2 = (A + 1) + s * (A - 1) * cw - sa;
        }
        b0_ = b0 / a0; b1_ = b1 / a0; b2_ = b2 / a0; a1_ = a1 / a0; a2_ = a2 / a0;
    }
    inline float process(float x) {
        const double y = b0_ * x + z1_;
        z1_ = b1_ * x - a1_ * y + z2_;
        z2_ = b2_ * x - a2_ * y;
        return (float)y;
    }
private:
    double b0_ = 1, b1_ = 0, b2_ = 0, a1_ = 0, a2_ = 0, z1_ = 0, z2_ = 0;
};

struct EQParams {
    bool enabled = false;
    double lowDb = 0.0, midDb = 0.0, highDb = 0.0; // -12..12: 180 Hz shelf, 1.2 kHz bell, 6 kHz shelf
};

class EQ3 {
public:
    void init(double sr) { sr_ = sr; set(p_); }
    void set(const EQParams& p) {
        p_ = p;
        for (int ch = 0; ch < 2; ++ch) {
            band_[ch][0].design(Biquad::LowShelf, sr_, 180.0, 0.707, std::clamp(p.lowDb, -12.0, 12.0));
            band_[ch][1].design(Biquad::Peak, sr_, 1200.0, 0.9, std::clamp(p.midDb, -12.0, 12.0));
            band_[ch][2].design(Biquad::HighShelf, sr_, 6000.0, 0.707, std::clamp(p.highDb, -12.0, 12.0));
        }
    }
    inline void process(float& l, float& r) {
        for (auto& b : band_[0]) l = b.process(l);
        for (auto& b : band_[1]) r = b.process(r);
    }
    const EQParams& params() const { return p_; }
private:
    double sr_ = 44100.0;
    EQParams p_;
    Biquad band_[2][3];
};

struct CompressorParams {
    bool enabled = false;
    double amount = 0.5; // 0..1: one-knob threshold, ratio and makeup
};

// Stereo-linked feed-forward compressor, one knob. amount sets threshold
// (-6 to -36 dB), ratio (1.5:1 to 8:1) and partial makeup gain (<= 6 dB).
// The peak detector catches transients instantly; the gain itself glides
// over ~2 ms (down) / 120 ms (up) so it never clicks or overshoots.
class Compressor {
public:
    void init(double sr) {
        sr_ = sr;
        atk_ = std::exp(-1.0 / (0.002 * sr));
        rel_ = std::exp(-1.0 / (0.12 * sr));
    }
    void set(const CompressorParams& p) {
        p_ = p;
        const double a = std::clamp(p.amount, 0.0, 1.0);
        thrDb_ = -6.0 - 30.0 * a;
        ratio_ = 1.5 + 6.5 * a;
        makeupDb_ = std::min(6.0, -thrDb_ * (1.0 - 1.0 / ratio_) * 0.3);
    }
    inline void process(float& l, float& r) {
        const double peak = std::max(std::fabs(l), std::fabs(r));
        env_ = peak > env_ ? peak : peak + rel_ * (env_ - peak);
        const double levelDb = 20.0 * std::log10(env_ + 1e-9);
        const double over = levelDb - thrDb_;
        const double target = over > 0.0 ? over * (1.0 - 1.0 / ratio_) : 0.0;
        // Gain reduction rises fast (2 ms) and recovers slowly (120 ms).
        grDb_ = target + (target > grDb_ ? atk_ : rel_) * (grDb_ - target);
        // Makeup only as far as the signal is being compressed, so a sudden
        // hit is never boosted before the reduction catches up.
        const double makeup = std::min(makeupDb_, grDb_ + 1.0);
        const float g = (float)std::pow(10.0, (makeup - grDb_) / 20.0);
        l *= g; r *= g;
    }
    double gainReductionDb() const { return grDb_; }
    const CompressorParams& params() const { return p_; }
private:
    double sr_ = 44100.0, atk_ = 0.0, rel_ = 0.0, env_ = 0.0;
    double thrDb_ = -21.0, ratio_ = 4.75, makeupDb_ = 0.0, grDb_ = 0.0;
    CompressorParams p_;
};

struct FXParams {
    ChorusParams chorus;
    DelayParams delay;
    ReverbParams reverb;
    // 0.7.0 rack additions. Off by default, so older presets are unchanged.
    DistortionParams dist;
    EQParams eq;
    CompressorParams comp;
};

// Rack order: distortion -> chorus -> delay -> compressor -> reverb -> EQ.
// Each stage passes through untouched when off.
class FXChain {
public:
    void init(double sr) { chorus_.init(sr); delay_.init(sr); reverb_.init(sr); eq_.init(sr); comp_.init(sr); }
    void set(const FXParams& p) {
        chorus_.set(p.chorus); delay_.set(p.delay); reverb_.set(p.reverb);
        dist_.set(p.dist); eq_.set(p.eq); comp_.set(p.comp);
        p_ = p;
    }
    // Macro routes into the distortion drive (Dest::DistDrive).
    void setDriveOffset(double d) { dist_.setDriveOffset(d); }
    inline void process(float& l, float& r) {
        if (p_.dist.enabled) dist_.process(l, r);
        if (p_.chorus.enabled) chorus_.process(l, r);
        if (p_.delay.enabled) delay_.process(l, r);
        if (p_.comp.enabled) comp_.process(l, r);
        if (p_.reverb.enabled) reverb_.process(l, r);
        if (p_.eq.enabled) eq_.process(l, r);
    }
    const FXParams& params() const { return p_; }
    double compressorReductionDb() const { return comp_.gainReductionDb(); }
private:
    FXParams p_;
    Chorus chorus_;
    StereoDelay delay_;
    Reverb reverb_;
    Distortion dist_;
    EQ3 eq_;
    Compressor comp_;
};

} // namespace muew
