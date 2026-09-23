#pragma once
#include "voice.h"
#include "fx.h"
#include <vector>
#include <algorithm>
#include <memory>
#include <cmath>

namespace muew {

// Polyphonic synth: fixed voice pool, oldest-voice stealing, soft-clipped mix.
class Synth {
public:
    explicit Synth(int maxVoices = 16) { voices_.resize(maxVoices); }

    void init(double sampleRate) {
        sr_ = sampleRate;
        table_ = std::make_unique<Wavetable>();
        fx_.init(sampleRate);
        for (auto& v : voices_) v.init(sampleRate, table_.get());
        setParams(VoiceParams{}, defaultRoutes());
    }

    void setFX(const FXParams& p) { fx_.set(p); }
    // Access to the shared wavetable for registering editor-built custom
    // shape slots (see wavetable_editor.h). Register before setParams.
    Wavetable* wavetable() { return table_.get(); }
    FXChain& fx() { return fx_; }

    void setParams(const VoiceParams& p, const std::vector<ModRoute>& routes) {
        for (auto& v : voices_) v.setParams(p, routes);
        // The FX rack is shared by all voices, so only the macro knobs (global
        // sources) can modulate it.
        double drive = 0.0;
        for (const auto& r : routes) {
            int s = (int)r.source - (int)ModRoute::Source::Macro1;
            if (r.dest == ModRoute::Dest::DistDrive && s >= 0 && s < 4) drive += p.macros[s] * r.amount;
        }
        fx_.setDriveOffset(drive);
    }

    // User tables for oscillators A/B (0.9.0). Rebuilt only when the frames
    // change; an empty table leaves that oscillator on the built-in shapes.
    void setTables(const TableFrames& a, const TableFrames& b) {
        const TableFrames* in[2] = {&a, &b};
        for (int i = 0; i < 2; ++i) {
            if (*in[i] == tableFrames_[i] && (bool)tables_[i] == !in[i]->empty()) continue;
            tableFrames_[i] = *in[i];
            tables_[i] = in[i]->empty() ? nullptr : std::make_shared<const CustomTable>(*in[i]);
        }
        for (auto& v : voices_) v.setCustomTables(tables_[0].get(), tables_[1].get());
    }

    // Host tempo (BPM) for tempo-synced LFOs; 120 until a host reports one.
    void setTempo(double bpm) { for (auto& v : voices_) v.setTempo(bpm); }

    void noteOn(int note, float velocity) {
        // Reuse a voice already playing this note, else a free one, else steal oldest.
        Voice* target = nullptr;
        for (auto& v : voices_) if (v.isActive() && v.note() == note) { target = &v; break; }
        if (!target) for (auto& v : voices_) if (!v.isActive()) { target = &v; break; }
        if (!target) {
            target = &voices_[0];
            for (auto& v : voices_) if (v.age() > target->age()) target = &v;
        }
        target->noteOn(note, velocity);
    }

    void noteOff(int note) {
        for (auto& v : voices_) if (v.isActive() && v.note() == note) v.noteOff();
    }

    int activeVoiceCount() const {
        int n = 0;
        for (const auto& v : voices_) if (v.isActive()) ++n;
        return n;
    }
    int maxVoices() const { return static_cast<int>(voices_.size()); }

    void render(float* out, int frames) {
        for (int i = 0; i < frames; ++i) {
            float mix = mixVoices();
            out[i] = std::tanh(mix * 1.6f);  // soft clip / master
        }
    }

    // Interleaved stereo: voice sum goes through the FX chain.
    void renderStereo(float* interleaved, int frames) {
        for (int i = 0; i < frames; ++i) {
            float l, r;
            mixVoicesStereo(l, r);
            fx_.process(l, r);
            interleaved[i * 2]     = std::tanh(l * 1.6f);
            interleaved[i * 2 + 1] = std::tanh(r * 1.6f);
        }
    }

    // Non-interleaved stereo (Audio Unit buffer layout): same path as renderStereo.
    void renderPlanar(float* left, float* right, int frames) {
        for (int i = 0; i < frames; ++i) {
            float l, r;
            mixVoicesStereo(l, r);
            fx_.process(l, r);
            left[i]  = std::tanh(l * 1.6f);
            right[i] = std::tanh(r * 1.6f);
        }
    }

    static std::vector<ModRoute> defaultRoutes() {
        return {
            {ModRoute::Source::ModEnv, ModRoute::Dest::FilterCutoff, 2.0},
            {ModRoute::Source::LFO1, ModRoute::Dest::Osc2Pitch, 0.05},
            {ModRoute::Source::Velocity, ModRoute::Dest::FilterCutoff, 1.0},
        };
    }

    inline float mixVoices() {
        float mix = 0.0f;
        for (auto& v : voices_) if (v.isActive()) mix += v.process();
        return mix * 0.25f;  // headroom
    }

    // Stereo voice sum (unison stacks spread across the field). For mono
    // voices l == r == mixVoices(), bit for bit.
    inline void mixVoicesStereo(float& l, float& r) {
        float ml = 0.0f, mr = 0.0f;
        for (auto& v : voices_) if (v.isActive()) { float a, b; v.processStereo(a, b); ml += a; mr += b; }
        l = ml * 0.25f; r = mr * 0.25f;
    }

    FXChain fx_;

private:
    double sr_ = 44100.0;
    std::unique_ptr<Wavetable> table_;
    std::vector<Voice> voices_;
    TableFrames tableFrames_[2];
    std::shared_ptr<const CustomTable> tables_[2];
};

} // namespace muew
