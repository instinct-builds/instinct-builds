#include <algorithm>
// tests_bank.cpp - factory preset bank: schema v2 round-trips, v1 presets
// still load unchanged, the embedded bank matches the authored files in AU
// order, browser filtering works, and every preset renders bounded,
// non-silent audio with real modulation.
#include "../src/synth.h"
#include "../src/preset_bank.h"
#include "../src/factory_bank.h"
#include <cstdio>
#include <cmath>
#include <fstream>
#include <map>
#include <set>

using namespace muew;

static int g_fail = 0;
static void check(bool cond, const char* name) {
    if (cond) printf("ok:   %s\n", name);
    else { printf("FAIL: %s\n", name); ++g_fail; }
}
static void check(bool cond, const std::string& name) { check(cond, name.c_str()); }

static std::string readFile(const std::string& path) {
    std::ifstream f(path); std::ostringstream ss; ss << f.rdbuf(); return ss.str();
}

struct RenderStats { bool finite = true; double peak = 0, rms = 0, lateRms = 0; };

static RenderStats render(const Preset& p, int note, double seconds) {
    const int sr = 44100, frames = (int)(sr * seconds);
    Synth synth(16);
    synth.init(sr);
    synth.setParams(p.voice, p.routes);
    synth.setFX(p.fx);
    synth.noteOn(note, 0.9f);
    std::vector<float> buf(frames * 2);
    synth.renderStereo(buf.data(), frames);
    RenderStats st; double late = 0; int lateN = 0;
    for (size_t i = 0; i < buf.size(); ++i) {
        float s = buf[i];
        if (!std::isfinite(s)) st.finite = false;
        st.peak = std::max(st.peak, (double)std::fabs(s));
        st.rms += s * s;
        if (i >= buf.size() / 2) { late += s * s; ++lateN; }
    }
    st.rms = std::sqrt(st.rms / buf.size());
    st.lateRms = std::sqrt(late / std::max(1, lateN));
    return st;
}

