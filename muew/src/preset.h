#pragma once
#include "synth.h"
#include "fx.h"
#include "table_recipe.h"
#include <algorithm>
#include <cstdio>
#include <cstring>
#include <string>
#include <iomanip>
#include <sstream>
#include <vector>

namespace muew {

// Browser metadata carried inside a preset. Tags are single words
// (hyphens allowed) so they serialize on one space-free line.
struct PresetInfo {
    std::string name;
    std::string category;
    std::string author;
    std::vector<std::string> tags;
    std::string description; // 0.11.0: one line of browser text (optional)

    bool operator==(const PresetInfo& o) const {
        return name == o.name && category == o.category && author == o.author && tags == o.tags
            && description == o.description;
    }
};

// Portable preset: metadata, voice params, mod routes, and FX settings as
// flat key/value lines. No external format library; round-trips exactly.
//
// Format history:
//   muew-preset 1  voice core, LFO1, routes, FX (0.1.x)
//   muew-preset 2  adds metadata, LFO2, oscillator warp, MSEG points (0.3.0)
//                  0.6.0 adds an optional `macros` line; 0.7.0 adds optional
//                  `unison`, `dist`, `eq` and `comp` lines. Optional lines are
//                  written only when they differ from the defaults, so older
//                  files round-trip byte-identical and older builds skip them.
//                  0.8.0 adds optional `lfo34`, `sync` and `env3` lines.
//                  0.10.0 adds optional `sub`, `noise` and `filter2` lines.
//                  0.11.0 adds an optional `desc` line (browser text).
//                  0.13.0 adds optional `phaser`, `flanger` and `fxorder` lines.
//                  0.14.0 adds an optional `delaysync` line.
//                  0.15.0 adds an optional `fxlfo` line (rack LFOs).
//                  0.27.0 adds optional `hyper <en> <rate> <detune> <dim> <mix>` and
//                  `filterfx <en> <mode> <cutoff> <reso> <drive> <rate> <sync> <depth> <mix>`
//                  lines; an older 8-unit `fxorder` line gets the new units appended.
//                  0.28.0 adds optional `reverbx <mode> <predelay ms> <size> <width> <lowcut Hz>`
//                  and `compx <mode> <upward> <speed> <low dB> <mid dB> <high dB> <mix>` lines.
//                  0.29.0 adds an optional `distx <quality>` line and an optional 8th compx field
//                  (AUTO GAIN 0/1, written only when on).
//                  0.30.0 adds an optional `oscq <quality>` line (global QUALITY, written only when HQ).
//                  0.17.0 adds optional `msegcurve`, `msegx` and `mseg2` lines.
//                  0.18.0 adds optional `lfox <i> <custom> <phase> <delay> <rise> <free>`
//                  and `lfopts <i> <n> (<t> <v> <c>)*` lines (drawn LFO shapes).
//                  0.25.0 adds optional `arp <on> <mode> <octaves> <rate> <gate> <swing> <latch>`.
//                  0.26.0 adds optional `arpx <clocksync> <pattern on> <length> (<velocity> <kind>)x16`.
//                  0.49.0 adds optional `arpo <octave shift>x16` (-1..+1); prior lines unchanged.
//                  0.50.0 adds optional `arpc <live> <chance>x16` (100/75/50/25).
//                  0.51.0 adds optional `noisex <character> <color>`; noise stays unchanged.
//                  0.52.0 appends NOISE COLOR as modulation destination 32 using the existing route line.
//                  0.53.0 adds optional `noisew <width>`; zero keeps the legacy mono stream.
//                  0.24.0 adds optional `perf <bendRange>`; route sources 15-18.
//                  0.23.0 adds optional `voice <mode> <polyVoices> <glideTime> <glideLegato> <uniPhase>`; route dest 27.
//                  0.32.0 adds optional `wtgen1/2 <recipe>` and `wtspec1/2 <formant> <stretch> <tilt> <oddeven>` (see table_recipe.h).
//                  0.22.0 adds optional `filterr <f1mix> <f2mix> <balance> <f2morph>`; filter2 types 6-8.
//                  0.21.0 adds optional `filterx <drive> <keytrack> <morph>`; filterMode 5-8.
//                  0.19.0 adds optional `warpx <modeA> <amtA> <modeB> <amtB>` (second
//                  warp slots) and `remap <osc> <n> (<t> <v> <c>)*` lines.
//                  0.16.0 adds optional `curve <c>` / `aux <source>` suffixes
//                  on `route` lines (older builds read the first three fields).
//                  0.9.0 adds optional `wtpos`, `wt1` and `wt2` lines (user
//                  wavetables: frame count, then 256 samples per frame).
// Version 1 text still parses; fields it lacks keep their VoiceParams
// defaults, which match how 0.1.x/0.2.0 rendered those presets.
struct Preset {
    PresetInfo info;
    VoiceParams voice;
    std::vector<ModRoute> routes;
    FXParams fx;
    // 0.9.0: user wavetables for oscillators A/B (empty = none). Played when
    // that oscillator's shape is kCustomShape.
    TableFrames tables[2];
    // 0.32.0: a table built from a `wtgen` recipe remembers it, so an unedited
    // table saves as its recipe line again (compact, byte-identical round trip).
    std::string tableRecipe[2], tableSpec[2];
    TableFrames recipeTable[2];
    int version = 2; // format version this preset was parsed from

    static constexpr const char* kMagicV1 = "muew-preset 1";
    static constexpr const char* kMagic = "muew-preset 2";
    static constexpr const char* kMagicPrefix = "muew-preset ";

