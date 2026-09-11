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

struct FXParams {
    ChorusParams chorus;
    DelayParams delay;
    ReverbParams reverb;
};

// Fixed chain: chorus -> delay -> reverb. Each stage passes through when off.
class FXChain {
public:
    void init(double sr) { chorus_.init(sr); delay_.init(sr); reverb_.init(sr); }
    void set(const FXParams& p) {
        chorus_.set(p.chorus); delay_.set(p.delay); reverb_.set(p.reverb);
        p_ = p;
    }
    inline void process(float& l, float& r) {
        if (p_.chorus.enabled) chorus_.process(l, r);
        if (p_.delay.enabled) delay_.process(l, r);
        if (p_.reverb.enabled) reverb_.process(l, r);
    }
    const FXParams& params() const { return p_; }
private:
    FXParams p_;
    Chorus chorus_;
    StereoDelay delay_;
    Reverb reverb_;
};

} // namespace muew
