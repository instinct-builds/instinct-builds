// 0.105.0 app-level output gain for the standalone (MIDI CC7). The target is an
// atomic written from the MIDI thread; apply() runs on the audio thread and
// ramps linearly across each block from the previous gain, so a move never
// clicks. At unity with unity requested it touches nothing.
#pragma once
#include "midi_in.h"
#include <atomic>
namespace muew {
class OutputGain {
public:
    void setFromMidi(float v) { target_.store(midiVolumeGain(v)); }
    float target() const { return target_.load(); }
    float current() const { return now_; }
    void apply(float* left, float* right, int count) {
        const float t = target_.load();
        if (now_ == 1.0f && t == 1.0f) return;
        const float step = count > 0 ? (t - now_) / (float)count : 0.0f; float g = now_;
        for (int i = 0; i < count; ++i) { g += step; left[i] *= g; right[i] *= g; }
        now_ = t;
    }
private:
    std::atomic<float> target_{1.0f};
    float now_ = 1.0f; // audio thread only
};
} // namespace muew