    std::string serialize() const {
        std::ostringstream o;
        o << kMagic << "\n";
        o << "name " << info.name << "\n";
        o << "category " << info.category << "\n";
        o << "author " << info.author << "\n";
        o << "tags";
        for (const auto& t : info.tags) o << " " << t;
        o << "\n";
        if (!info.description.empty()) o << "desc " << oneLine(info.description) << "\n";
        writeCore(o);
        o << "lfo2 " << voice.lfo2Rate << " " << voice.lfo2Shape << "\n";
        o << "warp1 " << voice.osc1WarpMode << " " << voice.osc1Warp << "\n";
        o << "warp2 " << voice.osc2WarpMode << " " << voice.osc2Warp << "\n";
        o << "mseg " << voice.mseg1Seconds << " " << (voice.mseg1Loop ? 1 : 0) << " "
          << voice.mseg1Points.size();
        for (const auto& p : voice.mseg1Points) o << " " << p.time << " " << p.value;
        o << "\n";
        writeMsegExtras(o);
        // Only when set, so factory files (all macros at 0) round-trip unchanged.
        if (voice.macros[0] != 0 || voice.macros[1] != 0 || voice.macros[2] != 0 || voice.macros[3] != 0)
            o << "macros " << voice.macros[0] << " " << voice.macros[1] << " " << voice.macros[2] << " " << voice.macros[3] << "\n";
        if (hasUnison())
            o << "unison " << voice.osc1Unison << " " << voice.osc2Unison << " " << voice.osc1UniDetune << " "
              << voice.osc2UniDetune << " " << voice.uniWidth << " " << voice.uniBlend << "\n";
        {
            const VoiceParams d;
            const auto& v = voice;
            if (v.lfo3Rate != d.lfo3Rate || v.lfo3Shape != d.lfo3Shape || v.lfo4Rate != d.lfo4Rate || v.lfo4Shape != d.lfo4Shape)
                o << "lfo34 " << v.lfo3Rate << " " << v.lfo3Shape << " " << v.lfo4Rate << " " << v.lfo4Shape << "\n";
            if (v.lfoSync[0] || v.lfoSync[1] || v.lfoSync[2] || v.lfoSync[3])
                o << "sync " << v.lfoSync[0] << " " << v.lfoSync[1] << " " << v.lfoSync[2] << " " << v.lfoSync[3] << "\n";
            if (v.env3A != d.env3A || v.env3D != d.env3D || v.env3S != d.env3S || v.env3R != d.env3R)
                o << "env3 " << v.env3A << " " << v.env3D << " " << v.env3S << " " << v.env3R << "\n";
            if (v.osc1WtPos != 0 || v.osc2WtPos != 0) o << "wtpos " << v.osc1WtPos << " " << v.osc2WtPos << "\n";
            if (v.subLevel != d.subLevel || v.subOctave != d.subOctave || v.subShape != d.subShape)
                o << "sub " << v.subLevel << " " << v.subOctave << " " << v.subShape << "\n";
            if (v.noiseLevel != d.noiseLevel || v.noiseTone != d.noiseTone) o << "noise " << v.noiseLevel << " " << v.noiseTone << "\n";
            if (v.noiseCharacter != d.noiseCharacter || v.noiseColor != d.noiseColor) o << "noisex " << v.noiseCharacter << " " << v.noiseColor << "\n";
            if (v.noiseWidth != d.noiseWidth) o << "noisew " << v.noiseWidth << "\n";
            if (v.filter2Type != d.filter2Type || v.filter2Cutoff != d.filter2Cutoff || v.filter2Reso != d.filter2Reso || v.filterRouting != d.filterRouting)
                o << "filter2 " << v.filter2Type << " " << v.filter2Cutoff << " " << v.filter2Reso << " " << v.filterRouting << "\n";
            // 0.33.0 live spectral morph and output trim
            if (v.osc1SpecMorph != 0 || v.osc2SpecMorph != 0) o << "specmorph " << v.osc1SpecMorph << " " << v.osc2SpecMorph << "\n";
            for (int t = 0; t < 2; ++t) {
                const SpectralProcess& ms = t ? v.osc2MorphSpec : v.osc1MorphSpec;
                if (!ms.isIdentity()) o << "morphspec" << (t + 1) << " " << ms.formantSt << " " << ms.stretch << " " << ms.tiltDb << " " << ms.oddEven << "\n";
            }
            if (v.trimDb != 0) o << "trim " << v.trimDb << "\n";
            for (int t = 0; t < 2; ++t) {
                if (tables[t].empty()) continue;
                if (!tableRecipe[t].empty() && tables[t] == recipeTable[t]) { // 0.32.0: unedited recipe table
                    o << "wtgen" << (t + 1) << " " << tableRecipe[t] << "\n";
                    if (!tableSpec[t].empty()) o << "wtspec" << (t + 1) << " " << tableSpec[t] << "\n";
                    continue;
                }
                std::ostringstream w;
                w << std::setprecision(9);
                w << "wt" << (t + 1) << " " << tables[t].size();
                for (const auto& f : tables[t]) for (float x : f) w << " " << x;
                o << w.str() << "\n";
            }
        }
        writeRoutesAndFX(o);
        const FXParams d;
        if (fx.dist.enabled != d.dist.enabled || fx.dist.mode != d.dist.mode || fx.dist.drive != d.dist.drive || fx.dist.mix != d.dist.mix)
            o << "dist " << (fx.dist.enabled ? 1 : 0) << " " << fx.dist.mode << " " << fx.dist.drive << " " << fx.dist.mix << "\n";
        if (fx.dist.quality != d.dist.quality) o << "distx " << fx.dist.quality << "\n"; // 0.29.0
        if (fx.eq.enabled != d.eq.enabled || fx.eq.lowDb != d.eq.lowDb || fx.eq.midDb != d.eq.midDb || fx.eq.highDb != d.eq.highDb)
            o << "eq " << (fx.eq.enabled ? 1 : 0) << " " << fx.eq.lowDb << " " << fx.eq.midDb << " " << fx.eq.highDb << "\n";
        if (fx.comp.enabled != d.comp.enabled || fx.comp.amount != d.comp.amount)
            o << "comp " << (fx.comp.enabled ? 1 : 0) << " " << fx.comp.amount << "\n";
        auto fxLine = [&](const char* k, bool en, double a, double b, double c, double m) {
            o << k << " " << (en ? 1 : 0) << " " << a << " " << b << " " << c << " " << m << "\n";
        };
        const auto& ph = fx.phaser; const auto& dp = d.phaser;
        if (ph.enabled != dp.enabled || ph.rateHz != dp.rateHz || ph.depth != dp.depth || ph.feedback != dp.feedback || ph.mix != dp.mix)
            fxLine("phaser", ph.enabled, ph.rateHz, ph.depth, ph.feedback, ph.mix);
        const auto& fl = fx.flanger; const auto& df = d.flanger;
        if (fl.enabled != df.enabled || fl.rateHz != df.rateHz || fl.depth != df.depth || fl.feedback != df.feedback || fl.mix != df.mix)
            fxLine("flanger", fl.enabled, fl.rateHz, fl.depth, fl.feedback, fl.mix);
        const auto& rv = fx.reverb; const auto& dr = d.reverb;
        if (rv.mode != dr.mode || rv.preDelayMs != dr.preDelayMs || rv.size != dr.size || rv.width != dr.width || rv.lowCutHz != dr.lowCutHz)
            o << "reverbx " << rv.mode << " " << rv.preDelayMs << " " << rv.size << " " << rv.width << " " << rv.lowCutHz << "\n";
        const auto& cp = fx.comp; const auto& dc = d.comp;
        if (cp.mode != dc.mode || cp.upward != dc.upward || cp.speed != dc.speed || cp.lowDb != dc.lowDb || cp.midDb != dc.midDb
            || cp.highDb != dc.highDb || cp.mix != dc.mix || cp.makeup != dc.makeup)
            o << "compx " << cp.mode << " " << cp.upward << " " << cp.speed << " " << cp.lowDb << " " << cp.midDb << " " << cp.highDb
              << " " << cp.mix << (cp.makeup ? " 1" : "") << "\n";
        const auto& hy = fx.hyper; const auto& dh = d.hyper;
        if (hy.enabled != dh.enabled || hy.rateHz != dh.rateHz || hy.detune != dh.detune || hy.dimension != dh.dimension || hy.mix != dh.mix)
            fxLine("hyper", hy.enabled, hy.rateHz, hy.detune, hy.dimension, hy.mix);
        const auto& ff = fx.filter; const auto& dff = d.filter;
        if (ff.enabled != dff.enabled || ff.mode != dff.mode || ff.cutoffHz != dff.cutoffHz || ff.reso != dff.reso || ff.drive != dff.drive
            || ff.lfoRateHz != dff.lfoRateHz || ff.lfoSync != dff.lfoSync || ff.lfoDepth != dff.lfoDepth || ff.mix != dff.mix)
            o << "filterfx " << (ff.enabled ? 1 : 0) << " " << ff.mode << " " << ff.cutoffHz << " " << ff.reso << " " << ff.drive << " "
              << ff.lfoRateHz << " " << ff.lfoSync << " " << ff.lfoDepth << " " << ff.mix << "\n";
        if (fx.delay.syncL != d.delay.syncL || fx.delay.syncR != d.delay.syncR)
            o << "delaysync " << fx.delay.syncL << " " << fx.delay.syncR << "\n";
        if (fx.lfo[0] != d.lfo[0] || fx.lfo[1] != d.lfo[1]) {
            o << "fxlfo";
            for (const auto& l : fx.lfo) o << " " << l.rateHz << " " << l.shape << " " << l.sync;
            o << "\n";
        }
        if (!fx.order.isDefault()) {
            o << "fxorder";
            for (int i = 0; i < kFxUnits; ++i) o << " " << fxUnitName(fx.order.slot[i]);
            o << "\n";
        }
        return o.str();
    }

    bool hasUnison() const {
        const VoiceParams d;
        return voice.osc1Unison != d.osc1Unison || voice.osc2Unison != d.osc2Unison
            || voice.osc1UniDetune != d.osc1UniDetune || voice.osc2UniDetune != d.osc2UniDetune
            || voice.uniWidth != d.uniWidth || voice.uniBlend != d.uniBlend;
    }

