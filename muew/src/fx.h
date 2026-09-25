#pragma once
#include <vector>
#include <cmath>
#include <algorithm>
#include <array>
#include "tempo_sync.h"
#include "mod_curve.h"
#include "filter.h"

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
    // Macro routes into the depth (Dest::FxChorusDepth), 1.0 = +10 ms.
    void setDepthOffset(double d) { depthOff_ = d; }
    inline void process(float& l, float& r) {
        const double depthMs = depthOff_ != 0.0 ? std::clamp(p_.depthMs + 10.0 * depthOff_, 0.0, 20.0) : p_.depthMs;
        double lfoL = std::sin(2.0 * M_PI * phase_);
        double lfoR = std::sin(2.0 * M_PI * phase_ + M_PI * 0.5);
        phase_ += p_.rateHz / sr_;
        phase_ -= std::floor(phase_);
        double dL = (p_.baseMs + depthMs * (0.5 + 0.5 * lfoL)) * 0.001 * sr_;
        double dR = (p_.baseMs + depthMs * (0.5 + 0.5 * lfoR)) * 0.001 * sr_;
        dl_.push(l); dr_.push(r);
        float wetL = dl_.read(dL), wetR = dr_.read(dR);
        l = (float)((1.0 - p_.mix) * l + p_.mix * wetL);
        r = (float)((1.0 - p_.mix) * r + p_.mix * wetR);
    }
    const ChorusParams& params() const { return p_; }
private:
    double sr_ = 44100.0, phase_ = 0.0, depthOff_ = 0.0;
    ChorusParams p_;
    DelayLine dl_, dr_;
};

struct DelayParams {
    bool enabled = false;
    double timeLSec = 0.28;
    double timeRSec = 0.42;
    double feedback = 0.35;
    double mix = 0.25;
    // 0.14.0: tempo sync per side (index into syncBeats, 0 = free time).
    int syncL = 0, syncR = 0;
};

// Stereo delay with independent L/R times and feedback.
class StereoDelay {
public:
    void init(double sr) {
        sr_ = sr;
        dl_.resize((int)(sr * 2.0) + 4);
        dr_.resize((int)(sr * 2.0) + 4);
    }
    void set(const DelayParams& p) { p_ = p; retime(); }
    void setTempo(double bpm) { if (bpm > 20.0 && bpm < 999.0 && bpm != bpm_) { bpm_ = bpm; retime(); } }
    // Macro routes into the feedback (Dest::FxDelayFeedback). 0 = untouched.
    void setFeedbackOffset(double d) { fbOff_ = d; }
    double feedback() const { return fbOff_ != 0.0 ? std::clamp(p_.feedback + fbOff_, 0.0, 0.95) : p_.feedback; }
    double timeL() const { return tL_; }
    double timeR() const { return tR_; }
    inline void process(float& l, float& r) {
        float fbL = dl_.read(tL_ * sr_);
        float fbR = dr_.read(tR_ * sr_);
        const float fb = (float)feedback();
        dl_.push(l + fbR * fb);   // cross-feedback for a wider tail
        dr_.push(r + fbL * fb);
        l = (float)((1.0 - p_.mix) * l + p_.mix * fbL);
        r = (float)((1.0 - p_.mix) * r + p_.mix * fbR);
    }
    const DelayParams& params() const { return p_; }
private:
    // Synced sides take their time from the host tempo (capped at the 2 s line).
    void retime() {
        auto t = [&](int sync, double sec) { double b = syncBeats(sync); return b > 0.0 ? std::min(1.99, b * 60.0 / bpm_) : sec; };
        tL_ = t(p_.syncL, p_.timeLSec); tR_ = t(p_.syncR, p_.timeRSec);
    }
    double sr_ = 44100.0, bpm_ = 120.0, fbOff_ = 0.0, tL_ = 0.28, tR_ = 0.42;
    DelayParams p_;
    DelayLine dl_, dr_;
};

struct ReverbParams {
    bool enabled = false;
    double decay = 0.6;   // 0..1 feedback amount (HALL/PLATE: RT60 on a log scale)
    double damping = 0.4; // 0..1 high-frequency loss
    double mix = 0.3;
    // 0.28.0: engine mode (0 CLASSIC = the 0.7.0 combs, 1 HALL, 2 PLATE; append only).
    // The rest only shape HALL/PLATE; CLASSIC ignores them so older sounds are unchanged.
    int mode = 0;
    double preDelayMs = 20.0; // 0..250
    double size = 0.6;        // 0..1 room size (delay-line lengths)
    double width = 1.0;       // 0..1 wet stereo width
    double lowCutHz = 100.0;  // 20..1000 wet high-pass
};

