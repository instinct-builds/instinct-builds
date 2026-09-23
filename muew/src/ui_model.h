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
#include <map>
#include <set>
#include <string>
#include <vector>

namespace muew {
namespace ui {

inline const char* shapeName(int s) {
    static const char* n[] = {"SINE", "TRI", "SAW", "SQUARE", "PULSE", "USER"};
    return (s >= 0 && s < 6) ? n[s] : "?";
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
    case ModRoute::Source::LFO3: return "LFO 3";
    case ModRoute::Source::LFO4: return "LFO 4";
    case ModRoute::Source::Env3: return "ENV 3";
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
    case ModRoute::Dest::Osc1Unison: return "UNISON A";
    case ModRoute::Dest::Osc2Unison: return "UNISON B";
    case ModRoute::Dest::UnisonWidth: return "WIDTH";
    case ModRoute::Dest::DistDrive: return "DRIVE";
    case ModRoute::Dest::Osc1WtPos: return "WT POS A";
    case ModRoute::Dest::Osc2WtPos: return "WT POS B";
    case ModRoute::Dest::SubLevel: return "SUB";
    case ModRoute::Dest::NoiseLevel: return "NOISE";
    case ModRoute::Dest::Filter2Cutoff: return "F2 CUTOFF";
    case ModRoute::Dest::FxDelayFeedback: return "DELAY FB";
    case ModRoute::Dest::FxReverbDecay: return "REV DECAY";
    case ModRoute::Dest::FxPhaserDepth: return "PH DEPTH";
    case ModRoute::Dest::FxFlangerDepth: return "FL DEPTH";
    case ModRoute::Dest::FxChorusDepth: return "CH DEPTH";
    }
    return "?";
}
inline const char* filter2TypeName(int t) {
    static const char* n[] = {"OFF", "LOW PASS", "BAND PASS", "HIGH PASS", "COMB", "FORMANT"};
    return (t >= 0 && t < 6) ? n[t] : "?";
}
inline const char* subShapeName(int s) {
    static const char* n[] = {"SINE", "TRI", "SQUARE"};
    return (s >= 0 && s < 3) ? n[s] : "?";
}
inline const char* filterModeName(int m) {
    static const char* n[] = {"LOW PASS", "BAND PASS", "HIGH PASS", "NOTCH", "PEAK"};
    return (m >= 0 && m < 5) ? n[m] : "?";
}

// Full-scale route amount per destination (units differ by dest): the
// matrix shows and edits amount / scale in -1..1.
inline double routeScale(ModRoute::Dest d) {
    switch (d) {
    case ModRoute::Dest::Osc1Pitch: case ModRoute::Dest::Osc2Pitch: return 24.0; // semitones
    case ModRoute::Dest::FilterCutoff: case ModRoute::Dest::Filter2Cutoff: return 5.0; // octaves
    case ModRoute::Dest::FilterResonance: return 8.0;                           // Q
    default: return 1.0;
    }
}
inline double routeDisplayAmount(const ModRoute& r) { return std::clamp(r.amount / routeScale(r.dest), -1.0, 1.0); }
inline void setRouteDisplayAmount(ModRoute& r, double n) { r.amount = std::clamp(n, -1.0, 1.0) * routeScale(r.dest); }
// The FX rack is shared by every voice, so FX destinations follow only the
// macro knobs (global sources); other sources show that instead of an amount.
inline bool isFxDest(ModRoute::Dest d) { return d == ModRoute::Dest::DistDrive || (int)d >= (int)ModRoute::Dest::FxDelayFeedback; }
inline bool isMacroSource(ModRoute::Source s) { return (int)s >= (int)ModRoute::Source::Macro1 && (int)s <= (int)ModRoute::Source::Macro4; }
inline std::string routeAmountReadout(const ModRoute& r) {
    char b[32];
    if (isFxDest(r.dest) && !isMacroSource(r.source)) return "MACROS ONLY";
    switch (r.dest) {
    case ModRoute::Dest::Osc1Pitch: case ModRoute::Dest::Osc2Pitch: snprintf(b, sizeof b, "%+.2f st", r.amount); break;
    case ModRoute::Dest::FilterCutoff: case ModRoute::Dest::Filter2Cutoff: snprintf(b, sizeof b, "%+.2f oct", r.amount); break;
    case ModRoute::Dest::FilterResonance: snprintf(b, sizeof b, "%+.2f Q", r.amount); break;
    default: snprintf(b, sizeof b, "%+.0f%%", r.amount * 100); break;
    }
    return b;
}

// Mod matrix editing (0.8.0). Sources in badge order and destinations in
// menu order; both are lists of the append-only enum values.
inline const std::vector<ModRoute::Source>& matrixSources() {
    using S = ModRoute::Source;
    static const std::vector<S> v{S::LFO1, S::LFO2, S::LFO3, S::LFO4, S::ModEnv, S::Env3, S::MSEG1, S::Velocity,
                                  S::Macro1, S::Macro2, S::Macro3, S::Macro4};
    return v;
}
inline const char* sourceBadge(ModRoute::Source s) {
    switch (s) {
    case ModRoute::Source::LFO1: return "LFO1";
    case ModRoute::Source::LFO2: return "LFO2";
    case ModRoute::Source::LFO3: return "LFO3";
    case ModRoute::Source::LFO4: return "LFO4";
    case ModRoute::Source::ModEnv: return "ENV2";
    case ModRoute::Source::Env3: return "ENV3";
    case ModRoute::Source::MSEG1: return "MSEG";
    case ModRoute::Source::Velocity: return "VEL";
    case ModRoute::Source::Macro1: return "M1";
    case ModRoute::Source::Macro2: return "M2";
    case ModRoute::Source::Macro3: return "M3";
    case ModRoute::Source::Macro4: return "M4";
    }
    return "?";
}
inline const std::vector<ModRoute::Dest>& matrixDests() {
    using D = ModRoute::Dest;
    static const std::vector<D> v{D::Osc1Pitch, D::Osc1Warp, D::Osc1Unison, D::Osc2Pitch, D::Osc2Warp, D::Osc2Unison,
                                  D::Osc2Level, D::UnisonWidth, D::FilterCutoff, D::FilterResonance, D::DistDrive,
                                  D::Osc1WtPos, D::Osc2WtPos, D::SubLevel, D::NoiseLevel, D::Filter2Cutoff,
                                  D::FxDelayFeedback, D::FxReverbDecay, D::FxPhaserDepth, D::FxFlangerDepth, D::FxChorusDepth};
    return v;
}
// A new route starts at a musical quarter of full scale.
inline double defaultRouteAmount(ModRoute::Dest d) { return 0.25 * routeScale(d); }
// Adds source -> dest. An existing identical route is reused (returns its
// slot); a full matrix returns -1.
inline int addRoute(std::vector<ModRoute>& routes, ModRoute::Source s, ModRoute::Dest d) {
    for (size_t i = 0; i < routes.size(); ++i) if (routes[i].source == s && routes[i].dest == d) return (int)i;
    if ((int)routes.size() >= kMaxRoutes) return -1;
    routes.push_back({s, d, defaultRouteAmount(d)});
    return (int)routes.size() - 1;
}
inline bool removeRoute(std::vector<ModRoute>& routes, int slot) {
    if (slot < 0 || slot >= (int)routes.size()) return false;
    routes.erase(routes.begin() + slot);
    return true;
}
// Changing a route's destination keeps its position on the -1..1 scale.
inline void setRouteDest(ModRoute& r, ModRoute::Dest d) { double n = routeDisplayAmount(r); r.dest = d; setRouteDisplayAmount(r, n); }
inline const char* syncName(int i) {
    static const char* n[kSyncCount] = {"FREE", "1/1", "1/2", "1/4", "1/8", "1/16", "1/4T", "1/8T", "1/4D", "2/1"};
    return (i >= 0 && i < kSyncCount) ? n[i] : "?";
}
inline const char* lfoShapeName(int s) {
    static const char* n[] = {"SINE", "TRIANGLE", "SAW", "SQUARE"};
    return (s >= 0 && s < 4) ? n[s] : "?";
}
// LFO n (0-3) fields.
inline double& lfoRate(VoiceParams& p, int n) { return n == 0 ? p.lfo1Rate : n == 1 ? p.lfo2Rate : n == 2 ? p.lfo3Rate : p.lfo4Rate; }
inline int& lfoShape(VoiceParams& p, int n) { return n == 0 ? p.lfo1Shape : n == 1 ? p.lfo2Shape : n == 2 ? p.lfo3Shape : p.lfo4Shape; }
inline std::string lfoRateReadout(const VoiceParams& p, int n) {
    int sy = p.lfoSync[std::clamp(n, 0, 3)];
    if (sy > 0) return syncName(sy);
    char b[24]; snprintf(b, sizeof b, "%.2f Hz", lfoRate(const_cast<VoiceParams&>(p), n)); return b;
}

enum Knob { WarpA, Mix, WarpB, Detune, Cutoff, Resonance, Attack, Release, MsegTime,
            Macro1, Macro2, Macro3, Macro4,
            UniDetuneA, UniDetuneB, Width, // 0.7.0
            F2Cutoff, F2Reso, Sub, Noise, NoiseTone, // 0.10.0 (FILTER 2 + SUB/NOISE page)
            KnobCount };

// What the factory presets assign each macro to (see presets/*.muew).
inline const char* macroName(int i) {
    static const char* n[] = {"BRIGHT", "WARP", "RESO", "SPREAD"};
    return (i >= 0 && i < 4) ? n[i] : "";
}
// Knobs shared by the two pages of the FILTER panel: -1 = always shown,
// 0 = FILTER 1 + AMP page, 1 = FILTER 2 + SUB/NOISE page (0.10.0).
inline int knobPage(int k) {
    switch (k) {
    case Cutoff: case Resonance: case Attack: case Release: case MsegTime: return 0;
    case F2Cutoff: case F2Reso: case Sub: case Noise: case NoiseTone: return 1;
    default: return -1;
    }
}
inline bool isMacro(int k) { return k >= Macro1 && k <= Macro4; }
inline bool isUnison(int k) { return k >= UniDetuneA && k <= Width; }
// Destination a knob modulates when a source is dropped on it (-1: none).
inline int knobDest(int k) {
    switch (k) {
    case WarpA: return (int)ModRoute::Dest::Osc1Warp;
    case Mix: return (int)ModRoute::Dest::Osc2Level;
    case WarpB: return (int)ModRoute::Dest::Osc2Warp;
    case Detune: return (int)ModRoute::Dest::Osc2Pitch;
    case Cutoff: return (int)ModRoute::Dest::FilterCutoff;
    case Resonance: return (int)ModRoute::Dest::FilterResonance;
    case UniDetuneA: return (int)ModRoute::Dest::Osc1Unison;
    case UniDetuneB: return (int)ModRoute::Dest::Osc2Unison;
    case Width: return (int)ModRoute::Dest::UnisonWidth;
    case F2Cutoff: return (int)ModRoute::Dest::Filter2Cutoff;
    case Sub: return (int)ModRoute::Dest::SubLevel;
    case Noise: return (int)ModRoute::Dest::NoiseLevel;
    default: return -1;
    }
}

inline const char* knobLabel(int k) {
    static const char* n[] = {"WARP A", "MIX", "WARP B", "DETUNE", "CUTOFF", "RESONANCE", "ATTACK", "RELEASE", "MSEG TIME",
                              "BRIGHT", "WARP", "RESO", "SPREAD", "UNISON", "UNISON", "WIDTH",
                              "CUTOFF", "RESONANCE", "SUB", "NOISE", "TONE"};
    return (k >= 0 && k < KnobCount) ? n[k] : "";
}

// AU parameter ID behind a knob (muew::params): knobs 0-8 are params 0-8,
// macros are params 12-15, unison detune A/B and width are 16-18.
inline int knobParam(int k) {
    if (isMacro(k)) return 12 + (k - Macro1);
    if (isUnison(k)) return 16 + (k - UniDetuneA);
    if (k >= F2Cutoff) { static const int m[] = {26, 27, 23, 24, 25}; return m[std::min(k - F2Cutoff, 4)]; }
    return k;
}

struct Range { double lo, hi; bool log; };
inline Range knobRange(int k) {
    switch (k) {
    case WarpA: case Mix: case WarpB: case Macro1: case Macro2: case Macro3: case Macro4:
    case UniDetuneA: case UniDetuneB: case Width: case Sub: case Noise: case NoiseTone: return {0.0, 1.0, false};
    case F2Cutoff: return {40.0, 18000.0, true};
    case F2Reso: return {0.1, 8.0, false};
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
    case UniDetuneA: return p.osc1UniDetune;
    case UniDetuneB: return p.osc2UniDetune;
    case Width: return p.uniWidth;
    case F2Cutoff: return p.filter2Cutoff;
    case F2Reso: return p.filter2Reso;
    case Sub: return p.subLevel;
    case Noise: return p.noiseLevel;
    case NoiseTone: return p.noiseTone;
    default: return p.mseg1Seconds;
    }
}
inline double knobValue(const VoiceParams& p, int k) { return to01(k, knobField(const_cast<VoiceParams&>(p), k)); }
inline void setKnob(VoiceParams& p, int k, double n) { knobField(p, k) = from01(k, n); }

// Summed modulation depth on a knob's destination (-1..1) for its mod ring.
inline double knobModDepth(const std::vector<ModRoute>& routes, int k) {
    int d = knobDest(k);
    if (d < 0) return 0.0;
    double sum = 0.0;
    for (const auto& r : routes) if ((int)r.dest == d) sum += routeDisplayAmount(r);
    return std::clamp(sum, -1.0, 1.0);
}
// Human-readable knob value for the hover/drag readout.
inline std::string knobReadout(const VoiceParams& p, int k) {
    char b[32];
    double v = knobField(const_cast<VoiceParams&>(p), k);
    switch (k) {
    case Cutoff: case F2Cutoff: if (v >= 1000) snprintf(b, sizeof b, "%.1f kHz", v / 1000); else snprintf(b, sizeof b, "%.0f Hz", v); break;
    case Detune: snprintf(b, sizeof b, "%+.2f st", v); break;
    case Attack: case Release: case MsegTime:
        if (v < 1) snprintf(b, sizeof b, "%.0f ms", v * 1000); else snprintf(b, sizeof b, "%.2f s", v); break;
    case Resonance: case F2Reso: snprintf(b, sizeof b, "Q %.2f", v); break;
    case UniDetuneA: case UniDetuneB: snprintf(b, sizeof b, "\u00b1%.0f ct", v * 100); break;
    default: snprintf(b, sizeof b, "%.0f%%", v * 100); break;
    }
    return b;
}

// Unison voice count of an oscillator (0 = A, 1 = B) and the readout shown
// under its waveform ("1 VOICE", "7 VOICES").
inline int unisonVoices(const VoiceParams& p, int osc) { return std::clamp(osc == 0 ? p.osc1Unison : p.osc2Unison, 1, kMaxUnison); }
inline void setUnisonVoices(VoiceParams& p, int osc, int n) { (osc == 0 ? p.osc1Unison : p.osc2Unison) = std::clamp(n, 1, kMaxUnison); }
inline std::string unisonReadout(const VoiceParams& p, int osc) {
    int n = unisonVoices(p, osc);
    return std::to_string(n) + (n == 1 ? " VOICE" : " VOICES");
}
// Detune offsets (semitones) of each stacked voice, for the unison display.
inline std::vector<double> unisonOffsets(const VoiceParams& p, int osc) {
    int n = unisonVoices(p, osc);
    double det = osc == 0 ? p.osc1UniDetune : p.osc2UniDetune;
    std::vector<double> o;
    for (int i = 0; i < n; ++i) o.push_back(n == 1 ? 0.0 : (2.0 * i / (n - 1) - 1.0) * det);
    return o;
}
inline const char* distModeName(int m) {
    static const char* n[] = {"SOFT CLIP", "FOLD", "BITCRUSH"};
    return (m >= 0 && m < 3) ? n[m] : "?";
}

// ---- 0.14.0 FX detail editor ----
// Every control of one rack unit (FxUnit id), in panel row order. Choice
// rows step through a list; the rest are sliders over lo..hi.
enum FxFmt { FmtPercent, FmtHz, FmtMs, FmtSec, FmtDb, FmtRatio, FmtChoice };
struct FxControl {
    const char* label;
    FxFmt fmt;
    double lo, hi;
    bool log;
    int dest; // ModRoute::Dest this row can be modulated through, or -1
};
inline const std::vector<FxControl>& fxControls(int unit) {
    using D = ModRoute::Dest;
    static const std::vector<FxControl> c[kFxUnits] = {
        {{"MODE", FmtChoice, 0, 2, false, -1}, {"DRIVE", FmtPercent, 0, 1, false, (int)D::DistDrive}, {"MIX", FmtPercent, 0, 1, false, -1}},
        {{"RATE", FmtHz, 0.05, 5, true, -1}, {"DEPTH", FmtMs, 0, 20, false, (int)D::FxChorusDepth}, {"DELAY", FmtMs, 5, 30, false, -1},
         {"MIX", FmtPercent, 0, 1, false, -1}},
        {{"TIME L", FmtSec, 0.01, 1.99, true, -1}, {"SYNC L", FmtChoice, 0, kSyncCount - 1, false, -1},
         {"TIME R", FmtSec, 0.01, 1.99, true, -1}, {"SYNC R", FmtChoice, 0, kSyncCount - 1, false, -1},
         {"FEEDBACK", FmtPercent, 0, 0.95, false, (int)D::FxDelayFeedback}, {"MIX", FmtPercent, 0, 1, false, -1}},
        {{"AMOUNT", FmtPercent, 0, 1, false, -1}},
        {{"DECAY", FmtPercent, 0, 0.97, false, (int)D::FxReverbDecay}, {"DAMPING", FmtPercent, 0, 1, false, -1},
         {"MIX", FmtPercent, 0, 1, false, -1}},
        {{"LOW 180 Hz", FmtDb, -12, 12, false, -1}, {"MID 1.2 kHz", FmtDb, -12, 12, false, -1}, {"HIGH 6 kHz", FmtDb, -12, 12, false, -1}},
        {{"RATE", FmtHz, 0.02, 8, true, -1}, {"DEPTH", FmtPercent, 0, 1, false, (int)D::FxPhaserDepth},
         {"FEEDBACK", FmtPercent, 0, 0.9, false, -1}, {"MIX", FmtPercent, 0, 1, false, -1}},
        {{"RATE", FmtHz, 0.02, 8, true, -1}, {"DEPTH", FmtPercent, 0, 1, false, (int)D::FxFlangerDepth},
         {"FEEDBACK", FmtPercent, 0, 0.9, false, -1}, {"MIX", FmtPercent, 0, 1, false, -1}},
    };
    static const std::vector<FxControl> none;
    return (unit >= 0 && unit < kFxUnits) ? c[unit] : none;
}
inline int fxControlCount(int unit) { return (int)fxControls(unit).size(); }
inline const char* fxUnitTitle(int unit) {
    static const char* n[kFxUnits] = {"DISTORTION", "CHORUS", "DELAY", "COMPRESSOR", "REVERB", "EQ", "PHASER", "FLANGER"};
    return (unit >= 0 && unit < kFxUnits) ? n[unit] : "";
}
// Raw value of a control (choice rows: the index as a double).
inline double fxGet(const FXParams& f, int unit, int i) {
    switch (unit) {
    case FxDist: return i == 0 ? f.dist.mode : i == 1 ? f.dist.drive : f.dist.mix;
    case FxChorus: return i == 0 ? f.chorus.rateHz : i == 1 ? f.chorus.depthMs : i == 2 ? f.chorus.baseMs : f.chorus.mix;
    case FxDelay: return i == 0 ? f.delay.timeLSec : i == 1 ? f.delay.syncL : i == 2 ? f.delay.timeRSec : i == 3 ? f.delay.syncR
                       : i == 4 ? f.delay.feedback : f.delay.mix;
    case FxComp: return f.comp.amount;
    case FxReverb: return i == 0 ? f.reverb.decay : i == 1 ? f.reverb.damping : f.reverb.mix;
    case FxEQ: return i == 0 ? f.eq.lowDb : i == 1 ? f.eq.midDb : f.eq.highDb;
    case FxPhaser: return i == 0 ? f.phaser.rateHz : i == 1 ? f.phaser.depth : i == 2 ? f.phaser.feedback : f.phaser.mix;
    case FxFlanger: return i == 0 ? f.flanger.rateHz : i == 1 ? f.flanger.depth : i == 2 ? f.flanger.feedback : f.flanger.mix;
    }
    return 0.0;
}
// Writes a control, clamped to its range (choice rows round to an index).
inline void fxSet(FXParams& f, int unit, int i, double v) {
    const auto& cs = fxControls(unit);
    if (i < 0 || i >= (int)cs.size() || !std::isfinite(v)) return;
    const FxControl& c = cs[i];
    v = std::clamp(v, c.lo, c.hi);
    const int k = (int)std::lround(v);
    switch (unit) {
    case FxDist: if (i == 0) f.dist.mode = k; else if (i == 1) f.dist.drive = v; else f.dist.mix = v; break;
    case FxChorus: (i == 0 ? f.chorus.rateHz : i == 1 ? f.chorus.depthMs : i == 2 ? f.chorus.baseMs : f.chorus.mix) = v; break;
    case FxDelay:
        if (i == 1) f.delay.syncL = k; else if (i == 3) f.delay.syncR = k;
        else (i == 0 ? f.delay.timeLSec : i == 2 ? f.delay.timeRSec : i == 4 ? f.delay.feedback : f.delay.mix) = v;
        break;
    case FxComp: f.comp.amount = v; break;
    case FxReverb: (i == 0 ? f.reverb.decay : i == 1 ? f.reverb.damping : f.reverb.mix) = v; break;
    case FxEQ: (i == 0 ? f.eq.lowDb : i == 1 ? f.eq.midDb : f.eq.highDb) = v; break;
    case FxPhaser: (i == 0 ? f.phaser.rateHz : i == 1 ? f.phaser.depth : i == 2 ? f.phaser.feedback : f.phaser.mix) = v; break;
    case FxFlanger: (i == 0 ? f.flanger.rateHz : i == 1 ? f.flanger.depth : i == 2 ? f.flanger.feedback : f.flanger.mix) = v; break;
    }
}
// Slider position 0..1 <-> value (log rows sweep geometrically).
inline double fxNorm(const FxControl& c, double v) {
    v = std::clamp(v, c.lo, c.hi);
    if (c.hi <= c.lo) return 0.0;
    return c.log ? std::log(v / c.lo) / std::log(c.hi / c.lo) : (v - c.lo) / (c.hi - c.lo);
}
inline double fxFromNorm(const FxControl& c, double n) {
    n = std::clamp(n, 0.0, 1.0);
    return c.log ? c.lo * std::pow(c.hi / c.lo, n) : c.lo + n * (c.hi - c.lo);
}
// A delay side follows the host tempo while its SYNC row is not FREE.
inline bool fxRowInactive(const FXParams& f, int unit, int i) {
    return unit == FxDelay && ((i == 0 && f.delay.syncL > 0) || (i == 2 && f.delay.syncR > 0));
}
inline std::string fxValueText(const FXParams& f, int unit, int i) {
    const auto& cs = fxControls(unit);
    if (i < 0 || i >= (int)cs.size()) return "";
    const double v = fxGet(f, unit, i);
    char b[40];
    switch (cs[i].fmt) {
    case FmtChoice:
        if (unit == FxDist) return distModeName((int)v);
        return syncName((int)v);
    case FmtPercent: snprintf(b, sizeof b, "%.0f%%", v * 100); break;
    case FmtHz: snprintf(b, sizeof b, v < 1 ? "%.2f Hz" : "%.1f Hz", v); break;
    case FmtMs: snprintf(b, sizeof b, "%.1f ms", v); break;
    case FmtSec:
        if (fxRowInactive(f, unit, i)) return "TEMPO";
        snprintf(b, sizeof b, "%.0f ms", v * 1000); break;
    case FmtDb: snprintf(b, sizeof b, "%+.1f dB", v); break;
    case FmtRatio: snprintf(b, sizeof b, "%.1f:1", v); break;
    }
    return b;
}
// Default of a control, for double-click reset (a fresh unit's value).
inline double fxDefault(int unit, int i) { return fxGet(FXParams{}, unit, i); }
// Sum of macro route amounts into a destination (what the detail row shows).
inline double fxRouteSum(const std::vector<ModRoute>& routes, int dest, int* count = nullptr) {
    double s = 0; int n = 0;
    for (const auto& r : routes) if ((int)r.dest == dest) { s += r.amount; ++n; }
    if (count) *count = n;
    return s;
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

// 0.9.0: one cycle of a user wavetable at frame position pos (0..1), with
// the same warp the engine applies, for the oscillator displays.
inline std::vector<float> waveformUser(const TableFrames& frames, double pos, int warpMode, double warp, int n) {
    CustomTable ct(frames);
    Oscillator osc;
    osc.setCustom(&ct);
    osc.setSampleRate(200.0 * n);
    osc.setFrequency(200.0);
    osc.setShape(kCustomShape);
    osc.setWtPos(pos);
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

// 0.11.0 banks. User presets saved in MUEW carry author "User"; any other
// file in the user folder (dropped in, or brought in with Import) is Imported.
// UserFolder (the compact browser's User chip) is User + Imported.
enum Bank { BankFactory = 0, BankUser = 1, BankImported = 2, BankUserFolder = 3 };
inline int bankOf(const Library& lib, int i) {
    if (!lib.isUser(i)) return BankFactory;
    return lib.at(i).info.author == "User" ? BankUser : BankImported;
}
inline bool inBank(const Library& lib, int i, int bank) {
    if (bank < 0) return true;
    int b = bankOf(lib, i);
    return bank == BankUserFolder ? b != BankFactory : b == bank;
}
inline const char* bankName(int b) {
    switch (b) {
    case BankFactory: return "Factory";
    case BankUser: return "User";
    case BankImported: return "Imported";
    case BankUserFolder: return "User folder";
    default: return "All";
    }
}

// Browser sort orders. Bank order is the AU preset order (factory numbers,
// then the user folder by name). Rating sorts best first; ties keep bank order.
enum SortMode { SortBank = 0, SortName, SortCategory, SortRating, SortModeCount };
inline const char* sortName(int m) {
    static const char* n[] = {"BANK", "NAME", "TYPE", "RATING"};
    return (m >= 0 && m < SortModeCount) ? n[m] : "?";
}
using Ratings = std::map<std::string, int>; // slug -> 1..5 stars (absent = unrated)
inline int ratingOf(const Ratings& r, const std::string& slug) {
    auto it = r.find(slug);
    return it == r.end() ? 0 : std::clamp(it->second, 0, 5);
}
// Clicking the star that is already set clears the rating.
inline void setRating(Ratings& r, const std::string& slug, int stars) {
    stars = std::clamp(stars, 0, 5);
    if (stars == 0 || ratingOf(r, slug) == stars) r.erase(slug); else r[slug] = stars;
}
inline void sortPresets(std::vector<int>& v, int mode, const Library& lib, const Ratings& ratings) {
    auto name = [&](int i) { return muewLower(lib.at(i).info.name); };
    switch (mode) {
    case SortName:
        std::stable_sort(v.begin(), v.end(), [&](int a, int b) { return name(a) < name(b); });
        break;
    case SortCategory: {
        auto rank = [&](int i) {
            const auto& c = factoryCategories();
            auto it = std::find(c.begin(), c.end(), lib.at(i).info.category);
            return (int)(it - c.begin());
        };
        std::stable_sort(v.begin(), v.end(), [&](int a, int b) {
            int x = rank(a), y = rank(b);
            return x != y ? x < y : name(a) < name(b);
        });
        break;
    }
    case SortRating:
        std::stable_sort(v.begin(), v.end(), [&](int a, int b) { return ratingOf(ratings, lib.slug(a)) > ratingOf(ratings, lib.slug(b)); });
        break;
    default: std::sort(v.begin(), v.end()); break;
    }
}

// Library indices visible under a browser filter, in bank order. userOnly
// (pre-0.11 callers) is the same as filter bank BankUserFolder.
inline std::vector<int> visiblePresets(const PresetFilter& f, const std::set<std::string>& favorites,
                                       const Library& lib, bool userOnly = false) {
    std::vector<int> out;
    int bank = userOnly ? (int)BankUserFolder : f.bank;
    for (int i = 0; i < lib.count(); ++i)
        if (inBank(lib, i, bank) && presetMatches(lib.at(i), lib.slug(i), f, favorites)) out.push_back(i);
    return out;
}
inline std::vector<int> visiblePresets(const PresetFilter& f, const std::set<std::string>& favorites,
                                       const Library& lib, const Ratings& ratings, int sort) {
    std::vector<int> out = visiblePresets(f, favorites, lib);
    sortPresets(out, sort, lib, ratings);
    return out;
}
// How many presets a sidebar row would show if picked (the other filters kept).
inline int countWith(PresetFilter f, const std::set<std::string>& favorites, const Library& lib) {
    return (int)visiblePresets(f, favorites, lib).size();
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