int main() {
    std::string err;
    PresetBank bank;
    check(bank.loadManifest("presets", err), "factory bank loads in manifest order: " + err);
    check(bank.size() >= 38 && bank.size() <= 128, "factory bank ships 38-128 presets");
    check((int)bank.size() == kFactoryPresetCount, "embedded bank has the same count as the files");

    // Legacy AU numbers 0-7 keep their original sounds and slugs.
    const char* legacy[] = {"airy-strings", "bright-lead", "init-saw", "pluck",
                            "punchy-bass", "soft-keys", "sub-bass", "warm-pad"};
    bool legacyOrder = bank.size() >= 8;
    for (int i = 0; legacyOrder && i < 8; ++i)
        legacyOrder = bank.presets()[i].name == legacy[i];
    check(legacyOrder, "AU factory numbers 0-7 keep their 0.2.0 presets");

    // Embedded text is byte-identical to the authored files, in order.
    bool embedded = true;
    for (int i = 0; i < kFactoryPresetCount && i < (int)bank.size(); ++i) {
        if (bank.presets()[i].name != kFactoryPresetTexts[i].slug
            || readFile(bank.presets()[i].path) != kFactoryPresetTexts[i].text) {
            printf("      embedded mismatch at %d (%s); run scripts/embed_factory_bank.py\n",
                   i, kFactoryPresetTexts[i].slug);
            embedded = false;
        }
    }
    check(embedded, "src/factory_bank.h matches presets/ exactly");
    check(factoryPresets().size() == bank.size(), "embedded bank parses every preset");

    // Every file is schema v2 and re-serializes to its exact on-disk text.
    bool allRoundTrip = true, allV2 = true, allMeta = true, catsKnown = true;
    std::set<std::string> names, cats(factoryCategories().begin(), factoryCategories().end());
    std::map<std::string, int> perCat;
    for (const auto& np : bank.presets()) {
        const std::string disk = readFile(np.path);
        Preset p;
        if (!p.parse(disk) || p.serialize() != disk) {
            printf("      round-trip mismatch in %s\n", np.path.c_str());
            allRoundTrip = false;
        }
        if (p.version != 2) allV2 = false;
        if (p.info.name.empty() || p.info.author.empty() || p.info.tags.empty()
            || !names.insert(p.info.name).second) allMeta = false;
        if (!cats.count(p.info.category)) { catsKnown = false; printf("      unknown category in %s\n", np.name.c_str()); }
        perCat[p.info.category]++;
    }
    check(allRoundTrip, "every preset file round-trips exactly");
    check(allV2, "every factory preset uses schema v2");
    check(allMeta, "every preset has a unique display name, author and tags");
    check(catsKnown, "every preset uses a browser category");
    bool everyCat = true;
    for (const auto& c : factoryCategories()) if (perCat[c] < 2) everyCat = false;
    check(everyCat, "every browser category has at least two presets");

    // Version 1 compatibility: the 0.2.0 warm-pad text loads, keeps its
    // values, defaults the new fields, and matches the v2 factory sound.
    Preset v1;
    check(v1.parse(readFile("tests/fixtures/legacy-v1-warm-pad.muew")) && v1.version == 1,
          "schema v1 preset still parses");
    VoiceParams defaults;
    check(v1.voice.osc1WarpMode == 0 && v1.voice.osc1Warp == 0 && v1.voice.lfo2Rate == defaults.lfo2Rate
          && v1.voice.mseg1Points.size() == defaults.mseg1Points.size() && v1.info.name.empty(),
          "v1 preset leaves new fields at their defaults");
    check(v1.serializeV1() == readFile("tests/fixtures/legacy-v1-warm-pad.muew"),
          "v1 writer still reproduces the legacy file");
    const NamedPreset* pad = bank.get("warm-pad");
    if (pad) {
        Preset stripped = pad->preset; stripped.info = PresetInfo{}; stripped.version = 1;
        // 0.6 macro routes are silent while the macros sit at 0 (the preset
        // default), so they are not part of the authored sound.
        stripped.routes.erase(std::remove_if(stripped.routes.begin(), stripped.routes.end(),
            [](const ModRoute& r) { return (int)r.source >= (int)ModRoute::Source::Macro1; }), stripped.routes.end());
        // 0.6 also gives clean oscillators a warp mode for the WARP macro;
        // at warp amount 0 every such mode is the clean waveform.
        if (stripped.voice.osc1Warp == 0) stripped.voice.osc1WarpMode = 0;
        if (stripped.voice.osc2Warp == 0) stripped.voice.osc2WarpMode = 0;
        check(stripped == v1, "warm-pad sounds identical in v1 and v2 form");
        auto render = [](const Preset& pr) {
            Synth s(4); s.init(44100); s.setParams(pr.voice, pr.routes); s.setFX(pr.fx);
            s.noteOn(57, 0.8f);
            std::vector<float> l(44100), r(44100);
            s.renderPlanar(l.data(), r.data(), 44100);
            return l;
        };
        check(render(pad->preset) == render(v1), "warm-pad renders sample-identical to the 0.2.0 file");
    } else check(false, "warm-pad is in the bank");
    check(!Preset().parse("muew-preset 9\nname x\n"), "unknown future version is refused");
    Preset badMseg;
    check(!badMseg.parse("muew-preset 2\nmseg 1 0 3 0 0 1\n"), "truncated MSEG points are refused");

    // New schema fields survive a round-trip.
    Preset custom;
    custom.info = {"Test Tone", "Lead", "MUEW Factory", {"a", "b"}};
    custom.voice.osc1WarpMode = 6; custom.voice.osc1Warp = 0.42;
    custom.voice.osc2WarpMode = 1; custom.voice.osc2Warp = 0.17;
    custom.voice.lfo2Rate = 1.25; custom.voice.lfo2Shape = 3;
    custom.voice.mseg1Seconds = 2.5; custom.voice.mseg1Loop = true;
    custom.voice.mseg1Points = {{0, -1}, {0.4, 0.5}, {1, 0}};
    custom.routes = {{ModRoute::Source::MSEG1, ModRoute::Dest::Osc2Warp, 0.3}};
    Preset back;
    check(back.parse(custom.serialize()) && back == custom, "warp, LFO2, MSEG and metadata round-trip");

    // Browser filtering.
    std::set<std::string> favs{"night-bloom", "sub-bass"};
    auto count = [&](const PresetFilter& f) {
        int n = 0;
        for (const auto& np : bank.presets()) if (presetMatches(np.preset, np.name, f, favs)) ++n;
        return n;
    };
    check(count({}) == (int)bank.size(), "empty filter shows the whole bank");
    check(count({"Bass", "", false}) == perCat["Bass"], "category filter matches category count");
    check(count({"", "NIGHT BLOOM", false}) == 1, "search matches names case-insensitively");
    check(count({"", "fold", false}) >= 2, "search matches tags");
    check(count({"", "", true}) == 2, "favorites filter shows only favorites");
    check(count({"Pad", "", true}) == 1, "favorites combine with category");
    check(count({"", "zzzz", false}) == 0, "no-match search is empty");

    // Every preset renders finite, bounded, non-silent audio; sustaining
    // presets are still sounding halfway through a held note.
    for (const auto& np : bank.presets()) {
        for (int note : {36, 60, 84}) {
            RenderStats st = render(np.preset, note, 1.0);
            check(st.finite && st.peak <= 1.0 && st.rms > 0.001,
                  "preset '" + np.name + "' note " + std::to_string(note) + " finite, bounded, non-silent"
                  + " (peak " + std::to_string(st.peak) + ", rms " + std::to_string(st.rms) + ")");
        }
    }

    // Modulation in the new bank is audible: a preset driven by MSEG
    // renders differently with its routes removed.
    for (const char* slug : {"night-bloom", "chrome-motion", "bent-circuit", "laser-drop"}) {
        const NamedPreset* np = bank.get(slug);
        if (!np) { check(false, std::string(slug) + " is in the bank"); continue; }
        Preset flat = np->preset; flat.routes.clear();
        RenderStats a = render(np->preset, 60, 1.0), b = render(flat, 60, 1.0);
        check(std::fabs(a.rms - b.rms) > 1e-4, std::string(slug) + " modulation changes the sound");
    }

    if (g_fail == 0) { printf("\nALL BANK TESTS PASSED\n"); return 0; }
    printf("\n%d BANK TEST(S) FAILED\n", g_fail);
    return 1;
}
