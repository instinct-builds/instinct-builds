#pragma once
#include "synth.h"
#include "fx.h"
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
//                  0.17.0 adds optional `msegcurve`, `msegx` and `mseg2` lines.
//                  0.18.0 adds optional `lfox <i> <custom> <phase> <delay> <rise> <free>`
//                  and `lfopts <i> <n> (<t> <v> <c>)*` lines (drawn LFO shapes).
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
            if (v.filter2Type != d.filter2Type || v.filter2Cutoff != d.filter2Cutoff || v.filter2Reso != d.filter2Reso || v.filterRouting != d.filterRouting)
                o << "filter2 " << v.filter2Type << " " << v.filter2Cutoff << " " << v.filter2Reso << " " << v.filterRouting << "\n";
            for (int t = 0; t < 2; ++t) {
                if (tables[t].empty()) continue;
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
            else if (key == "filterMode") ls >> voice.filterMode;
            else if (key == "amp") ls >> voice.ampA >> voice.ampD >> voice.ampS >> voice.ampR;
            else if (key == "mod") ls >> voice.modA >> voice.modD >> voice.modS >> voice.modR;
            else if (key == "lfo1Rate") ls >> voice.lfo1Rate;
            else if (key == "lfo1Shape") ls >> voice.lfo1Shape;
            else if (key == "lfo2") ls >> voice.lfo2Rate >> voice.lfo2Shape;
            else if (key == "warp1") ls >> voice.osc1WarpMode >> voice.osc1Warp;
            else if (key == "warp2") ls >> voice.osc2WarpMode >> voice.osc2Warp;
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
                FxOrder ord;
                if (n == kFxUnits && ord.assign(v, n)) fx.order = ord;
            }
            else if (key == "routes") { size_t n; ls >> n; } // count is advisory
            else if (key == "route") {
                ModRoute r; int s, d;
                ls >> s >> d >> r.amount;
                // Sources/destinations from a newer build are skipped, not guessed.
                if (ls && (int)routes.size() < kMaxRoutes && s >= 0 && s <= (int)ModRoute::Source::MSEG2 && d >= 0 && d <= (int)ModRoute::Dest::FxChorusDepth) {
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
            // Unknown keys are ignored so minor additions stay loadable.
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
            && a.noiseLevel == b.noiseLevel && a.noiseTone == b.noiseTone
            && a.filter2Type == b.filter2Type && a.filter2Cutoff == b.filter2Cutoff && a.filter2Reso == b.filter2Reso
            && a.filterRouting == b.filterRouting
            && tables[0] == o.tables[0] && tables[1] == o.tables[1];
        if (!voiceEq || !(info == o.info) || routes.size() != o.routes.size()) return false;
        if (!pointsEq(a.mseg1Points, b.mseg1Points) || !pointsEq(a.mseg2Points, b.mseg2Points)) return false;
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
