// ui_model.h - platform-neutral model behind the MUEW instrument UI: knob
// mappings onto real VoiceParams fields, display names, engine-accurate
// waveform previews, and preset-browser filtering over the factory bank.
// Kept free of AppKit so it is unit-tested on every platform.
#pragma once
#include "factory_bank.h"
#include "preset_bank.h"
#include "oscillator.h"
#include <algorithm>
#include <cmath>
#include <set>
#include <string>
#include <vector>

namespace muew {
namespace ui {

inline const char* shapeName(int s) {
    static const char* n[] = {"SINE", "TRI", "SAW", "SQUARE", "PULSE"};
    return (s >= 0 && s < 5) ? n[s] : "CUSTOM";
}
inline const char* warpName(int w) {
    static const char* n[] = {"CLEAN", "SYNC", "BEND+", "BEND-", "PWM", "QUANTIZE", "FOLD"};
    return (w >= 0 && w < 7) ? n[w] : "?";
}
inline const char* sourceName(ModRoute::Source s) {
    switch (s) {
    case ModRoute::Source::LFO1: return "LFO 1";
    case ModRoute::Source::ModEnv: return "ENV 2";
    case ModRoute::Source::Velocity: return "VELOCITY";
    case ModRoute::Source::LFO2: return "LFO 2";
    case ModRoute::Source::MSEG1: return "MSEG 1";
    case ModRoute::Source::Macro1: return "MACRO 1";
    case ModRoute::Source::Macro2: return "MACRO 2";
    case ModRoute::Source::Macro3: return "MACRO 3";
    case ModRoute::Source::Macro4: return "MACRO 4";
    }
    return "?";
}
inline const char* destName(ModRoute::Dest d) {
    switch (d) {
    case ModRoute::Dest::Osc1Pitch: return "PITCH A";
    case ModRoute::Dest::Osc2Pitch: return "PITCH B";
    case ModRoute::Dest::FilterCutoff: return "CUTOFF";
    case ModRoute::Dest::Osc2Level: return "LEVEL B";
    case ModRoute::Dest::FilterResonance: return "RESO";
    case ModRoute::Dest::Osc1Warp: return "WARP A";
    case ModRoute::Dest::Osc2Warp: return "WARP B";
    }
    return "?";
}
inline const char* filterModeName(int m) {
    static const char* n[] = {"LOW PASS", "BAND PASS", "HIGH PASS", "NOTCH", "PEAK"};
    return (m >= 0 && m < 5) ? n[m] : "?";
}

// Route amount normalized to -1..1 for drawing (units differ by dest).
inline double routeDisplayAmount(const ModRoute& r) {
    double scale = 1.0;
    switch (r.dest) {
    case ModRoute::Dest::Osc1Pitch: case ModRoute::Dest::Osc2Pitch: scale = 24.0; break;
    case ModRoute::Dest::FilterCutoff: scale = 5.0; break;
    case ModRoute::Dest::FilterResonance: scale = 8.0; break;
    default: scale = 1.0; break;
    }
    return std::clamp(r.amount / scale, -1.0, 1.0);
}

enum Knob { WarpA, Mix, WarpB, Detune, Cutoff, Resonance, Attack, Release, MsegTime,
            Macro1, Macro2, Macro3, Macro4, KnobCount };

// What the factory presets assign each macro to (see presets/*.muew).
inline const char* macroName(int i) {
    static const char* n[] = {"BRIGHT", "WARP", "RESO", "SPREAD"};
    return (i >= 0 && i < 4) ? n[i] : "";
}
inline bool isMacro(int k) { return k >= Macro1 && k <= Macro4; }

inline const char* knobLabel(int k) {
    static const char* n[] = {"WARP A", "MIX", "WARP B", "DETUNE", "CUTOFF", "RESONANCE", "ATTACK", "RELEASE", "MSEG TIME",
                              "BRIGHT", "WARP", "RESO", "SPREAD"};
    return (k >= 0 && k < KnobCount) ? n[k] : "";
}

// AU parameter ID behind a knob (muew::params): knobs 0-8 are params 0-8,
// macros are params 12-15.
inline int knobParam(int k) { return isMacro(k) ? 12 + (k - Macro1) : k; }

struct Range { double lo, hi; bool log; };
inline Range knobRange(int k) {
    switch (k) {
    case WarpA: case Mix: case WarpB: case Macro1: case Macro2: case Macro3: case Macro4: return {0.0, 1.0, false};
    case Detune: return {-24.0, 24.0, false};
    case Cutoff: return {40.0, 18000.0, true};
    case Resonance: return {0.1, 8.0, false};
    case Attack: return {0.001, 4.0, true};
    case Release: return {0.01, 5.0, true};
    case MsegTime: return {0.05, 8.0, true};
    }
    return {0.0, 1.0, false};
}

inline double to01(int k, double v) {
    Range r = knobRange(k);
    v = std::clamp(v, r.lo, r.hi);
    return r.log ? std::log(v / r.lo) / std::log(r.hi / r.lo) : (v - r.lo) / (r.hi - r.lo);
}
inline double from01(int k, double n) {
    Range r = knobRange(k);
    n = std::clamp(n, 0.0, 1.0);
    return r.log ? r.lo * std::pow(r.hi / r.lo, n) : r.lo + n * (r.hi - r.lo);
}

inline double& knobField(VoiceParams& p, int k) {
    switch (k) {
    case WarpA: return p.osc1Warp;
    case Mix: return p.osc2Level;
    case WarpB: return p.osc2Warp;
    case Detune: return p.osc2Detune;
    case Cutoff: return p.filterCutoff;
    case Resonance: return p.filterReso;
    case Attack: return p.ampA;
    case Release: return p.ampR;
    case Macro1: case Macro2: case Macro3: case Macro4: return p.macros[k - Macro1];
    default: return p.mseg1Seconds;
    }
}
inline double knobValue(const VoiceParams& p, int k) { return to01(k, knobField(const_cast<VoiceParams&>(p), k)); }
inline void setKnob(VoiceParams& p, int k, double n) { knobField(p, k) = from01(k, n); }

// Human-readable knob value for the hover/drag readout.
inline std::string knobReadout(const VoiceParams& p, int k) {
    char b[32];
    double v = knobField(const_cast<VoiceParams&>(p), k);
    switch (k) {
    case Cutoff: if (v >= 1000) snprintf(b, sizeof b, "%.1f kHz", v / 1000); else snprintf(b, sizeof b, "%.0f Hz", v); break;
    case Detune: snprintf(b, sizeof b, "%+.2f st", v); break;
    case Attack: case Release: case MsegTime:
        if (v < 1) snprintf(b, sizeof b, "%.0f ms", v * 1000); else snprintf(b, sizeof b, "%.2f s", v); break;
    case Resonance: snprintf(b, sizeof b, "Q %.2f", v); break;
    default: snprintf(b, sizeof b, "%.0f%%", v * 100); break;
    }
    return b;
}

// One cycle of the engine's own oscillator output (band-limited table,
// same warp algorithm) for the oscillator displays.
inline std::vector<float> waveform(const Wavetable& table, int shape, int warpMode, double warp, int n) {
    Oscillator osc;
    osc.setTable(&table);
    osc.setSampleRate(200.0 * n);
    osc.setFrequency(200.0);
    osc.setShape(shape);
    osc.setWarp(static_cast<Oscillator::WarpMode>(warpMode), warp);
    osc.reset();
    std::vector<float> out(n);
    for (int i = 0; i < n; ++i) out[i] = osc.process();
    return out;
}

// Everything the browser can show: the factory bank (indices 0..N-1, equal to
// AU preset numbers) followed by the user's saved presets.
struct Library {
    std::vector<Preset> user;
    std::vector<std::string> userFiles; // file names, parallel to `user`

