#pragma once
#include "oscillator.h"
#include "filter.h"
#include "envelope.h"
#include "lfo.h"
#include "mseg.h"
#include "layers.h"
#include "tempo_sync.h"
#include <cmath>

namespace muew {

inline double midiToFreq(int note) {
    return 440.0 * std::pow(2.0, (note - 69) / 12.0);
}

// Modulation routing: a source scales into a destination.
struct ModRoute {
    // Append only: values are stored in presets and host projects.
    enum class Source { LFO1 = 0, ModEnv = 1, Velocity = 2, LFO2 = 3, MSEG1 = 4,
                        Macro1 = 5, Macro2 = 6, Macro3 = 7, Macro4 = 8,
                        LFO3 = 9, LFO4 = 10, Env3 = 11 } source; // 0.8.0: LFO 3/4, ENV 3
    enum class Dest { Osc1Pitch = 0, Osc2Pitch = 1, FilterCutoff = 2, Osc2Level = 3, FilterResonance = 4, Osc1Warp = 5, Osc2Warp = 6,
                      Osc1Unison = 7, Osc2Unison = 8, UnisonWidth = 9, // 0.7.0: unison detune A/B, stereo width (0..1 units)
                      DistDrive = 10,                                   // 0.7.0: FX-rack drive, macro sources only (global FX)
                      Osc1WtPos = 11, Osc2WtPos = 12,                   // 0.9.0: user-table frame position (0..1 units)
                      SubLevel = 13, NoiseLevel = 14, Filter2Cutoff = 15, // 0.10.0 (0..1 levels, octaves)
                      // 0.14.0: FX detail controls, macro sources only (global FX)
                      FxDelayFeedback = 16, FxReverbDecay = 17, FxPhaserDepth = 18, FxFlangerDepth = 19, FxChorusDepth = 20 } dest;
    double amount = 0.0; // semitones for pitch, Hz-scaled multiplier for cutoff, 0..1 for level
};

struct VoiceParams {
    int osc1Shape = 2;       // Saw
    int osc2Shape = 3;       // Square
    double osc2Detune = 7.0; // semitones
    double osc2Level = 0.5;
    double filterCutoff = 8000.0;
    double filterReso = 0.7;
    int filterMode = 0;      // SVFilter::Mode
    double ampA = 0.005, ampD = 0.15, ampS = 0.8, ampR = 0.3;
    double modA = 0.01, modD = 0.3, modS = 0.0, modR = 0.2;
    double lfo1Rate = 5.0, lfo2Rate = 0.35;
    int lfo1Shape = 0, lfo2Shape = 1;
    int osc1WarpMode = 0, osc2WarpMode = 0;
    double osc1Warp = 0.0, osc2Warp = 0.0;
    double mseg1Seconds = 1.0;
    bool mseg1Loop = false;
    // Breakpoints (time 0..1, value -1..1). Defaults match MSEG's built-in
    // shape so presets written before points were stored sound identical.
    std::vector<MSEG::Point> mseg1Points{{0.0, 0.0}, {0.15, 1.0}, {0.55, -0.3}, {1.0, 0.0}};
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
    double env3A = 0.01, env3D = 0.4, env3S = 0.0, env3R = 0.3;
    // 0.9.0: frame position (0..1) through each oscillator's user table; only
    // heard when the oscillator's shape is kCustomShape.
    double osc1WtPos = 0.0, osc2WtPos = 0.0;
    // 0.10.0 layers. Level 0 / type Off skip the stage entirely.
    double subLevel = 0.0;     // 0..1
    int subOctave = 1;         // 1 or 2 octaves below oscillator A
    int subShape = 0;          // kSubShapes: SINE, TRI, SQUARE
    double noiseLevel = 0.0;   // 0..1
    double noiseTone = 1.0;    // 0 dark .. 1 white
    int filter2Type = 0;       // Filter2Type
    double filter2Cutoff = 2000.0, filter2Reso = 0.7;
    int filterRouting = 0;     // 0 serial (filter 1 -> filter 2), 1 parallel
};

constexpr int kMaxUnison = 8;
constexpr int kMaxRoutes = 16; // mod matrix slots

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
            osc1_[i].setSampleRate(sr); osc1_[i].setTable(table);
            osc2_[i].setSampleRate(sr); osc2_[i].setTable(table);
        }
        filter_.setSampleRate(sr); filterR_.setSampleRate(sr);
        ampEnv_.setSampleRate(sr);
        modEnv_.setSampleRate(sr);
        lfo1_.setSampleRate(sr); lfo2_.setSampleRate(sr);
        lfo3_.setSampleRate(sr); lfo4_.setSampleRate(sr); env3_.setSampleRate(sr);
        mseg1_.setSampleRate(sr);
        sub_.setSampleRate(sr); sub_.setTable(table);
        noise_.setSampleRate(sr);
        dcL_.setSampleRate(sr); dcR_.setSampleRate(sr);
        f2L_.setSampleRate(sr); f2R_.setSampleRate(sr);
    }

    void setParams(const VoiceParams& p, const std::vector<ModRoute>& routes) {
        params_ = p; routes_ = routes;
        for (int i = 0; i < kMaxUnison; ++i) { osc1_[i].setShape(std::clamp(p.osc1Shape, 0, 4)); osc2_[i].setShape(std::clamp(p.osc2Shape, 0, 4)); }
        applyCustom();
        filter_.setMode(static_cast<SVFilter::Mode>(p.filterMode));
        filterR_.setMode(static_cast<SVFilter::Mode>(p.filterMode));
        ampEnv_.set(p.ampA, p.ampD, p.ampS, p.ampR);
        modEnv_.set(p.modA, p.modD, p.modS, p.modR);
        lfo1_.setShape(static_cast<LFO::Shape>(p.lfo1Shape));
        lfo2_.setShape(static_cast<LFO::Shape>(p.lfo2Shape));
        lfo3_.setShape(static_cast<LFO::Shape>(std::clamp(p.lfo3Shape, 0, 3)));
        lfo4_.setShape(static_cast<LFO::Shape>(std::clamp(p.lfo4Shape, 0, 3)));
        applyRates();
        env3_.set(p.env3A, p.env3D, p.env3S, p.env3R);
        usesLfo3_ = usesLfo4_ = false;
        for (const auto& r : routes) {
            if (r.source == ModRoute::Source::LFO3) usesLfo3_ = true;
            if (r.source == ModRoute::Source::LFO4) usesLfo4_ = true;
        }
        mseg1_.setRate(p.mseg1Seconds); mseg1_.setPoints(p.mseg1Points);
        mseg1_.setLoop(1, (int)mseg1_.pointCount() - 1, p.mseg1Loop);
        
        usesSub_ = p.subLevel > 0; usesNoise_ = p.noiseLevel > 0;
        for (const auto& r : routes) {
            if (r.dest == ModRoute::Dest::SubLevel) usesSub_ = true;
            if (r.dest == ModRoute::Dest::NoiseLevel) usesNoise_ = true;
        }
        sub_.setShape(subTableShape(p.subShape));
        noise_.setTone(p.noiseTone);
        const int t2 = std::clamp(p.filter2Type, 0, kFilter2Types - 1);
        if (t2 != f2Type_) { f2Type_ = t2; f2L_.setType(t2); f2R_.setType(t2); f2L_.reset(); f2R_.reset(); }
    }

    // User tables for oscillators A/B (null = none; the synth owns them).
    void setCustomTables(const CustomTable* a, const CustomTable* b) { custom1_ = a; custom2_ = b; applyCustom(); }

    // Host tempo for synced LFOs.
    void setTempo(double bpm) {
        if (!(bpm > 1.0 && bpm < 1000.0) || bpm == bpm_) return;
        bpm_ = bpm;
        applyRates();
    }

    void noteOn(int note, float velocity) {
        note_ = note;
        velocity_ = velocity;
        baseFreq_ = midiToFreq(note);
        ampEnv_.noteOn();
        modEnv_.noteOn();
        lfo1_.reset(); lfo2_.reset(); lfo3_.reset(); lfo4_.reset(); mseg1_.reset();
        env3_.noteOn();
        // Stacked voices start at spread phases so a unison stack sounds wide
        // from the first cycle instead of flanging out of one phase. Voice 0
        // starts at 0 like the single-oscillator path.
        for (int i = 0; i < kMaxUnison; ++i) {
            osc1_[i].setPhase(i == 0 ? 0.0 : std::fmod(i * 0.618034, 1.0));
            osc2_[i].setPhase(i == 0 ? 0.0 : std::fmod(i * 0.381966 + 0.25, 1.0));
        }
        age_ = 0;
        sub_.setPhase(0.0);
        dcL_.reset(); dcR_.reset(); dcOn_ = false;
        noise_.reset(0x9e3779b9u ^ (uint32_t)(note * 2654435761u));
    }

    void noteOff() { ampEnv_.noteOff(); modEnv_.noteOff(); env3_.noteOff(); mseg1_.release(); }

    bool isActive() const { return ampEnv_.isActive(); }
    bool dcBlockerOn() const { return dcOn_; } // 0.12.0 (tests)
    int note() const { return note_; }
    uint64_t age() const { return age_; }

    // Mono output (sum of the stereo voice); equals either channel whenever
    // the voice is mono, which is always the case without unison.
    inline float process() { float l, r; processStereo(l, r); return 0.5f * (l + r); }

    inline void processStereo(float& outL, float& outR) {
        float lfo = lfo1_.process();
        float lfo2 = lfo2_.process();
        float modEnv = modEnv_.process();
        float mseg1 = mseg1_.process();
        float lfo3 = usesLfo3_ ? lfo3_.process() : 0.0f;
        float lfo4 = usesLfo4_ ? lfo4_.process() : 0.0f;
        float env3 = env3_.process();

        auto modSum = [&](ModRoute::Dest d) {
            double sum = 0.0;
            for (const auto& r : routes_) {
                if (r.dest != d) continue;
                double src = 0.0;
                switch (r.source) {
                case ModRoute::Source::LFO1: src = lfo; break;
                case ModRoute::Source::LFO2: src = lfo2; break;
                case ModRoute::Source::ModEnv: src = modEnv; break;
                case ModRoute::Source::MSEG1: src = mseg1; break;
                case ModRoute::Source::Velocity: src = velocity_; break;
                case ModRoute::Source::Macro1: src = params_.macros[0]; break;
                case ModRoute::Source::Macro2: src = params_.macros[1]; break;
                case ModRoute::Source::Macro3: src = params_.macros[2]; break;
                case ModRoute::Source::Macro4: src = params_.macros[3]; break;
                case ModRoute::Source::LFO3: src = lfo3; break;
                case ModRoute::Source::LFO4: src = lfo4; break;
                case ModRoute::Source::Env3: src = env3; break;
                }
                sum += src * r.amount;
            }
            return sum;
        };

        const double pitch1 = modSum(ModRoute::Dest::Osc1Pitch);
        const double pitch2 = params_.osc2Detune + modSum(ModRoute::Dest::Osc2Pitch);
        const auto wm1 = static_cast<Oscillator::WarpMode>(params_.osc1WarpMode);
        const auto wm2 = static_cast<Oscillator::WarpMode>(params_.osc2WarpMode);
        const double warp1 = std::clamp(params_.osc1Warp + modSum(ModRoute::Dest::Osc1Warp), 0.0, 1.0);
        const double warp2 = std::clamp(params_.osc2Warp + modSum(ModRoute::Dest::Osc2Warp), 0.0, 1.0);
        float osc2Level = static_cast<float>(
            std::clamp(params_.osc2Level + modSum(ModRoute::Dest::Osc2Level), 0.0, 1.0));
        const float g1 = 1.0f - osc2Level * 0.5f, g2 = osc2Level;
        // 0.12.0: engage the DC blocker for the rest of the note the first time
        // an oscillator that can carry DC is heard. Sounds that never do so
        // never run it, and stay sample-identical to 0.11.0.
        if (!dcOn_ && ((shapeProne(params_.osc1Shape) || (warpProne(params_.osc1WarpMode) && warp1 > 0))
                       || (g2 > 0 && (shapeProne(params_.osc2Shape) || (warpProne(params_.osc2WarpMode) && warp2 > 0)))))
            dcOn_ = true;

        const int n1 = std::clamp(params_.osc1Unison, 1, kMaxUnison);
        const int n2 = std::clamp(params_.osc2Unison, 1, kMaxUnison);
        if (active1_) { const double wp = std::clamp(params_.osc1WtPos + modSum(ModRoute::Dest::Osc1WtPos), 0.0, 1.0); for (int i = 0; i < n1; ++i) osc1_[i].setWtPos(wp); }
        if (active2_) { const double wp = std::clamp(params_.osc2WtPos + modSum(ModRoute::Dest::Osc2WtPos), 0.0, 1.0); for (int i = 0; i < n2; ++i) osc2_[i].setWtPos(wp); }
        float l, r;
        bool stereo = false;
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
            const double det1 = std::clamp(params_.osc1UniDetune + modSum(ModRoute::Dest::Osc1Unison), 0.0, 1.0);
            const double det2 = std::clamp(params_.osc2UniDetune + modSum(ModRoute::Dest::Osc2Unison), 0.0, 1.0);
            float l1 = 0, r1 = 0, l2 = 0, r2 = 0;
            stack(osc1_, gains1_, n1, pitch1, det1, width, wm1, warp1, l1, r1);
            stack(osc2_, gains2_, n2, pitch2, det2, width, wm2, warp2, l2, r2);
            l = l1 * g1 + l2 * g2;
            r = r1 * g1 + r2 * g2;
            stereo = width > 0.0;
        }

        // 0.12.0 DC blocker on the oscillator mix (see dcOn_ above).
        if (dcOn_) { l = dcL_.process(l); r = dcR_.process(r); }

        // 0.10.0 sub oscillator (follows oscillator A's pitch) and noise, mono, pre-filter.
        if (usesSub_) {
            const float lv = (float)std::clamp(params_.subLevel + modSum(ModRoute::Dest::SubLevel), 0.0, 1.0);
            sub_.setFrequency(baseFreq_ * (params_.subOctave >= 2 ? 0.25 : 0.5));
            sub_.setDetuneSemitones(pitch1);
            const float sv = sub_.process() * lv * 0.8f;
            l += sv; r += sv;
        }
        if (usesNoise_) {
            const float lv = (float)std::clamp(params_.noiseLevel + modSum(ModRoute::Dest::NoiseLevel), 0.0, 1.0);
            const float nv = noise_.process() * lv;
            l += nv; r += nv;
        }
        const float preL = l, preR = r;

        // Cutoff modulation is exponential: amount 1.0 = one octave up at full source.
        double cutoffMod = modSum(ModRoute::Dest::FilterCutoff);
        double cutoff = params_.filterCutoff * std::pow(2.0, cutoffMod);
        double resonance = std::clamp(params_.filterReso + modSum(ModRoute::Dest::FilterResonance), 0.1, 18.0);
        filter_.set(cutoff, resonance);
        l = filter_.process(l);
        if (stereo) { filterR_.set(cutoff, resonance); r = filterR_.process(r); }
        else { r = l; filterR_.copyStateFrom(filter_); } // keep the right filter warm for a width change

        // 0.10.0 filter 2: after filter 1 (serial) or beside it on the dry mix (parallel).
        if (f2Type_ != 0) {
            const double c2 = params_.filter2Cutoff * std::pow(2.0, modSum(ModRoute::Dest::Filter2Cutoff));
            f2L_.set(c2, params_.filter2Reso);
            const bool par = params_.filterRouting == 1;
            const float inL = par ? preL : l;
            const float yL = f2L_.process(inL);
            float yR = yL;
            if (stereo) { f2R_.set(c2, params_.filter2Reso); yR = f2R_.process(par ? preR : r); }
            if (par) { l = 0.5f * (l + yL); r = 0.5f * (r + yR); }
            else { l = yL; r = yR; }
        }

        float amp = ampEnv_.process();
        ++age_;
        outL = l * amp * velocity_;
        outR = r * amp * velocity_;
    }

