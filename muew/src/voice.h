#pragma once
#include "noise_burst_envelope.h"
#include "oscillator.h"
#include "filter.h"
#include "envelope.h"
#include "lfo.h"
#include "mseg.h"
#include "layers.h"
#include "tempo_sync.h"
#include "mod_curve.h"
#include "spectral_process.h"
#include <cmath>
#include <array>

namespace muew {

inline double midiToFreq(int note) {
    return 440.0 * std::pow(2.0, (note - 69) / 12.0);
}

// Modulation routing: a source scales into a destination.
struct ModRoute {
    // Append only: values are stored in presets and host projects.
    enum class Source { LFO1 = 0, ModEnv = 1, Velocity = 2, LFO2 = 3, MSEG1 = 4,
                        Macro1 = 5, Macro2 = 6, Macro3 = 7, Macro4 = 8,
                        LFO3 = 9, LFO4 = 10, Env3 = 11, // 0.8.0: LFO 3/4, ENV 3
                        FxLfo1 = 12, FxLfo2 = 13,  // 0.15.0: rack LFOs (FX destinations only)
                        MSEG2 = 14,                  // 0.17.0
                        ModWheel = 15, Aftertouch = 16, PitchBend = 17, Keytrack = 18 } source; // 0.24.0 MIDI performance
    enum class Dest { Osc1Pitch = 0, Osc2Pitch = 1, FilterCutoff = 2, Osc2Level = 3, FilterResonance = 4, Osc1Warp = 5, Osc2Warp = 6,
                      Osc1Unison = 7, Osc2Unison = 8, UnisonWidth = 9, // 0.7.0: unison detune A/B, stereo width (0..1 units)
                      DistDrive = 10,                                   // 0.7.0: FX-rack drive, macro sources only (global FX)
                      Osc1WtPos = 11, Osc2WtPos = 12,                   // 0.9.0: user-table frame position (0..1 units)
                      SubLevel = 13, NoiseLevel = 14, Filter2Cutoff = 15, // 0.10.0 (0..1 levels, octaves)
                      // 0.14.0: FX detail controls, macro sources only (global FX)
                      FxDelayFeedback = 16, FxReverbDecay = 17, FxPhaserDepth = 18, FxFlangerDepth = 19, FxChorusDepth = 20,
                      Osc1Warp2 = 21, Osc2Warp2 = 22,                 // 0.19.0: second warp slot amounts (0..1)
                      FilterDrive = 23, FilterMorph = 24,             // 0.21.0: filter 1 drive / morph (0..1)
                      Filter2Morph = 25, FilterBalance = 26,          // 0.22.0: filter 2 morph, parallel F1/F2 balance (0..1)
                      UnisonBlend = 27,                               // 0.23.0: unison outer-voice level (0..1)
                      FxHyperDetune = 28, FxFilterCutoff = 29,        // 0.27.0: HYPER detune, FILTER FX cutoff (1 = +4 oct)
                      Osc1SpecMorph = 30, Osc2SpecMorph = 31, // 0.33.0: live spectral morph
                      NoiseColor = 32 } dest; // 0.52.0: modulated AIR/GRAIN/DUST color, never CLASSIC
    double amount = 0.0; // semitones for pitch, Hz-scaled multiplier for cutoff, 0..1 for level
    // 0.16.0: response curve and aux source. curve bends the source value
    // (-1 log .. 0 linear .. +1 exp, symmetric for bipolar sources); aux is
    // another source (Source value, -1 = none) that scales the route by its
    // 0..1 level. Defaults leave the route exactly as before.
    double curve = 0.0;
    int aux = -1;
};

constexpr int kModSources = 19; // Source values 0..18
// Bipolar sources run -1..1; the rest 0..1.
inline bool sourceBipolar(int s) {
    using S = ModRoute::Source;
    switch ((S)s) {
    case S::LFO1: case S::LFO2: case S::LFO3: case S::LFO4: case S::MSEG1: case S::MSEG2: case S::FxLfo1: case S::FxLfo2:
    case S::PitchBend: case S::Keytrack: return true; // 0.24.0
    default: return false;
    }
}
// 0.24.0 MIDI performance state shared by every voice (the synth owns it):
// mod wheel and channel aftertouch 0..1, pitch bend -1..1.
struct Performance { double wheel = 0.0, aftertouch = 0.0, bend = 0.0; };
inline bool sourceIsRack(int s) { return s == (int)ModRoute::Source::FxLfo1 || s == (int)ModRoute::Source::FxLfo2; }
// Aux level 0..1 from a source value.
inline double auxLevel(int s, double v) { return sourceBipolar(s) ? std::clamp(0.5 * (v + 1.0), 0.0, 1.0) : std::clamp(v, 0.0, 1.0); }

struct VoiceParams {
    int osc1Shape = 2;       // Saw
    int osc2Shape = 3;       // Square
    double osc2Detune = 7.0; // semitones
    double osc2Level = 0.5;
    double filterCutoff = 8000.0;
    double filterReso = 0.7;
    int filterMode = 0;      // 0-4 SVF modes, 5 LADDER 24, 6 COMB +, 7 COMB -, 8 MORPH (0.21.0)
    double filterDrive = 0.0, filterKeytrack = 0.0, filterMorph = 0.0; // 0.21.0 (0..1)
    double ampA = 0.005, ampD = 0.15, ampS = 0.8, ampR = 0.3;
    double modA = 0.01, modD = 0.3, modS = 0.0, modR = 0.2;
    double lfo1Rate = 5.0, lfo2Rate = 0.35;
    int lfo1Shape = 0, lfo2Shape = 1;
    int osc1WarpMode = 0, osc2WarpMode = 0;
    double osc1Warp = 0.0, osc2Warp = 0.0;
    // 0.19.0 second warp slot per oscillator (runs after the first; 0 = off)
    // and each oscillator's REMAP curve (time = phase in, value -1..1 = phase
    // out), used by a REMAP warp in either slot. Defaults change nothing.
    int osc1Warp2Mode = 0, osc2Warp2Mode = 0;
    double osc1Warp2 = 0.0, osc2Warp2 = 0.0;
    std::vector<MSEG::Point> remapPoints[2] = {kDefaultRemap(), kDefaultRemap()};
    static std::vector<MSEG::Point> kDefaultRemap() { return {{0.0, -1.0, 0.0}, {1.0, 1.0, 0.0}}; }
    double mseg1Seconds = 1.0;
    bool mseg1Loop = false;
    // Breakpoints (time 0..1, value -1..1). Defaults match MSEG's built-in
    // shape so presets written before points were stored sound identical.
    std::vector<MSEG::Point> mseg1Points{{0.0, 0.0}, {0.15, 1.0}, {0.55, -0.3}, {1.0, 0.0}};
    // 0.17.0 MSEG editor: tempo-synced length, loop span (point indices,
    // end -1 = last point) and free LOOP mode (keeps cycling after release).
    int mseg1Sync = 0, mseg1LoopStart = 1, mseg1LoopEnd = -1;
    bool mseg1FreeLoop = false;
    // 0.17.0 MSEG 2. mode: 0 one-shot, 1 sustain loop, 2 loop.
    double mseg2Seconds = 1.0;
    int mseg2Sync = 0, mseg2Mode = 0, mseg2LoopStart = 1, mseg2LoopEnd = -1;
    std::vector<MSEG::Point> mseg2Points{{0.0, 0.0}, {0.15, 1.0}, {0.55, -0.3}, {1.0, 0.0}};
    // Macro knobs, 0..1. Unipolar mod sources: a route from a macro adds
    // nothing at 0, so presets sound as authored until a macro is turned.
    double macros[4] = {0.0, 0.0, 0.0, 0.0};
    // Unison (0.7.0). One voice per oscillator is the classic single-osc
    // path, so every preset written before unison renders sample-identical.
    int osc1Unison = 1, osc2Unison = 1;          // stacked voices, 1..8
    double osc1UniDetune = 0.25, osc2UniDetune = 0.25; // 0..1: outer voices +-1 semitone at 1
    double uniWidth = 0.8;                       // 0..1 stereo spread of the stack
    double uniBlend = 0.75;                      // 0..1 level of the outer voices vs the center
    // 0.8.0 modulators. They only matter once a route uses them.
    double lfo3Rate = 1.0, lfo4Rate = 2.0;
    int lfo3Shape = 0, lfo4Shape = 1;
    // Tempo sync per LFO (1-4): 0 = free (Hz), else a note division (see
    // kSyncBeats). Synced LFOs follow the host tempo.
    int lfoSync[4] = {0, 0, 0, 0};
    // 0.18.0 LFO extras (LFO 1-4). custom plays the drawn lfoPoints cycle
    // instead of the shape; phase is the start phase (0..1); delay/rise in
    // seconds fade the LFO in after each note; free keeps a shared running
    // phase instead of restarting per note. Defaults change nothing.
    bool lfoCustom[4] = {false, false, false, false};
    double lfoPhase[4] = {0, 0, 0, 0}, lfoDelay[4] = {0, 0, 0, 0}, lfoRise[4] = {0, 0, 0, 0};
    bool lfoFree[4] = {false, false, false, false};
    std::vector<MSEG::Point> lfoPoints[4] = {kDefaultLfoPoints(), kDefaultLfoPoints(), kDefaultLfoPoints(), kDefaultLfoPoints()};
    static std::vector<MSEG::Point> kDefaultLfoPoints() { return {{0.0, 0.0, 0.0}, {0.25, 1.0, 0.0}, {0.75, -1.0, 0.0}, {1.0, 0.0, 0.0}}; }
    double env3A = 0.01, env3D = 0.4, env3S = 0.0, env3R = 0.3;
    // 0.9.0: frame position (0..1) through each oscillator's user table; only
    // heard when the oscillator's shape is kCustomShape.
    double osc1WtPos = 0.0, osc2WtPos = 0.0;
    // 0.33.0 live spectral morph: each oscillator's table can carry a morph
    // target (a SPECTRAL setting); the amount crossfades toward it and is a
    // mod destination. trimDb is a per-preset output trim (0 = untouched).
    double osc1SpecMorph = 0.0, osc2SpecMorph = 0.0;
    SpectralProcess osc1MorphSpec, osc2MorphSpec;
    double trimDb = 0.0;
    // 0.10.0 layers. Level 0 / type Off skip the stage entirely.
    double subLevel = 0.0;     // 0..1
    int subOctave = 1;         // 1 or 2 octaves below oscillator A
    int subShape = 0;          // kSubShapes: SINE, TRI, SQUARE
    double noiseLevel = 0.0;   // 0..1
    double noiseTone = 1.0;    // 0 dark .. 1 white
    int noiseCharacter = 0;    // 0 legacy, 1 AIR, 2 GRAIN, 3 DUST
    double noiseColor = 0.5;   // new modes only; old NOISE TONE behavior unchanged
    double noiseWidth = 0.0;   // 0.53.0: 0 mono legacy, 1 decorrelated stereo
    double noiseBurst = 0.0;   // 0.55.0: 0 off, 0.005..0.5 s per-note noise-only decay
    double noiseBurstAttack = 0.0; // 0.57.0: 0..0.8 fraction of total burst time
    double noiseBurstCurve = 0.0;  // 0.57.0: -1 fast, 0 linear, +1 slow tail
    int filter2Type = 0;       // Filter2Type
    double filter2Cutoff = 2000.0, filter2Reso = 0.7;
    int filterRouting = 0;     // 0 serial (filter 1 -> filter 2), 1 parallel
    // 0.22.0: per-filter dry/wet, parallel balance (0 all F1 .. 1 all F2), filter 2 MORPH position.
    double filter1Mix = 1.0, filter2Mix = 1.0, filterBalance = 0.5, filter2Morph = 0.0;
    // 0.23.0 voice depth. Defaults are the 0.22.0 behavior exactly: 16-voice
    // poly, no glide, unison stacks restarting at their fixed spread phases.
    int voiceMode = 0;          // 0 poly, 1 mono (retrigger), 2 legato (mono, no retrigger while held)
    int polyVoices = 16;        // 1..16 voices in poly mode
    double glideTime = 0.0;     // seconds for a full glide, 0 = off
    bool glideLegato = false;   // glide only between overlapping notes
    int uniPhase = 0;           // 0 spread (fixed phases, retriggered), 1 random per note
    // 0.24.0: pitch bend range in semitones (both directions).
    int bendRange = 2;
    // 0.30.0 global QUALITY: 0 STANDARD, 1 HQ (oscillator stacks run at 2x and
    // come back down through a halfband, which removes warp and FM aliasing).
    int oscQuality = 0;
    // 0.25.0 arpeggiator (see arp.h). Off: the synth plays keys directly.
    bool arpOn = false;
    int arpMode = 0;            // arp::Mode
    int arpOctaves = 1;         // 1..4
    int arpRate = 3;            // arp rate index, 3 = 1/16
    double arpGate = 0.5;       // 0.05..1 of a step (1 = tied)
    double arpSwing = 0.0;      // 0..0.5 (straight .. 75/25)
    bool arpLatch = false;      // keep playing after the keys come up
    // 0.26.0: lock the arp grid and synced FREE LFOs (voice + rack) to the
    // host's bar while its transport plays; off (or stopped) = free clock.
    bool clockSync = false;
    // 0.26.0 step pattern (arp.h): off = every step plays at key velocity.
    bool arpPatOn = false;
    int arpPatLen = 16;                                   // 1..16
    int arpPatVel[16] = {127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127}; // 1..127
    int arpPatKind[16] = {};                              // arp::StepKind
    int arpPatRatchet[16] = {1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1}; // retriggers per ON step, 1..4
    int arpPatOctave[16] = {}; // 0.49.0 ON-step octave shift, -1..+1; TIE retains sounding pitch
    int arpPatChance[16] = {100, 100, 100, 100, 100, 100, 100, 100, 100, 100, 100, 100, 100, 100, 100, 100}; // 0.50.0 ON-step chance
    bool arpChanceLive = false; // opt-in evolving chance; fixed mode follows absolute pattern cycle
    bool arpPatDefault() const {
        for (int i = 0; i < 16; ++i) if (arpPatVel[i] != 127 || arpPatKind[i] != 0) return false;
        return !arpPatOn && arpPatLen == 16;
    }
};

constexpr int kMaxUnison = 8;
constexpr int kMaxRoutes = 16; // mod matrix slots
// Display full scale for route activity, shared with the matrix depth control.
inline double routeMeterScale(ModRoute::Dest d) {
    switch (d) {
    case ModRoute::Dest::Osc1Pitch: case ModRoute::Dest::Osc2Pitch: return 24.0;
    case ModRoute::Dest::FilterCutoff: case ModRoute::Dest::Filter2Cutoff: return 5.0;
    case ModRoute::Dest::FilterResonance: return 8.0;
    default: return 1.0;
    }
}

// Tempo-sync divisions (kSyncCount, syncBeats) live in tempo_sync.h.
// LFO rate in Hz for a free rate or a synced division at `bpm`.
inline double lfoHz(double freeHz, int sync, double bpm) {
    double beats = syncBeats(sync);
    return beats > 0 ? (bpm / 60.0) / beats : freeHz;
}

// 0.12.0: one-pole DC blocker (high pass near 12 Hz): y = x - x1 + R * y1.
class DCBlocker {
public:
    void setSampleRate(double sr) { R_ = std::exp(-2.0 * 3.14159265358979323846 * 12.0 / sr); }
    void reset() { x1_ = y1_ = 0.0; }
    inline float process(float x) {
        const double y = x - x1_ + R_ * y1_;
        x1_ = x; y1_ = y;
        return static_cast<float>(y);
    }
private:
    double R_ = 0.9983, x1_ = 0.0, y1_ = 0.0;
};

class Voice {
public:
    void init(double sr, const Wavetable* table) {
        sr_ = sr;
        for (int i = 0; i < kMaxUnison; ++i) {
            osc1_[i].setSampleRate(hq_ ? 2 * sr : sr); osc1_[i].setTable(table);
            osc2_[i].setSampleRate(hq_ ? 2 * sr : sr); osc2_[i].setTable(table);
        }
        filter_.setSampleRate(sr); filterR_.setSampleRate(sr);
        ampEnv_.setSampleRate(sr);
        modEnv_.setSampleRate(sr);
        lfo1_.setSampleRate(sr); lfo2_.setSampleRate(sr);
        lfo3_.setSampleRate(sr); lfo4_.setSampleRate(sr); env3_.setSampleRate(sr);
        mseg1_.setSampleRate(sr);
        sub_.setSampleRate(hq_ ? 2 * sr : sr); sub_.setTable(table);
        noise_.setSampleRate(sr); noiseR_.setSampleRate(sr);
        noiseBurstPos_ = 0; noiseBurstLength_ = 0;
        dcL_.setSampleRate(sr); dcR_.setSampleRate(sr);
        f2L_.setSampleRate(sr); f2R_.setSampleRate(sr);
    }

