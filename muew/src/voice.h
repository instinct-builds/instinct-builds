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
    enum class Dest { Osc1Pitch = 0, Osc2Pitch = 1, FilterCutoff = 2, Osc2Level = 3, FilterResonance = 4, Osc1Warp = 5, Osc2Warp = 6 } dest;
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
};

class Voice {
public:
    void init(double sr, const Wavetable* table) {
        sr_ = sr;
        osc1_.setSampleRate(sr); osc1_.setTable(table);
        osc2_.setSampleRate(sr); osc2_.setTable(table);
        filter_.setSampleRate(sr);
        ampEnv_.setSampleRate(sr);
        modEnv_.setSampleRate(sr);
        lfo1_.setSampleRate(sr); lfo2_.setSampleRate(sr);
        mseg1_.setSampleRate(sr);
    }

    void setParams(const VoiceParams& p, const std::vector<ModRoute>& routes) {
        params_ = p; routes_ = routes;
        osc1_.setShape(p.osc1Shape);
        osc2_.setShape(p.osc2Shape);
        filter_.setMode(static_cast<SVFilter::Mode>(p.filterMode));
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
        osc1_.reset();
        osc2_.reset();
        age_ = 0;
    }

    void noteOff() { ampEnv_.noteOff(); modEnv_.noteOff(); mseg1_.release(); }

    bool isActive() const { return ampEnv_.isActive(); }
    int note() const { return note_; }
    uint64_t age() const { return age_; }

    inline float process() {
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

        osc1_.setFrequency(baseFreq_);
        osc1_.setDetuneSemitones(modSum(ModRoute::Dest::Osc1Pitch));
        osc1_.setWarp(static_cast<Oscillator::WarpMode>(params_.osc1WarpMode),
                      std::clamp(params_.osc1Warp + modSum(ModRoute::Dest::Osc1Warp), 0.0, 1.0));
        osc2_.setFrequency(baseFreq_);
        osc2_.setDetuneSemitones(params_.osc2Detune + modSum(ModRoute::Dest::Osc2Pitch));
        osc2_.setWarp(static_cast<Oscillator::WarpMode>(params_.osc2WarpMode),
                      std::clamp(params_.osc2Warp + modSum(ModRoute::Dest::Osc2Warp), 0.0, 1.0));

        float osc2Level = static_cast<float>(
            std::clamp(params_.osc2Level + modSum(ModRoute::Dest::Osc2Level), 0.0, 1.0));
        float sig = osc1_.process() * (1.0f - osc2Level * 0.5f)
                  + osc2_.process() * osc2Level;

        // Cutoff modulation is exponential: amount 1.0 = one octave up at full source.
        double cutoffMod = modSum(ModRoute::Dest::FilterCutoff);
        double cutoff = params_.filterCutoff * std::pow(2.0, cutoffMod);
        double resonance = std::clamp(params_.filterReso + modSum(ModRoute::Dest::FilterResonance), 0.1, 18.0);
        filter_.set(cutoff, resonance);
        sig = filter_.process(sig);

        float amp = ampEnv_.process();
        ++age_;
        return sig * amp * velocity_;
    }

private:
    double sr_ = 44100.0;
    int note_ = -1;
    float velocity_ = 0.0f;
    double baseFreq_ = 440.0;
    uint64_t age_ = 0;
    Oscillator osc1_, osc2_;
    SVFilter filter_;
    Envelope ampEnv_, modEnv_;
    LFO lfo1_, lfo2_;
    MSEG mseg1_;
    VoiceParams params_;
    std::vector<ModRoute> routes_;
};

} // namespace muew