// 0.28.0 HALL / PLATE engine: stereo pre-delay, four input allpass diffusers
// per side, then an eight-line feedback delay network (Hadamard mixing) with
// per-line damping, gains set from the RT60 and slow modulation on four
// lines so the tail never rings metallic. HALL uses long, sparse lines;
// PLATE short, dense lines and brighter damping.
class SpaceReverb {
public:
    static constexpr int kLines = 8;
    void init(double sr) {
        sr_ = sr;
        pre_[0].resize((int)(sr * 0.26) + 4); pre_[1].resize((int)(sr * 0.26) + 4);
        for (auto& l : lines_) l.resize((int)(sr * 0.2) + 8);
        for (auto& side : diff_) for (auto& d : side) d.line.resize((int)(sr * 0.03) + 8);
        for (double& v : lp_) v = 0.0;
        for (int i = 0; i < 4; ++i) modPh_[i] = 0.25 * i;
        hpL_ = hpR_ = hpXL_ = hpXR_ = 0.0;
        configured_ = false;
    }
    // Rebuilds lengths and gains; cheap, called when parameters change.
    void configure(int mode, double decay, double damping, double size, double preDelayMs, double lowCutHz) {
        const bool plate = mode == 2;
        static const double hallMs[kLines] = {37.1, 41.9, 47.3, 53.9, 59.1, 67.7, 73.3, 79.9};
        static const double plateMs[kLines] = {11.3, 13.7, 17.1, 19.9, 23.3, 27.1, 29.9, 33.7};
        static const double diffMs[2][4] = {{4.71, 3.59, 12.73, 9.31}, {4.93, 3.77, 12.29, 9.67}};
        const double sz = std::clamp(size, 0.0, 1.0);
        const double scale = plate ? 0.6 + 0.8 * sz : 0.5 + sz;
        rt60_ = rt60(mode, decay);
        for (int i = 0; i < kLines; ++i) {
            len_[i] = (plate ? plateMs[i] : hallMs[i]) * 0.001 * scale * sr_;
            gain_[i] = std::pow(10.0, -3.0 * len_[i] / (rt60_ * sr_));
        }
        for (int c = 0; c < 2; ++c) for (int k = 0; k < 4; ++k) diff_[c][k].length = diffMs[c][k] * 0.001 * (0.6 + 0.6 * sz) * sr_;
        diffG_ = plate ? 0.75 : 0.68;
        damp_ = std::clamp(1.0 - std::clamp(damping, 0.0, 1.0) * (plate ? 0.6 : 0.85), 0.05, 1.0);
        modDepth_ = (plate ? 0.00012 : 0.00032) * sr_;
        preLen_ = std::clamp(preDelayMs, 0.0, 250.0) * 0.001 * sr_;
        hpA_ = std::exp(-2.0 * M_PI * std::clamp(lowCutHz, 20.0, 1000.0) / sr_);
        configured_ = true;
    }
    // RT60 (seconds) the DECAY knob gives in a mode: HALL 0.8..12 s, PLATE 0.5..6 s.
    static double rt60(int mode, double decay) {
        const double d = std::clamp(decay, 0.0, 0.97) / 0.97;
        return mode == 2 ? 0.5 * std::pow(12.0, d) : 0.8 * std::pow(15.0, d);
    }
    double rt60() const { return rt60_; }
    inline void process(float inL, float inR, float& wetL, float& wetR, double width) {
        pre_[0].push(inL); pre_[1].push(inR);
        double x[2] = {preLen_ >= 1.0 ? pre_[0].read(preLen_) : inL, preLen_ >= 1.0 ? pre_[1].read(preLen_) : inR};
        for (int c = 0; c < 2; ++c)
            for (auto& d : diff_[c]) { // Schroeder allpass
                const double buf = d.line.read(d.length);
                const double v = x[c] + diffG_ * buf;
                d.line.push((float)v);
                x[c] = buf - diffG_ * v;
            }
        double y[kLines];
        for (int i = 0; i < kLines; ++i) {
            double d = len_[i];
            if (i < 4) { d += modDepth_ * (1.0 + std::sin(2.0 * M_PI * modPh_[i])); modPh_[i] += kModHz[i] / sr_; modPh_[i] -= std::floor(modPh_[i]); }
            y[i] = lines_[i].read(d);
            lp_[i] += damp_ * (y[i] - lp_[i]);
            y[i] = lp_[i] * gain_[i];
        }
        // Fast Walsh-Hadamard transform, normalised: a lossless mix of all lines.
        for (int h = 1; h < kLines; h <<= 1)
            for (int i = 0; i < kLines; i += h << 1)
                for (int j = i; j < i + h; ++j) { const double a = y[j], b = y[j + h]; y[j] = a + b; y[j + h] = a - b; }
        for (int i = 0; i < kLines; ++i) lines_[i].push((float)(y[i] * 0.35355339059327373 + (i & 1 ? x[1] : x[0]) * 0.5));
        double l = (lp_[0] - lp_[2] + lp_[4] - lp_[6]) * 0.5, r = (lp_[1] - lp_[3] + lp_[5] - lp_[7]) * 0.5;
        // Wet low cut (one-pole high-pass), then width on mid/side.
        hpL_ = hpA_ * (hpL_ + l - hpXL_); hpXL_ = l;
        hpR_ = hpA_ * (hpR_ + r - hpXR_); hpXR_ = r;
        const double m = 0.5 * (hpL_ + hpR_), sd = 0.5 * (hpL_ - hpR_) * std::clamp(width, 0.0, 1.0);
        wetL = (float)(m + sd); wetR = (float)(m - sd);
    }
    bool configured() const { return configured_; }
private:
    struct AP { DelayLine line; double length = 1.0; };
    static constexpr double kModHz[4] = {0.31, 0.43, 0.57, 0.71};
    double sr_ = 44100.0, len_[kLines] = {}, gain_[kLines] = {}, lp_[kLines] = {}, modPh_[4] = {0.0, 0.25, 0.5, 0.75};
    double diffG_ = 0.7, damp_ = 0.5, modDepth_ = 0.0, preLen_ = 0.0, hpA_ = 1.0, rt60_ = 2.0;
    double hpL_ = 0, hpR_ = 0, hpXL_ = 0, hpXR_ = 0;
    bool configured_ = false;
    DelayLine pre_[2], lines_[kLines];
    AP diff_[2][4];
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
                combs_[ch][i].store = 0.0f; // 0.29.0: Reset clears the damping memory too
            }
            for (int i = 0; i < 2; ++i) {
                aps_[ch][i].line.resize(apTun[ch][i] + 4);
                aps_[ch][i].length = apTun[ch][i];
            }
        }
        space_.init(sr); // 0.28.0
        redecay();
    }
    void set(const ReverbParams& p) { p_ = p; redecay(); }
    const SpaceReverb& space() const { return space_; }
    // Macro routes into the decay (Dest::FxReverbDecay). 0 = untouched.
    void setDecayOffset(double d) { decOff_ = d; redecay(); }
    float decay() const { return decay_; }

    inline float processOne(int ch, float in) {
        float acc = 0.0f;
        for (auto& c : combs_[ch]) {
            float out = c.line.read(c.length);
            c.store += (out - c.store) * (float)p_.damping; // one-pole lowpass in the feedback path
            c.line.push(in + c.store * decay_);
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
        float wetL, wetR;
        if (p_.mode == 1 || p_.mode == 2) space_.process(l, r, wetL, wetR, p_.width); // 0.28.0 HALL / PLATE
        else { wetL = processOne(0, l); wetR = processOne(1, r); }
        l = (float)((1.0 - p_.mix) * l + p_.mix * wetL);
        r = (float)((1.0 - p_.mix) * r + p_.mix * wetR);
    }
    const ReverbParams& params() const { return p_; }
private:
    struct Comb { DelayLine line; int length = 0; float store = 0.0f; };
    struct AP { DelayLine line; int length = 0; };
    double sr_ = 44100.0;
    ReverbParams p_;
    float decay_ = 0.6f;
    double decOff_ = 0.0;
    void redecay() {
        decay_ = (float)(decOff_ != 0.0 ? std::clamp(p_.decay + decOff_, 0.0, 0.97) : p_.decay);
        if (p_.mode == 1 || p_.mode == 2) space_.configure(p_.mode, decay_, p_.damping, p_.size, p_.preDelayMs, p_.lowCutHz);
    }
    Comb combs_[2][4];
    AP aps_[2][2];
    SpaceReverb space_;
};