    void setParams(const VoiceParams& p, const std::vector<ModRoute>& routes) {
        params_ = p; routes_ = routes;
        noiseBurstLength_ = p.noiseBurst > 0.0 ? (uint64_t)std::ceil(std::clamp(p.noiseBurst, 0.005, 0.5) * sr_) : 0;
        for (int i = 0; i < kMaxUnison; ++i) { osc1_[i].setShape(std::clamp(p.osc1Shape, 0, 4)); osc2_[i].setShape(std::clamp(p.osc2Shape, 0, 4)); }
        applyCustom();
        filter_.setMode(p.filterMode);
        filterR_.setMode(p.filterMode);
        filter_.setDrive(p.filterDrive); filterR_.setDrive(p.filterDrive);   // 0.21.0
        filter_.setMorph(p.filterMorph); filterR_.setMorph(p.filterMorph);
        usesFilterX_ = false;
        bool driveRouted = false;
        usesF2Morph_ = false; usesBalance_ = false; usesUniBlend_ = false; usesSpecMorph_[0] = usesSpecMorph_[1] = false;
        for (const auto& r : routes) {
            if (r.dest == ModRoute::Dest::FilterDrive || r.dest == ModRoute::Dest::FilterMorph) usesFilterX_ = true;
            if (r.dest == ModRoute::Dest::FilterDrive) driveRouted = true;
            if (r.dest == ModRoute::Dest::Filter2Morph) usesF2Morph_ = true;   // 0.22.0
            if (r.dest == ModRoute::Dest::FilterBalance) usesBalance_ = true;
            if (r.dest == ModRoute::Dest::UnisonBlend) usesUniBlend_ = true; // 0.23.0
            if (r.dest == ModRoute::Dest::Osc1SpecMorph) usesSpecMorph_[0] = true; // 0.33.0
            if (r.dest == ModRoute::Dest::Osc2SpecMorph) usesSpecMorph_[1] = true;
        }
        filter_.setOversample(p.filterDrive > 0 || driveRouted); filterR_.setOversample(p.filterDrive > 0 || driveRouted); // 0.22.0
        ampEnv_.set(p.ampA, p.ampD, p.ampS, p.ampR);
        modEnv_.set(p.modA, p.modD, p.modS, p.modR);
        lfo1_.setShape(static_cast<LFO::Shape>(p.lfo1Shape));
        lfo2_.setShape(static_cast<LFO::Shape>(p.lfo2Shape));
        lfo3_.setShape(static_cast<LFO::Shape>(std::clamp(p.lfo3Shape, 0, 3)));
        lfo4_.setShape(static_cast<LFO::Shape>(std::clamp(p.lfo4Shape, 0, 3)));
        applyLfoExtras();
        applyWarpX();
        applyRates();
        env3_.set(p.env3A, p.env3D, p.env3S, p.env3R);
        usesLfo3_ = usesLfo4_ = false;
        for (const auto& r : routes) {
            if (r.source == ModRoute::Source::LFO3) usesLfo3_ = true;
            if (r.source == ModRoute::Source::LFO4) usesLfo4_ = true;
        }
        mseg1_.setPoints(p.mseg1Points);
        mseg1_.setLoop(p.mseg1LoopStart, p.mseg1LoopEnd < 0 ? (int)mseg1_.pointCount() - 1 : p.mseg1LoopEnd, p.mseg1Loop);
        mseg1_.setFreeLoop(p.mseg1FreeLoop);
        mseg2_.setPoints(p.mseg2Points);
        mseg2_.setLoop(p.mseg2LoopStart, p.mseg2LoopEnd < 0 ? (int)mseg2_.pointCount() - 1 : p.mseg2LoopEnd, p.mseg2Mode != 0);
        mseg2_.setFreeLoop(p.mseg2Mode == 2);
        usesMseg2_ = false;
        for (const auto& r : routes) if (r.source == ModRoute::Source::MSEG2 || r.aux == (int)ModRoute::Source::MSEG2) usesMseg2_ = true;
        applyMsegRates();
        
        usesSub_ = p.subLevel > 0; usesNoise_ = p.noiseLevel > 0; usesNoiseColor_ = false;
        for (const auto& r : routes) {
            if (r.dest == ModRoute::Dest::SubLevel) usesSub_ = true;
            if (r.dest == ModRoute::Dest::NoiseLevel) usesNoise_ = true;
            if (r.dest == ModRoute::Dest::NoiseColor && !sourceIsRack((int)r.source)) usesNoiseColor_ = true;
        }
        sub_.setShape(subTableShape(p.subShape));
        noise_.setTone(p.noiseTone); noiseR_.setTone(p.noiseTone);
        noise_.setCharacter(p.noiseCharacter, p.noiseColor); noiseR_.setCharacter(p.noiseCharacter, p.noiseColor);
        const int t2 = std::clamp(p.filter2Type, 0, kFilter2Types - 1);
        if (t2 != f2Type_) { f2Type_ = t2; f2L_.setType(t2); f2R_.setType(t2); f2L_.reset(); f2R_.reset(); }
        f2L_.setMorph(p.filter2Morph); f2R_.setMorph(p.filter2Morph); // 0.22.0
    }

