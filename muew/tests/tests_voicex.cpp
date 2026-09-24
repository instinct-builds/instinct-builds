// 0.23.0 voice depth: POLY voice count, MONO / LEGATO with a last-note stack,
// constant-time glide (ALWAYS / LEGATO), unison RANDOM phase, UNI BLEND route.
#include "../src/preset.h"
#include "../src/synth.h"
#include "../src/ui_model.h"
#include "../src/au_params.h"
#include <cstdio>
#include <cmath>
#include <string>
#include <vector>
using namespace muew;
static int g_fail = 0;
static void check(bool ok, const char* what) { printf("%s %s\n", ok ? "ok:  " : "FAIL:", what); if (!ok) g_fail = 1; }
static void run(Synth& s, int n) { std::vector<float> L(n), R(n); s.renderPlanar(L.data(), R.data(), n); }
static std::vector<float> renderL(Synth& s, int n) { std::vector<float> L(n), R(n); s.renderPlanar(L.data(), R.data(), n); return L; }
static bool near(double a, double b, double rel = 1e-6) { return std::fabs(a - b) <= rel * std::fabs(b); }

int main() {
    { // defaults change nothing and are not written
        VoiceParams d;
        check(d.voiceMode == 0 && d.polyVoices == 16 && d.glideTime == 0 && !d.glideLegato && d.uniPhase == 0, "defaults are 16-voice poly, no glide, spread phases");
        Preset p; p.voice = d;
        check(p.serialize().find("\nvoice ") == std::string::npos, "a default preset writes no voice line");
        Preset q = p; q.voice.voiceMode = 2; q.voice.polyVoices = 6; q.voice.glideTime = 0.25; q.voice.glideLegato = true; q.voice.uniPhase = 1;
        Preset r; check(r.parse(q.serialize()) && r == q && r.voice.glideTime == 0.25 && r.voice.voiceMode == 2 && r.voice.polyVoices == 6 && r.voice.glideLegato && r.voice.uniPhase == 1,
                        "voice line round-trips");
        std::string txt = q.serialize();
        size_t at = txt.find("voice 2 6 0.25 1 1");
        check(at != std::string::npos, "voice line format: mode voices glide legato phase");
        txt.replace(at, 18, "voice 9 99 60 1 7");
        Preset c; c.parse(txt);
        check(c.voice.voiceMode == 2 && c.voice.polyVoices == 16 && c.voice.glideTime == 5.0 && c.voice.uniPhase == 1, "out-of-range voice values clamp");
    }
    VoiceParams base; base.osc1Shape = 2; base.osc2Level = 0; base.ampA = 0.001; base.ampR = 0.05;
    { // explicit 16 == default render; POLY voice count limits the pool
        auto render = [&](VoiceParams v) { Synth s; s.init(44100); s.setParams(v, {}); s.noteOn(45, 0.8f); s.noteOn(52, 0.8f); return renderL(s, 8000); };
        VoiceParams e = base; e.polyVoices = 16; e.voiceMode = 0; e.glideTime = 0; e.uniPhase = 0;
        check(render(base) == render(e), "POLY 16 with glide off renders exactly the 0.22.0 path");
        Synth s; s.init(44100); VoiceParams v = base; v.polyVoices = 2; s.setParams(v, {});
        s.noteOn(40, 0.8f); s.noteOn(44, 0.8f); s.noteOn(47, 0.8f); run(s, 64);
        check(s.activeVoiceCount() == 2, "POLY 2 keeps two voices (third note steals the oldest)");
        bool has40 = false; for (int i = 0; i < 2; ++i) if (s.voice(i).note() == 40) has40 = true;
        check(!has40, "the stolen voice was the oldest note");
    }
    { // MONO: one voice, last-note priority, retrigger
        Synth s; s.init(44100); VoiceParams v = base; v.voiceMode = 1; s.setParams(v, {});
        s.noteOn(45, 0.8f); run(s, 2000); s.noteOn(52, 0.8f); run(s, 200);
        check(s.activeVoiceCount() == 1 && s.voice(0).note() == 52, "MONO plays only the newest key");
        check(s.voice(0).age() == 200, "MONO retriggers the envelopes on a new key");
        s.noteOff(52); run(s, 100);
        check(s.voice(0).isActive() && s.voice(0).note() == 45 && s.voice(0).age() == 100, "MONO releases back to the held key with a new attack");
        s.noteOff(45); run(s, 44100);
        check(s.activeVoiceCount() == 0 && s.heldCount() == 0, "MONO voice releases once no key is held");
    }
    { // LEGATO: overlapping keys keep the envelope running
        Synth s; s.init(44100); VoiceParams v = base; v.voiceMode = 2; s.setParams(v, {});
        s.noteOn(45, 0.8f); run(s, 2000); s.noteOn(52, 0.8f); run(s, 200);
        check(s.voice(0).note() == 52 && s.voice(0).age() == 2200, "LEGATO changes pitch without retriggering");
        s.noteOff(52); run(s, 100);
        check(s.voice(0).note() == 45 && s.voice(0).age() == 2300, "LEGATO slides back to the held key without an attack");
        s.noteOff(45); run(s, 44100); s.noteOn(50, 0.8f); run(s, 10);
        check(s.voice(0).age() == 10, "LEGATO retriggers after a gap");
    }
    { // constant-time glide
        Synth s; s.init(44100); VoiceParams v = base; v.voiceMode = 1; v.glideTime = 0.1; s.setParams(v, {});
        s.noteOn(45, 0.8f); run(s, 1000);
        check(near(s.voice(0).currentFreq(), midiToFreq(45)), "first note starts on pitch");
        s.noteOn(57, 0.8f); run(s, 2205);
        const double mid = s.voice(0).currentFreq();
        check(near(mid, midiToFreq(51), 2e-3), "halfway through a 100 ms glide the pitch is halfway in semitones");
        run(s, 2300);
        check(s.voice(0).currentFreq() == midiToFreq(57) && !s.voice(0).gliding(), "the glide lands exactly on the target");
        Synth s2; s2.init(44100); s2.setParams(v, {});
        s2.noteOn(45, 0.8f); run(s2, 1000); s2.noteOn(81, 0.8f); run(s2, 2205);
        check(near(s2.voice(0).currentFreq(), midiToFreq(63), 2e-3), "glide time is constant: a 3-octave slide is also halfway at 50 ms");
    }
    { // ALWAYS vs LEGATO glide, poly
        auto midFreq = [&](bool legatoOnly, bool overlap) {
            Synth s; s.init(44100); VoiceParams v = base; v.glideTime = 0.1; v.glideLegato = legatoOnly; s.setParams(v, {});
            s.noteOn(45, 0.8f); run(s, 1000);
            if (!overlap) { s.noteOff(45); run(s, 200); }
            s.noteOn(57, 0.8f); run(s, 2205);
            for (int i = 0; i < 16; ++i) if (s.voice(i).isActive() && s.voice(i).note() == 57) return s.voice(i).currentFreq();
            return 0.0;
        };
        check(near(midFreq(false, false), midiToFreq(51), 2e-3), "POLY glide ALWAYS slides from the last note even after release");
        check(near(midFreq(true, true), midiToFreq(51), 2e-3), "glide LEGATO slides between overlapping notes");
        check(midFreq(true, false) == midiToFreq(57), "glide LEGATO skips detached notes");
    }
    { // unison phase: RANDOM restarts differently each note; SPREAD repeats
        VoiceParams u = base; u.osc1Unison = 5; u.osc1UniDetune = 0.2;
        auto two = [&](VoiceParams v) {
            Synth s; s.init(44100); s.setParams(v, {});
            s.noteOn(45, 0.8f); auto a = renderL(s, 4000); s.noteOff(45); run(s, 44100);
            s.noteOn(45, 0.8f); auto b = renderL(s, 4000);
            return std::make_pair(a, b);
        };
        auto sp = two(u); u.uniPhase = 1; auto rn = two(u);
        auto maxd = [](const std::vector<float>& a, const std::vector<float>& b) { double m = 0; for (size_t i = 0; i < a.size(); ++i) m = std::max(m, (double)std::fabs(a[i] - b[i])); return m; };
        check(maxd(sp.first, sp.second) < 0.01, "SPREAD phase: every note starts the stack the same way (filter tail aside)");
        check(maxd(rn.first, rn.second) > 0.05, "RANDOM phase: each note starts the stack at new phases");
        Synth x; x.init(44100); x.setParams(u, {}); x.noteOn(45, 0.8f); auto x1 = renderL(x, 4000);
        check(x1 == rn.first, "RANDOM phase is deterministic per session (renders repeat)");
    }
    { // UNI BLEND destination
        check((int)ModRoute::Dest::UnisonBlend == 27 && std::string(ui::destName(ModRoute::Dest::UnisonBlend)) == "UNI BLEND" && !ui::isFxDest(ModRoute::Dest::UnisonBlend),
              "UNI BLEND is appended as per-voice destination 27");
        VoiceParams u = base; u.osc1Unison = 5; u.osc1UniDetune = 0.3; u.uniBlend = 0.2;
        auto render = [&](std::vector<ModRoute> r) { Synth s; s.init(44100); s.setParams(u, r); s.noteOn(45, 0.8f); return renderL(s, 8000); };
        check(render({}) == render({{ModRoute::Source::Macro1, ModRoute::Dest::UnisonBlend, 0.8}}), "a UNI BLEND route at macro 0 changes nothing");
        std::vector<ModRoute> lr = {{ModRoute::Source::LFO1, ModRoute::Dest::UnisonBlend, 0.6}};
        check(render({}) != render(lr), "an LFO on UNI BLEND moves the stack balance");
        Preset p; p.voice = u; p.routes = lr; Preset q; q.parse(p.serialize());
        check(q.routes.size() == 1 && q.routes[0].dest == ModRoute::Dest::UnisonBlend, "UNI BLEND routes survive save/load");
    }
    { // AU parameters 30/31
        Preset p; params::set(p, params::GlideTime, 0.4); params::set(p, params::UnisonBlend, 25);
        check(p.voice.glideTime == 0.4 && p.voice.uniBlend == 0.25, "AU Glide Time / Unison Blend write the sound");
        check(std::string(params::def(params::GlideTime).name) == "Glide Time" && params::defaultValue(params::GlideTime) == 0, "Glide Time defaults to off");
    }
    { // switching mode releases notes and clears the key stack
        Synth s; s.init(44100); s.setParams(base, {}); s.noteOn(45, 0.8f); s.noteOn(49, 0.8f);
        VoiceParams m = base; m.voiceMode = 2; s.setParams(m, {}); run(s, 44100);
        check(s.activeVoiceCount() == 0 && s.heldCount() == 0, "changing POLY to LEGATO releases held voices");
        s.setParams(m, {}); s.noteOn(50, 0.8f); run(s, 10);
        check(s.activeVoiceCount() == 1, "setting the same mode again keeps playing");
    }
    printf(g_fail ? "SOME CHECKS FAILED\n" : "all voice-depth checks passed\n");
    return g_fail;
}