    // Legacy writer, kept so version-1 compatibility stays testable.
    std::string serializeV1() const {
        std::ostringstream o;
        o << kMagicV1 << "\n";
        writeCore(o);
        writeRoutesAndFX(o);
        return o.str();
    }

    bool parse(const std::string& text) {
        std::istringstream in(text);
        std::string line;
        if (!std::getline(in, line)) return false;
        if (line == kMagicV1) version = 1;
        else if (line == kMagic) version = 2;
        else return false; // unknown or future version: refuse rather than guess
        *this = Preset{};
        version = (line == kMagicV1) ? 1 : 2;
        SpectralProcess pendingSpec[2]; // 0.32.0: applied after every line is read
        while (std::getline(in, line)) {
            std::istringstream ls(line);
            std::string key;
            ls >> key;
            if (key == "name") info.name = restOf(line, key);
            else if (key == "category") info.category = restOf(line, key);
            else if (key == "author") info.author = restOf(line, key);
            else if (key == "tags") { std::string t; while (ls >> t) info.tags.push_back(t); }
            else if (key == "desc") info.description = restOf(line, key);
            else if (key == "osc1Shape") ls >> voice.osc1Shape;
            else if (key == "osc2Shape") ls >> voice.osc2Shape;
            else if (key == "osc2Detune") ls >> voice.osc2Detune;
            else if (key == "osc2Level") ls >> voice.osc2Level;
            else if (key == "filterCutoff") ls >> voice.filterCutoff;
            else if (key == "filterReso") ls >> voice.filterReso;
            else if (key == "filterMode") { ls >> voice.filterMode; voice.filterMode = std::clamp(voice.filterMode, 0, kFilterModes - 1); }
            else if (key == "amp") ls >> voice.ampA >> voice.ampD >> voice.ampS >> voice.ampR;
            else if (key == "mod") ls >> voice.modA >> voice.modD >> voice.modS >> voice.modR;
            else if (key == "lfo1Rate") ls >> voice.lfo1Rate;
            else if (key == "lfo1Shape") ls >> voice.lfo1Shape;
            else if (key == "lfo2") ls >> voice.lfo2Rate >> voice.lfo2Shape;
            else if (key == "warp1") ls >> voice.osc1WarpMode >> voice.osc1Warp;
            else if (key == "warp2") ls >> voice.osc2WarpMode >> voice.osc2Warp;
            else if (key == "arpx") { // 0.26.0: clock sync + step pattern
                int sy = 0, on = 0, len = 16;
                if (ls >> sy >> on >> len) {
                    voice.clockSync = sy != 0; voice.arpPatOn = on != 0; voice.arpPatLen = std::clamp(len, 1, arp::kPatSteps);
                    for (int i = 0; i < arp::kPatSteps; ++i) {
                        int ve = 127, k = 0;
                        if (!(ls >> ve >> k)) break;
                        voice.arpPatVel[i] = std::clamp(ve, 1, 127); voice.arpPatKind[i] = std::clamp(k, 0, arp::kStepKinds - 1);
                    }
                }
            }
            else if (key == "arpr") { // 0.48.0: optional per-step ratchet counts, arpx remains byte-identical
                for (int i = 0; i < arp::kPatSteps; ++i) {
                    int n = 1; if (!(ls >> n)) break;
                    voice.arpPatRatchet[i] = std::clamp(n, 1, 4);
                }
            }
            else if (key == "arpo") { // 0.49.0: optional per-step octave shifts
                for (int i = 0; i < arp::kPatSteps; ++i) {
                    int n = 0; if (!(ls >> n)) break;
                    voice.arpPatOctave[i] = std::clamp(n, -1, 1);
                }
            }
            else if (key == "arpc") { // 0.50.0: optional chance and LIVE mode
                int live = 0;
                if (ls >> live) {
                    voice.arpChanceLive = live != 0;
                    for (int i = 0; i < arp::kPatSteps; ++i) {
                        int n = 100; if (!(ls >> n)) break;
                        voice.arpPatChance[i] = n >= 100 ? 100 : n >= 75 ? 75 : n >= 50 ? 50 : 25;
                    }
                }
            }
            else if (key == "arp") { // 0.25.0: on mode octaves rate gate swing latch
                int on = 0, m = 0, oc = 1, r = 3, la = 0; double g = 0.5, sw = 0;
                if (ls >> on >> m >> oc >> r >> g >> sw >> la && std::isfinite(g) && std::isfinite(sw)) {
                    voice.arpOn = on != 0; voice.arpMode = std::clamp(m, 0, arp::kModes - 1); voice.arpOctaves = std::clamp(oc, 1, 4);
                    voice.arpRate = std::clamp(r, 0, arp::kRates - 1); voice.arpGate = std::clamp(g, 0.05, 1.0);
                    voice.arpSwing = std::clamp(sw, 0.0, 0.5); voice.arpLatch = la != 0;
                }
            }
            else if (key == "perf") { int b = 2; if (ls >> b) voice.bendRange = std::clamp(b, 0, 24); } // 0.24.0
            else if (key == "oscq") { int q = 0; if (ls >> q) voice.oscQuality = std::clamp(q, 0, 1); } // 0.30.0
            else if (key == "voice") { // 0.23.0: mode poly-voices glide-time glide-legato unison-phase
                int m = 0, n = 16, gl = 0, ph = 0; double g = 0;
                if (ls >> m >> n >> g >> gl >> ph && std::isfinite(g)) {
                    voice.voiceMode = std::clamp(m, 0, 2); voice.polyVoices = std::clamp(n, 1, 16);
                    voice.glideTime = std::clamp(g, 0.0, 5.0); voice.glideLegato = gl != 0; voice.uniPhase = std::clamp(ph, 0, 1);
                }
            }
            else if (key == "filterr") { // 0.22.0: f1 mix, f2 mix, parallel balance, f2 morph
                double m1 = 1, m2 = 1, b = 0.5, f2m = 0;
                if (ls >> m1 >> m2 >> b >> f2m && std::isfinite(m1) && std::isfinite(m2) && std::isfinite(b) && std::isfinite(f2m)) {
                    voice.filter1Mix = std::clamp(m1, 0.0, 1.0); voice.filter2Mix = std::clamp(m2, 0.0, 1.0);
                    voice.filterBalance = std::clamp(b, 0.0, 1.0); voice.filter2Morph = std::clamp(f2m, 0.0, 1.0);
                }
            }
            else if (key == "filterx") { // 0.21.0: drive keytrack morph
                double d = 0, k = 0, m = 0;
                if (ls >> d >> k >> m && std::isfinite(d) && std::isfinite(k) && std::isfinite(m)) {
                    voice.filterDrive = std::clamp(d, 0.0, 1.0); voice.filterKeytrack = std::clamp(k, 0.0, 1.0); voice.filterMorph = std::clamp(m, 0.0, 1.0);
                }
            }
            else if (key == "warpx") { // 0.19.0
                int m1 = 0, m2 = 0; double a1 = 0, a2 = 0;
                if (ls >> m1 >> a1 >> m2 >> a2 && std::isfinite(a1) && std::isfinite(a2)) {
                    voice.osc1Warp2Mode = std::clamp(m1, 0, 10); voice.osc1Warp2 = std::clamp(a1, 0.0, 1.0);
                    voice.osc2Warp2Mode = std::clamp(m2, 0, 10); voice.osc2Warp2 = std::clamp(a2, 0.0, 1.0);
                }
            }
            else if (key == "remap") {
                int o = -1; size_t n = 0;
                if (ls >> o >> n && o >= 0 && o < 2 && n >= 2 && n <= 64) {
                    std::vector<MSEG::Point> pts;
                    for (size_t k = 0; k < n; ++k) {
                        MSEG::Point p;
                        if (!(ls >> p.time >> p.value >> p.curve) || !std::isfinite(p.time) || !std::isfinite(p.value) || !std::isfinite(p.curve)) break;
                        p.time = std::clamp(p.time, 0.0, 1.0); p.value = std::clamp(p.value, -1.0, 1.0); p.curve = std::clamp(p.curve, -1.0, 1.0);
                        pts.push_back(p);
                    }
                    if (pts.size() == n) voice.remapPoints[o] = pts;
                }
            }
            else if (key == "mseg") {
                int loop = 0; size_t n = 0;
                ls >> voice.mseg1Seconds >> loop >> n;
                voice.mseg1Loop = loop != 0;
                std::vector<MSEG::Point> pts;
                for (size_t i = 0; i < n && i < 64; ++i) {
                    MSEG::Point p;
                    if (!(ls >> p.time >> p.value)) return false;
                    pts.push_back(p);
                }
                if (pts.size() < 2) return false;
                voice.mseg1Points = pts;
            }
            else if (key == "msegcurve") { // curves for the MSEG 1 points; a count mismatch is ignored
                size_t n = 0; ls >> n;
                std::vector<double> c;
                for (size_t i = 0; i < n && i < 64; ++i) { double x; if (!(ls >> x) || !std::isfinite(x)) break; c.push_back(std::clamp(x, -1.0, 1.0)); }
                if (c.size() == n && n == voice.mseg1Points.size()) for (size_t i = 0; i < n; ++i) voice.mseg1Points[i].curve = c[i];
            }
            else if (key == "msegx") {
                int sy, a, b, f;
                if (ls >> sy >> a >> b >> f) {
                    voice.mseg1Sync = std::clamp(sy, 0, kSyncCount - 1);
                    voice.mseg1LoopStart = std::clamp(a, 0, 63); voice.mseg1LoopEnd = std::clamp(b, -1, 63); voice.mseg1FreeLoop = f != 0;
                }
            }
            else if (key == "lfox") { // 0.18.0
                int i = -1, c = 0, f = 0; double ph = 0, de = 0, ri = 0;
                if (ls >> i >> c >> ph >> de >> ri >> f && i >= 0 && i < 4 && std::isfinite(ph) && std::isfinite(de) && std::isfinite(ri)) {
                    voice.lfoCustom[i] = c != 0; voice.lfoPhase[i] = std::clamp(ph, 0.0, 1.0);
                    voice.lfoDelay[i] = std::clamp(de, 0.0, 8.0); voice.lfoRise[i] = std::clamp(ri, 0.0, 8.0); voice.lfoFree[i] = f != 0;
                }
            }
            else if (key == "lfopts") {
                int i = -1; size_t n = 0;
                if (ls >> i >> n && i >= 0 && i < 4 && n >= 2 && n <= 64) {
                    std::vector<MSEG::Point> pts;
                    for (size_t k = 0; k < n; ++k) {
                        MSEG::Point p;
                        if (!(ls >> p.time >> p.value >> p.curve) || !std::isfinite(p.time) || !std::isfinite(p.value) || !std::isfinite(p.curve)) break;
                        p.time = std::clamp(p.time, 0.0, 1.0); p.value = std::clamp(p.value, -1.0, 1.0); p.curve = std::clamp(p.curve, -1.0, 1.0);
                        pts.push_back(p);
                    }
                    if (pts.size() == n) voice.lfoPoints[i] = pts;
                }
            }
            else if (key == "mseg2") {
                double sec; int sy, mode, a, b; size_t n = 0;
                if (ls >> sec >> sy >> mode >> a >> b >> n && std::isfinite(sec) && n >= 2 && n <= 64) {
                    std::vector<MSEG::Point> pts;
                    for (size_t i = 0; i < n; ++i) {
                        MSEG::Point p;
                        if (!(ls >> p.time >> p.value >> p.curve) || !std::isfinite(p.time) || !std::isfinite(p.value) || !std::isfinite(p.curve)) break;
                        p.time = std::clamp(p.time, 0.0, 1.0); p.value = std::clamp(p.value, -1.0, 1.0); p.curve = std::clamp(p.curve, -1.0, 1.0);
                        pts.push_back(p);
                    }
                    if (pts.size() == n) {
                        voice.mseg2Seconds = std::clamp(sec, 0.05, 8.0); voice.mseg2Sync = std::clamp(sy, 0, kSyncCount - 1);
                        voice.mseg2Mode = std::clamp(mode, 0, 2); voice.mseg2LoopStart = std::clamp(a, 0, 63); voice.mseg2LoopEnd = std::clamp(b, -1, 63);
                        voice.mseg2Points = pts;
                    }
                }
            }
            else if (key == "macros") { for (double& m : voice.macros) { double v = 0; if (ls >> v) m = std::clamp(v, 0.0, 1.0); } }
            else if (key == "unison") {
                ls >> voice.osc1Unison >> voice.osc2Unison >> voice.osc1UniDetune >> voice.osc2UniDetune
                   >> voice.uniWidth >> voice.uniBlend;
                voice.osc1Unison = std::clamp(voice.osc1Unison, 1, kMaxUnison);
                voice.osc2Unison = std::clamp(voice.osc2Unison, 1, kMaxUnison);
                voice.osc1UniDetune = std::clamp(voice.osc1UniDetune, 0.0, 1.0);
                voice.osc2UniDetune = std::clamp(voice.osc2UniDetune, 0.0, 1.0);
                voice.uniWidth = std::clamp(voice.uniWidth, 0.0, 1.0);
                voice.uniBlend = std::clamp(voice.uniBlend, 0.0, 1.0);
            }
            else if (key == "lfo34") {
                ls >> voice.lfo3Rate >> voice.lfo3Shape >> voice.lfo4Rate >> voice.lfo4Shape;
                voice.lfo3Rate = std::clamp(voice.lfo3Rate, 0.01, 40.0);
                voice.lfo4Rate = std::clamp(voice.lfo4Rate, 0.01, 40.0);
                voice.lfo3Shape = std::clamp(voice.lfo3Shape, 0, 3);
                voice.lfo4Shape = std::clamp(voice.lfo4Shape, 0, 3);
            }
            else if (key == "sync") {
                for (int& sy : voice.lfoSync) { int x = 0; if (ls >> x) sy = std::clamp(x, 0, kSyncCount - 1); }
            }
            else if (key == "env3") {
                ls >> voice.env3A >> voice.env3D >> voice.env3S >> voice.env3R;
                voice.env3A = std::clamp(voice.env3A, 0.001, 10.0);
                voice.env3D = std::clamp(voice.env3D, 0.001, 10.0);
                voice.env3S = std::clamp(voice.env3S, 0.0, 1.0);
                voice.env3R = std::clamp(voice.env3R, 0.001, 10.0);
            }
            else if (key == "wtpos") {
                ls >> voice.osc1WtPos >> voice.osc2WtPos;
                voice.osc1WtPos = std::clamp(voice.osc1WtPos, 0.0, 1.0);
                voice.osc2WtPos = std::clamp(voice.osc2WtPos, 0.0, 1.0);
            }
            else if (key == "sub") {
                ls >> voice.subLevel >> voice.subOctave >> voice.subShape;
                voice.subLevel = std::clamp(voice.subLevel, 0.0, 1.0);
                voice.subOctave = std::clamp(voice.subOctave, 1, 2);
                voice.subShape = std::clamp(voice.subShape, 0, kSubShapes - 1);
            }
            else if (key == "noise") {
                ls >> voice.noiseLevel >> voice.noiseTone;
                voice.noiseLevel = std::clamp(voice.noiseLevel, 0.0, 1.0);
                voice.noiseTone = std::clamp(voice.noiseTone, 0.0, 1.0);
            }
            else if (key == "noisex") {
                int mode = 0; double color = 0.5;
                if (ls >> mode >> color && std::isfinite(color)) {
                    voice.noiseCharacter = std::clamp(mode, 0, 3);
                    voice.noiseColor = std::clamp(color, 0.0, 1.0);
                }
            }
            else if (key == "noisew") {
                double width; if (ls >> width && std::isfinite(width)) voice.noiseWidth = std::clamp(width, 0.0, 1.0);
            }
            else if (key == "filter2") {
                ls >> voice.filter2Type >> voice.filter2Cutoff >> voice.filter2Reso >> voice.filterRouting;
                voice.filter2Type = std::clamp(voice.filter2Type, 0, kFilter2Types - 1);
                voice.filter2Cutoff = std::clamp(voice.filter2Cutoff, 40.0, 18000.0);
                voice.filter2Reso = std::clamp(voice.filter2Reso, 0.1, 8.0);
                voice.filterRouting = std::clamp(voice.filterRouting, 0, 1);
            }
            else if (key == "wt1" || key == "wt2") {
                int n = 0; ls >> n;
                TableFrames t;
                if (n >= 1 && n <= kMaxFrames) {
                    t.assign(n, Frame(kFrameSize));
                    bool ok = true;
                    for (auto& f : t) for (float& x : f) { if (!(ls >> x) || !std::isfinite(x)) { ok = false; break; } x = std::clamp(x, -1.0f, 1.0f); }
                    if (!ok) t.clear(); // truncated or damaged: no table rather than a wrong one
                }
                tables[key == "wt1" ? 0 : 1] = t;
            }
            else if (key == "dist") {
                int e = 0; ls >> e >> fx.dist.mode >> fx.dist.drive >> fx.dist.mix;
                fx.dist.enabled = e != 0;
                fx.dist.mode = std::clamp(fx.dist.mode, 0, 2);
                fx.dist.drive = std::clamp(fx.dist.drive, 0.0, 1.0);
                fx.dist.mix = std::clamp(fx.dist.mix, 0.0, 1.0);
            }
            else if (key == "eq") {
                int e = 0; ls >> e >> fx.eq.lowDb >> fx.eq.midDb >> fx.eq.highDb;
                fx.eq.enabled = e != 0;
                fx.eq.lowDb = std::clamp(fx.eq.lowDb, -12.0, 12.0);
                fx.eq.midDb = std::clamp(fx.eq.midDb, -12.0, 12.0);
                fx.eq.highDb = std::clamp(fx.eq.highDb, -12.0, 12.0);
            }
            else if (key == "comp") {
                int e = 0; ls >> e >> fx.comp.amount;
                fx.comp.enabled = e != 0;
                fx.comp.amount = std::clamp(fx.comp.amount, 0.0, 1.0);
            }
            else if (key == "phaser" || key == "flanger") {
                int e = 0; double rate, depth, fb, mix;
                if (ls >> e >> rate >> depth >> fb >> mix && std::isfinite(rate) && std::isfinite(depth) && std::isfinite(fb) && std::isfinite(mix)) {
                    rate = std::clamp(rate, 0.02, 8.0); depth = std::clamp(depth, 0.0, 1.0);
                    fb = std::clamp(fb, 0.0, 0.9); mix = std::clamp(mix, 0.0, 1.0);
                    if (key == "phaser") fx.phaser = PhaserParams{e != 0, rate, depth, fb, mix};
                    else fx.flanger = FlangerParams{e != 0, rate, depth, fb, mix};
                }
            }
            else if (key == "reverbx") {
                int m = 0; double pre, size, width, lc;
                if (ls >> m >> pre >> size >> width >> lc && std::isfinite(pre) && std::isfinite(size) && std::isfinite(width) && std::isfinite(lc)) {
                    fx.reverb.mode = std::clamp(m, 0, 2); fx.reverb.preDelayMs = std::clamp(pre, 0.0, 250.0);
                    fx.reverb.size = std::clamp(size, 0.0, 1.0); fx.reverb.width = std::clamp(width, 0.0, 1.0);
                    fx.reverb.lowCutHz = std::clamp(lc, 20.0, 1000.0);
                }
            }
            else if (key == "distx") { int q = 0; if (ls >> q) fx.dist.quality = std::clamp(q, 0, 1); } // 0.29.0
            else if (key == "compx") {
                int m = 0; double up, sp, lo, mid, hi, mix;
                if (ls >> m >> up >> sp >> lo >> mid >> hi >> mix && std::isfinite(up) && std::isfinite(sp) && std::isfinite(lo)
                    && std::isfinite(mid) && std::isfinite(hi) && std::isfinite(mix)) {
                    auto& c = fx.comp;
                    c.mode = std::clamp(m, 0, 1); c.upward = std::clamp(up, 0.0, 1.0); c.speed = std::clamp(sp, 0.0, 1.0);
                    c.lowDb = std::clamp(lo, -12.0, 12.0); c.midDb = std::clamp(mid, -12.0, 12.0); c.highDb = std::clamp(hi, -12.0, 12.0);
                    c.mix = std::clamp(mix, 0.0, 1.0);
                    int mk = 0; if (ls >> mk) c.makeup = mk != 0 ? 1 : 0; // 0.29.0 optional AUTO GAIN field
                }
            }
            else if (key == "hyper") {
                int e = 0; double rate, det, dim, mix;
                if (ls >> e >> rate >> det >> dim >> mix && std::isfinite(rate) && std::isfinite(det) && std::isfinite(dim) && std::isfinite(mix))
                    fx.hyper = HyperParams{e != 0, std::clamp(rate, 0.05, 5.0), std::clamp(det, 0.0, 1.0), std::clamp(dim, 0.0, 1.0), std::clamp(mix, 0.0, 1.0)};
            }
            else if (key == "filterfx") {
                int e = 0, mode = 0, sync = 0; double cut, reso, drive, rate, depth, mix;
                if (ls >> e >> mode >> cut >> reso >> drive >> rate >> sync >> depth >> mix && std::isfinite(cut) && std::isfinite(reso)
                    && std::isfinite(drive) && std::isfinite(rate) && std::isfinite(depth) && std::isfinite(mix)) {
                    FilterFxParams f;
                    f.enabled = e != 0; f.mode = std::clamp(mode, 0, 4); f.cutoffHz = std::clamp(cut, 40.0, 18000.0);
                    f.reso = std::clamp(reso, 0.0, 1.0); f.drive = std::clamp(drive, 0.0, 1.0); f.lfoRateHz = std::clamp(rate, 0.02, 20.0);
                    f.lfoSync = std::clamp(sync, 0, kSyncCount - 1); f.lfoDepth = std::clamp(depth, 0.0, 1.0); f.mix = std::clamp(mix, 0.0, 1.0);
                    fx.filter = f;
                }
            }
            else if (key == "fxlfo") {
                RackLfoParams l[2];
                bool ok = true;
                for (auto& x : l) ok = ok && (ls >> x.rateHz >> x.shape >> x.sync) && std::isfinite(x.rateHz);
                if (ok) for (int k = 0; k < 2; ++k) {
                    fx.lfo[k].rateHz = std::clamp(l[k].rateHz, 0.02, 20.0);
                    fx.lfo[k].shape = std::clamp(l[k].shape, 0, 3);
                    fx.lfo[k].sync = std::clamp(l[k].sync, 0, kSyncCount - 1);
                }
            }
            else if (key == "delaysync") {
                int a = 0, b = 0;
                if (ls >> a >> b) { fx.delay.syncL = std::clamp(a, 0, kSyncCount - 1); fx.delay.syncR = std::clamp(b, 0, kSyncCount - 1); }
            }
            else if (key == "fxorder") { // unit names; anything but a full permutation keeps the default
                int v[kFxUnits]; int n = 0; std::string w;
                while (ls >> w) {
                    int u = -1;
                    for (int k = 0; k < kFxUnits; ++k) if (w == fxUnitName(k)) u = k;
                    if (u < 0 || n >= kFxUnits) { n = -1; break; }
                    v[n++] = u;
                }
                if (n == 8) { // 0.13.0-0.26.0 8-unit line: units added later keep their default place at the end
                    bool seen[kFxUnits] = {};
                    for (int k = 0; k < n; ++k) seen[v[k]] = true;
                    for (int k = 0; k < kFxUnits; ++k) if (!seen[k] && n < kFxUnits) v[n++] = k;
                }
                FxOrder ord;
                if (n == kFxUnits && ord.assign(v, n)) fx.order = ord;
            }
            else if (key == "routes") { size_t n; ls >> n; } // count is advisory
            else if (key == "route") {
                ModRoute r; int s, d;
                ls >> s >> d >> r.amount;
                // Sources/destinations from a newer build are skipped, not guessed.
                if (ls && (int)routes.size() < kMaxRoutes && s >= 0 && s <= (int)ModRoute::Source::Keytrack && d >= 0 && d <= (int)ModRoute::Dest::NoiseColor) {
                    r.source = (ModRoute::Source)s; r.dest = (ModRoute::Dest)d;
                    // 0.16.0 optional keyed suffix: `curve <c>` and `aux <source>`.
                    std::string k2;
                    while (ls >> k2) {
                        if (k2 == "curve") { double c; if (ls >> c && std::isfinite(c)) r.curve = std::clamp(c, -1.0, 1.0); }
                        else if (k2 == "aux") { int a; if (ls >> a && a >= 0 && a < kModSources) r.aux = a; }
                        else break;
                    }
                    routes.push_back(r);
                }
            }
            else if (key == "chorus") {
                int e; ls >> e >> fx.chorus.rateHz >> fx.chorus.depthMs >> fx.chorus.baseMs >> fx.chorus.mix;
                fx.chorus.enabled = e != 0;
            }
            else if (key == "delay") {
                int e; ls >> e >> fx.delay.timeLSec >> fx.delay.timeRSec >> fx.delay.feedback >> fx.delay.mix;
                fx.delay.enabled = e != 0;
            }
            else if (key == "reverb") {
                int e; ls >> e >> fx.reverb.decay >> fx.reverb.damping >> fx.reverb.mix;
                fx.reverb.enabled = e != 0;
            }
            else if (key == "wtgen1" || key == "wtgen2") { // 0.32.0 table recipe
                const int o = key == "wtgen1" ? 0 : 1;
                tableRecipe[o] = restOf(line, key);
                tables[o] = tableFromRecipe(tableRecipe[o]);
            }
            else if (key == "specmorph") { // 0.33.0
                ls >> voice.osc1SpecMorph >> voice.osc2SpecMorph;
                voice.osc1SpecMorph = std::clamp(voice.osc1SpecMorph, 0.0, 1.0); voice.osc2SpecMorph = std::clamp(voice.osc2SpecMorph, 0.0, 1.0);
            }
            else if (key == "morphspec1" || key == "morphspec2") {
                specFromText(restOf(line, key), key == "morphspec1" ? voice.osc1MorphSpec : voice.osc2MorphSpec);
            }
            else if (key == "trim") { ls >> voice.trimDb; voice.trimDb = std::clamp(voice.trimDb, -24.0, 12.0); }
            else if (key == "wtspec1" || key == "wtspec2") {
                const int o = key == "wtspec1" ? 0 : 1;
                if (specFromText(restOf(line, key), pendingSpec[o])) tableSpec[o] = restOf(line, key);
            }
            // Unknown keys are ignored so minor additions stay loadable.
        }
        for (int o = 0; o < 2; ++o) {
            if (!tables[o].empty() && !pendingSpec[o].isIdentity()) tables[o] = processTable(tables[o], pendingSpec[o]);
            if (tables[o].empty() || tableRecipe[o].empty()) { tableRecipe[o].clear(); tableSpec[o].clear(); }
            else recipeTable[o] = tables[o];
        }
        return true;
    }