    int count() const { return kFactoryPresetCount + (int)user.size(); }
    bool isUser(int i) const { return i >= kFactoryPresetCount && i < count(); }
    const Preset& at(int i) const {
        return isUser(i) ? user[(size_t)(i - kFactoryPresetCount)] : factoryPresets()[(size_t)std::clamp(i, 0, kFactoryPresetCount - 1)];
    }
    // Stable key for favorites. User presets are keyed by file name.
    std::string slug(int i) const {
        return isUser(i) ? "user/" + userFiles[(size_t)(i - kFactoryPresetCount)]
                         : std::string(kFactoryPresetTexts[std::clamp(i, 0, kFactoryPresetCount - 1)].slug);
    }
    // Factory number (AU preset number) or -1 for user presets.
    int factoryNumber(int i) const { return (i >= 0 && i < kFactoryPresetCount) ? i : -1; }
    int indexOfUserFile(const std::string& file) const {
        for (size_t i = 0; i < userFiles.size(); ++i) if (userFiles[i] == file) return kFactoryPresetCount + (int)i;
        return -1;
    }
    // Library index whose display name matches: factory first, then user.
    int indexOfName(const std::string& name) const {
        for (int i = 0; i < count(); ++i) if (at(i).info.name == name) return i;
        return -1;
    }
};

inline Library& library() { static Library lib; return lib; }

// Library indices visible under a browser filter. userOnly shows only saved
// presets; otherwise factory and user presets are listed together.
inline std::vector<int> visiblePresets(const PresetFilter& f, const std::set<std::string>& favorites,
                                       const Library& lib, bool userOnly = false) {
    std::vector<int> out;
    for (int i = userOnly ? kFactoryPresetCount : 0; i < lib.count(); ++i)
        if (presetMatches(lib.at(i), lib.slug(i), f, favorites)) out.push_back(i);
    return out;
}
inline std::vector<int> visiblePresets(const PresetFilter& f, const std::set<std::string>& favorites) {
    return visiblePresets(f, favorites, library());
}

inline int indexOfSlug(const std::string& slug) {
    for (int i = 0; i < kFactoryPresetCount; ++i)
        if (slug == kFactoryPresetTexts[i].slug) return i;
    return -1;
}

// Factory index of the preset whose display name matches (edited sounds keep
// their original name), or -1.
inline int indexOfName(const std::string& name) {
    const auto& bank = factoryPresets();
    for (int i = 0; i < (int)bank.size(); ++i)
        if (bank[i].info.name == name) return i;
    return -1;
}

} // namespace ui
} // namespace muew
