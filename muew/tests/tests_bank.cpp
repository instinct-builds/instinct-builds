// tests_bank.cpp - factory preset bank: files parse, round-trip exactly,
// names are unique, and every preset renders bounded, non-silent audio.
#include "../src/synth.h"
#include "../src/preset_bank.h"
#include <cstdio>
#include <cmath>
#include <fstream>
#include <set>

using namespace muew;

static int g_fail = 0;
static void check(bool cond, const char* name) {
    if (cond) printf("ok:   %s\n", name);
    else { printf("FAIL: %s\n", name); ++g_fail; }
}
static void check(bool cond, const std::string& name) { check(cond, name.c_str()); }

int main() {
    std::string err;
    PresetBank bank;
    check(bank.loadDir("presets", err), "preset bank directory loads");
    check(bank.size() == 8, "factory bank ships 8 presets");

    std::set<std::string> seen;
    bool unique = true;
    for (const auto& n : bank.names())
        if (!seen.insert(n).second) unique = false;
    check(unique, "preset names are unique");

    // Every file must re-serialize to its exact on-disk text.
    bool allRoundTrip = true;
    for (const auto& np : bank.presets()) {
        std::ifstream f(np.path);
        std::ostringstream ss; ss << f.rdbuf();
        std::string disk = ss.str();
        Preset p;
        if (!p.parse(disk) || p.serialize() != disk) {
            printf("      round-trip mismatch in %s\n", np.path.c_str());
            allRoundTrip = false;
        }
    }
    check(allRoundTrip, "every preset file round-trips exactly");

    check(bank.get("warm-pad") != nullptr, "warm-pad is in the bank");
    check(bank.get("no-such-preset") == nullptr, "missing preset lookup returns null");

    const NamedPreset* pad = bank.get("warm-pad");
    check(pad && pad->preset.fx.reverb.enabled && pad->preset.fx.chorus.enabled,
          "warm-pad uses chorus and reverb");
    const NamedPreset* bass = bank.get("punchy-bass");
    check(bass && !bass->preset.fx.chorus.enabled && !bass->preset.fx.reverb.enabled,
          "punchy-bass leaves the FX off");

    // Every preset renders finite, bounded, non-silent stereo audio.
    const int sr = 44100, frames = sr / 2;
    for (const auto& np : bank.presets()) {
        Synth synth(16);
        synth.init(sr);
        synth.setParams(np.preset.voice, np.preset.routes);
        synth.setFX(np.preset.fx);
        synth.noteOn(60, 0.9f);
        std::vector<float> buf(frames * 2);
        synth.renderStereo(buf.data(), frames);
        bool finite = true, bounded = true;
        double rms = 0.0;
        for (float s : buf) {
            if (!std::isfinite(s)) finite = false;
            if (std::fabs(s) > 1.0f) bounded = false;
            rms += s * s;
        }
        rms = std::sqrt(rms / buf.size());
        check(finite && bounded && rms > 0.001,
              "preset '" + np.name + "' renders finite, bounded, non-silent audio");
    }

    if (g_fail == 0) { printf("\nALL BANK TESTS PASSED\n"); return 0; }
    printf("\n%d BANK TEST(S) FAILED\n", g_fail);
    return 1;
}