    // User tables for oscillators A/B (null = none; the synth owns them).
    void setCustomTables(const CustomTable* a, const CustomTable* b) { custom1_ = a; custom2_ = b; applyCustom(); }

    // Host tempo for synced LFOs.
    void setTempo(double bpm) {
        if (!(bpm > 1.0 && bpm < 1000.0) || bpm == bpm_) return;
        bpm_ = bpm;
        applyRates();
        applyMsegRates();
    }

    // 0.26.0: synced FREE LFOs take their phase from the host beat. The fade
    // (delay/rise) keeps running; only the phase moves.
    double lfoPhaseOf(int i) const { return const_cast<Voice*>(this)->lfo(std::clamp(i, 0, 3)).phase(); }
    void lockLfos(double beat) {
        for (int i = 0; i < 4; ++i) {
            if (!params_.lfoFree[i]) continue;
            const double b = syncBeats(params_.lfoSync[i]);
            if (b > 0.0) lfo(i).setPhase(beat / b + params_.lfoPhase[i]);
        }
    }
    void noteOn(int note, float velocity) {
        note_ = note;
        velocity_ = velocity;
        baseFreq_ = midiToFreq(note);
        glideLeft_ = 0; glideSemi_ = 0.0;
        polyAT_ = -1.0;
        ampEnv_.noteOn();
        modEnv_.noteOn();
        resetLfos();
        mseg1_.reset(); mseg2_.reset();
        env3_.noteOn();
        // Stacked voices start at spread phases so a unison stack sounds wide
        // from the first cycle instead of flanging out of one phase. Voice 0
        // starts at 0 like the single-oscillator path.
        if (params_.uniPhase == 1) { // 0.23.0 RANDOM: fresh start phases every note, all voices
            for (int i = 0; i < kMaxUnison; ++i) { osc1_[i].setPhase(nextRand()); osc2_[i].setPhase(nextRand()); }
        } else {
            for (int i = 0; i < kMaxUnison; ++i) {
                osc1_[i].setPhase(i == 0 ? 0.0 : std::fmod(i * 0.618034, 1.0));
                osc2_[i].setPhase(i == 0 ? 0.0 : std::fmod(i * 0.381966 + 0.25, 1.0));
            }
        }
        age_ = 0;
        sub_.setPhase(0.0);
        dcL_.reset(); dcR_.reset(); dcOn_ = false;
        noiseBurstPos_ = 0; // the burst retriggers with each played note
        noise_.reset(0x9e3779b9u ^ (uint32_t)(note * 2654435761u));
        noiseR_.reset(0x6c8e9cf5u ^ (uint32_t)(note * 2246822519u));
    }

