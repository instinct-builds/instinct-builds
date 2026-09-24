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
    explicit Synth(int maxVoices = 16) {
        voices_.resize(maxVoices); polyVoices_ = maxVoices;
        for (int i = 0; i < maxVoices; ++i) voices_[i].seedPhases(0x9e3779b9u * (uint32_t)(i + 1)); // 0.23.0 RANDOM phase streams
    }

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
        const int mode = std::clamp(p.voiceMode, 0, 2);
        if (mode != voiceMode_) { // leaving or entering mono: release everything, start from a clean note stack
            for (auto& v : voices_) if (v.isActive()) v.noteOff();
            held_ = 0;
        }
        voiceMode_ = mode;
        polyVoices_ = std::clamp(p.polyVoices, 1, (int)voices_.size());
        glideOn_ = p.glideTime > 0.0;
        glideLegato_ = p.glideLegato;
        // The FX rack is shared by all voices, so only global sources (macros,
        // rack LFOs) can modulate it.
        FXChain::Mod m;
        std::vector<FXChain::LfoRoute> lr;
        for (const auto& r : routes) {
            int d = -1;
            switch (r.dest) {
            case ModRoute::Dest::DistDrive: d = FXChain::kDrive; break;
            case ModRoute::Dest::FxDelayFeedback: d = FXChain::kDelayFb; break;
            case ModRoute::Dest::FxReverbDecay: d = FXChain::kRevDecay; break;
            case ModRoute::Dest::FxPhaserDepth: d = FXChain::kPhDepth; break;
            case ModRoute::Dest::FxFlangerDepth: d = FXChain::kFlDepth; break;
            case ModRoute::Dest::FxChorusDepth: d = FXChain::kChDepth; break;
            default: break;
            }
            if (d < 0) continue;
            // 0.16.0 aux on a global route: a macro scales statically, a rack LFO
            // makes the route move at block rate; voice sources can't reach the rack.
            const int ax = r.aux;
            const bool auxMacro = ax >= (int)ModRoute::Source::Macro1 && ax <= (int)ModRoute::Source::Macro4;
            const bool auxRack = sourceIsRack(ax);
            const double auxScale = auxMacro ? std::clamp(p.macros[ax - (int)ModRoute::Source::Macro1], 0.0, 1.0) : 1.0;
            const int auxLfo = auxRack ? ax - (int)ModRoute::Source::FxLfo1 : -1;
            if (r.source == ModRoute::Source::FxLfo1 || r.source == ModRoute::Source::FxLfo2) {
                FXChain::LfoRoute x{r.source == ModRoute::Source::FxLfo2 ? 1 : 0, d, r.amount};
                x.curve = r.curve; x.auxLfo = auxLfo; x.auxScale = auxScale;
                lr.push_back(x);
                continue;
            }
            int s = (int)r.source - (int)ModRoute::Source::Macro1;
            if (s < 0 || s >= 4) continue;
            double src = p.macros[s];
            if (r.curve != 0.0) src = routeCurve(src, r.curve);
            if (auxMacro) src *= auxScale;
            if (auxRack) { FXChain::LfoRoute x{-1, d, r.amount}; x.auxLfo = auxLfo; x.value = src; lr.push_back(x); continue; }
            const double v = src * r.amount;
            switch (d) {
            case FXChain::kDrive: m.drive += v; break;
            case FXChain::kDelayFb: m.delayFeedback += v; break;
            case FXChain::kRevDecay: m.reverbDecay += v; break;
            case FXChain::kPhDepth: m.phaserDepth += v; break;
            case FXChain::kFlDepth: m.flangerDepth += v; break;
            default: m.chorusDepth += v; break;
            }
        }
        fx_.setLfoRoutes(m, lr);
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
    void setTempo(double bpm) { for (auto& v : voices_) v.setTempo(bpm); fx_.setTempo(bpm); }

    void noteOn(int note, float velocity) {
        if (voiceMode_ != 0) { monoNoteOn(note, velocity); return; }
        // Poly: reuse a voice already playing this note, else a free one, else
        // steal the oldest, among the first polyVoices voices.
        const int n = polyVoices_;
        const bool overlap = anyHeld();
        Voice* target = nullptr;
        for (int i = 0; i < n; ++i) if (voices_[i].isActive() && voices_[i].note() == note) { target = &voices_[i]; break; }
        if (!target) for (int i = 0; i < n; ++i) if (!voices_[i].isActive()) { target = &voices_[i]; break; }
        if (!target) {
            target = &voices_[0];
            for (int i = 0; i < n; ++i) if (voices_[i].age() > target->age()) target = &voices_[i];
        }
        target->setClock(clock_);
        target->noteOn(note, velocity);
        // 0.23.0 poly glide: from the last note played (ALWAYS), or only while
        // another key is still down (LEGATO).
        if (glideOn_ && lastNote_ >= 0 && (!glideLegato_ || overlap)) target->glideFrom(lastFreq_);
        lastNote_ = note; lastFreq_ = midiToFreq(note);
        push(note, velocity);
    }

    void noteOff(int note) {
        if (voiceMode_ != 0) { monoNoteOff(note); return; }
        remove(note);
        for (auto& v : voices_) if (v.isActive() && v.note() == note) v.noteOff();
    }

    // 0.23.0 inspection (tests, UI).
    int voiceMode() const { return voiceMode_; }
    int heldCount() const { return held_; }
    const Voice& voice(int i) const { return voices_[std::clamp(i, 0, (int)voices_.size() - 1)]; }

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
        ++clock_;
        float mix = 0.0f;
        for (auto& v : voices_) if (v.isActive()) mix += v.process();
        return mix * 0.25f;  // headroom
    }

    // Stereo voice sum (unison stacks spread across the field). For mono
    // voices l == r == mixVoices(), bit for bit.
    inline void mixVoicesStereo(float& l, float& r) {
        ++clock_;
        float ml = 0.0f, mr = 0.0f;
        for (auto& v : voices_) if (v.isActive()) { float a, b; v.processStereo(a, b); ml += a; mr += b; }
        l = ml * 0.25f; r = mr * 0.25f;
    }

    FXChain fx_;