struct DistortionParams {
    bool enabled = false;
    int mode = 0;       // 0 soft clip, 1 fold, 2 bitcrush
    double drive = 0.4; // 0..1
    double mix = 1.0;   // 0..1
    int quality = 0;    // 0.29.0: 0 STANDARD, 1 HQ (soft clip and fold run 4x oversampled). Append only.
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
    void reset() { for (auto& h : os_) for (auto& s : h) s.reset(); holdCount_ = 0; heldL_ = heldR_ = 0; hqWas_ = false; }
    inline void process(float& l, float& r) {
        const double d = drive();
        if (hqActive()) {
            if (!hqWas_) { for (auto& h : os_) for (auto& st : h) st.reset(); hqWas_ = true; } // 0.30.0: start the 4x path clean
            processHQ(l, r, d); return;
        }
        hqWas_ = false;
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
    // 0.30.0: an HQ render (offline bounce) runs soft clip and fold at 4x whatever the QUALITY row says.
    void setForceHQ(bool on) { forceHQ_ = on; }
    bool hqActive() const { return (p_.quality == 1 || forceHQ_) && p_.mode != 2; }
    static constexpr double kHQLatencyExact = Halfband2x::kLatency * 1.5; // 22.5 samples at 1x
    static constexpr int kHQLatency = Halfband2x::kLatency + Halfband2x::kLatency / 2; // 22 whole samples (+0.5)
private:
    // 0.29.0 HQ: two halfband stages up to 4x; dry and wet mix inside the oversampled domain so they stay aligned.
    inline double shapeMix(double x, double d, float trim, float m) const { return x + m * (shape(p_.mode, d, (float)x) * trim - x); }
    inline void processHQ(float& l, float& r, double d) {
        const float trim = (float)(1.0 / (1.0 + d * (p_.mode == 0 ? 1.2 : 0.4)));
        const float m = (float)std::clamp(p_.mix, 0.0, 1.0);
        float* io[2] = {&l, &r};
        for (int c = 0; c < 2; ++c) {
            double a, b, q[4];
            os_[c][0].up(*io[c], a, b);
            os_[c][1].up(a, q[0], q[1]); os_[c][1].up(b, q[2], q[3]);
            for (double& v : q) v = shapeMix(v, d, trim, m);
            const double y0 = os_[c][2].down(q[0], q[1]), y1 = os_[c][2].down(q[2], q[3]);
            *io[c] = (float)os_[c][3].down(y0, y1);
        }
    }
    Halfband2x os_[2][4]; // per channel: up 1x->2x, up 2x->4x, down 4x->2x, down 2x->1x
    DistortionParams p_;
    double driveOffset_ = 0.0;
    int holdCount_ = 0;
    float heldL_ = 0, heldR_ = 0;
    bool forceHQ_ = false, hqWas_ = false; // 0.30.0
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
    void reset() { z1_ = z2_ = 0.0; } // 0.29.0
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
    void init(double sr) { sr_ = sr; set(p_); for (auto& ch : band_) for (auto& b : ch) b.reset(); }
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
    double amount = 0.5; // 0..1: one-knob threshold, ratio and makeup (MULTIBAND: depth)
    // 0.28.0: 0 ONE-KNOB (the 0.7.0 compressor), 1 MULTIBAND. Append only.
    // The rest only shape MULTIBAND; ONE-KNOB ignores them.
    int mode = 0;
    double upward = 0.4;  // 0..1 upward compression (lifts quiet detail)
    double speed = 0.5;   // 0..1 slow..fast attack/release
    double lowDb = 0.0, midDb = 0.0, highDb = 0.0; // -12..12 band output trims
    double mix = 1.0;     // 0..1
    int makeup = 0;       // 0.29.0 MULTIBAND auto gain: 0 off, 1 on. Append only.
};

// 0.28.0 MULTIBAND: three bands split at 120 Hz and 2.5 kHz by complementary
// two-pole lowpasses (low = LP(x), high = rest - LP(rest)), so with no gain
// change the bands sum back to the input exactly. Each band, stereo linked,
// is pushed down above its threshold and lifted below it (upward, faded out
// between -60 and -80 dBFS so silence and noise floors are not raised), then trimmed.
class MultibandComp {
    // Direct-form-II-transposed biquad in double precision (crossover sections).
    struct BQ {
        double b0 = 1, b1 = 0, b2 = 0, a1 = 0, a2 = 0, z1 = 0, z2 = 0;
        void design(int kind, double sr, double hz) { // 0 low pass, 1 high pass, 2 all pass; Q = 1/sqrt(2)
            z1 = z2 = 0.0;
            const double w = 2.0 * M_PI * hz / sr, cw = std::cos(w), al = std::sin(w) / (2.0 * M_SQRT1_2), a0 = 1.0 + al;
            if (kind == 0) { b0 = (1 - cw) / 2; b1 = 1 - cw; b2 = (1 - cw) / 2; }
            else if (kind == 1) { b0 = (1 + cw) / 2; b1 = -(1 + cw); b2 = (1 + cw) / 2; }
            else { b0 = 1 - al; b1 = -2 * cw; b2 = 1 + al; }
            b0 /= a0; b1 /= a0; b2 /= a0; a1 = -2 * cw / a0; a2 = (1 - al) / a0;
        }
        inline double run(double x) { const double y = b0 * x + z1; z1 = b1 * x - a1 * y + z2; z2 = b2 * x - a2 * y; return y; }
    };
public:
    static constexpr int kBands = 3;
    // Linkwitz-Riley 4th-order splits: the bands stay in phase with each other, so lifting or cutting
    // one never cancels its neighbours; the low band passes the 2.5 kHz split's all-pass to stay aligned.
    void init(double sr) {
        sr_ = sr;
        // Reset clears the detectors, gains and crossover memories (a host Reset must not carry the last note's state).
        for (int b = 0; b < kBands; ++b) { env_[b] = 0.0; gDb_[b] = 0.0; }
        for (int c = 0; c < 2; ++c) {
            for (int k = 0; k < 2; ++k) { lp1_[c][k].design(0, sr, 120.0); hp1_[c][k].design(1, sr, 120.0);
                                          lp2_[c][k].design(0, sr, 2500.0); hp2_[c][k].design(1, sr, 2500.0); }
            ap_[c].design(2, sr, 2500.0);
            dryAp_[c][0].design(2, sr, 120.0); dryAp_[c][1].design(2, sr, 2500.0);
        }
        setTimes(0.5);
    }
    void set(const CompressorParams& p) {
        p_ = p;
        setTimes(p.speed);
        const double d = std::clamp(p.amount, 0.0, 1.0);
        thrDb_ = -12.0 - 18.0 * d;
        ratio_ = 1.0 + 5.0 * d;
        upThrDb_ = thrDb_ - 6.0;
        upRatio_ = 1.0 + 3.0 * std::clamp(p.upward, 0.0, 1.0) * d;
        upMaxDb_ = 18.0 * std::clamp(p.upward, 0.0, 1.0);
        trim_[0] = std::pow(10.0, std::clamp(p.lowDb, -12.0, 12.0) / 20.0);
        trim_[1] = std::pow(10.0, std::clamp(p.midDb, -12.0, 12.0) / 20.0);
        trim_[2] = std::pow(10.0, std::clamp(p.highDb, -12.0, 12.0) / 20.0);
        // 0.29.0 AUTO GAIN: give back half the squeeze a -12 dBFS band gets, at most +12 dB.
        makeup_ = p.makeup ? std::pow(10.0, std::clamp(-0.5 * gainFor(-12.0), 0.0, 12.0) / 20.0) : 1.0;
    }
    double makeupDb() const { return 20.0 * std::log10(makeup_); }
    // Static gain (dB) a band applies at a steady input level; the panel draws it.
    double staticGainDb(double levelDb) const { return gainFor(levelDb); }
    double bandGainDb(int b) const { return gDb_[std::clamp(b, 0, kBands - 1)]; }
    inline void process(float& l, float& r) {
        double in[2] = {l, r}, band[2][kBands];
        for (int c = 0; c < 2; ++c) {
            const double low = ap_[c].run(lp1_[c][1].run(lp1_[c][0].run(in[c])));
            const double rest = hp1_[c][1].run(hp1_[c][0].run(in[c]));
            band[c][0] = low; band[c][1] = lp2_[c][1].run(lp2_[c][0].run(rest)); band[c][2] = hp2_[c][1].run(hp2_[c][0].run(rest));
        }
        double out[2] = {0.0, 0.0};
        for (int b = 0; b < kBands; ++b) {
            const double pk = std::max(std::fabs(band[0][b]), std::fabs(band[1][b]));
            env_[b] = pk > env_[b] ? pk + atk_ * (env_[b] - pk) : pk + rel_ * (env_[b] - pk);
            const double target = gainFor(20.0 * std::log10(env_[b] + 1e-9));
            gDb_[b] = target + (target < gDb_[b] ? gAtk_ : gRel_) * (gDb_[b] - target);
            const double g = std::pow(10.0, gDb_[b] / 20.0) * trim_[b] * makeup_;
            out[0] += band[0][b] * g; out[1] += band[1][b] * g;
        }
        const double mix = std::clamp(p_.mix, 0.0, 1.0);
        if (mix >= 1.0) { l = (float)out[0]; r = (float)out[1]; return; }
        // The dry side takes the crossovers' all-pass phase so a part-wet MIX never combs.
        const double d0 = dryAp_[0][1].run(dryAp_[0][0].run(in[0])), d1 = dryAp_[1][1].run(dryAp_[1][0].run(in[1]));
        l = (float)((1.0 - mix) * d0 + mix * out[0]);
        r = (float)((1.0 - mix) * d1 + mix * out[1]);
    }
private:
    double coef(double hz) const { return 1.0 - std::exp(-2.0 * M_PI * hz / sr_); }
    void setTimes(double speed) {
        const double s = std::clamp(speed, 0.0, 1.0);
        const double atkMs = 12.0 - 10.0 * s, relMs = 260.0 - 200.0 * s;
        atk_ = std::exp(-1.0 / (atkMs * 0.001 * sr_)); rel_ = std::exp(-1.0 / (relMs * 0.001 * sr_));
        gAtk_ = std::exp(-1.0 / (0.002 * sr_)); gRel_ = std::exp(-1.0 / (relMs * 0.0005 * sr_));
    }
    double gainFor(double lv) const {
        if (lv > thrDb_) return -(lv - thrDb_) * (1.0 - 1.0 / ratio_);
        if (lv < upThrDb_ && upMaxDb_ > 0.0) {
            double up = std::min(upMaxDb_, (upThrDb_ - lv) * (1.0 - 1.0 / upRatio_));
            if (lv < -60.0) up *= std::clamp((lv + 80.0) / 20.0, 0.0, 1.0); // fades out from -60 to -80 dBFS: noise floors stay put
            return up;
        }
        return 0.0;
    }
    double sr_ = 44100.0, atk_ = 0.0, rel_ = 0.0, gAtk_ = 0.0, gRel_ = 0.0;
    double thrDb_ = -21.0, ratio_ = 3.5, upThrDb_ = -27.0, upRatio_ = 1.6, upMaxDb_ = 7.2;
    BQ lp1_[2][2], hp1_[2][2], lp2_[2][2], hp2_[2][2], ap_[2], dryAp_[2][2];
    double env_[kBands] = {}, gDb_[kBands] = {}, trim_[kBands] = {1.0, 1.0, 1.0}, makeup_ = 1.0;
    CompressorParams p_;
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
        mb_.init(sr); mb_.set(p_); // 0.28.0
        env_ = 0.0; grDb_ = 0.0;     // 0.29.0: a host Reset starts the detector fresh
    }
    void set(const CompressorParams& p) {
        p_ = p;
        const double a = std::clamp(p.amount, 0.0, 1.0);
        thrDb_ = -6.0 - 30.0 * a;
        ratio_ = 1.5 + 6.5 * a;
        makeupDb_ = std::min(6.0, -thrDb_ * (1.0 - 1.0 / ratio_) * 0.3);
        mb_.set(p);
    }
    const MultibandComp& multiband() const { return mb_; }
    inline void process(float& l, float& r) {
        if (p_.mode == 1) { mb_.process(l, r); return; } // 0.28.0 MULTIBAND
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
    MultibandComp mb_;
};

struct PhaserParams {
    bool enabled = false;
    double rateHz = 0.4;   // 0.02..8
    double depth = 0.7;    // 0..1 sweep width
    double feedback = 0.5; // 0..0.9
    double mix = 0.5;      // 0..1
};

// Six first-order allpass stages per channel with a swept break frequency
// (log sweep 180 Hz to ~4.5 kHz at full depth). The right channel's LFO runs
// a quarter cycle ahead for width. Feedback from the last stage deepens the
// notches. 0.13.0.
class Phaser {
public:
    void init(double sr) { sr_ = sr; }
    void set(const PhaserParams& p) { p_ = p; }
    // Macro routes into the depth (Dest::FxPhaserDepth). 0 = untouched.
    void setDepthOffset(double d) { depthOff_ = d; }
    inline void process(float& l, float& r) {
        const double fb = std::clamp(p_.feedback, 0.0, 0.9), mix = std::clamp(p_.mix, 0.0, 1.0);
        const double depth = std::clamp(p_.depth + depthOff_, 0.0, 1.0);
        // Dry + swept copy cancels about half the power at mid mix; this
        // keeps switching the unit on at roughly the same loudness.
        const double comp = 1.0 / std::sqrt((1.0 - mix) * (1.0 - mix) + mix * mix);
        for (int ch = 0; ch < 2; ++ch) {
            double lfo = 0.5 + 0.5 * std::sin(2.0 * M_PI * (phase_ + ch * 0.25));
            double hz = 180.0 * std::pow(25.0, depth * lfo);
            double t = std::tan(M_PI * std::min(hz, sr_ * 0.45) / sr_);
            double a = (t - 1.0) / (t + 1.0);
            // Negative, soft-limited feedback: no low-end build-up, and the
            // resonance stays bounded; the wet side is trimmed to match.
            double x = (ch ? r : l) - fb * std::tanh(last_[ch]);
            for (int k = 0; k < kStages; ++k) {
                double y = a * x + s_[ch][k];
                s_[ch][k] = x - a * y;
                if (std::fabs(s_[ch][k]) < 1e-20) s_[ch][k] = 0.0;
                x = y;
            }
            last_[ch] = x;
            x *= 1.0 - 0.25 * fb;
            float& io = ch ? r : l;
            io = (float)(((1.0 - mix) * io + mix * x) * comp);
        }
        phase_ += std::clamp(p_.rateHz, 0.02, 8.0) / sr_;
        phase_ -= std::floor(phase_);
    }
    const PhaserParams& params() const { return p_; }
private:
    static const int kStages = 6;
    double sr_ = 44100.0, phase_ = 0.0, depthOff_ = 0.0;
    double s_[2][kStages] = {}, last_[2] = {};
    PhaserParams p_;
};

struct FlangerParams {
    bool enabled = false;
    double rateHz = 0.25;  // 0.02..8
    double depth = 0.7;    // 0..1: sweep 0.3 ms to 0.3 + 4 ms
    double feedback = 0.5; // 0..0.9
    double mix = 0.5;      // 0..1
};

// Short modulated delay with feedback: the comb notches sweep through the
// spectrum. Quadrature LFOs per side. 0.13.0.
class Flanger {
public:
    void init(double sr) {
        sr_ = sr;
        int maxD = (int)(sr * 0.01) + 4;
        dl_.resize(maxD); dr_.resize(maxD);
    }
    void set(const FlangerParams& p) { p_ = p; }
    // Macro routes into the depth (Dest::FxFlangerDepth). 0 = untouched.
    void setDepthOffset(double d) { depthOff_ = d; }
    inline void process(float& l, float& r) {
        const double fb = std::clamp(p_.feedback, 0.0, 0.9), mix = std::clamp(p_.mix, 0.0, 1.0);
        const double depth = std::clamp(p_.depth + depthOff_, 0.0, 1.0);
        double lfoL = 0.5 + 0.5 * std::sin(2.0 * M_PI * phase_);
        double lfoR = 0.5 + 0.5 * std::sin(2.0 * M_PI * (phase_ + 0.25));
        double dL = (0.3 + 4.0 * depth * lfoL) * 0.001 * sr_;
        double dR = (0.3 + 4.0 * depth * lfoR) * 0.001 * sr_;
        float wL = dl_.read(dL), wR = dr_.read(dR);
        dl_.push(l + (float)(fb * std::tanh(wL)));
        dr_.push(r + (float)(fb * std::tanh(wR)));
        wL *= (float)(1.0 - 0.25 * fb); wR *= (float)(1.0 - 0.25 * fb);
        const double comp = 1.0 / std::sqrt((1.0 - mix) * (1.0 - mix) + mix * mix); // level match, as in Phaser
        l = (float)(((1.0 - mix) * l + mix * wL) * comp);
        r = (float)(((1.0 - mix) * r + mix * wR) * comp);
        phase_ += std::clamp(p_.rateHz, 0.02, 8.0) / sr_;
        phase_ -= std::floor(phase_);
    }
    const FlangerParams& params() const { return p_; }
private:
    double sr_ = 44100.0, phase_ = 0.0, depthOff_ = 0.0;
    FlangerParams p_;
    DelayLine dl_, dr_;
};

// ---- 0.27.0 HYPER / DIMENSION ----
struct HyperParams {
    bool enabled = false;
    double rateHz = 0.35;  // 0.05..5: drift speed of the detuned copies
    double detune = 0.5;   // 0..1: pitch spread (full = about +-18 cents)
    double dimension = 0.4;// 0..1: cross-fed early taps that widen the image
    double mix = 0.5;      // 0..1
};

// Six detuned copies of the signal (short delay lines, each swept by its own
// slow sine at a different rate and phase, panned alternately left/right) plus
// a dimension stage: four short cross-fed taps with alternating polarity and a
// gentle lowpass, which spread the image without a comb-y tone. 0.27.0.
class Hyper {
public:
    void init(double sr) {
        sr_ = sr;
        const int maxD = (int)(sr * 0.06) + 4;
        dl_.resize(maxD); dr_.resize(maxD);
    }
    void set(const HyperParams& p) { p_ = p; }
    // Mod routes into the detune (Dest::FxHyperDetune). 0 = untouched.
    void setDetuneOffset(double d) { detOff_ = d; }
    inline void process(float& l, float& r) {
        const double mix = std::clamp(p_.mix, 0.0, 1.0), det = std::clamp(p_.detune + detOff_, 0.0, 1.0);
        const double dim = std::clamp(p_.dimension, 0.0, 1.0), rate = std::clamp(p_.rateHz, 0.05, 5.0);
        dl_.push(l); dr_.push(r);
        // Sweep amplitude so the peak pitch change is ~18 cents at full detune
        // regardless of rate (Doppler: ratio = 2 pi f A).
        const double amp = det * 0.0104 / (2.0 * M_PI * rate);
        double wl = 0.0, wr = 0.0;
        for (int v = 0; v < kVoices; ++v) {
            const double ph = phase_[v];
            const double d = (kBaseMs[v] * 0.001 + std::min(amp, 0.012) * (0.5 + 0.5 * std::sin(2.0 * M_PI * ph))) * sr_;
            const float x = (v & 1) ? dr_.read(d) : dl_.read(d);
            const double pan = kPan[v];
            wl += x * (1.0 - pan); wr += x * (1.0 + pan);
            phase_[v] += rate * kRateMul[v] / sr_;
            phase_[v] -= std::floor(phase_[v]);
        }
        wl *= kGain; wr *= kGain;
        // Dimension: cross-fed taps, low-passed at ~6 kHz.
        const double tl = (dr_.read(kTap[0] * sr_) - dr_.read(kTap[2] * sr_)) * 0.5;
        const double tr = (dl_.read(kTap[1] * sr_) - dl_.read(kTap[3] * sr_)) * 0.5;
        lpL_ += kLp * (tl - lpL_); lpR_ += kLp * (tr - lpR_);
        wl += dim * 0.7 * lpL_; wr += dim * 0.7 * lpR_;
        const double comp = 1.0 / std::sqrt((1.0 - mix) * (1.0 - mix) + mix * mix);
        l = (float)(((1.0 - mix) * l + mix * wl) * comp);
        r = (float)(((1.0 - mix) * r + mix * wr) * comp);
    }
    const HyperParams& params() const { return p_; }
    // Panel display: voice layout and the peak pitch swing (cents) of voice v.
    static constexpr int kVoices = 6;
    static double voicePan(int v) { return kPan[std::clamp(v, 0, kVoices - 1)]; }
    static double voiceBaseMs(int v) { return kBaseMs[std::clamp(v, 0, kVoices - 1)]; }
    static double peakCents(int v, double rateHz, double detune) {
        const double rate = std::clamp(rateHz, 0.05, 5.0), det = std::clamp(detune, 0.0, 1.0);
        const double a = std::min(det * 0.0104 / (2.0 * M_PI * rate), 0.012);
        return 1200.0 * std::log2(1.0 + 2.0 * M_PI * rate * kRateMul[std::clamp(v, 0, kVoices - 1)] * a);
    }
private:
    static constexpr double kBaseMs[kVoices] = {9.0, 11.3, 13.7, 16.1, 19.3, 22.9};
    static constexpr double kRateMul[kVoices] = {1.0, 1.17, 0.83, 1.31, 0.71, 1.07};
    static constexpr double kPan[kVoices] = {-0.9, 0.9, -0.5, 0.5, -0.2, 0.2};
    static constexpr double kTap[4] = {0.0131, 0.0173, 0.0229, 0.0293};
    static constexpr double kGain = 0.42;  // six copies summed back near unity
    static constexpr double kLp = 0.58;    // one-pole ~6 kHz at 44.1 kHz
    double sr_ = 44100.0, detOff_ = 0.0, lpL_ = 0.0, lpR_ = 0.0;
    double phase_[kVoices] = {0.0, 0.17, 0.33, 0.5, 0.67, 0.83};
    HyperParams p_;
    DelayLine dl_, dr_;
};

// ---- 0.27.0 FILTER FX ----
struct FilterFxParams {
    bool enabled = false;
    int mode = 0;          // 0 LP, 1 BP, 2 HP, 3 NOTCH, 4 PEAK (SVFilter modes). Append only.
    double cutoffHz = 1200;// 40..18000
    double reso = 0.3;     // 0..1 -> Q 0.5..14
    double drive = 0.0;    // 0..1 pre-filter saturation
    double lfoRateHz = 0.5;// 0.02..20 cutoff sweep
    int lfoSync = 0;       // syncBeats index, 0 = free
    double lfoDepth = 0.0; // 0..1 -> +-4 octaves
    double mix = 1.0;      // 0..1
};

// A stereo state-variable filter as an effect: optional drive, a cutoff that
// can sweep with its own LFO (free or tempo-synced; the right side runs a
// little ahead for motion) and a dry/wet mix. 0.27.0.
class FilterFx {
public:
    void init(double sr) { sr_ = sr; fl_.setSampleRate(sr); fr_.setSampleRate(sr); tick_ = 0; }
    void set(const FilterFxParams& p) {
        p_ = p;
        const auto m = static_cast<SVFilter::Mode>(std::clamp(p.mode, 0, 4));
        fl_.setMode(m); fr_.setMode(m);
        tick_ = 0;
    }
    void setTempo(double bpm) { if (bpm > 20.0 && bpm < 999.0) bpm_ = bpm; }
    // Mod routes into the cutoff, in octaves (Dest::FxFilterCutoff). 0 = untouched.
    void setCutoffOffset(double oct) { cutOff_ = oct; }
    double lfoHz() const { const double b = syncBeats(p_.lfoSync); return b > 0.0 ? (bpm_ / 60.0) / b : std::clamp(p_.lfoRateHz, 0.02, 20.0); }
    double lfoPhase() const { return phase_; }
    void lockPhase(double beat) { const double b = syncBeats(p_.lfoSync); if (b > 0.0) { const double ph = beat / b; phase_ = ph - std::floor(ph); } }
    // Cutoff (Hz) the filter is at now, for the detail page.
    double cutoffNow(int ch = 0) const {
        const double lfo = std::sin(2.0 * M_PI * (phase_ + ch * 0.08));
        return std::clamp(std::clamp(p_.cutoffHz, 40.0, 18000.0) * std::pow(2.0, cutOff_ + 4.0 * std::clamp(p_.lfoDepth, 0.0, 1.0) * lfo), 20.0, sr_ * 0.45);
    }
    inline void process(float& l, float& r) {
        if (--tick_ < 0) { // recompute coefficients every 16 samples
            tick_ = 15;
            const double q = 0.5 * std::pow(28.0, std::clamp(p_.reso, 0.0, 1.0));
            fl_.set(cutoffNow(0), q); fr_.set(cutoffNow(1), q);
        }
        const double mix = std::clamp(p_.mix, 0.0, 1.0), drv = std::clamp(p_.drive, 0.0, 1.0);
        double xl = l, xr = r;
        if (drv > 0.0) { const double g = 1.0 + 7.0 * drv, n = 1.0 / std::tanh(g); xl = std::tanh(xl * g) * n; xr = std::tanh(xr * g) * n; }
        const double yl = fl_.process((float)xl), yr = fr_.process((float)xr);
        l = (float)((1.0 - mix) * l + mix * yl);
        r = (float)((1.0 - mix) * r + mix * yr);
        phase_ += lfoHz() / sr_;
        phase_ -= std::floor(phase_);
    }
    const FilterFxParams& params() const { return p_; }
private:
    double sr_ = 44100.0, bpm_ = 120.0, phase_ = 0.0, cutOff_ = 0.0;
    int tick_ = 0;
    SVFilter fl_, fr_;
    FilterFxParams p_;
};

// FX units by stable id. The ids are the serialized chain-order values:
// append-only, never renumber.
enum FxUnit { FxDist, FxChorus, FxDelay, FxComp, FxReverb, FxEQ, FxPhaser, FxFlanger, FxHyper, FxFilter, kFxUnits }; // 0.27.0: HYPER, FILTER appended

inline const char* fxUnitName(int u) {
    static const char* n[kFxUnits] = {"dist", "chorus", "delay", "comp", "reverb", "eq", "phaser", "flanger", "hyper", "filterfx"};
    return (u >= 0 && u < kFxUnits) ? n[u] : "";
}

// Chain order: slot -> unit id. The default is the 0.7.0 signal order with
// the 0.13.0 units appended, so older presets render exactly as before.
struct FxOrder {
    int slot[kFxUnits] = {FxDist, FxChorus, FxDelay, FxComp, FxReverb, FxEQ, FxPhaser, FxFlanger, FxHyper, FxFilter};
    bool isDefault() const { for (int i = 0; i < kFxUnits; ++i) if (slot[i] != i) return false; return true; }
    bool operator==(const FxOrder& o) const { for (int i = 0; i < kFxUnits; ++i) if (slot[i] != o.slot[i]) return false; return true; }
    bool operator!=(const FxOrder& o) const { return !(*this == o); }
    int slotOf(int unit) const { for (int i = 0; i < kFxUnits; ++i) if (slot[i] == unit) return i; return -1; }
    // Takes the unit in slot `from` out and reinserts it at slot `to`;
    // the units between shift by one. Returns false for a no-op or bad slot.
    bool move(int from, int to) {
        if (from < 0 || from >= kFxUnits || to < 0 || to >= kFxUnits || from == to) return false;
        int u = slot[from];
        if (from < to) for (int i = from; i < to; ++i) slot[i] = slot[i + 1];
        else for (int i = from; i > to; --i) slot[i] = slot[i - 1];
        slot[to] = u;
        return true;
    }
    // Accepts only a full permutation of the known units.
    bool assign(const int* v, int n) {
        if (n != kFxUnits) return false;
        bool seen[kFxUnits] = {};
        for (int i = 0; i < n; ++i) { if (v[i] < 0 || v[i] >= kFxUnits || seen[v[i]]) return false; seen[v[i]] = true; }
        for (int i = 0; i < n; ++i) slot[i] = v[i];
        return true;
    }
};

// 0.15.0: two free-running LFOs for the shared FX rack (matrix sources
// FX LFO 1/2). Bipolar sine / triangle / saw / square; sync > 0 locks the
// cycle to the host tempo (syncBeats beats per cycle).
struct RackLfoParams {
    double rateHz = 0.5; // 0.02..20
    int shape = 0;       // 0 sine, 1 triangle, 2 saw, 3 square
    int sync = 0;
    bool operator==(const RackLfoParams& o) const { return rateHz == o.rateHz && shape == o.shape && sync == o.sync; }
    bool operator!=(const RackLfoParams& o) const { return !(*this == o); }
};
inline double rackLfoValue(int shape, double ph) {
    switch (shape) {
    case 1: return ph < 0.5 ? 4.0 * ph - 1.0 : 3.0 - 4.0 * ph;
    case 2: return 2.0 * ph - 1.0;
    case 3: return ph < 0.5 ? 1.0 : -1.0;
    default: return std::sin(2.0 * M_PI * ph);
    }
}

struct FXParams {
    ChorusParams chorus;
    DelayParams delay;
    ReverbParams reverb;
    // 0.7.0 rack additions. Off by default, so older presets are unchanged.
    DistortionParams dist;
    EQParams eq;
    CompressorParams comp;
    // 0.13.0: phaser, flanger (off by default) and a reorderable chain.
    PhaserParams phaser;
    FlangerParams flanger;
    FxOrder order;
    RackLfoParams lfo[2]; // 0.15.0
    // 0.27.0 (off by default; appended to the chain)
    HyperParams hyper;
    FilterFxParams filter;
};

// Rack order comes from FXParams::order (default: distortion -> chorus ->
// delay -> compressor -> reverb -> EQ -> phaser -> flanger). Each stage
// passes through untouched when off.
class FXChain {
public:
    static constexpr int kRouteMeters = 16;
    // init is also the host Reset (0.29.0): every unit starts from power-on state - buffers, filter
    // memories, LFO phases, detectors - then the current sound and tempo are put back.
    void init(double sr) {
        const FXParams keep = p_; const double bpm = bpm_; const Mod base = base_; const std::vector<LfoRoute> routes = lfoRoutes_;
        chorus_ = Chorus{}; delay_ = StereoDelay{}; reverb_ = Reverb{}; dist_ = Distortion{}; eq_ = EQ3{}; comp_ = Compressor{};
        phaser_ = Phaser{}; flanger_ = Flanger{}; hyper_ = Hyper{}; filter_ = FilterFx{};
        lfoPhase_[0] = lfoPhase_[1] = 0.0; lfoTick_ = 0;
        sr_ = sr; chorus_.init(sr); delay_.init(sr); reverb_.init(sr); eq_.init(sr); comp_.init(sr); phaser_.init(sr); flanger_.init(sr); hyper_.init(sr); filter_.init(sr);
        set(keep); setTempo(bpm);
        if (!routes.empty()) setLfoRoutes(base, routes); else { base_ = base; setMod(base); }
    }
    void set(const FXParams& p) {
        chorus_.set(p.chorus); delay_.set(p.delay); reverb_.set(p.reverb);
        dist_.set(p.dist); eq_.set(p.eq); comp_.set(p.comp);
        phaser_.set(p.phaser); flanger_.set(p.flanger);
        hyper_.set(p.hyper);
        filter_.set(p.filter);
        p_ = p;
    }
    // Macro routes into the distortion drive (Dest::DistDrive).
    void setDriveOffset(double d) { dist_.setDriveOffset(d); }
    // 0.30.0 HQ render and the latency the chain adds (samples at 1x).
    void setForceHQ(bool on) { dist_.setForceHQ(on); }
    double latencySamples() const { return p_.dist.enabled && dist_.hqActive() ? Distortion::kHQLatencyExact : 0.0; }
    // 0.14.0: macro routes into the detail controls (global FX, macro sources).
    struct Mod { double drive = 0, delayFeedback = 0, reverbDecay = 0, phaserDepth = 0, flangerDepth = 0, chorusDepth = 0;
                 double hyperDetune = 0, filterCutoff = 0; }; // 0.27.0 (filterCutoff: 1 = +4 octaves)
    void setMod(const Mod& m) {
        dist_.setDriveOffset(m.drive); delay_.setFeedbackOffset(m.delayFeedback); reverb_.setDecayOffset(m.reverbDecay);
        phaser_.setDepthOffset(m.phaserDepth); flanger_.setDepthOffset(m.flangerDepth); chorus_.setDepthOffset(m.chorusDepth);
        hyper_.setDetuneOffset(m.hyperDetune); filter_.setCutoffOffset(4.0 * m.filterCutoff);
    }
    void setTempo(double bpm) { delay_.setTempo(bpm); filter_.setTempo(bpm); if (bpm > 20.0 && bpm < 999.0) bpm_ = bpm; }
    const Hyper& hyper() const { return hyper_; }
    const FilterFx& filterFx() const { return filter_; }
    // 0.15.0: routes from the rack LFOs. The static (macro) part is `base`;
    // every kLfoBlock samples the LFO part is added on top. No LFO routes
    // leaves the rack exactly as setMod left it.
    // 0.16.0: lfo -1 is a static (macro) value `value` whose route has a rack
    // LFO aux; curve shapes the LFO; auxLfo (-1 none) scales by its 0..1 level;
    // auxScale is a static aux factor (a macro aux), 1 = none.
    struct LfoRoute { int lfo; int dest; double amount; double curve = 0.0; int auxLfo = -1; double auxScale = 1.0; double value = 0.0; int slot = -1; };
    enum { kDrive, kDelayFb, kRevDecay, kPhDepth, kFlDepth, kChDepth, kHyDetune, kFiCutoff };
    void setRouteBaseMeter(int slot, float level) {
        if (slot >= 0 && slot < kRouteMeters) routeLevel_[slot] = level;
    }
    void clearRouteMeters() { routeLevel_.fill(0.0f); }
    float routeLevel(int slot) const { return slot >= 0 && slot < kRouteMeters ? routeLevel_[slot] : 0.0f; }
    void setLfoRoutes(const Mod& base, const std::vector<LfoRoute>& routes) {
        base_ = base; lfoRoutes_ = routes;
        if (routes.empty()) setMod(base); else lfoTick_ = 0;
    }
    double rackLfoHz(int k) const {
        const auto& l = p_.lfo[k];
        double b = syncBeats(l.sync);
        return b > 0.0 ? (bpm_ / 60.0) / b : std::clamp(l.rateHz, 0.02, 20.0);
    }
    double rackLfoPhase(int k) const { return lfoPhase_[k]; }
    // 0.26.0: synced rack LFOs follow the host beat (clock sync, transport playing).
    void lockLfos(double beat) {
        for (int k = 0; k < 2; ++k) {
            const double b = syncBeats(p_.lfo[k].sync);
            if (b > 0.0) { const double ph = beat / b; lfoPhase_[k] = ph - std::floor(ph); }
        }
        filter_.lockPhase(beat); // 0.27.0: a synced FILTER FX sweep follows the bar too
    }
    const StereoDelay& delay() const { return delay_; }
    const Reverb& reverb() const { return reverb_; }
    inline void process(float& l, float& r) {
        if (!lfoRoutes_.empty() && --lfoTick_ < 0) updateLfoMod();
        for (int i = 0; i < kFxUnits; ++i) {
            switch (p_.order.slot[i]) {
            case FxDist: if (p_.dist.enabled) dist_.process(l, r); break;
            case FxChorus: if (p_.chorus.enabled) chorus_.process(l, r); break;
            case FxDelay: if (p_.delay.enabled) delay_.process(l, r); break;
            case FxComp: if (p_.comp.enabled) comp_.process(l, r); break;
            case FxReverb: if (p_.reverb.enabled) reverb_.process(l, r); break;
            case FxEQ: if (p_.eq.enabled) eq_.process(l, r); break;
            case FxPhaser: if (p_.phaser.enabled) phaser_.process(l, r); break;
            case FxFlanger: if (p_.flanger.enabled) flanger_.process(l, r); break;
            case FxHyper: if (p_.hyper.enabled) hyper_.process(l, r); break;
            case FxFilter: if (p_.filter.enabled) filter_.process(l, r); break;
            default: break;
            }
        }
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
    Phaser phaser_;
    Flanger flanger_;
    Hyper hyper_;      // 0.27.0
    FilterFx filter_;  // 0.27.0
    static const int kLfoBlock = 32;
    double sr_ = 44100.0, bpm_ = 120.0, lfoPhase_[2] = {0, 0};
    int lfoTick_ = 0;
    Mod base_;
    std::vector<LfoRoute> lfoRoutes_;
    std::array<float, kRouteMeters> routeLevel_{}; // latest rack tick, audio-thread owned
    void updateLfoMod() {
        lfoTick_ = kLfoBlock - 1;
        double v[2];
        for (int k = 0; k < 2; ++k) {
            v[k] = rackLfoValue(p_.lfo[k].shape, lfoPhase_[k]);
            lfoPhase_[k] += kLfoBlock * rackLfoHz(k) / sr_;
            lfoPhase_[k] -= std::floor(lfoPhase_[k]);
        }
        Mod m = base_;
        for (const auto& r : lfoRoutes_) {
            double src = r.lfo >= 0 ? v[r.lfo & 1] : r.value;
            if (r.lfo >= 0 && r.curve != 0.0) src = routeCurve(src, r.curve);
            if (r.auxScale != 1.0) src *= r.auxScale;
            if (r.auxLfo >= 0) src *= std::clamp(0.5 * (v[r.auxLfo & 1] + 1.0), 0.0, 1.0);
            const double x = src * r.amount;
            if (r.slot >= 0 && r.slot < kRouteMeters)
                routeLevel_[r.slot] = (float)std::clamp(x, -1.0, 1.0);
            switch (r.dest) {
            case kDrive: m.drive += x; break;
            case kDelayFb: m.delayFeedback += x; break;
            case kRevDecay: m.reverbDecay += x; break;
            case kPhDepth: m.phaserDepth += x; break;
            case kFlDepth: m.flangerDepth += x; break;
            case kHyDetune: m.hyperDetune += x; break;
            case kFiCutoff: m.filterCutoff += x; break;
            default: m.chorusDepth += x; break;
            }
        }
        setMod(m);
    }
};

} // namespace muew
