#pragma once
#include <cmath>
#include <cstdint>
#include <algorithm>

namespace muew {

// Tempo-free LFO in Hz, bipolar output in [-1, 1].
class LFO {
public:
    enum class Shape { Sine, Triangle, Saw, Square };

    void setSampleRate(double sr) { sr_ = sr; }
    void setRate(double hz) { rate_ = hz; }
    void setShape(Shape s) { shape_ = s; }
    void reset() { phase_ = start_; age_ = 0; }
    // 0.18.0: start phase (0..1) used by reset(); resetTo() places the phase
    // directly (free-run LFOs follow a shared clock). Custom table: kTable+1
    // samples of one cycle, drawn in the LFO editor (null = built-in shape).
    // Delay/rise: output is 0 for `delay` samples, then fades in over `rise`.
    static constexpr int kTable = 512;
    void setStartPhase(double p) { start_ = p - std::floor(p); }
    void resetTo(double p) { phase_ = p - std::floor(p); age_ = 0; }
    void setCustom(const float* table) { custom_ = table; }
    void setFade(double delaySamples, double riseSamples) { delay_ = std::max(0.0, delaySamples); rise_ = std::max(0.0, riseSamples); }
    double phase() const { return phase_; }

    inline float process() {
        float v = 0.0f;
        if (custom_) {
            const double x = phase_ * kTable; const int i = (int)x; const double f = x - i;
            v = static_cast<float>(custom_[i] + (custom_[i + 1] - custom_[i]) * f);
        } else
        switch (shape_) {
        case Shape::Sine:     v = static_cast<float>(std::sin(2.0 * M_PI * phase_)); break;
        case Shape::Triangle: v = static_cast<float>(phase_ < 0.5 ? 4.0 * phase_ - 1.0 : 3.0 - 4.0 * phase_); break;
        case Shape::Saw:      v = static_cast<float>(2.0 * phase_ - 1.0); break;
        case Shape::Square:   v = phase_ < 0.5 ? 1.0f : -1.0f; break;
        }
        phase_ += rate_ / sr_;
        phase_ -= std::floor(phase_);
        if (delay_ > 0.0 || rise_ > 0.0) { // default 0/0 leaves the output untouched
            const double a = (double)age_++ - delay_;
            if (a < 0.0) return 0.0f;
            if (a < rise_) v = static_cast<float>(v * (a / rise_));
        }
        return v;
    }

private:
    double sr_ = 44100.0;
    double rate_ = 1.0;
    double phase_ = 0.0, start_ = 0.0, delay_ = 0.0, rise_ = 0.0;
    uint64_t age_ = 0;
    const float* custom_ = nullptr;
    Shape shape_ = Shape::Sine;
};

} // namespace muew