    // 0.23.0 glide: slide the pitch from `fromHz` to the current note over
    // glideTime (constant time, straight line in semitones). No-op when off.
    void glideFrom(double fromHz) {
        if (!(params_.glideTime > 0.0) || !(fromHz > 0.0) || note_ < 0) return;
        glideTarget_ = midiToFreq(note_);
        glideSemi_ = 12.0 * std::log2(fromHz / glideTarget_);
        if (std::fabs(glideSemi_) < 1e-9) { glideSemi_ = 0.0; return; }
        glideLeft_ = std::max<int64_t>(1, (int64_t)std::llround(params_.glideTime * sr_));
        glideStep_ = -glideSemi_ / (double)glideLeft_;
        baseFreq_ = fromHz;
    }
    // 0.23.0 legato: move a sounding voice to a new note without restarting
    // its envelopes, LFOs or phases; glides there when glide is on.
    void legatoTo(int note) {
        const double from = baseFreq_;
        note_ = note;
        baseFreq_ = midiToFreq(note);
        glideLeft_ = 0; glideSemi_ = 0.0;
        glideFrom(from);
    }
    double currentFreq() const { return baseFreq_; }
    // 0.24.0: shared MIDI performance state and this voice's poly aftertouch (-1 = none, use channel pressure).
    void setPerformance(const Performance* p) { perf_ = p; }
    void setPolyAftertouch(double v) { polyAT_ = v; }
    double polyAftertouch() const { return polyAT_; }
    bool gliding() const { return glideLeft_ > 0; }

    void noteOff() { ampEnv_.noteOff(); modEnv_.noteOff(); env3_.noteOff(); mseg1_.release(); mseg2_.release(); }

    // 0.29.0: hard silence for a host Reset - envelopes, filter memories and glide cleared, so the next
    // note renders exactly as the first note after power-on (no release tail, no attack resuming mid-way).
    void silence() {
        ampEnv_.reset(); modEnv_.reset(); env3_.reset();
        filter_.reset(); filterR_.reset(); f2L_.reset(); f2R_.reset();
        dcL_.reset(); dcR_.reset();
        glideLeft_ = 0; glideSemi_ = 0.0;
        hbL_.reset(); hbR_.reset(); hbSub_.reset(); hbNoise_.reset(); hbNoiseR_.reset(); // 0.30.0 / 0.31.0 / 0.53.0
        noiseBurstPos_ = 0;
        resetRouteMeters();
    }
    // 0.30.0: oscillator oversampling on/off (the synth passes the effective QUALITY).
    void setHQ(bool on) {
        if (on == hq_) return;
        hq_ = on;
        const double osr = on ? 2.0 * sr_ : sr_;
        for (int i = 0; i < kMaxUnison; ++i) { osc1_[i].setSampleRate(osr); osc2_[i].setSampleRate(osr); }
        sub_.setSampleRate(osr); // 0.31.0
        hbL_.reset(); hbR_.reset(); hbSub_.reset(); hbNoise_.reset(); hbNoiseR_.reset();
    }
    bool hq() const { return hq_; }
    static constexpr double kHQLatency = Halfband2x::kLatency * 0.5; // 7.5 samples at 1x
    bool isActive() const { return ampEnv_.isActive(); }
    // Peak signed contribution this voice actually applied since its last meter reset.
    void resetRouteMeters() { routePeak_.fill(0.0f); routeMin_.fill(0.0f); routeMax_.fill(0.0f); }
    float routeMin(int slot) const { return slot >= 0 && slot < kMaxRoutes ? routeMin_[slot] : 0.0f; }
    float routeMax(int slot) const { return slot >= 0 && slot < kMaxRoutes ? routeMax_[slot] : 0.0f; }
    float routePeak(int slot) const { return slot >= 0 && slot < kMaxRoutes ? routePeak_[slot] : 0.0f; }
    double liveSpecMorph(int o) const { return liveMorph_[o ? 1 : 0]; } // 0.35.0 meter: the morph this voice last played
    bool dcBlockerOn() const { return dcOn_; } // 0.12.0 (tests)
    int note() const { return note_; }
    uint64_t age() const { return age_; }

