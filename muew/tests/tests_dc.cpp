// tests_dc.cpp - 0.12.0 DC blocker: oscillator settings that can carry a DC
// offset (BEND+/BEND-/PWM warp above 0, the PULSE shape, user tables) come out
// centred; everything else never runs the blocker.
#include "../src/preset.h"
#include "../src/factory_bank.h"
#include <cmath>
#include <cstdio>
#include <vector>

using namespace muew;
static int g_fail = 0;
static void check(bool c, const std::string& n) { printf("%s %s\n", c ? "ok:  " : "FAIL:", n.c_str()); if (!c) ++g_fail; }

struct Stats { double dc, ac; bool on; };
static Stats run(const VoiceParams& p, const std::vector<ModRoute>& routes, const TableFrames* t1 = nullptr) {
    Wavetable wt; Voice v; v.init(44100, &wt);
    CustomTable ct(t1 ? *t1 : TableFrames{});
    if (t1) v.setCustomTables(&ct, nullptr);
    v.setParams(p, routes); v.noteOn(57, 0.9f);
    double m = 0, s2 = 0; int n = 0;
    for (int i = 0; i < 44100; ++i) {
        float l, r; v.processStereo(l, r);
        if (i >= 11025) { m += l; s2 += l * l; ++n; }
    }
    m /= n;
    return {std::fabs(m), std::sqrt(std::max(0.0, s2 / n - m * m)), v.dcBlockerOn()};
}

int main() {
    VoiceParams saw; saw.osc1Shape = 2; saw.osc2Level = 0; saw.filterCutoff = 18000; saw.ampS = 1;
    Stats clean = run(saw, {});
    check(!clean.on, "a clean saw never engages the blocker");
    VoiceParams bend = saw; bend.osc1WarpMode = 3; bend.osc1Warp = 0.8;
    Stats b = run(bend, {});
    check(b.on && b.dc < 0.01 * b.ac, "BEND- saw comes out centred");
    VoiceParams zero = saw; zero.osc1WarpMode = 4; zero.osc1Warp = 0;
    check(!run(zero, {}).on, "PWM at amount 0 is untouched");
    std::vector<ModRoute> lfoWarp{{ModRoute::Source::LFO1, ModRoute::Dest::Osc1Warp, 0.6}};
    VoiceParams mod = zero; mod.lfo1Rate = 3;
    Stats m = run(mod, lfoWarp);
    check(m.on && m.dc < 0.02 * m.ac, "PWM driven by an LFO engages the blocker and stays centred");
    VoiceParams pulse = saw; pulse.osc1Shape = 4;
    Stats pu = run(pulse, {});
    check(pu.on && pu.dc < 0.01 * pu.ac, "PULSE shape comes out centred");
    VoiceParams quiet = saw; quiet.osc2Shape = 4; quiet.osc2Level = 0;
    check(!run(quiet, {}).on, "a silent osc B never engages the blocker");
    TableFrames offset{std::vector<float>(kFrameSize, 0.0f)};
    for (int i = 0; i < kFrameSize; ++i) offset[0][i] = 0.5f + 0.4f * (float)std::sin(2 * M_PI * i / kFrameSize);
    VoiceParams user = saw; user.osc1Shape = kCustomShape;
    Stats u = run(user, {}, &offset);
    check(u.on && u.dc < 0.01 * u.ac, "a user table drawn above the centre line comes out centred");

    // Factory sounds: every preset that can carry DC is now centred.
    int fixed = 0, unaffected = 0; bool centred = true;
    for (const auto& p : factoryPresets()) {
        Stats s = run(p.voice, p.routes, p.tables[0].empty() ? nullptr : &p.tables[0]);
        if (s.on) { ++fixed; if (s.dc > 0.03 * s.ac + 1e-4) { centred = false; printf("  %s dc %.4f ac %.4f\n", p.info.name.c_str(), s.dc, s.ac); } }
        else ++unaffected;
    }
    printf("blocker engaged on %d factory presets, idle on %d\n", fixed, unaffected);
    check(centred && fixed >= 10 && unaffected >= 50, "DC-prone factory presets are centred; the rest never run the blocker");

    if (g_fail == 0) { printf("\nALL DC TESTS PASSED\n"); return 0; }
    printf("\n%d DC TEST(S) FAILED\n", g_fail); return 1;
}
