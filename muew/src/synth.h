#pragma once
#include "voice.h"
#include "fx.h"
#include "arp.h"
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
        linkPerformance();
    }
    Synth(const Synth&) = delete;             // voices point at this synth's performance state
    Synth& operator=(const Synth&) = delete;

    void init(double sampleRate) {
        sr_ = sampleRate;
        table_ = std::make_unique<Wavetable>();
        fx_.init(sampleRate);
        for (auto& v : voices_) v.init(sampleRate, table_.get());
        // 0.29.0: init is also the host Reset - clear every note, tail and stack so the next note
        // renders the same whether or not anything played before.
        allNotesOff();
        for (auto& v : voices_) v.silence();
        lastNote_ = -1; lastFreq_ = 0.0; clock_ = 0;
        setParams(VoiceParams{}, defaultRoutes());
    }

    void setFX(const FXParams& p) { fx_.set(p); }
    // Access to the shared wavetable for registering editor-built custom
    // shape slots (see wavetable_editor.h). Register before setParams.
    Wavetable* wavetable() { return table_.get(); }
    FXChain& fx() { return fx_; }

    void setParams(const VoiceParams& p, const std::vector<ModRoute>& routes) {
        // 0.33.0: a changed morph target rebuilds that oscillator's playback table first.
        if (p.osc1MorphSpec != morphSpec_[0] || p.osc2MorphSpec != morphSpec_[1]) {
            const bool c0 = p.osc1MorphSpec != morphSpec_[0], c1 = p.osc2MorphSpec != morphSpec_[1];
            morphSpec_[0] = p.osc1MorphSpec; morphSpec_[1] = p.osc2MorphSpec;
            if (c0) buildTable(0);
            if (c1) buildTable(1);
            for (auto& v : voices_) v.setCustomTables(tables_[0].get(), tables_[1].get());
        }
        trim_ = p.trimDb == 0.0 ? 1.0f : (float)std::pow(10.0, std::clamp(p.trimDb, -24.0, 12.0) / 20.0);
        for (auto& v : voices_) v.setParams(p, routes);
        oscQ_ = std::clamp(p.oscQuality, 0, 1); applyHQ(); // 0.30.0
        const int mode = std::clamp(p.voiceMode, 0, 2);
        if (mode != voiceMode_) { // leaving or entering mono: release everything, start from a clean note stack
            for (auto& v : voices_) if (v.isActive()) v.noteOff();
            held_ = 0;
        }
        voiceMode_ = mode;
        setArp(p);
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
            case ModRoute::Dest::FxHyperDetune: d = FXChain::kHyDetune; break;   // 0.27.0
            case ModRoute::Dest::FxFilterCutoff: d = FXChain::kFiCutoff; break; // 0.27.0
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
            case FXChain::kHyDetune: m.hyperDetune += v; break;
            case FXChain::kFiCutoff: m.filterCutoff += v; break;
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
            buildTable(i);
        }
        for (auto& v : voices_) v.setCustomTables(tables_[0].get(), tables_[1].get());
    }

    void buildTable(int i) {
        if (tableFrames_[i].empty()) { tables_[i] = nullptr; return; }
        if (morphSpec_[i].isIdentity()) tables_[i] = std::make_shared<const CustomTable>(tableFrames_[i]);
        else tables_[i] = std::make_shared<const CustomTable>(tableFrames_[i], processTable(tableFrames_[i], morphSpec_[i]));
    }

    // Host tempo (BPM) for tempo-synced LFOs; 120 until a host reports one.
    void setTempo(double bpm) { tempo_ = bpm > 0 ? bpm : 120.0; for (auto& v : voices_) v.setTempo(bpm); fx_.setTempo(bpm); }

    // 0.26.0 host transport, called before each render block with the host's
    // beat position (quarter notes) at the block's first sample. With clock
    // sync on and the transport playing, the arp steps on the host's bar grid
    // and synced FREE LFOs lock their phase to it; otherwise nothing changes.
    void setTransport(double beat, bool playing) {
        const bool lock = clockSync_ && playing && std::isfinite(beat);
        if (!lock) { if (locked_) { locked_ = false; arpGridLast_ = kNoGrid; } return; }
        if (!locked_) arpGridLast_ = kNoGrid;
        locked_ = true;
        beat_ = beat;
        beatInc_ = tempo_ / 60.0 / sr_;
        for (auto& v : voices_) if (v.isActive()) v.lockLfos(beat_);
        fx_.lockLfos(beat_);
    }
    bool hostLocked() const { return locked_; }
    double hostBeat() const { return beat_; }

    // ---- 0.24.0 MIDI performance ----
    void setModWheel(double v) { perf_.wheel = std::clamp(v, 0.0, 1.0); }
    void setAftertouch(double v) { perf_.aftertouch = std::clamp(v, 0.0, 1.0); }
    void setPitchBend(double v) { perf_.bend = std::clamp(v, -1.0, 1.0); }
    void setPolyAftertouch(int note, double v) {
        for (auto& vc : voices_) if (vc.isActive() && vc.note() == note) vc.setPolyAftertouch(std::clamp(v, 0.0, 1.0));
    }
    // Sustain pedal: key releases wait until the pedal comes up.
    void setSustain(bool down) {
        if (down == sustain_) return;
        sustain_ = down;
        if (down) return;
        for (int n = 0; n < 128; ++n) if (sustained_[n]) {
            sustained_[n] = false;
            if (keyDown_[n]) continue;
            if (arpOn_) { if (!arpLatch_) poolRemove(n); }
            else release(n);
        }
    }
    bool sustain() const { return sustain_; }
    // All notes off (CC 123 / 120): releases every voice, pedal included.
    void allNotesOff() {
        sustain_ = false;
        for (int n = 0; n < 128; ++n) { sustained_[n] = false; keyDown_[n] = false; }
        held_ = 0;
        pool_ = 0; arpSounding_ = 0; arpPos_ = 0; arpStep_ = 0; arpIdx_ = 0; arpClock_ = 0;
        for (auto& v : voices_) if (v.isActive()) v.noteOff();
    }
    const Performance& performance() const { return perf_; }
    int lastNote() const { return lastNote_; }

    void noteOn(int note, float velocity) {
        if (arpOn_) { arpKeyOn(note, velocity); return; }
        if (note >= 0 && note < 128) { keyDown_[note] = true; sustained_[note] = false; }
        noteOnImpl(note, velocity);
    }
    void noteOff(int note) {
        if (arpOn_) { arpKeyOff(note); return; }
        if (note >= 0 && note < 128) {
            keyDown_[note] = false;
            if (sustain_) { sustained_[note] = true; return; }
        }
        release(note);
    }

    // ---- 0.25.0 arpeggiator inspection (tests, UI) ----
    bool arpOn() const { return arpOn_; }
    int arpPoolCount() const { return pool_; }
    int arpPoolNote(int i) const { return poolNote_[std::clamp(i, 0, arp::kPool - 1)]; }
    int arpStep() const { return arpStep_; }
    int arpPosition() const { return arpPos_; } // samples into the current step
    int arpCycleIndex() const { return arpLastIdx_; }
    int arpSoundingNote() const { return arpSounding_ ? arpNotes_[0] : -1; }
    int arpPatternStep() const { return patOn_ ? arpPatIdx_ : -1; } // 0.26.0: pattern cell of the current step