    // Mono output (sum of the stereo voice); equals either channel whenever
    // the voice is mono, which is always the case without unison.
    inline float process() { float l, r; processStereo(l, r); return 0.5f * (l + r); }

    inline void processStereo(float& outL, float& outR) {
        if (glideLeft_ > 0) { // 0.23.0 glide
            if (--glideLeft_ == 0) { glideSemi_ = 0.0; baseFreq_ = glideTarget_; }
            else { glideSemi_ += glideStep_; baseFreq_ = glideTarget_ * std::pow(2.0, glideSemi_ / 12.0); }
        }
        float lfo = lfo1_.process();
        float lfo2 = lfo2_.process();
        float modEnv = modEnv_.process();
        float mseg1 = mseg1_.process();
        float lfo3 = usesLfo3_ ? lfo3_.process() : 0.0f;
        float lfo4 = usesLfo4_ ? lfo4_.process() : 0.0f;
        float env3 = env3_.process();
        float mseg2 = usesMseg2_ ? mseg2_.process() : 0.0f;

        // Source values in Source order; the rack LFOs (12, 13) live in the FX rack.
        const Performance& pf = perf_ ? *perf_ : kNoPerf;
        const double sv[kModSources] = {lfo, modEnv, velocity_, lfo2, mseg1,
                                        params_.macros[0], params_.macros[1], params_.macros[2], params_.macros[3],
                                        lfo3, lfo4, env3, 0.0, 0.0, mseg2,
                                        pf.wheel, polyAT_ >= 0 ? polyAT_ : pf.aftertouch, pf.bend, // 0.24.0
                                        note_ >= 0 ? std::clamp((note_ - 60) / 60.0, -1.0, 1.0) : 0.0};
        auto modSum = [&](ModRoute::Dest d) {
            double sum = 0.0;
            for (size_t slot = 0; slot < routes_.size(); ++slot) {
                const auto& r = routes_[slot];
                if (r.dest != d) continue;
                const int si = (int)r.source;
                double src = (si >= 0 && si < kModSources) ? sv[si] : 0.0;
                if (r.curve != 0.0) src = routeCurve(src, r.curve);
                if (r.aux >= 0 && r.aux < kModSources && !sourceIsRack(r.aux)) src *= auxLevel(r.aux, sv[r.aux]); // 0.16.0
                const double contribution = src * r.amount;
                if (slot < kMaxRoutes) {
                    const float level = (float)std::clamp(contribution / routeMeterScale(d), -1.0, 1.0);
                    if (std::fabs(level) > std::fabs(routePeak_[slot])) routePeak_[slot] = level;
                    routeMin_[slot] = std::min(routeMin_[slot], level);
                    routeMax_[slot] = std::max(routeMax_[slot], level);
                }
                sum += contribution;
            }
            return sum;
        };

        double pitch1 = modSum(ModRoute::Dest::Osc1Pitch);
        double pitch2 = params_.osc2Detune + modSum(ModRoute::Dest::Osc2Pitch);
        if (pf.bend != 0.0) { // 0.24.0 pitch bend moves both oscillators (and the sub, which follows A)
            const double b = pf.bend * std::clamp(params_.bendRange, 0, 24);
            pitch1 += b; pitch2 += b;
        }
        const auto wm1 = static_cast<Oscillator::WarpMode>(params_.osc1WarpMode);
        const auto wm2 = static_cast<Oscillator::WarpMode>(params_.osc2WarpMode);
        const double warp1 = std::clamp(params_.osc1Warp + modSum(ModRoute::Dest::Osc1Warp), 0.0, 1.0);
        const double warp2 = std::clamp(params_.osc2Warp + modSum(ModRoute::Dest::Osc2Warp), 0.0, 1.0);
        if (usesWarpX_) { // 0.19.0: second slots, oscillator B feed for FM B / AM B
            const auto m1 = static_cast<Oscillator::WarpMode>(std::clamp(params_.osc1Warp2Mode, 0, Oscillator::kWarpModes - 1));
            const auto m2 = static_cast<Oscillator::WarpMode>(std::clamp(params_.osc2Warp2Mode, 0, Oscillator::kWarpModes - 1));
            const double a1 = std::clamp(params_.osc1Warp2 + modSum(ModRoute::Dest::Osc1Warp2), 0.0, 1.0);
            const double a2 = std::clamp(params_.osc2Warp2 + modSum(ModRoute::Dest::Osc2Warp2), 0.0, 1.0);
            w2a_ = a1; w2b_ = a2;
            const float mB = osc2_[0].lastOut();
            for (int i = 0; i < kMaxUnison; ++i) {
                osc1_[i].setWarp2(m1, a1); osc2_[i].setWarp2(m2, a2);
                osc1_[i].setModInput(mB); osc2_[i].setModInput(mB);
            }
        }
        float osc2Level = static_cast<float>(
            std::clamp(params_.osc2Level + modSum(ModRoute::Dest::Osc2Level), 0.0, 1.0));
        const float g1 = 1.0f - osc2Level * 0.5f, g2 = osc2Level;
        // 0.12.0: engage the DC blocker for the rest of the note the first time
        // an oscillator that can carry DC is heard. Sounds that never do so
        // never run it, and stay sample-identical to 0.11.0.
        if (!dcOn_ && ((shapeProne(params_.osc1Shape) || (warpProne(params_.osc1WarpMode) && warp1 > 0))
                       || (g2 > 0 && (shapeProne(params_.osc2Shape) || (warpProne(params_.osc2WarpMode) && warp2 > 0)))))
            dcOn_ = true;
        if (!dcOn_ && usesWarpX_ && ((warp2Prone(params_.osc1Warp2Mode) && w2a_ > 0) || (g2 > 0 && warp2Prone(params_.osc2Warp2Mode) && w2b_ > 0)))
            dcOn_ = true; // 0.19.0: a second slot can carry DC once its amount is above 0

        const int n1 = std::clamp(params_.osc1Unison, 1, kMaxUnison);
        const int n2 = std::clamp(params_.osc2Unison, 1, kMaxUnison);
        if (active1_) { const double wp = std::clamp(params_.osc1WtPos + modSum(ModRoute::Dest::Osc1WtPos), 0.0, 1.0); for (int i = 0; i < n1; ++i) osc1_[i].setWtPos(wp); }
        if (active2_) { const double wp = std::clamp(params_.osc2WtPos + modSum(ModRoute::Dest::Osc2WtPos), 0.0, 1.0); for (int i = 0; i < n2; ++i) osc2_[i].setWtPos(wp); }
        if (active1_ && (params_.osc1SpecMorph != 0.0 || usesSpecMorph_[0])) { // 0.33.0
            const double sm = std::clamp(params_.osc1SpecMorph + modSum(ModRoute::Dest::Osc1SpecMorph), 0.0, 1.0); for (int i = 0; i < n1; ++i) osc1_[i].setSpecMorph(sm); liveMorph_[0] = sm; }
        else liveMorph_[0] = 0.0;
        if (active2_ && (params_.osc2SpecMorph != 0.0 || usesSpecMorph_[1])) {
            const double sm = std::clamp(params_.osc2SpecMorph + modSum(ModRoute::Dest::Osc2SpecMorph), 0.0, 1.0); for (int i = 0; i < n2; ++i) osc2_[i].setSpecMorph(sm); liveMorph_[1] = sm; }
        else liveMorph_[1] = 0.0;
        float l, r;
        bool stereo = false;
        auto oscBlock = [&](float& l, float& r) {
            if (n1 == 1 && n2 == 1) {
                // Classic path, unchanged since 0.1: one oscillator each, mono.
                osc1_[0].setFrequency(baseFreq_);
                osc1_[0].setDetuneSemitones(pitch1);
                osc1_[0].setWarp(wm1, warp1);
                osc2_[0].setFrequency(baseFreq_);
                osc2_[0].setDetuneSemitones(pitch2);
                osc2_[0].setWarp(wm2, warp2);
                l = r = osc1_[0].process() * g1 + osc2_[0].process() * g2;
            } else {
                const double width = std::clamp(params_.uniWidth + modSum(ModRoute::Dest::UnisonWidth), 0.0, 1.0);
                if (usesUniBlend_) blendMod_ = modSum(ModRoute::Dest::UnisonBlend); // 0.23.0
                const double det1 = std::clamp(params_.osc1UniDetune + modSum(ModRoute::Dest::Osc1Unison), 0.0, 1.0);
                const double det2 = std::clamp(params_.osc2UniDetune + modSum(ModRoute::Dest::Osc2Unison), 0.0, 1.0);
                float l1 = 0, r1 = 0, l2 = 0, r2 = 0;
                stack(osc1_, gains1_, n1, pitch1, det1, width, wm1, warp1, l1, r1);
                stack(osc2_, gains2_, n2, pitch2, det2, width, wm2, warp2, l2, r2);
                l = l1 * g1 + l2 * g2;
                r = r1 * g1 + r2 * g2;
                stereo = width > 0.0;
            }
        };
        if (!hq_) oscBlock(l, r);
        else { // 0.30.0 HQ: two oscillator samples at 2x, then one halfband down (7.5 samples late)
            float la, ra, lb, rb;
            oscBlock(la, ra); oscBlock(lb, rb);
            l = (float)hbL_.down(la, lb); r = (float)hbR_.down(ra, rb);
        }

        // 0.12.0 DC blocker on the oscillator mix (see dcOn_ above).
        if (dcOn_) { l = dcL_.process(l); r = dcR_.process(r); }

        // 0.10.0 sub oscillator (follows oscillator A's pitch) and noise, mono, pre-filter.
        if (usesSub_) {
            const float lv = (float)std::clamp(params_.subLevel + modSum(ModRoute::Dest::SubLevel), 0.0, 1.0);
            sub_.setFrequency(baseFreq_ * (params_.subOctave >= 2 ? 0.25 : 0.5));
            sub_.setDetuneSemitones(pitch1);
            // 0.31.0: in HQ the sub runs at 2x through its own halfband, so it lines up with the oscillators (7.5 samples).
            float sub = sub_.process();
            if (hq_) { const float sub2 = sub_.process(); sub = (float)hbSub_.down(sub, sub2); }
            const float sv = sub * lv * 0.8f;
            l += sv; r += sv;
        }
        if (usesNoise_) {
            if (params_.noiseCharacter != 0 && usesNoiseColor_) {
                const double color = std::clamp(params_.noiseColor + modSum(ModRoute::Dest::NoiseColor), 0.0, 1.0);
                noise_.setCharacter(params_.noiseCharacter, color);
                if (params_.noiseWidth > 0) noiseR_.setCharacter(params_.noiseCharacter, color);
            }
            float burst = 1.0f;
            if (noiseBurstLength_ > 0) {
                burst = noiseBurstGain(noiseBurstPos_, noiseBurstLength_, params_.noiseBurstAttack, params_.noiseBurstCurve);
                if (noiseBurstPos_ < noiseBurstLength_) ++noiseBurstPos_;
            }
            const float lv = (float)std::clamp(params_.noiseLevel + modSum(ModRoute::Dest::NoiseLevel), 0.0, 1.0);
            float nv = noise_.process() * lv * burst;
            if (hq_) nv = (float)hbNoise_.down(nv, nv); // legacy left/mono alignment
            l += nv;
            if (params_.noiseWidth > 0) {
                const double width = std::clamp(params_.noiseWidth, 0.0, 1.0);
                float nr = noiseR_.process() * lv * burst;
                if (hq_) nr = (float)hbNoiseR_.down(nr, nr);
                // Keep the left legacy stream untouched. Normalize the right
                // blend's power; width 1 is an independent right channel.
                const double mid = 1.0 - width;
                r += (float)((mid * nv + width * nr) / std::sqrt(mid * mid + width * width));
                stereo = true;
            } else r += nv; // exact old operations and single RNG stream
        }
        const float preL = l, preR = r;

        // Cutoff modulation is exponential: amount 1.0 = one octave up at full source.
        double cutoffMod = modSum(ModRoute::Dest::FilterCutoff);
        if (params_.filterKeytrack > 0 && note_ >= 0) cutoffMod += params_.filterKeytrack * (note_ - 60) / 12.0; // 0.21.0
        double cutoff = params_.filterCutoff * std::pow(2.0, cutoffMod);
        double resonance = std::clamp(params_.filterReso + modSum(ModRoute::Dest::FilterResonance), 0.1, 18.0);
        if (usesFilterX_) { // routed drive/morph: per-sample
            const double dv = std::clamp(params_.filterDrive + modSum(ModRoute::Dest::FilterDrive), 0.0, 1.0);
            const double mv = std::clamp(params_.filterMorph + modSum(ModRoute::Dest::FilterMorph), 0.0, 1.0);
            filter_.setDrive(dv); filterR_.setDrive(dv); filter_.setMorph(mv); filterR_.setMorph(mv);
        }
        filter_.set(cutoff, resonance);
        l = filter_.process(l);
        if (stereo) { filterR_.set(cutoff, resonance); r = filterR_.process(r); }
        else { r = l; filterR_.copyStateFrom(filter_); } // keep the right filter warm for a width change
        // 0.22.0: an oversampled filter runs d1 samples late; dry paths are delayed to match so MIX / PARALLEL don't comb.
        const int d1 = filter_.latency();
        const float dryL1 = alignDry1L_.process(preL, d1), dryR1 = alignDry1R_.process(preR, d1);
        if (params_.filter1Mix != 1.0) { // 0.22.0 filter 1 dry/wet
            const float m1 = (float)std::clamp(params_.filter1Mix, 0.0, 1.0);
            l = dryL1 + m1 * (l - dryL1); r = dryR1 + m1 * (r - dryR1);
        }

        // 0.10.0 filter 2: after filter 1 (serial) or beside it on the dry mix (parallel).
        if (f2Type_ != 0) {
            const double c2 = params_.filter2Cutoff * std::pow(2.0, modSum(ModRoute::Dest::Filter2Cutoff));
            if (usesF2Morph_) { const double mv = std::clamp(params_.filter2Morph + modSum(ModRoute::Dest::Filter2Morph), 0.0, 1.0); f2L_.setMorph(mv); f2R_.setMorph(mv); }
            f2L_.set(c2, params_.filter2Reso);
            const bool par = params_.filterRouting == 1;
            const float inL = par ? preL : l;
            const float inR = par ? preR : r;
            float yL = f2L_.process(inL);
            float yR = yL;
            if (stereo) { f2R_.set(c2, params_.filter2Reso); yR = f2R_.process(inR); }
            const int d2 = f2L_.latency();
            const float dryL2 = alignDry2L_.process(inL, d2), dryR2 = alignDry2R_.process(stereo ? inR : inL, d2);
            if (params_.filter2Mix != 1.0) { // 0.22.0 filter 2 dry/wet
                const float m2 = (float)std::clamp(params_.filter2Mix, 0.0, 1.0);
                yL = dryL2 + m2 * (yL - dryL2); yR = dryR2 + m2 * (yR - dryR2);
            }
            if (par) { // line the two paths up: the earlier one waits for the later one
                const int dd = d1 - d2;
                l = alignParL_.process(l, dd < 0 ? -dd : 0); r = alignParR_.process(r, dd < 0 ? -dd : 0);
                yL = alignPar2L_.process(yL, dd > 0 ? dd : 0); yR = alignPar2R_.process(yR, dd > 0 ? dd : 0);
            }
            if (par) {
                if (params_.filterBalance == 0.5 && !usesBalance_) { l = 0.5f * (l + yL); r = 0.5f * (r + yR); } // 0.10.0 mix, unchanged
                else { // 0.22.0 balance: 0 = filter 1 only .. 1 = filter 2 only
                    const float b = (float)std::clamp(params_.filterBalance + modSum(ModRoute::Dest::FilterBalance), 0.0, 1.0);
                    l = (1.0f - b) * l + b * yL; r = (1.0f - b) * r + b * yR;
                }
            }
            else { l = yL; r = yR; }
        }

        float amp = ampEnv_.process();
        ++age_;
        outL = l * amp * velocity_;
        outR = r * amp * velocity_;
    }

private:
    double sr_ = 44100.0;
    bool hq_ = false;          // 0.30.0
    Halfband2x hbL_, hbR_;
    Halfband2x hbSub_, hbNoise_, hbNoiseR_; // 0.31.0 sub / noise alignment in HQ
    uint64_t noiseBurstPos_ = 0, noiseBurstLength_ = 0; // samples since note-on; saturates at end of burst
    int note_ = -1;
    float velocity_ = 0.0f;
    double baseFreq_ = 440.0;
    uint64_t age_ = 0;
    // 0.23.0 glide state and the RANDOM unison phase generator.
    double glideTarget_ = 440.0, glideSemi_ = 0.0, glideStep_ = 0.0;
    int64_t glideLeft_ = 0;
    const Performance* perf_ = nullptr; // 0.24.0
    double polyAT_ = -1.0;
    static inline const Performance kNoPerf{};
    uint32_t rng_ = 0x6d2b79f5u;
    double nextRand() { rng_ ^= rng_ << 13; rng_ ^= rng_ >> 17; rng_ ^= rng_ << 5; return (rng_ >> 8) * (1.0 / 16777216.0); }
public:
    void seedPhases(uint32_t s) { rng_ = s ? s : 0x6d2b79f5u; }
private:
    // One unison stack of n voices: symmetric detune (outer voices at
    // +-detune semitones), constant-power pan across +-width, outer voices
    // at `blend` level, sum normalized by 1/sqrt(weights) so a stack keeps
    // the loudness of a single oscillator.
    struct StackGains {
        int n = 0; double width = -1, blend = -1, detune = -1;
        float gl[kMaxUnison], gr[kMaxUnison];
        double ratio[kMaxUnison];
        void update(int n_, double width_, double blend_) {
            if (n_ == n && width_ == width && blend_ == blend) return; // cached: trig only on change
            if (n_ != n) detune = -1; // voice count changed: ratios too
            n = n_; width = width_; blend = blend_;
            double norm = 0.0, w[kMaxUnison];
            for (int i = 0; i < n; ++i) {
                const double pos = 2.0 * i / (n - 1) - 1.0;
                w[i] = 1.0 - (1.0 - blend) * std::fabs(pos);
                norm += w[i] * w[i];
            }
            const double k = 1.0 / std::sqrt(norm);
            for (int i = 0; i < n; ++i) {
                const double pos = 2.0 * i / (n - 1) - 1.0;
                const double ang = (pos * width + 1.0) * M_PI * 0.25; // 0..pi/2, center = equal
                gl[i] = static_cast<float>(w[i] * k * std::cos(ang) * M_SQRT2);
                gr[i] = static_cast<float>(w[i] * k * std::sin(ang) * M_SQRT2);
            }
        }
    };

