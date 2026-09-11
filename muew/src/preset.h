#pragma once
#include "synth.h"
#include "fx.h"
#include <cstdio>
#include <cstring>
#include <string>
#include <sstream>

namespace muew {

// Portable preset: voice params, mod routes, and FX settings as flat
// key/value lines. No external format library; round-trips exactly.
struct Preset {
    VoiceParams voice;
    std::vector<ModRoute> routes;
    FXParams fx;

    static constexpr const char* kMagic = "muew-preset 1";

    std::string serialize() const {
        std::ostringstream o;
        o << kMagic << "\n";
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
        o << "routes " << routes.size() << "\n";
        for (const auto& r : routes)
            o << "route " << (int)r.source << " " << (int)r.dest << " " << r.amount << "\n";
        o << "chorus " << (fx.chorus.enabled ? 1 : 0) << " " << fx.chorus.rateHz << " "
          << fx.chorus.depthMs << " " << fx.chorus.baseMs << " " << fx.chorus.mix << "\n";
        o << "delay " << (fx.delay.enabled ? 1 : 0) << " " << fx.delay.timeLSec << " "
          << fx.delay.timeRSec << " " << fx.delay.feedback << " " << fx.delay.mix << "\n";
        o << "reverb " << (fx.reverb.enabled ? 1 : 0) << " " << fx.reverb.decay << " "
          << fx.reverb.damping << " " << fx.reverb.mix << "\n";
        return o.str();
    }

    bool parse(const std::string& text) {
        std::istringstream in(text);
        std::string line;
        if (!std::getline(in, line) || line != kMagic) return false;
        routes.clear();
        while (std::getline(in, line)) {
            std::istringstream ls(line);
            std::string key;
            ls >> key;
            if (key == "osc1Shape") ls >> voice.osc1Shape;
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
        }
        return true;
    }

    bool operator==(const Preset& o) const {
        const auto& a = voice; const auto& b = o.voice;
        bool voiceEq = a.osc1Shape == b.osc1Shape && a.osc2Shape == b.osc2Shape
            && a.osc2Detune == b.osc2Detune && a.osc2Level == b.osc2Level
            && a.filterCutoff == b.filterCutoff && a.filterReso == b.filterReso
            && a.filterMode == b.filterMode
            && a.ampA == b.ampA && a.ampD == b.ampD && a.ampS == b.ampS && a.ampR == b.ampR
            && a.modA == b.modA && a.modD == b.modD && a.modS == b.modS && a.modR == b.modR
            && a.lfo1Rate == b.lfo1Rate && a.lfo1Shape == b.lfo1Shape;
        if (!voiceEq || routes.size() != o.routes.size()) return false;
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
};

} // namespace muew