private:
    void applyHQ() { const bool on = oscHQ(); for (auto& v : voices_) v.setHQ(on); fx_.setForceHQ(renderHQ_); }
    int oscQ_ = 0; bool renderHQ_ = false; // 0.30.0
    void linkPerformance() { for (auto& v : voices_) v.setPerformance(&perf_); }
    void noteOnImpl(int note, float velocity) {
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
        if (locked_) target->lockLfos(beat_);
        // 0.23.0 poly glide: from the last note played (ALWAYS), or only while
        // another key is still down (LEGATO).
        if (glideOn_ && lastNote_ >= 0 && (!glideLegato_ || overlap)) target->glideFrom(lastFreq_);
        lastNote_ = note; lastFreq_ = midiToFreq(note);
        push(note, velocity);
    }

    void release(int note) {
        if (voiceMode_ != 0) { monoNoteOff(note); return; }
        remove(note);
        for (auto& v : voices_) if (v.isActive() && v.note() == note) v.noteOff();
    }

public:
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
    // 0.35.0 live morph meter: the highest morph amount any sounding voice
    // played on oscillator o in the last block, -1 when nothing sounds.
    float specMorphMeter(int o) const {
        float m = -1.0f;
        for (const auto& v : voices_) if (v.isActive()) m = std::max(m, (float)v.liveSpecMorph(o));
        return m;
    }
    // 0.36.0 per-voice ghosts: each sounding voice's morph on oscillator o,
    // highest first, up to max entries. Returns the count.
    int specMorphVoices(int o, float* out, int max) const {
        float all[64]; int n = 0;
        for (const auto& v : voices_) if (v.isActive() && n < 64) all[n++] = (float)v.liveSpecMorph(o);
        std::sort(all, all + n, [](float a, float b) { return a > b; });
        n = std::min(n, max);
        for (int i = 0; i < n; ++i) out[i] = all[i];
        return n;
    }

    // 0.30.0 HQ. The QUALITY setting oversamples the oscillators; an HQ render
    // (the host's offline bounce) also forces the distortion to 4x.
    void setRenderHQ(bool on) { renderHQ_ = on; applyHQ(); }
    bool renderHQ() const { return renderHQ_; }
    bool oscHQ() const { return oscQ_ == 1 || renderHQ_; }
    // Samples the engine output runs late (fractional: the halfbands are half-sample aligned).
    double latencySamples() const { return (oscHQ() ? Voice::kHQLatency : 0.0) + fx_.latencySamples(); }

    void render(float* out, int frames) {
        for (int i = 0; i < frames; ++i) {
            if (arpOn_) arpTick();
            float mix = mixVoices();
            if (locked_) beat_ += beatInc_;
            out[i] = std::tanh(mix * 1.6f);  // soft clip / master
        }
    }

    // Interleaved stereo: voice sum goes through the FX chain.
    void renderStereo(float* interleaved, int frames) {
        for (int i = 0; i < frames; ++i) {
            float l, r;
            if (arpOn_) arpTick();
            mixVoicesStereo(l, r);
            if (trim_ != 1.0f) { l *= trim_; r *= trim_; } // 0.33.0 preset trim
            if (locked_) beat_ += beatInc_;
            fx_.process(l, r);
            interleaved[i * 2]     = std::tanh(l * 1.6f);
            interleaved[i * 2 + 1] = std::tanh(r * 1.6f);
        }
    }

    // Non-interleaved stereo (Audio Unit buffer layout): same path as renderStereo.
    void renderPlanar(float* left, float* right, int frames) {
        for (int i = 0; i < frames; ++i) {
            float l, r;
            if (arpOn_) arpTick();
            mixVoicesStereo(l, r);
            if (trim_ != 1.0f) { l *= trim_; r *= trim_; } // 0.33.0 preset trim
            if (locked_) beat_ += beatInc_;
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
        if (locked_) v.lockLfos(beat_);
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
    // ---- 0.25.0 arpeggiator ----
    // Keys fill a pool (press order); the arp clock plays the pool's notes one
    // step at a time through the normal voice path (poly, mono or legato).
    void setArp(const VoiceParams& p) {
        const bool on = p.arpOn;
        arpMode_ = std::clamp(p.arpMode, 0, arp::kModes - 1);
        arpOct_ = std::clamp(p.arpOctaves, 1, 4);
        arpRate_ = std::clamp(p.arpRate, 0, arp::kRates - 1);
        arpGate_ = std::clamp(p.arpGate, 0.05, 1.0);
        arpSwing_ = std::clamp(p.arpSwing, 0.0, 0.5);
        clockSync_ = p.clockSync;
        if (!clockSync_ && locked_) { locked_ = false; arpGridLast_ = kNoGrid; }
        patOn_ = p.arpPatOn;
        patLen_ = std::clamp(p.arpPatLen, 1, arp::kPatSteps);
        for (int i = 0; i < arp::kPatSteps; ++i) { patVel_[i] = std::clamp(p.arpPatVel[i], 1, 127); patKind_[i] = std::clamp(p.arpPatKind[i], 0, arp::kStepKinds - 1); }
        const bool latch = p.arpLatch;
        if (arpLatch_ && !latch) { // latch off: drop keys that are no longer held
            int w = 0;
            for (int i = 0; i < pool_; ++i) { const int n = poolNote_[i]; if (keyDown_[n] || sustained_[n]) { poolNote_[w] = n; poolVel_[w] = poolVel_[i]; ++w; } }
            pool_ = w;
        }
        arpLatch_ = latch;
        if (on == arpOn_) return;
        arpOn_ = on;
        arpRelease();
        if (on) { // keys already down join the pool; direct notes stop
            for (int n = 0; n < 128; ++n) if (keyDown_[n] || sustained_[n]) release(n);
            pool_ = 0;
            for (int n = 0; n < 128; ++n) if ((keyDown_[n] || sustained_[n]) && pool_ < arp::kPool) { poolNote_[pool_] = n; poolVel_[pool_] = 0.8f; ++pool_; }
        } else {
            pool_ = 0;
        }
        arpPos_ = 0; arpStep_ = 0; arpIdx_ = 0; arpClock_ = 0;
    }
    void arpKeyOn(int note, float vel) {
        if (note < 0 || note >= 128) return;
        bool anyDown = false;
        for (int n = 0; n < 128 && !anyDown; ++n) anyDown = keyDown_[n];
        if (arpLatch_ && !anyDown) pool_ = 0; // a fresh chord replaces the latched one
        keyDown_[note] = true; sustained_[note] = false;
        if (pool_ == 0) { arpPos_ = 0; arpStep_ = 0; arpIdx_ = 0; arpClock_ = 0; }
        for (int i = 0; i < pool_; ++i) if (poolNote_[i] == note) { poolVel_[i] = vel; return; }
        if (pool_ == arp::kPool) poolRemove(poolNote_[0]);
        poolNote_[pool_] = note; poolVel_[pool_] = vel; ++pool_;
    }
    void arpKeyOff(int note) {
        if (note < 0 || note >= 128) return;
        keyDown_[note] = false;
        if (arpLatch_) return;
        if (sustain_) { sustained_[note] = true; return; }
        poolRemove(note);
    }
    void poolRemove(int note) {
        int w = 0;
        for (int i = 0; i < pool_; ++i) if (poolNote_[i] != note) { poolNote_[w] = poolNote_[i]; poolVel_[w] = poolVel_[i]; ++w; }
        pool_ = w;
    }
    float poolVelocity(int note) const {
        const int pc = ((note % 12) + 12) % 12;
        for (int i = 0; i < pool_; ++i) if (poolNote_[i] == note) return poolVel_[i];
        for (int i = 0; i < pool_; ++i) if (poolNote_[i] % 12 == pc) return poolVel_[i]; // octave copies
        return pool_ ? poolVel_[0] : 0.8f;
    }
    void arpRelease() {
        for (int i = 0; i < arpSounding_; ++i) release(arpNotes_[i]);
        arpSounding_ = 0;
    }
    // Starts step arpStep_: picks and plays its notes, honoring the step
    // pattern. Returns the gate as a fraction of the step (>= 1 holds through).
    double arpBeginStep() {
        int kind = arp::StepOn; float vel = 1.0f; bool nextTie = false;
        if (patOn_) {
            const int k = arp::wrapStep(arpStep_, patLen_);
            kind = patKind_[k]; vel = patVel_[k] / 127.0f;
            nextTie = patKind_[arp::wrapStep(arpStep_ + 1, patLen_)] == arp::StepTie;
            arpPatIdx_ = k;
        }
        if (kind == arp::StepTie && arpSounding_ == 0) kind = arp::StepRest;
        if (kind == arp::StepRest) { arpRelease(); return 0.0; }
        if (kind == arp::StepTie) return nextTie ? 1.0 : arpGate_;
        arpRelease();
        if (arpMode_ == arp::Chord) {
            const int o = arpStep_ % arpOct_;
            for (int i = 0; i < pool_ && arpSounding_ < arp::kPool; ++i) arpNotes_[arpSounding_++] = std::min(127, poolNote_[i] + 12 * o);
            arpLastIdx_ = o;
        } else if (arpMode_ == arp::Random) {
            const int n = arp::sequence(arp::Up, poolNote_, pool_, arpOct_, seq_);
            rng_ ^= rng_ << 13; rng_ ^= rng_ >> 17; rng_ ^= rng_ << 5;
            arpLastIdx_ = (int)(rng_ % (uint32_t)n);
            arpNotes_[arpSounding_++] = seq_[arpLastIdx_];
        } else {
            const int n = arp::sequence(arpMode_, poolNote_, pool_, arpOct_, seq_);
            arpLastIdx_ = arpIdx_ % n;
            arpNotes_[arpSounding_++] = seq_[arpLastIdx_];
            arpIdx_ = arpLastIdx_ + 1;
        }
        for (int i = 0; i < arpSounding_; ++i) noteOnImpl(arpNotes_[i], patOn_ ? poolVelocity(arpNotes_[i]) * vel : poolVelocity(arpNotes_[i]));
        return nextTie ? 1.0 : arpGate_;
    }
    // 0.26.0: host bar grid. A step starts when the host beat enters it; the
    // first step after the keys go down plays at once unless under a quarter
    // of it remains (then it waits for the next grid line).
    void arpTickLocked() {
        if (pool_ == 0) {
            if (arpSounding_) arpRelease();
            arpPos_ = 0; arpIdx_ = 0; arpGridLast_ = kNoGrid;
            return;
        }
        double st = 0, ln = 1;
        const long long g = arp::gridStep(beat_, arpRate_, arpSwing_, &st, &ln);
        if (g != arpGridLast_ && !(arpGridLast_ == kNoGrid && st + ln - beat_ < 0.25 * ln)) {
            arpGridLast_ = g;
            arpStep_ = (int)(g % 1000000000LL);
            const double gate = arpBeginStep();
            arpGateEnd_ = gate >= 1.0 ? 1e300 : st + ln * gate;
            arpPos_ = 0;
        }
        if (arpGridLast_ == kNoGrid) return;
        ++arpPos_;
        if (arpSounding_ && beat_ + beatInc_ > arpGateEnd_) arpRelease();
    }
    void arpTick() {
        if (locked_) { arpTickLocked(); return; }
        if (pool_ == 0) {
            if (arpSounding_) arpRelease();
            arpPos_ = 0; arpStep_ = 0; arpIdx_ = 0; arpClock_ = 0;
            return;
        }
        if (arpPos_ == 0) {
            arpLen_ = arp::stepSamplesAt(arpClock_, sr_, tempo_, arpRate_, arpSwing_, arpStep_);
            arpClock_ += arp::stepLength(sr_, tempo_, arpRate_, arpSwing_, arpStep_);
            const double gate = arpBeginStep();
            arpGateLen_ = gate >= 1.0 ? arpLen_ : std::max(1, (int)std::lround(arpLen_ * gate));
        }
        ++arpPos_;
        if (arpPos_ == arpGateLen_ && arpGateLen_ < arpLen_) arpRelease();
        if (arpPos_ >= arpLen_) { arpPos_ = 0; ++arpStep_; }
    }
    bool arpOn_ = false, arpLatch_ = false;
    int arpMode_ = 0, arpOct_ = 1, arpRate_ = 3;
    double arpGate_ = 0.5, arpSwing_ = 0.0, tempo_ = 120.0, arpClock_ = 0.0;
    // 0.26.0 clock sync + step pattern
    static constexpr long long kNoGrid = -(1LL << 62);
    bool clockSync_ = false, locked_ = false, patOn_ = false;
    double beat_ = 0.0, beatInc_ = 0.0, arpGateEnd_ = 0.0;
    long long arpGridLast_ = kNoGrid;
    int patLen_ = 16, patVel_[arp::kPatSteps] = {}, patKind_[arp::kPatSteps] = {}, arpPatIdx_ = -1;
    int poolNote_[arp::kPool] = {};
    float poolVel_[arp::kPool] = {};
    int pool_ = 0;
    int arpNotes_[arp::kPool] = {};
    int arpSounding_ = 0;
    int arpPos_ = 0, arpLen_ = 1, arpGateLen_ = 1, arpStep_ = 0, arpIdx_ = 0, arpLastIdx_ = 0;
    uint32_t rng_ = 0x2545f491u;
    std::array<int, arp::kSeq> seq_{};

    Performance perf_;                              // 0.24.0
    bool sustain_ = false, sustained_[128] = {}, keyDown_[128] = {};
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
    SpectralProcess morphSpec_[2]; // 0.33.0
    float trim_ = 1.0f;            // 0.33.0
};

} // namespace muew