    // One unison stack of n voices: symmetric detune (outer voices at
    // +-detune semitones), constant-power pan across +-width, outer voices
    // at `blend` level, normalized by 1/sqrt(sum of squared weights) so a
    // stack keeps roughly the loudness of a single oscillator.
    inline void stack(Oscillator* osc, StackGains& gains, int n, double pitch, double detune, double width,
                      Oscillator::WarpMode wm, double warp, float& l, float& r) {
        if (n == 1) {
            osc[0].setFrequency(baseFreq_); osc[0].setDetuneSemitones(pitch); osc[0].setWarp(wm, warp);
            float s = osc[0].process();
            l += s; r += s;
            return;
        }
        gains.update(n, width, usesUniBlend_ ? std::clamp(params_.uniBlend + blendMod_, 0.0, 1.0) : std::clamp(params_.uniBlend, 0.0, 1.0));
        if (detune != gains.detune) { // per-voice pitch ratios, recomputed only when the spread moves
            gains.detune = detune;
            for (int i = 0; i < n; ++i) gains.ratio[i] = std::pow(2.0, (2.0 * i / (n - 1) - 1.0) * detune / 12.0);
        }
        const double hz = baseFreq_ * std::pow(2.0, pitch / 12.0);
        // Band-limit the whole stack for its highest voice: no aliasing, one mip lookup.
        const double level = Wavetable::levelForFrequency(hz * gains.ratio[n - 1], sr_);
        for (int i = 0; i < n; ++i) {
            osc[i].setWarp(wm, warp);
            const float s = osc[i].processAt(hz * gains.ratio[i], level);
            l += s * gains.gl[i];
            r += s * gains.gr[i];
        }
    }

