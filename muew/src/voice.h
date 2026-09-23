#pragma once
#include "oscillator.h"
#include "filter.h"
#include "envelope.h"
#include "lfo.h"
#include "mseg.h"
#include <cmath>

namespace muew {

inline double midiToFreq(int note) {
    return 440.0 * std::pow(2.0, (note - 69) / 12.0);
}

// Modulation routing: a source scales into a destination.
struct ModRoute {
    // Append only: values are stored in presets and host projects.
    enum class Source { LFO1 = 0, ModEnv = 1, Velocity = 2, LFO2 = 3, MSEG1 = 4,
                        Macro1 = 5, Macro2 = 6, Macro3 = 7, Macro4 = 8 } source;
    enum class Dest { Osc1Pitch = 0, Osc2Pitch = 1, FilterCutoff = 2, Osc2Level = 3, FilterResonance = 4, Osc1Warp = 5, Osc2Warp = 6,
                      Osc1Unison = 7, Osc2Unison = 8, UnisonWidth = 9, // 0.7.0: unison detune A/B, stereo width (0..1 units)
                      DistDrive = 10 } dest;                            // 0.7.0: FX-rack drive, macro sources only (global FX)
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
};

constexpr int kMaxUnison = 8;

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
        mseg1_.setSampleRate(sr);
    }

    void setParams(const VoiceParams& p, const std::vector<ModRoute>& routes) {
        params_ = p; routes_ = routes;
        for (int i = 0; i < kMaxUnison; ++i) { osc1_[i].setShape(p.osc1Shape); osc2_[i].setShape(p.osc2Shape); }
        filter_.setMode(static_cast<SVFilter::Mode>(p.filterMode));
        filterR_.setMode(static_cast<SVFilter::Mode>(p.filterMode));
        ampEnv_.set(p.ampA, p.ampD, p.ampS, p.ampR);
        modEnv_.set(p.modA, p.modD, p.modS, p.modR);
        lfo1_.setRate(p.lfo1Rate);
        lfo1_.setShape(static_cast<LFO::Shape>(p.lfo1Shape));
        lfo2_.setRate(p.lfo2Rate); lfo2_.setShape(static_cast<LFO::Shape>(p.lfo2Shape));
        mseg1_.setRate(p.mseg1Seconds); mseg1_.setPoints(p.mseg1Points);
        mseg1_.setLoop(1, (int)mseg1_.pointCount() - 1, p.mseg1Loop);
    }

    void noteOn(int note, float velocity) {
        note_ = note;
        velocity_ = velocity;
        baseFreq_ = midiToFreq(note);
        ampEnv_.noteOn();
        modEnv_.noteOn();
        lfo1_.reset(); lfo2_.reset(); mseg1_.reset();
        // Stacked voices start at spread phases so a unison stack sounds wide
        // from the first cycle instead of flanging out of one phase. Voice 0
        // starts at 0 like the single-oscillator path.
        for (int i = 0; i < kMaxUnison; ++i) {
            osc1_[i].setPhase(i == 0 ? 0.0 : std::fmod(i * 0.618034, 1.0));
            osc2_[i].setPhase(i == 0 ? 0.0 : std::fmod(i * 0.381966 + 0.25, 1.0));
        }
        age_ = 0;
    }

    void noteOff() { ampEnv_.noteOff(); modEnv_.noteOff(); mseg1_.release(); }

    bool isActive() const { return ampEnv_.isActive(); }
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

        const int n1 = std::clamp(params_.osc1Unison, 1, kMaxUnison);
        const int n2 = std::clamp(params_.osc2Unison, 1, kMaxUnison);
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

        // Cutoff modulation is exponential: amount 1.0 = one octave up at full source.
        double cutoffMod = modSum(ModRoute::Dest::FilterCutoff);
        double cutoff = params_.filterCutoff * std::pow(2.0, cutoffMod);
        double resonance = std::clamp(params_.filterReso + modSum(ModRoute::Dest::FilterResonance), 0.1, 18.0);
        filter_.set(cutoff, resonance);
        l = filter_.process(l);
        if (stereo) { filterR_.set(cutoff, resonance); r = filterR_.process(r); }
        else { r = l; filterR_.copyStateFrom(filter_); } // keep the right filter warm for a width change

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

    StackGains gains1_, gains2_;
    Oscillator osc1_[kMaxUnison], osc2_[kMaxUnison];
    SVFilter filter_, filterR_;
    Envelope ampEnv_, modEnv_;
    LFO lfo1_, lfo2_;
    MSEG mseg1_;
    VoiceParams params_;
    std::vector<ModRoute> routes_;
};

} // namespace muew
