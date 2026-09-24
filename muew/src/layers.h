#pragma once
// layers.h - 0.10.0 extra sound layers: a sub oscillator, a noise source and
// a second filter (low/band/high pass, comb, formant) that runs in series or
// in parallel with the main filter. All of them are skipped entirely while
// unused, so every sound written before 0.10.0 renders sample-identical.
#include "filter.h"
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <vector>

namespace muew {

// Sub oscillator shapes (stored in presets, append only) and the built-in
// wavetable shape each one plays.
constexpr int kSubShapes = 3; // SINE, TRI, SQUARE
inline int subTableShape(int s) { static const int m[kSubShapes] = {0, 1, 3}; return m[std::clamp(s, 0, kSubShapes - 1)]; }

// White noise through a one-pole lowpass. tone 1 = white, 0 = dark (~200 Hz).
class NoiseSource {
public:
    void setSampleRate(double sr) { sr_ = sr; tone_ = -1; }
    void reset(uint32_t seed) { state_ = seed ? seed : 0x9e3779b9u; lp_ = 0; }
    void setTone(double tone) {
        tone = std::clamp(tone, 0.0, 1.0);
        if (tone == tone_) return;
        tone_ = tone;
        const double fc = 200.0 * std::pow(2.0, tone * 7.0); // 200 Hz .. 25.6 kHz
        a_ = tone >= 1.0 ? 1.0 : 1.0 - std::exp(-2.0 * M_PI * std::min(fc, sr_ * 0.45) / sr_);
    }
    inline float process() {
        state_ ^= state_ << 13; state_ ^= state_ >> 17; state_ ^= state_ << 5; // xorshift32
        const double w = (double)state_ / 2147483648.0 - 1.0;
        lp_ += a_ * (w - lp_);
        // Dark noise loses level through the lowpass; give some of it back.
        return static_cast<float>(lp_ * (1.0 + 1.5 * (1.0 - tone_)));
    }
private:
    double sr_ = 44100.0, tone_ = -1, a_ = 1.0, lp_ = 0.0;
    uint32_t state_ = 0x9e3779b9u;
};

// Filter 2 types (stored in presets, append only). Off skips the stage.
// 0.22.0 appends the filter 1 models: 6 LADDER 24, 7 COMB - (4 is COMB +), 8 MORPH.
enum class Filter2Type { Off = 0, Lowpass = 1, Bandpass = 2, Highpass = 3, Comb = 4, Formant = 5, Ladder = 6, CombNeg = 7, Morph = 8 };
constexpr int kFilter2Types = 9;

class Filter2 {
public:
    void setSampleRate(double sr) {
        sr_ = sr;
        svf_.setSampleRate(sr);
        x_.setSampleRate(sr);
        for (auto& f : formant_) { f.setSampleRate(sr); f.setMode(SVFilter::Mode::Bandpass); }
        buf_.assign((size_t)(sr / 20.0) + 8, 0.0f);
        pos_ = 0;
    }
    void setType(int t) {
        type_ = static_cast<Filter2Type>(std::clamp(t, 0, kFilter2Types - 1));
        if (type_ == Filter2Type::Lowpass) svf_.setMode(SVFilter::Mode::Lowpass);
        if (type_ == Filter2Type::Bandpass) svf_.setMode(SVFilter::Mode::Bandpass);
        if (type_ == Filter2Type::Highpass) svf_.setMode(SVFilter::Mode::Highpass);
        if (type_ == Filter2Type::Ladder) x_.setMode(5);
        if (type_ == Filter2Type::CombNeg) x_.setMode(7);
        if (type_ == Filter2Type::Morph) x_.setMode(8);
    }
    int latency() const { return type_ == Filter2Type::Ladder ? x_.latency() : 0; } // 0.22.0: LADDER runs at 2x
    void setMorph(double m) { x_.setMorph(m); } // 0.22.0: MORPH type's LP -> BP -> HP position
    Filter2Type type() const { return type_; }
    void reset() {
        svf_.reset();
        x_.reset();
        for (auto& f : formant_) f.reset();
        std::fill(buf_.begin(), buf_.end(), 0.0f);
    }
    // cutoff in Hz; reso is the main filter's Q range (0.1..8).
    void set(double cutoff, double reso) {
        cutoff = std::clamp(cutoff, 20.0, sr_ * 0.45);
        reso = std::clamp(reso, 0.1, 8.0);
        switch (type_) {
        case Filter2Type::Off: break;
        case Filter2Type::Ladder: case Filter2Type::CombNeg: case Filter2Type::Morph: x_.set(cutoff, reso); break;
        case Filter2Type::Lowpass: case Filter2Type::Bandpass: case Filter2Type::Highpass: svf_.set(cutoff, reso); break;
        case Filter2Type::Comb: {
            // Feedback comb tuned to the cutoff: peaks at cutoff and its harmonics.
            delay_ = std::clamp(sr_ / std::max(cutoff, 20.0), 2.0, (double)buf_.size() - 3.0);
            fb_ = std::clamp((reso - 0.1) / 7.9, 0.0, 1.0) * 0.96;
            norm_ = (float)std::sqrt(1.0 - fb_ * fb_);
            break;
        }
        case Filter2Type::Formant: {
            // Cutoff 100 Hz..8 kHz sweeps the vowels A-E-I-O-U; reso sharpens them.
            const double v = std::clamp(std::log(cutoff / 100.0) / std::log(80.0), 0.0, 1.0) * 4.0;
            const int a = std::min(3, (int)v); const double t = v - a;
            const double q = 4.0 + reso * 2.5;
            for (int i = 0; i < 3; ++i) {
                const double f = kVowels[a][i] + t * (kVowels[a + 1][i] - kVowels[a][i]);
                formant_[i].set(f, q);
            }
            break;
        }
        }
    }
    inline float process(float x) {
        switch (type_) {
        case Filter2Type::Off: return x;
        case Filter2Type::Ladder: case Filter2Type::CombNeg: case Filter2Type::Morph: return x_.process(x);
        case Filter2Type::Lowpass: case Filter2Type::Bandpass: case Filter2Type::Highpass: return svf_.process(x);
        case Filter2Type::Comb: {
            const size_t n = buf_.size();
            double rp = (double)pos_ - delay_;
            while (rp < 0) rp += (double)n;
            const size_t i0 = (size_t)rp % n, i1 = (i0 + 1) % n;
            const float fr = (float)(rp - std::floor(rp));
            const float d = buf_[i0] + fr * (buf_[i1] - buf_[i0]);
            const float y = x + (float)fb_ * d;
            buf_[pos_] = y;
            pos_ = (pos_ + 1) % n;
            return y * norm_;
        }
        case Filter2Type::Formant:
            return 1.6f * (formant_[0].process(x) + 0.6f * formant_[1].process(x) + 0.3f * formant_[2].process(x));
        }
        return x;
    }

private:
    // Average adult vowel formants F1-F3 (Hz), A E I O U.
    static constexpr double kVowels[5][3] = {{730, 1090, 2440}, {530, 1840, 2480}, {270, 2290, 3010},
                                             {570, 840, 2410}, {300, 870, 2240}};
    double sr_ = 44100.0;
    Filter2Type type_ = Filter2Type::Off;
    SVFilter svf_;
    Filter1 x_; // 0.22.0 types 6-8
    SVFilter formant_[3];
    std::vector<float> buf_;
    size_t pos_ = 0;
    double delay_ = 100.0, fb_ = 0.0;
    float norm_ = 1.0f;
};

} // namespace muew
