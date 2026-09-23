#pragma once
#include "synth.h"
#include "fx.h"
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
        writeRoutesAndFX(o);
        return o.str();
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
            else if (key == "routes") { size_t n; ls >> n; } // count is advisory
            else if (key == "route") {
                ModRoute r; int s, d;
                ls >> s >> d >> r.amount;
                r.source = (ModRoute::Source)s; r.dest = (ModRoute::Dest)d;
                routes.push_back(r);
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
            && a.mseg1Points.size() == b.mseg1Points.size();
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
            && fa.reverb.damping == fb.reverb.damping && fa.reverb.mix == fb.reverb.mix;
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
