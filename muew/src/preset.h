#pragma once
#include "synth.h"
#include "fx.h"
#include <algorithm>
#include <cstdio>
#include <cstring>
#include <string>
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

    bool operator==(const PresetInfo& o) const {
        return name == o.name && category == o.category && author == o.author && tags == o.tags;
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
// Version 1 text still parses; fields it lacks keep their VoiceParams
// defaults, which match how 0.1.x/0.2.0 rendered those presets.
struct Preset {
    PresetInfo info;
    VoiceParams voice;
    std::vector<ModRoute> routes;
    FXParams fx;
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
        writeCore(o);
        o << "lfo2 " << voice.lfo2Rate << " " << voice.lfo2Shape << "\n";
        o << "warp1 " << voice.osc1WarpMode << " " << voice.osc1Warp << "\n";
        o << "warp2 " << voice.osc2WarpMode << " " << voice.osc2Warp << "\n";
        o << "mseg " << voice.mseg1Seconds << " " << (voice.mseg1Loop ? 1 : 0) << " "
          << voice.mseg1Points.size();
        for (const auto& p : voice.mseg1Points) o << " " << p.time << " " << p.value;
        o << "\n";
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
        }
        writeRoutesAndFX(o);
        const FXParams d;
        if (fx.dist.enabled != d.dist.enabled || fx.dist.mode != d.dist.mode || fx.dist.drive != d.dist.drive || fx.dist.mix != d.dist.mix)
            o << "dist " << (fx.dist.enabled ? 1 : 0) << " " << fx.dist.mode << " " << fx.dist.drive << " " << fx.dist.mix << "\n";
        if (fx.eq.enabled != d.eq.enabled || fx.eq.lowDb != d.eq.lowDb || fx.eq.midDb != d.eq.midDb || fx.eq.highDb != d.eq.highDb)
            o << "eq " << (fx.eq.enabled ? 1 : 0) << " " << fx.eq.lowDb << " " << fx.eq.midDb << " " << fx.eq.highDb << "\n";
        if (fx.comp.enabled != d.comp.enabled || fx.comp.amount != d.comp.amount)
            o << "comp " << (fx.comp.enabled ? 1 : 0) << " " << fx.comp.amount << "\n";
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
            else if (key == "routes") { size_t n; ls >> n; } // count is advisory
            else if (key == "route") {
                ModRoute r; int s, d;
                ls >> s >> d >> r.amount;
                // Sources/destinations from a newer build are skipped, not guessed.
                if (ls && (int)routes.size() < kMaxRoutes && s >= 0 && s <= (int)ModRoute::Source::Env3 && d >= 0 && d <= (int)ModRoute::Dest::DistDrive) {
                    r.source = (ModRoute::Source)s; r.dest = (ModRoute::Dest)d;
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
            && a.env3A == b.env3A && a.env3D == b.env3D && a.env3S == b.env3S && a.env3R == b.env3R;
        if (!voiceEq || !(info == o.info) || routes.size() != o.routes.size()) return false;
        for (size_t i = 0; i < a.mseg1Points.size(); ++i)
            if (a.mseg1Points[i].time != b.mseg1Points[i].time
                || a.mseg1Points[i].value != b.mseg1Points[i].value) return false;
        for (size_t i = 0; i < routes.size(); ++i)
            if (routes[i].source != o.routes[i].source || routes[i].dest != o.routes[i].dest
                || routes[i].amount != o.routes[i].amount) return false;
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
            && fa.comp.enabled == fb.comp.enabled && fa.comp.amount == fb.comp.amount;
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

    void writeRoutesAndFX(std::ostringstream& o) const {
        o << "routes " << routes.size() << "\n";
        for (const auto& r : routes)
            o << "route " << (int)r.source << " " << (int)r.dest << " " << r.amount << "\n";
        o << "chorus " << (fx.chorus.enabled ? 1 : 0) << " " << fx.chorus.rateHz << " "
          << fx.chorus.depthMs << " " << fx.chorus.baseMs << " " << fx.chorus.mix << "\n";
        o << "delay " << (fx.delay.enabled ? 1 : 0) << " " << fx.delay.timeLSec << " "
          << fx.delay.timeRSec << " " << fx.delay.feedback << " " << fx.delay.mix << "\n";
        o << "reverb " << (fx.reverb.enabled ? 1 : 0) << " " << fx.reverb.decay << " "
          << fx.reverb.damping << " " << fx.reverb.mix << "\n";
    }
};

} // namespace muew
