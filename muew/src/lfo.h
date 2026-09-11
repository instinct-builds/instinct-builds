#pragma once
#include <cmath>
#include <cstdint>

namespace muew {

// Tempo-free LFO in Hz, bipolar output in [-1, 1].
class LFO {
public:
    enum class Shape { Sine, Triangle, Saw, Square };

    void setSampleRate(double sr) { sr_ = sr; }
    void setRate(double hz) { rate_ = hz; }
    void setShape(Shape s) { shape_ = s; }
    void reset() { phase_ = 0.0; }

    inline float process() {
        float v = 0.0f;
        switch (shape_) {
        case Shape::Sine:     v = static_cast<float>(std::sin(2.0 * M_PI * phase_)); break;
        case Shape::Triangle: v = static_cast<float>(phase_ < 0.5 ? 4.0 * phase_ - 1.0 : 3.0 - 4.0 * phase_); break;
        case Shape::Saw:      v = static_cast<float>(2.0 * phase_ - 1.0); break;
        case Shape::Square:   v = phase_ < 0.5 ? 1.0f : -1.0f; break;
        }
        phase_ += rate_ / sr_;
        phase_ -= std::floor(phase_);
        return v;
    }

private:
    double sr_ = 44100.0;
    double rate_ = 1.0;
    double phase_ = 0.0;
    Shape shape_ = Shape::Sine;
};

} // namespace muew
