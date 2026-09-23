// au_params.h - MUEW's automatable parameters. The Audio Unit publishes these
// to hosts (automation lanes, MIDI mapping). Each one maps onto a field of the
// current sound, so parameters, presets and saved state never disagree.
//
// IDs are serialized by hosts inside saved sets and automation: append only,
// never renumber. IDs 0-8 match ui::Knob 0-8; ui::knobParam maps the macro
// knobs to 12-15 and the unison knobs to 16-18.
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
    Macro1, Macro2, Macro3, Macro4, // 0.6.0
    UnisonDetuneA, UnisonDetuneB, UnisonWidth, DistDrive, CompAmount, // 0.7.0
    WtPosA, WtPosB, // 0.9.0: user-table frame position
    SubLevel, NoiseLevel, NoiseTone, Filter2Cutoff, Filter2Reso, // 0.10.0
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
        {"Macro 1 Bright", Percent, 0, 100, false},
        {"Macro 2 Warp", Percent, 0, 100, false},
        {"Macro 3 Reso", Percent, 0, 100, false},
        {"Macro 4 Spread", Percent, 0, 100, false},
        {"Unison Detune A", Percent, 0, 100, false},
        {"Unison Detune B", Percent, 0, 100, false},
        {"Unison Width", Percent, 0, 100, false},
        {"Distortion Drive", Percent, 0, 100, false},
        {"Compressor", Percent, 0, 100, false},
        {"WT Position A", Percent, 0, 100, false},
        {"WT Position B", Percent, 0, 100, false},
        {"Sub Level", Percent, 0, 100, false},
        {"Noise Level", Percent, 0, 100, false},
        {"Noise Tone", Percent, 0, 100, false},
        {"Filter 2 Cutoff", Hertz, 40, 18000, true},
        {"Filter 2 Resonance", Generic, 0.1, 8, false},
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
    case Macro1: case Macro2: case Macro3: case Macro4: return p.voice.macros[id - Macro1];
    case UnisonDetuneA: return p.voice.osc1UniDetune;
    case UnisonDetuneB: return p.voice.osc2UniDetune;
    case UnisonWidth: return p.voice.uniWidth;
    case DistDrive: return p.fx.dist.drive;
    case CompAmount: return p.fx.comp.amount;
    case WtPosA: return p.voice.osc1WtPos;
    case WtPosB: return p.voice.osc2WtPos;
    case SubLevel: return p.voice.subLevel;
    case NoiseLevel: return p.voice.noiseLevel;
    case NoiseTone: return p.voice.noiseTone;
    case Filter2Cutoff: return p.voice.filter2Cutoff;
    case Filter2Reso: return p.voice.filter2Reso;
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
