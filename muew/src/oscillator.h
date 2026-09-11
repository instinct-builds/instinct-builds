#pragma once
#include "wavetable.h"

namespace muew {

// Wavetable oscillator: frequency + detune in semitones, shape, linear
// interpolation, automatic band-limiting via mipmaps.
class Oscillator {
public:
    void setSampleRate(double sr) { sr_ = sr; }
    void setFrequency(double hz) { freq_ = hz; }
    void setDetuneSemitones(double st) { detune_ = st; }
    void setShape(int shape) { shape_ = shape; }
    void setPhase(double p) { phase_ = p; }
    void reset() { phase_ = 0.0; }

    inline float process() {
        double hz = freq_ * std::pow(2.0, detune_ / 12.0);
        double level = Wavetable::levelForFrequency(hz, sr_);
        float out = table_->sampleFractional(shape_, level, phase_);
        phase_ += hz / sr_;
        phase_ -= std::floor(phase_);
        return out;
    }

    void setTable(const Wavetable* t) { table_ = t; }
    double frequency() const { return freq_; }

private:
    const Wavetable* table_ = nullptr;
    double sr_ = 44100.0;
    double freq_ = 440.0;
    double detune_ = 0.0;
    double phase_ = 0.0;
    int shape_ = 0;
};

} // namespace muew