    // Descriptions live on one line; newlines and tabs become spaces.
    static std::string oneLine(std::string s) {
        for (auto& c : s) if (c == '\n' || c == '\r' || c == '\t') c = ' ';
        return s;
    }

    bool hasTag(const std::string& t) const {
        for (const auto& x : info.tags) if (x == t) return true;
        return false;
    }

    bool operator==(const Preset& o) const {
        const auto& a = voice; const auto& b = o.voice;
        bool voiceEq = a.osc1Shape == b.osc1Shape && a.osc2Shape == b.osc2Shape
            && a.osc2Detune == b.osc2Detune && a.osc2Level == b.osc2Level
            && a.filterCutoff == b.filterCutoff && a.filterReso == b.filterReso
            && a.filterMode == b.filterMode
            && a.ampA == b.ampA && a.ampD == b.ampD && a.ampS == b.ampS && a.ampR == b.ampR
            && a.modA == b.modA && a.modD == b.modD && a.modS == b.modS && a.modR == b.modR
            && a.lfo1Rate == b.lfo1Rate && a.lfo1Shape == b.lfo1Shape
            && a.lfo2Rate == b.lfo2Rate && a.lfo2Shape == b.lfo2Shape
            && a.osc1WarpMode == b.osc1WarpMode && a.osc1Warp == b.osc1Warp
            && a.osc2WarpMode == b.osc2WarpMode && a.osc2Warp == b.osc2Warp
            && a.mseg1Seconds == b.mseg1Seconds && a.mseg1Loop == b.mseg1Loop
            && a.mseg1Points.size() == b.mseg1Points.size()
            && a.macros[0] == b.macros[0] && a.macros[1] == b.macros[1]
            && a.macros[2] == b.macros[2] && a.macros[3] == b.macros[3]
            && a.osc1Unison == b.osc1Unison && a.osc2Unison == b.osc2Unison
            && a.osc1UniDetune == b.osc1UniDetune && a.osc2UniDetune == b.osc2UniDetune
            && a.uniWidth == b.uniWidth && a.uniBlend == b.uniBlend
            && a.lfo3Rate == b.lfo3Rate && a.lfo3Shape == b.lfo3Shape && a.lfo4Rate == b.lfo4Rate && a.lfo4Shape == b.lfo4Shape
            && a.lfoSync[0] == b.lfoSync[0] && a.lfoSync[1] == b.lfoSync[1] && a.lfoSync[2] == b.lfoSync[2] && a.lfoSync[3] == b.lfoSync[3]
            && a.env3A == b.env3A && a.env3D == b.env3D && a.env3S == b.env3S && a.env3R == b.env3R
            && a.osc1WtPos == b.osc1WtPos && a.osc2WtPos == b.osc2WtPos
            && a.subLevel == b.subLevel && a.subOctave == b.subOctave && a.subShape == b.subShape
            && a.noiseLevel == b.noiseLevel && a.noiseTone == b.noiseTone && a.noiseCharacter == b.noiseCharacter && a.noiseColor == b.noiseColor && a.noiseWidth == b.noiseWidth
            && a.filter2Type == b.filter2Type && a.filter2Cutoff == b.filter2Cutoff && a.filter2Reso == b.filter2Reso
            && a.filterRouting == b.filterRouting
            && a.osc1SpecMorph == b.osc1SpecMorph && a.osc2SpecMorph == b.osc2SpecMorph
            && a.osc1MorphSpec == b.osc1MorphSpec && a.osc2MorphSpec == b.osc2MorphSpec && a.trimDb == b.trimDb
            && tables[0] == o.tables[0] && tables[1] == o.tables[1];
        if (!voiceEq || !(info == o.info) || routes.size() != o.routes.size()) return false;
        if (!pointsEq(a.mseg1Points, b.mseg1Points) || !pointsEq(a.mseg2Points, b.mseg2Points)) return false;
        if (a.bendRange != b.bendRange) return false; // 0.24.0
        if (a.oscQuality != b.oscQuality) return false; // 0.30.0
        if (a.arpOn != b.arpOn || a.arpMode != b.arpMode || a.arpOctaves != b.arpOctaves || a.arpRate != b.arpRate
            || a.arpGate != b.arpGate || a.arpSwing != b.arpSwing || a.arpLatch != b.arpLatch) return false; // 0.25.0
        if (a.clockSync != b.clockSync || a.arpPatOn != b.arpPatOn || a.arpPatLen != b.arpPatLen || a.arpChanceLive != b.arpChanceLive) return false; // 0.26.0
        for (int i = 0; i < arp::kPatSteps; ++i) if (a.arpPatVel[i] != b.arpPatVel[i] || a.arpPatKind[i] != b.arpPatKind[i] || a.arpPatRatchet[i] != b.arpPatRatchet[i] || a.arpPatOctave[i] != b.arpPatOctave[i] || a.arpPatChance[i] != b.arpPatChance[i]) return false;
        if (a.voiceMode != b.voiceMode || a.polyVoices != b.polyVoices || a.glideTime != b.glideTime || a.glideLegato != b.glideLegato || a.uniPhase != b.uniPhase) return false; // 0.23.0
        if (a.filter1Mix != b.filter1Mix || a.filter2Mix != b.filter2Mix || a.filterBalance != b.filterBalance || a.filter2Morph != b.filter2Morph) return false; // 0.22.0
        if (a.filterDrive != b.filterDrive || a.filterKeytrack != b.filterKeytrack || a.filterMorph != b.filterMorph) return false; // 0.21.0
        if (a.osc1Warp2Mode != b.osc1Warp2Mode || a.osc1Warp2 != b.osc1Warp2 || a.osc2Warp2Mode != b.osc2Warp2Mode || a.osc2Warp2 != b.osc2Warp2
            || !pointsEq(a.remapPoints[0], b.remapPoints[0]) || !pointsEq(a.remapPoints[1], b.remapPoints[1])) return false;
        for (int i = 0; i < 4; ++i)
            if (a.lfoCustom[i] != b.lfoCustom[i] || a.lfoPhase[i] != b.lfoPhase[i] || a.lfoDelay[i] != b.lfoDelay[i] || a.lfoRise[i] != b.lfoRise[i]
                || a.lfoFree[i] != b.lfoFree[i] || !pointsEq(a.lfoPoints[i], b.lfoPoints[i])) return false;
        if (a.mseg1Sync != b.mseg1Sync || a.mseg1LoopStart != b.mseg1LoopStart || a.mseg1LoopEnd != b.mseg1LoopEnd || a.mseg1FreeLoop != b.mseg1FreeLoop
            || a.mseg2Seconds != b.mseg2Seconds || a.mseg2Sync != b.mseg2Sync || a.mseg2Mode != b.mseg2Mode
            || a.mseg2LoopStart != b.mseg2LoopStart || a.mseg2LoopEnd != b.mseg2LoopEnd) return false;
        for (size_t i = 0; i < routes.size(); ++i)
            if (routes[i].source != o.routes[i].source || routes[i].dest != o.routes[i].dest
                || routes[i].amount != o.routes[i].amount || routes[i].curve != o.routes[i].curve
                || routes[i].aux != o.routes[i].aux) return false;
        const auto& fa = fx; const auto& fb = o.fx;
        return fa.chorus.enabled == fb.chorus.enabled && fa.chorus.rateHz == fb.chorus.rateHz
            && fa.chorus.depthMs == fb.chorus.depthMs && fa.chorus.baseMs == fb.chorus.baseMs
            && fa.chorus.mix == fb.chorus.mix
            && fa.delay.enabled == fb.delay.enabled && fa.delay.timeLSec == fb.delay.timeLSec
            && fa.delay.timeRSec == fb.delay.timeRSec && fa.delay.feedback == fb.delay.feedback
            && fa.delay.mix == fb.delay.mix
            && fa.reverb.enabled == fb.reverb.enabled && fa.reverb.decay == fb.reverb.decay
            && fa.reverb.damping == fb.reverb.damping && fa.reverb.mix == fb.reverb.mix
            && fa.reverb.mode == fb.reverb.mode && fa.reverb.preDelayMs == fb.reverb.preDelayMs && fa.reverb.size == fb.reverb.size
            && fa.reverb.width == fb.reverb.width && fa.reverb.lowCutHz == fb.reverb.lowCutHz
            && fa.comp.mode == fb.comp.mode && fa.comp.upward == fb.comp.upward && fa.comp.speed == fb.comp.speed
            && fa.comp.lowDb == fb.comp.lowDb && fa.comp.midDb == fb.comp.midDb && fa.comp.highDb == fb.comp.highDb && fa.comp.mix == fb.comp.mix
            && fa.comp.makeup == fb.comp.makeup && fa.dist.quality == fb.dist.quality
            && fa.dist.enabled == fb.dist.enabled && fa.dist.mode == fb.dist.mode
            && fa.dist.drive == fb.dist.drive && fa.dist.mix == fb.dist.mix
            && fa.eq.enabled == fb.eq.enabled && fa.eq.lowDb == fb.eq.lowDb
            && fa.eq.midDb == fb.eq.midDb && fa.eq.highDb == fb.eq.highDb
            && fa.comp.enabled == fb.comp.enabled && fa.comp.amount == fb.comp.amount
            && fa.phaser.enabled == fb.phaser.enabled && fa.phaser.rateHz == fb.phaser.rateHz
            && fa.phaser.depth == fb.phaser.depth && fa.phaser.feedback == fb.phaser.feedback && fa.phaser.mix == fb.phaser.mix
            && fa.flanger.enabled == fb.flanger.enabled && fa.flanger.rateHz == fb.flanger.rateHz
            && fa.flanger.depth == fb.flanger.depth && fa.flanger.feedback == fb.flanger.feedback && fa.flanger.mix == fb.flanger.mix
            && fa.delay.syncL == fb.delay.syncL && fa.delay.syncR == fb.delay.syncR
            && fa.lfo[0] == fb.lfo[0] && fa.lfo[1] == fb.lfo[1]
            && fa.hyper.enabled == fb.hyper.enabled && fa.hyper.rateHz == fb.hyper.rateHz && fa.hyper.detune == fb.hyper.detune
            && fa.hyper.dimension == fb.hyper.dimension && fa.hyper.mix == fb.hyper.mix
            && fa.filter.enabled == fb.filter.enabled && fa.filter.mode == fb.filter.mode && fa.filter.cutoffHz == fb.filter.cutoffHz
            && fa.filter.reso == fb.filter.reso && fa.filter.drive == fb.filter.drive && fa.filter.lfoRateHz == fb.filter.lfoRateHz
            && fa.filter.lfoSync == fb.filter.lfoSync && fa.filter.lfoDepth == fb.filter.lfoDepth && fa.filter.mix == fb.filter.mix
            && fa.order == fb.order;
    }

private:
    static std::string restOf(const std::string& line, const std::string& key) {
        return line.size() > key.size() + 1 ? line.substr(key.size() + 1) : std::string();
    }