    // Shape kCustomShape plays the oscillator's table; without one it falls
    // back to the saw so an incomplete preset still sounds.
public:
    // 0.18.0: shared clock (samples since the synth started) for free-run LFOs.
    void setClock(uint64_t samples) { clock_ = samples; }
    LFO& lfo(int i) { return i == 0 ? lfo1_ : i == 1 ? lfo2_ : i == 2 ? lfo3_ : lfo4_; }
    // Oscillator settings that can leave a DC offset: bending or splitting the
    // phase of an asymmetric table, the PULSE shape, and user-drawn tables.
    // Per oscillator: the PULSE shape and user tables can always carry DC;
    // BEND+/BEND-/PWM only once their warp amount is above 0.
    static bool shapeProne(int shape) { return shape == 4 || shape == kCustomShape; }
    static bool warpProne(int mode) { return mode == 2 || mode == 3 || mode == 4 || mode >= 7; } // 0.19.0: FM/AM/WINDOW/REMAP too
private:
    void applyCustom() {
        active1_ = params_.osc1Shape == kCustomShape; active2_ = params_.osc2Shape == kCustomShape;
        for (int i = 0; i < kMaxUnison; ++i) {
            osc1_[i].setCustom(active1_ ? (custom1_ ? custom1_ : fallback()) : nullptr);
            osc2_[i].setCustom(active2_ ? (custom2_ ? custom2_ : fallback()) : nullptr);
        }
    }
    static const CustomTable* fallback() { static const CustomTable t{TableFrames{}}; return &t; }