private:
    double sr_ = 44100.0;
    int note_ = -1;
    float velocity_ = 0.0f;
    double baseFreq_ = 440.0;
    uint64_t age_ = 0;
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
        gains.update(n, width, std::clamp(params_.uniBlend, 0.0, 1.0));
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
    // Oscillator settings that can leave a DC offset: bending or splitting the
    // phase of an asymmetric table, the PULSE shape, and user-drawn tables.
    // Per oscillator: the PULSE shape and user tables can always carry DC;
    // BEND+/BEND-/PWM only once their warp amount is above 0.
    static bool shapeProne(int shape) { return shape == 4 || shape == kCustomShape; }
    static bool warpProne(int mode) { return mode == 2 || mode == 3 || mode == 4; }
private:
    void applyCustom() {
        active1_ = params_.osc1Shape == kCustomShape; active2_ = params_.osc2Shape == kCustomShape;
        for (int i = 0; i < kMaxUnison; ++i) {
            osc1_[i].setCustom(active1_ ? (custom1_ ? custom1_ : fallback()) : nullptr);
            osc2_[i].setCustom(active2_ ? (custom2_ ? custom2_ : fallback()) : nullptr);
        }
    }
    static const CustomTable* fallback() { static const CustomTable t{TableFrames{}}; return &t; }

    void applyRates() {
        lfo1_.setRate(lfoHz(params_.lfo1Rate, params_.lfoSync[0], bpm_));
        lfo2_.setRate(lfoHz(params_.lfo2Rate, params_.lfoSync[1], bpm_));
        lfo3_.setRate(lfoHz(params_.lfo3Rate, params_.lfoSync[2], bpm_));
        lfo4_.setRate(lfoHz(params_.lfo4Rate, params_.lfoSync[3], bpm_));
    }

    Oscillator sub_;
    NoiseSource noise_;
    DCBlocker dcL_, dcR_;
    bool dcOn_ = false;
    Filter2 f2L_, f2R_;
    int f2Type_ = 0;
    bool usesSub_ = false, usesNoise_ = false;
    StackGains gains1_, gains2_;
    LFO lfo3_, lfo4_;
    Envelope env3_;
    bool usesLfo3_ = false, usesLfo4_ = false;
    const CustomTable* custom1_ = nullptr; const CustomTable* custom2_ = nullptr;
    bool active1_ = false, active2_ = false;
    double bpm_ = 120.0;
    Oscillator osc1_[kMaxUnison], osc2_[kMaxUnison];
    SVFilter filter_, filterR_;
    Envelope ampEnv_, modEnv_;
    LFO lfo1_, lfo2_;
    MSEG mseg1_;
    VoiceParams params_;
    std::vector<ModRoute> routes_;
};

} // namespace muew
