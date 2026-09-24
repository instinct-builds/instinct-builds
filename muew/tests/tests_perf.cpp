// 0.24.0 MIDI performance: MOD WHEEL, AFTERTOUCH (channel + poly), PITCH BEND
// with a range, KEYTRACK sources; sustain pedal; all notes off.
#include "../src/preset.h"
#include "../src/synth.h"
#include "../src/ui_model.h"
#include <cstdio>
#include <cmath>
#include <string>
#include <vector>
using namespace muew;
static int g_fail = 0;
static void check(bool ok, const char* what) { printf("%s %s\n", ok ? "ok:  " : "FAIL:", what); if (!ok) g_fail = 1; }
static std::vector<float> renderL(Synth& s, int n) { std::vector<float> L(n), R(n); s.renderPlanar(L.data(), R.data(), n); return L; }
static int crossings(const std::vector<float>& x, int from) { int c = 0; for (size_t i = from + 1; i < x.size(); ++i) if (x[i - 1] <= 0 && x[i] > 0) ++c; return c; }
using S = ModRoute::Source; using D = ModRoute::Dest;

int main() {
    check((int)S::ModWheel == 15 && (int)S::Aftertouch == 16 && (int)S::PitchBend == 17 && (int)S::Keytrack == 18 && kModSources == 19,
          "performance sources are appended as 15-18");
    check(std::string(ui::sourceBadge(S::ModWheel)) == "WHL" && std::string(ui::sourceBadge(S::Aftertouch)) == "AT" && std::string(ui::sourceBadge(S::PitchBend)) == "PB"
          && std::string(ui::sourceBadge(S::Keytrack)) == "KEY" && std::string(ui::sourceName(S::PitchBend)) == "PITCH BEND", "badges and names");
    check(ui::matrixSources().size() == 19 && ui::matrixSources()[15] == S::ModWheel && ui::matrixSources()[18] == S::Keytrack, "badge order appends the new sources");
    check(!sourceBipolar(15) && !sourceBipolar(16) && sourceBipolar(17) && sourceBipolar(18), "WHL / AT are unipolar, PB / KEY bipolar");

    VoiceParams base; base.osc1Shape = 0; base.osc2Level = 0; base.filterCutoff = 16000; base.ampA = 0.001; base.ampR = 0.05;
    auto make = [&](Synth& s, const VoiceParams& v, std::vector<ModRoute> r = {}) { s.init(44100); s.setParams(v, r); FXParams fx; s.setFX(fx); };
    { // pitch bend
        Synth a; make(a, base); a.noteOn(45, 0.8f); auto ref = renderL(a, 44100);
        Synth b; make(b, base); b.setPitchBend(0.0); b.noteOn(45, 0.8f);
        check(renderL(b, 44100) == ref, "bend at center renders exactly the unbent sound");
        VoiceParams v12 = base; v12.bendRange = 12;
        Synth c; make(c, v12); c.setPitchBend(1.0); c.noteOn(45, 0.8f); auto up = renderL(c, 44100);
        Synth d; make(d, base); d.noteOn(57, 0.8f); auto oct = renderL(d, 44100);
        const int cu = crossings(up, 4410), co = crossings(oct, 4410);
        printf("  bend +12: %d cycles, note 57: %d cycles\n", cu, co);
        check(std::abs(cu - co) <= 1, "full bend up with RANGE 12 plays an octave up");
        Synth e; make(e, base); e.setPitchBend(-1.0); e.noteOn(45, 0.8f); auto dn = renderL(e, 44100);
        Synth f; make(f, base); f.noteOn(43, 0.8f); auto m2 = renderL(f, 44100);
        check(std::abs(crossings(dn, 4410) - crossings(m2, 4410)) <= 1, "full bend down with the default RANGE 2 plays a whole tone down");
        Synth g; make(g, base); g.noteOn(45, 0.8f); renderL(g, 4410); g.setPitchBend(1.0);
        auto late = renderL(g, 44100);
        Synth g2; make(g2, base); g2.noteOn(47, 0.8f); auto tone = renderL(g2, 44100);
        check(std::abs(crossings(late, 0) - crossings(tone, 0)) <= 1, "bend applies to a note that is already sounding");
        VoiceParams v0 = base; v0.bendRange = 0;
        Synth h; make(h, v0); h.setPitchBend(1.0); h.noteOn(45, 0.8f);
        check(std::abs(crossings(renderL(h, 44100), 4410) - crossings(ref, 4410)) <= 1, "RANGE 0 ignores the bend");
    }
    { // mod wheel route
        std::vector<ModRoute> r = {{S::ModWheel, D::FilterCutoff, -4.0}};
        Synth a; make(a, base); a.noteOn(45, 0.8f); auto ref = renderL(a, 8000);
        Synth b; make(b, base, r); b.noteOn(45, 0.8f);
        check(renderL(b, 8000) == ref, "a MOD WHEEL route at wheel 0 changes nothing");
        Synth c; make(c, base, r); c.setModWheel(1.0); c.noteOn(45, 0.8f);
        check(renderL(c, 8000) != ref, "wheel up moves the routed cutoff");
    }
    { // aftertouch: channel vs poly
        VoiceParams v = base; v.osc1Shape = 2;
        std::vector<ModRoute> r = {{S::Aftertouch, D::FilterCutoff, -4.0}};
        Synth a; make(a, v, r); a.noteOn(45, 0.8f); a.setAftertouch(1.0); auto chan = renderL(a, 8000);
        Synth b; make(b, v, r); b.noteOn(45, 0.8f); b.setPolyAftertouch(45, 1.0); auto poly = renderL(b, 8000);
        Synth c; make(c, v, r); c.noteOn(45, 0.8f); c.setPolyAftertouch(52, 1.0); auto other = renderL(c, 8000);
        Synth d; make(d, v, r); d.noteOn(45, 0.8f); auto none = renderL(d, 8000);
        check(poly == chan, "poly aftertouch on a note equals channel pressure for that voice");
        check(other == none && chan != none, "poly aftertouch on another key leaves the voice alone");
        Synth e; make(e, v, r); e.noteOn(45, 0.8f); e.setPolyAftertouch(45, 1.0); renderL(e, 100); e.noteOff(45); renderL(e, 44100); e.noteOn(45, 0.8f);
        check(e.voice(0).isActive() && e.voice(0).polyAftertouch() < 0, "a new note starts without the old poly pressure");
    }
    { // keytrack
        std::vector<ModRoute> r = {{S::Keytrack, D::FilterCutoff, 2.0}};
        VoiceParams v = base; v.osc1Shape = 2; v.filterCutoff = 800;
        Synth a; make(a, v); a.noteOn(60, 0.8f); auto ref = renderL(a, 8000);
        Synth b; make(b, v, r); b.noteOn(60, 0.8f);
        check(renderL(b, 8000) == ref, "KEYTRACK is 0 at C3 (note 60)");
        Synth c; make(c, v); c.noteOn(84, 0.8f); auto hi = renderL(c, 8000);
        Synth d; make(d, v, r); d.noteOn(84, 0.8f);
        check(renderL(d, 8000) != hi, "KEYTRACK opens the routed cutoff above C3");
    }
    { // sustain pedal
        Synth s; make(s, base);
        s.noteOn(45, 0.8f); s.setSustain(true); s.noteOff(45); renderL(s, 44100);
        check(s.activeVoiceCount() == 1, "a released key rings on while the pedal is down");
        s.noteOn(52, 0.8f); s.setSustain(false); renderL(s, 44100);
        check(s.activeVoiceCount() == 1 && s.voice(0).isActive() == false, "pedal up releases the sustained key only");
        bool has52 = false; for (int i = 0; i < 16; ++i) if (s.voice(i).isActive() && s.voice(i).note() == 52) has52 = true;
        check(has52, "the key still held keeps playing after the pedal comes up");
        s.setSustain(true); s.noteOff(52); s.noteOn(52, 0.8f); s.setSustain(false); renderL(s, 4410);
        check(s.activeVoiceCount() == 1, "re-pressing a sustained key keeps it held after pedal up");
        s.allNotesOff(); renderL(s, 44100);
        check(s.activeVoiceCount() == 0 && !s.sustain(), "all notes off releases everything");
        VoiceParams m = base; m.voiceMode = 1;
        Synth t; make(t, m); t.noteOn(45, 0.8f); t.setSustain(true); t.noteOff(45); renderL(t, 22050);
        check(t.activeVoiceCount() == 1, "MONO holds under the pedal too");
        t.setSustain(false); renderL(t, 44100);
        check(t.activeVoiceCount() == 0, "MONO releases on pedal up");
    }
    { // presets
        Preset p; check(p.serialize().find("\nperf ") == std::string::npos, "default bend range writes no perf line");
        p.voice.bendRange = 7; p.routes = {{S::PitchBend, D::Osc2Pitch, 3.0}, {S::ModWheel, D::FilterCutoff, 2.0}};
        p.routes[1].aux = (int)S::Aftertouch;
        Preset q; check(q.parse(p.serialize()) && q == p && q.voice.bendRange == 7 && q.routes.size() == 2 && q.routes[0].source == S::PitchBend
                        && q.routes[1].aux == (int)S::Aftertouch, "perf line and performance routes / aux round-trip");
        std::string t = p.serialize(); t.replace(t.find("perf 7"), 6, "perf 99");
        Preset c; c.parse(t); check(c.voice.bendRange == 24, "bend range clamps to 24");
    }
    printf(g_fail ? "SOME CHECKS FAILED\n" : "all performance checks passed\n");
    return g_fail;
}