    void resetLfos() {
        for (int i = 0; i < 4; ++i) {
            if (params_.lfoFree[i]) {
                const double hz = lfoHz(i == 0 ? params_.lfo1Rate : i == 1 ? params_.lfo2Rate : i == 2 ? params_.lfo3Rate : params_.lfo4Rate, params_.lfoSync[i], bpm_);
                lfo(i).resetTo(std::fmod((double)clock_ / sr_ * hz, 1.0) + params_.lfoPhase[i]);
            } else lfo(i).reset();
        }
    }
    void applyWarpX() {
        const auto& v = params_;
        usesWarpX_ = v.osc1Warp2Mode != 0 || v.osc2Warp2Mode != 0 || v.osc1WarpMode >= 7 || v.osc2WarpMode >= 7;
        for (int o = 0; o < 2; ++o) {
            const bool used = (o ? v.osc2WarpMode : v.osc1WarpMode) == 10 || (o ? v.osc2Warp2Mode : v.osc1Warp2Mode) == 10;
            if (used && !(remapValid_[o] && remapPts_[o].size() == v.remapPoints[o].size() && samePoints(remapPts_[o], v.remapPoints[o]))) {
                MSEG m; m.setPoints(v.remapPoints[o]);
                for (int k = 0; k <= Oscillator::kRemapTable; ++k) remapTable_[o][k] = static_cast<float>(m.valueAt((double)k / Oscillator::kRemapTable));
                remapPts_[o] = v.remapPoints[o]; remapValid_[o] = true;
            }
            for (int i = 0; i < kMaxUnison; ++i) (o ? osc2_[i] : osc1_[i]).setRemap(used ? remapTable_[o] : nullptr);
        }
        if (!usesWarpX_) for (int i = 0; i < kMaxUnison; ++i) { osc1_[i].setWarp2(Oscillator::WarpMode::Off, 0); osc2_[i].setWarp2(Oscillator::WarpMode::Off, 0); }
    }
    float remapTable_[2][Oscillator::kRemapTable + 1] = {};
    std::vector<MSEG::Point> remapPts_[2];
    bool remapValid_[2] = {false, false};
    bool usesWarpX_ = false;
    bool usesFilterX_ = false;
    bool usesF2Morph_ = false, usesBalance_ = false; // 0.22.0
    bool usesUniBlend_ = false; double blendMod_ = 0.0; // 0.23.0
    bool usesSpecMorph_[2] = {false, false}; // 0.33.0
    double liveMorph_[2] = {0.0, 0.0};        // 0.35.0
    AlignDelay alignDry1L_, alignDry1R_, alignDry2L_, alignDry2R_, alignParL_, alignParR_, alignPar2L_, alignPar2R_; // 0.22.0 // 0.21.0: a route targets FILTER DRIVE or MORPH
    double w2a_ = 0.0, w2b_ = 0.0;
    static bool warp2Prone(int mode) { return mode >= 2 && mode != 5 && mode != 6 ? true : false; }
    void applyLfoExtras() {
        for (int i = 0; i < 4; ++i) {
            LFO& l = lfo(i);
            l.setStartPhase(params_.lfoPhase[i]);
            l.setFade(params_.lfoDelay[i] * sr_, params_.lfoRise[i] * sr_);
            if (params_.lfoCustom[i]) {
                if (!(lfoTablePts_[i].size() == params_.lfoPoints[i].size() && lfoTableValid_[i] && samePoints(lfoTablePts_[i], params_.lfoPoints[i]))) {
                    MSEG m; m.setPoints(params_.lfoPoints[i]);
                    for (int k = 0; k <= LFO::kTable; ++k) lfoTable_[i][k] = static_cast<float>(m.valueAt((double)k / LFO::kTable));
                    lfoTablePts_[i] = params_.lfoPoints[i]; lfoTableValid_[i] = true;
                }
                l.setCustom(lfoTable_[i]);
            } else l.setCustom(nullptr);
        }
    }
    static bool samePoints(const std::vector<MSEG::Point>& a, const std::vector<MSEG::Point>& b) {
        for (size_t k = 0; k < a.size(); ++k) if (a[k].time != b[k].time || a[k].value != b[k].value || a[k].curve != b[k].curve) return false;
        return true;
    }
    float lfoTable_[4][LFO::kTable + 1] = {};
    std::vector<MSEG::Point> lfoTablePts_[4];
    bool lfoTableValid_[4] = {false, false, false, false};
    uint64_t clock_ = 0;

    void applyRates() {
        lfo1_.setRate(lfoHz(params_.lfo1Rate, params_.lfoSync[0], bpm_));
        lfo2_.setRate(lfoHz(params_.lfo2Rate, params_.lfoSync[1], bpm_));
        lfo3_.setRate(lfoHz(params_.lfo3Rate, params_.lfoSync[2], bpm_));
        lfo4_.setRate(lfoHz(params_.lfo4Rate, params_.lfoSync[3], bpm_));
    }

    Oscillator sub_;
    NoiseSource noise_, noiseR_;
    DCBlocker dcL_, dcR_;
    bool dcOn_ = false;
    Filter2 f2L_, f2R_;
    int f2Type_ = 0;
    bool usesNoiseColor_ = false;
    bool usesSub_ = false, usesNoise_ = false;
    StackGains gains1_, gains2_;
    LFO lfo3_, lfo4_;
    Envelope env3_;
    bool usesLfo3_ = false, usesLfo4_ = false;
    const CustomTable* custom1_ = nullptr; const CustomTable* custom2_ = nullptr;
    bool active1_ = false, active2_ = false;
    double bpm_ = 120.0;
    Oscillator osc1_[kMaxUnison], osc2_[kMaxUnison];
    Filter1 filter_, filterR_; // 0.21.0 (SVF modes run exactly as the old SVFilter)
    Envelope ampEnv_, modEnv_;
    LFO lfo1_, lfo2_;
    MSEG mseg1_, mseg2_;
    bool usesMseg2_ = false;
    // MSEG length: seconds, or a synced division (beats) at the host tempo.
    static double msegSeconds(double sec, int sync, double bpm) { double b = syncBeats(sync); return b > 0 ? b * 60.0 / bpm : sec; }
    void applyMsegRates() {
        mseg1_.setRate(msegSeconds(params_.mseg1Seconds, params_.mseg1Sync, bpm_));
        mseg2_.setRate(msegSeconds(params_.mseg2Seconds, params_.mseg2Sync, bpm_));
    }
    VoiceParams params_;
    std::array<float, kMaxRoutes> routePeak_{}; // render-block peaks; audio-thread owned
    std::array<float, kMaxRoutes> routeMin_{}, routeMax_{}; // 0.59.0 signed extrema
    std::vector<ModRoute> routes_;
};

} // namespace muew
