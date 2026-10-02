#pragma once
#include <algorithm>

namespace muew {

// ADSR envelope with per-sample linear ramps.
class Envelope {
public:
    enum class Stage { Idle, Attack, Decay, Sustain, Release };

    void setSampleRate(double sr) { sr_ = sr; }
    // times in seconds, sustain 0..1
    void set(double attack, double decay, double sustain, double release) {
        a_ = std::max(0.001, attack);
        d_ = std::max(0.001, decay);
        s_ = std::clamp(sustain, 0.0, 1.0);
        r_ = std::max(0.001, release);
    }

    // 0.94.0: live time multiplier on attack, decay and release (1 = unchanged, so unrouted envelopes are bit-identical).
    void setTimeScale(double s) { scale_ = std::clamp(s, 1.0 / 16.0, 16.0); }

    // 0.29.0: hard stop (host Reset) - no release tail, the next note starts from zero.
    void reset() { level_ = 0.0; stage_ = Stage::Idle; }
    void noteOn() { stage_ = Stage::Attack; }
    void noteOff() {
        if (stage_ != Stage::Idle) stage_ = Stage::Release;
    }

    inline float process() {
        switch (stage_) {
        case Stage::Idle: level_ = 0.0; break;
        case Stage::Attack:
            level_ += 1.0 / (a_ * scale_ * sr_);
            if (level_ >= 1.0) { level_ = 1.0; stage_ = Stage::Decay; }
            break;
        case Stage::Decay:
            level_ -= (1.0 - s_) / (d_ * scale_ * sr_);
            if (level_ <= s_) { level_ = s_; stage_ = Stage::Sustain; }
            break;
        case Stage::Sustain: break;
        case Stage::Release:
            level_ -= level_ > 0 ? std::max(1.0 / (r_ * scale_ * sr_), level_ / (r_ * scale_ * sr_)) : 0.0;
            if (level_ <= 0.0005) { level_ = 0.0; stage_ = Stage::Idle; }
            break;
        }
        return static_cast<float>(level_);
    }

    bool isActive() const { return stage_ != Stage::Idle; }
    double level() const { return level_; }
    Stage stage() const { return stage_; }

private:
    double sr_ = 44100.0;
    double a_ = 0.01, d_ = 0.1, s_ = 0.7, r_ = 0.2;
    double scale_ = 1.0;
    double level_ = 0.0;
    Stage stage_ = Stage::Idle;
};

} // namespace muew