    void writeCore(std::ostringstream& o) const {
        o << "osc1Shape " << voice.osc1Shape << "\n";
        o << "osc2Shape " << voice.osc2Shape << "\n";
        o << "osc2Detune " << voice.osc2Detune << "\n";
        o << "osc2Level " << voice.osc2Level << "\n";
        o << "filterCutoff " << voice.filterCutoff << "\n";
        o << "filterReso " << voice.filterReso << "\n";
        o << "filterMode " << voice.filterMode << "\n";
        o << "amp " << voice.ampA << " " << voice.ampD << " " << voice.ampS << " " << voice.ampR << "\n";
        o << "mod " << voice.modA << " " << voice.modD << " " << voice.modS << " " << voice.modR << "\n";
        o << "lfo1Rate " << voice.lfo1Rate << "\n";
        o << "lfo1Shape " << voice.lfo1Shape << "\n";
    }

    // 0.17.0 MSEG editor lines, each only when it differs from the default.
    static bool anyCurve(const std::vector<MSEG::Point>& pts) { for (const auto& p : pts) if (p.curve != 0.0) return true; return false; }
    void writeMsegExtras(std::ostringstream& o) const {
        const VoiceParams d;
        const auto& v = voice;
        if (anyCurve(v.mseg1Points)) {
            o << "msegcurve " << v.mseg1Points.size();
            for (const auto& p : v.mseg1Points) o << " " << p.curve;
            o << "\n";
        }
        if (v.mseg1Sync != d.mseg1Sync || v.mseg1LoopStart != d.mseg1LoopStart || v.mseg1LoopEnd != d.mseg1LoopEnd || v.mseg1FreeLoop != d.mseg1FreeLoop)
            o << "msegx " << v.mseg1Sync << " " << v.mseg1LoopStart << " " << v.mseg1LoopEnd << " " << (v.mseg1FreeLoop ? 1 : 0) << "\n";
        if (!mseg2IsDefault()) {
            o << "mseg2 " << v.mseg2Seconds << " " << v.mseg2Sync << " " << v.mseg2Mode << " " << v.mseg2LoopStart << " " << v.mseg2LoopEnd
              << " " << v.mseg2Points.size();
            for (const auto& p : v.mseg2Points) o << " " << p.time << " " << p.value << " " << p.curve;
            o << "\n";
        }
        if (v.bendRange != 2) o << "perf " << v.bendRange << "\n"; // 0.24.0
        if (v.oscQuality != 0) o << "oscq " << v.oscQuality << "\n"; // 0.30.0
        if (v.arpOn || v.arpMode != 0 || v.arpOctaves != 1 || v.arpRate != 3 || v.arpGate != 0.5 || v.arpSwing != 0 || v.arpLatch) // 0.25.0
            o << "arp " << (v.arpOn ? 1 : 0) << " " << v.arpMode << " " << v.arpOctaves << " " << v.arpRate << " " << v.arpGate << " " << v.arpSwing
              << " " << (v.arpLatch ? 1 : 0) << "\n";
        if (v.clockSync || !v.arpPatDefault()) { // 0.26.0
            o << "arpx " << (v.clockSync ? 1 : 0) << " " << (v.arpPatOn ? 1 : 0) << " " << v.arpPatLen;
            for (int i = 0; i < arp::kPatSteps; ++i) o << " " << v.arpPatVel[i] << " " << v.arpPatKind[i];
            o << "\n";
        }
        bool ratchets = false;
        for (int i = 0; i < arp::kPatSteps; ++i) ratchets |= v.arpPatRatchet[i] != 1;
        if (ratchets) {
            o << "arpr";
            for (int i = 0; i < arp::kPatSteps; ++i) o << " " << std::clamp(v.arpPatRatchet[i], 1, 4);
            o << "\n";
        }
        bool octaves = false;
        for (int i = 0; i < arp::kPatSteps; ++i) octaves |= v.arpPatOctave[i] != 0;
        if (octaves) {
            o << "arpo";
            for (int i = 0; i < arp::kPatSteps; ++i) o << " " << std::clamp(v.arpPatOctave[i], -1, 1);
            o << "\n";
        }
        bool chances = v.arpChanceLive;
        for (int i = 0; i < arp::kPatSteps; ++i) chances |= v.arpPatChance[i] != 100;
        if (chances) {
            o << "arpc " << (v.arpChanceLive ? 1 : 0);
            for (int i = 0; i < arp::kPatSteps; ++i) o << " " << v.arpPatChance[i];
            o << "\n";
        }
        if (v.voiceMode != 0 || v.polyVoices != 16 || v.glideTime != 0 || v.glideLegato || v.uniPhase != 0) // 0.23.0
            o << "voice " << v.voiceMode << " " << v.polyVoices << " " << v.glideTime << " " << (v.glideLegato ? 1 : 0) << " " << v.uniPhase << "\n";
        if (v.filter1Mix != 1 || v.filter2Mix != 1 || v.filterBalance != 0.5 || v.filter2Morph != 0) // 0.22.0
            o << "filterr " << v.filter1Mix << " " << v.filter2Mix << " " << v.filterBalance << " " << v.filter2Morph << "\n";
        if (v.filterDrive != 0 || v.filterKeytrack != 0 || v.filterMorph != 0) // 0.21.0
            o << "filterx " << v.filterDrive << " " << v.filterKeytrack << " " << v.filterMorph << "\n";
        if (v.osc1Warp2Mode != 0 || v.osc1Warp2 != 0 || v.osc2Warp2Mode != 0 || v.osc2Warp2 != 0) // 0.19.0
            o << "warpx " << v.osc1Warp2Mode << " " << v.osc1Warp2 << " " << v.osc2Warp2Mode << " " << v.osc2Warp2 << "\n";
        for (int k = 0; k < 2; ++k)
            if (!pointsEq(v.remapPoints[k], VoiceParams::kDefaultRemap())) {
                o << "remap " << k << " " << v.remapPoints[k].size();
                for (const auto& p : v.remapPoints[k]) o << " " << p.time << " " << p.value << " " << p.curve;
                o << "\n";
            }
        for (int i = 0; i < 4; ++i) { // 0.18.0
            if (v.lfoCustom[i] || v.lfoPhase[i] != 0 || v.lfoDelay[i] != 0 || v.lfoRise[i] != 0 || v.lfoFree[i])
                o << "lfox " << i << " " << (v.lfoCustom[i] ? 1 : 0) << " " << v.lfoPhase[i] << " " << v.lfoDelay[i] << " " << v.lfoRise[i]
                  << " " << (v.lfoFree[i] ? 1 : 0) << "\n";
            if (!pointsEq(v.lfoPoints[i], VoiceParams::kDefaultLfoPoints())) {
                o << "lfopts " << i << " " << v.lfoPoints[i].size();
                for (const auto& p : v.lfoPoints[i]) o << " " << p.time << " " << p.value << " " << p.curve;
                o << "\n";
            }
        }
    }
    static bool pointsEq(const std::vector<MSEG::Point>& a, const std::vector<MSEG::Point>& b) {
        if (a.size() != b.size()) return false;
        for (size_t i = 0; i < a.size(); ++i) if (a[i].time != b[i].time || a[i].value != b[i].value || a[i].curve != b[i].curve) return false;
        return true;
    }
    bool mseg2IsDefault() const {
        const VoiceParams d; const auto& v = voice;
        return v.mseg2Seconds == d.mseg2Seconds && v.mseg2Sync == d.mseg2Sync && v.mseg2Mode == d.mseg2Mode
            && v.mseg2LoopStart == d.mseg2LoopStart && v.mseg2LoopEnd == d.mseg2LoopEnd && pointsEq(v.mseg2Points, d.mseg2Points);
    }

    void writeRoutesAndFX(std::ostringstream& o) const {
        o << "routes " << routes.size() << "\n";
        for (const auto& r : routes) {
            o << "route " << (int)r.source << " " << (int)r.dest << " " << r.amount;
            if (r.curve != 0.0) o << " curve " << r.curve; // 0.16.0, only when set
            if (r.aux >= 0) o << " aux " << r.aux;
            o << "\n";
        }
        o << "chorus " << (fx.chorus.enabled ? 1 : 0) << " " << fx.chorus.rateHz << " "
          << fx.chorus.depthMs << " " << fx.chorus.baseMs << " " << fx.chorus.mix << "\n";
        o << "delay " << (fx.delay.enabled ? 1 : 0) << " " << fx.delay.timeLSec << " "
          << fx.delay.timeRSec << " " << fx.delay.feedback << " " << fx.delay.mix << "\n";
        o << "reverb " << (fx.reverb.enabled ? 1 : 0) << " " << fx.reverb.decay << " "
          << fx.reverb.damping << " " << fx.reverb.mix << "\n";
    }
};

} // namespace muew
