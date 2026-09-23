// au_params.h - MUEW's automatable parameters. The Audio Unit publishes these
// to hosts (automation lanes, MIDI mapping). Each one maps onto a field of the
// current sound, so parameters, presets and saved state never disagree.
//
// IDs are serialized by hosts inside saved sets and automation: append only,
// never renumber. IDs 0-8 match ui::Knob so editor knobs map 1:1.
#pragma once
#include "preset.h"
#include "factory_bank.h"
#include <algorithm>
#include <cmath>

namespace muew {
namespace params {

enum ID {
    WarpA, OscMix, WarpB, Detune, Cutoff, Resonance, Attack, Release, MsegTime,
    ChorusMix, DelayMix, ReverbMix,
    Count
};

enum Unit { Percent, Hertz, Semitones, Seconds, Generic };

struct Def {
    const char* name;
    Unit unit;
    double lo, hi; // in parameter units (Percent: 0-100)
    bool log;      // displayed logarithmically
};

inline const Def& def(int id) {
    static const Def d[Count] = {
        {"Warp A", Percent, 0, 100, false},
        {"Osc Mix", Percent, 0, 100, false},
        {"Warp B", Percent, 0, 100, false},
        {"Osc B Detune", Semitones, -24, 24, false},
        {"Cutoff", Hertz, 40, 18000, true},
        {"Resonance", Generic, 0.1, 8, false},
        {"Attack", Seconds, 0.001, 4, true},
        {"Release", Seconds, 0.01, 5, true},
        {"MSEG Time", Seconds, 0.05, 8, true},
        {"Chorus Mix", Percent, 0, 100, false},
        {"Delay Mix", Percent, 0, 100, false},
        {"Reverb Mix", Percent, 0, 100, false},
    };
    return d[std::clamp(id, 0, Count - 1)];
}

inline bool valid(int id) { return id >= 0 && id < Count; }

inline double& field(Preset& p, int id) {
    switch (id) {
    case WarpA: return p.voice.osc1Warp;
    case OscMix: return p.voice.osc2Level;
    case WarpB: return p.voice.osc2Warp;
    case Detune: return p.voice.osc2Detune;
    case Cutoff: return p.voice.filterCutoff;
    case Resonance: return p.voice.filterReso;
    case Attack: return p.voice.ampA;
    case Release: return p.voice.ampR;
    case MsegTime: return p.voice.mseg1Seconds;
    case ChorusMix: return p.fx.chorus.mix;
    case DelayMix: return p.fx.delay.mix;
    default: return p.fx.reverb.mix;
    }
}

inline double clampValue(int id, double v) {
    const Def& d = def(id);
    if (!std::isfinite(v)) v = d.lo;
    return std::clamp(v, d.lo, d.hi);
}

// Parameter value (host units) of a sound.
inline double get(const Preset& p, int id) {
    double v = field(const_cast<Preset&>(p), id);
    return clampValue(id, def(id).unit == Percent ? v * 100.0 : v);
}

// Writes a host value into a sound, clamped to the parameter range.
inline void set(Preset& p, int id, double v) {
    v = clampValue(id, v);
    field(p, id) = def(id).unit == Percent ? v / 100.0 : v;
}

// Defaults are the power-on sound (factory preset 7, Warm Pad).
inline double defaultValue(int id) { return get(factoryPresets()[7], id); }

} // namespace params
} // namespace muew