private:
    // 0.23.0 mono / legato. One voice (voice 0) plays the newest held key;
    // releasing it falls back to the previous held key (last-note priority).
    void monoNoteOn(int note, float velocity) {
        Voice& v = voices_[0];
        const bool overlap = anyHeld() && v.isActive();
        remove(note);
        push(note, velocity);
        if (voiceMode_ == 2 && overlap) { v.legatoTo(note); return; } // LEGATO: no retrigger while held
        const double from = v.isActive() ? v.currentFreq() : lastFreq_;
        v.setClock(clock_);
        v.noteOn(note, velocity);
        if (glideOn_ && lastNote_ >= 0 && (!glideLegato_ || overlap)) v.glideFrom(from);
        lastNote_ = note; lastFreq_ = midiToFreq(note);
    }
    void monoNoteOff(int note) {
        const bool wasTop = held_ > 0 && heldNote_[held_ - 1] == note;
        remove(note);
        Voice& v = voices_[0];
        if (!wasTop || !v.isActive()) return;
        if (held_ == 0) { v.noteOff(); return; }
        const int back = heldNote_[held_ - 1];
        if (voiceMode_ == 2) v.legatoTo(back);          // LEGATO: slide back without a new attack
        else {                                           // MONO: retrigger the previous key
            const double from = v.currentFreq();
            v.setClock(clock_);
            v.noteOn(back, heldVel_[held_ - 1]);
            if (glideOn_) v.glideFrom(from);
        }
        lastNote_ = back; lastFreq_ = midiToFreq(back);
    }
    bool anyHeld() const { return held_ > 0; }
    void push(int note, float vel) {
        remove(note);
        if (held_ == kHeld) { for (int i = 1; i < kHeld; ++i) { heldNote_[i - 1] = heldNote_[i]; heldVel_[i - 1] = heldVel_[i]; } --held_; }
        heldNote_[held_] = note; heldVel_[held_] = vel; ++held_;
    }
    void remove(int note) {
        int w = 0;
        for (int i = 0; i < held_; ++i) if (heldNote_[i] != note) { heldNote_[w] = heldNote_[i]; heldVel_[w] = heldVel_[i]; ++w; }
        held_ = w;
    }
    static constexpr int kHeld = 32;
    int heldNote_[kHeld] = {};
    float heldVel_[kHeld] = {};
    int held_ = 0;
    int voiceMode_ = 0, polyVoices_ = 16, lastNote_ = -1;
    double lastFreq_ = 0.0;
    bool glideOn_ = false, glideLegato_ = false;

    double sr_ = 44100.0;
    std::unique_ptr<Wavetable> table_;
    std::vector<Voice> voices_;
    uint64_t clock_ = 0; // 0.18.0: samples rendered, for free-run LFOs
    TableFrames tableFrames_[2];
    std::shared_ptr<const CustomTable> tables_[2];
};

} // namespace muew
