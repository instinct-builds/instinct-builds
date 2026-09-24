// 0.25.0 arpeggiator: modes, octaves, tempo-synced rate, gate, swing, latch,
// sustain, chord, mono voices, preset line.
#include "../src/preset.h"
#include "../src/synth.h"
#include "../src/arp.h"
#include <cstdio>
#include <cmath>
#include <string>
#include <vector>
using namespace muew;
static int g_fail = 0;
static void check(bool ok, const char* what) { printf("%s %s\n", ok ? "ok:  " : "FAIL:", what); if (!ok) g_fail = 1; }
static void render(Synth& s, int n) { std::vector<float> L(n), R(n); s.renderPlanar(L.data(), R.data(), n); }
static std::vector<int> seqOf(int mode, std::vector<int> pool, int oct) {
    std::array<int, arp::kSeq> out{}; int n = arp::sequence(mode, pool.data(), (int)pool.size(), oct, out);
    return std::vector<int>(out.begin(), out.begin() + n);
}
// Note sounding at the start of each of `steps` steps, stepping sample by sample.
static std::vector<int> played(Synth& s, int steps, std::vector<int>* starts = nullptr) {
    std::vector<int> notes;
    for (int t = 0; (int)notes.size() < steps && t < 44100 * 60; ++t) {
        render(s, 1);
        if (s.arpPosition() == 1) { notes.push_back(s.arpSoundingNote()); if (starts) starts->push_back(t); }
    }
    return notes;
}

int main() {
    check(seqOf(arp::Up, {67, 60, 64}, 2) == std::vector<int>({60, 64, 67, 72, 76, 79}), "UP sorts the pool and climbs the octaves");
    check(seqOf(arp::Down, {67, 60, 64}, 1) == std::vector<int>({67, 64, 60}), "DOWN");
    check(seqOf(arp::UpDown, {67, 60, 64}, 1) == std::vector<int>({60, 64, 67, 64}), "UP/DN does not repeat the ends");
    check(seqOf(arp::UpDown, {60}, 1) == std::vector<int>({60}) && seqOf(arp::UpDown, {60, 64}, 1) == std::vector<int>({60, 64}), "UP/DN with one or two notes");
    check(seqOf(arp::Order, {67, 60, 64}, 2) == std::vector<int>({67, 60, 64, 79, 72, 76}), "ORDER keeps the press order");
    check(arp::stepSamples(44100, 120, 3, 0, 0) == 5513 && arp::stepSamples(44100, 120, 0, 0, 1) == 22050 && arp::stepSamples(44100, 90, 2, 0, 0) == 9800,
          "step lengths follow tempo and rate (1/16, 1/4, 1/8T)");
    check(arp::stepSamples(44100, 120, 3, 0.5, 0) == 8269 && arp::stepSamples(44100, 120, 3, 0.5, 1) == 2756, "swing 75/25 lengthens even and shortens odd steps");
    check(std::string(arp::modeName(arp::Chord)) == "CHORD" && std::string(arp::rateName(4)) == "1/16T", "names");

    VoiceParams base; base.osc1Shape = 0; base.osc2Level = 0; base.filterCutoff = 16000; base.ampA = 0.001; base.ampR = 0.02;
    auto make = [&](Synth& s, const VoiceParams& v) { s.init(44100); s.setTempo(120); s.setParams(v, {}); FXParams fx; s.setFX(fx); };
    { // arp off: nothing changes
        Synth a; make(a, base); a.noteOn(60, 0.8f);
        check(!a.arpOn() && a.arpPoolCount() == 0 && a.activeVoiceCount() == 1, "arp off plays keys directly");
    }
    VoiceParams ap = base; ap.arpOn = true; ap.arpMode = arp::Up; ap.arpRate = 3; ap.arpGate = 0.5;
    { // UP at 1/16, 120 BPM
        Synth s; make(s, ap);
        s.noteOn(67, 0.8f); s.noteOn(60, 0.7f); s.noteOn(64, 0.9f);
        check(s.activeVoiceCount() == 0 && s.arpPoolCount() == 3, "keys fill the pool; nothing sounds until the clock runs");
        std::vector<int> st; auto n = played(s, 7, &st);
        printf("up: "); for (size_t i = 0; i < n.size(); ++i) printf("%d@%d ", n[i], st[i]); printf("\n");
        check(n == std::vector<int>({60, 64, 67, 60, 64, 67, 60}), "UP plays 60 64 67 and repeats");
        bool grid = st.size() == 7; for (size_t i = 0; grid && i < st.size(); ++i) grid = st[i] == (int)std::llround(i * 5512.5);
        Synth lg; make(lg, ap); lg.noteOn(60, 0.8f); std::vector<int> ls; played(lg, 400, &ls);
        check(grid && ls.size() == 400 && ls[399] == (int)std::llround(399 * 5512.5), "steps land on the exact 1/16 grid at 120 BPM (5512.5 samples, no drift)");
        Synth g; make(g, ap); g.noteOn(60, 0.8f); render(g, 2000);
        const int mid = g.arpSoundingNote(); render(g, 1000);
        check(mid == 60 && g.arpSoundingNote() == -1, "gate 50% releases the note half way through the step");
    }
    { // octaves, down, up/down, order
        VoiceParams v = ap; v.arpOctaves = 2;
        Synth s; make(s, v); s.noteOn(60, 0.8f); s.noteOn(64, 0.8f);
        check(played(s, 5) == std::vector<int>({60, 64, 72, 76, 60}), "2 octaves");
        v.arpOctaves = 1; v.arpMode = arp::UpDown;
        Synth u; make(u, v); for (int k : {60, 64, 67}) u.noteOn(k, 0.8f);
        check(played(u, 6) == std::vector<int>({60, 64, 67, 64, 60, 64}), "UP/DN in the engine");
        v.arpMode = arp::Order;
        Synth o; make(o, v); for (int k : {67, 60, 64}) o.noteOn(k, 0.8f);
        check(played(o, 4) == std::vector<int>({67, 60, 64, 67}), "ORDER in the engine");
        v.arpMode = arp::Random;
        Synth r; make(r, v); for (int k : {60, 64, 67}) r.noteOn(k, 0.8f);
        auto rn = played(r, 24); bool inPool = rn.size() == 24; int seen[3] = {};
        for (int k : rn) { inPool = inPool && (k == 60 || k == 64 || k == 67); seen[k == 60 ? 0 : k == 64 ? 1 : 2]++; }
        Synth r2; make(r2, v); for (int k : {60, 64, 67}) r2.noteOn(k, 0.8f);
        check(inPool && seen[0] && seen[1] && seen[2] && played(r2, 24) == rn, "RANDOM stays in the pool, reaches every note and repeats per render");
    }
    { // chord mode: the whole pool each step, octave climbing
        VoiceParams v = ap; v.arpMode = arp::Chord; v.arpOctaves = 2;
        Synth s; make(s, v); for (int k : {60, 64, 67}) s.noteOn(k, 0.8f);
        render(s, 10);
        int c0 = 0; for (int i = 0; i < s.maxVoices(); ++i) if (s.voice(i).isActive() && s.voice(i).note() >= 60 && s.voice(i).note() <= 67) ++c0;
        render(s, 5513);
        int c1 = 0; for (int i = 0; i < s.maxVoices(); ++i) if (s.voice(i).isActive() && s.voice(i).note() >= 72 && s.voice(i).note() <= 79 && s.voice(i).note() != 0) ++c1;
        check(c0 == 3 && c1 == 3, "CHORD plays the held chord, then an octave up");
    }
    { // key up stops, latch keeps, a fresh chord replaces the latched one
        Synth s; make(s, ap); s.noteOn(60, 0.8f); render(s, 100); s.noteOff(60); render(s, 6000);
        check(s.arpPoolCount() == 0 && s.arpSoundingNote() == -1, "without latch the arp stops when the key comes up");
        VoiceParams v = ap; v.arpLatch = true;
        Synth l; make(l, v); l.noteOn(60, 0.8f); l.noteOn(64, 0.8f); l.noteOff(60); l.noteOff(64);
        auto n = played(l, 4);
        check(n == std::vector<int>({60, 64, 60, 64}) && l.arpPoolCount() == 2, "LATCH keeps playing after the keys come up");
        l.noteOn(67, 0.8f); l.noteOn(71, 0.8f);
        check(l.arpPoolCount() == 2 && l.arpPoolNote(0) == 67 && l.arpPoolNote(1) == 71, "a new chord replaces the latched one");
        l.noteOn(74, 0.8f);
        check(l.arpPoolCount() == 3, "keys added while others are held join the chord");
        v.arpLatch = false; l.setParams(v, {}); l.noteOff(67); l.noteOff(71); l.noteOff(74);
        check(l.arpPoolCount() == 0, "turning latch off drops released keys");
    }
    { // sustain pedal holds the pool
        Synth s; make(s, ap); s.setSustain(true); s.noteOn(60, 0.8f); s.noteOn(64, 0.8f); s.noteOff(60); s.noteOff(64);
        auto n = played(s, 3);
        s.setSustain(false); render(s, 6000);
        check(n == std::vector<int>({60, 64, 60}) && s.arpPoolCount() == 0 && s.arpSoundingNote() == -1, "sustain holds the pool; pedal up empties it");
        Synth a; make(a, ap); a.noteOn(60, 0.8f); render(a, 100); a.allNotesOff();
        check(a.arpPoolCount() == 0 && a.arpSoundingNote() == -1, "all notes off stops the arp");
    }
    { // turning the arp on / off while keys are held
        Synth s; make(s, base); s.noteOn(60, 0.8f); s.noteOn(64, 0.8f);
        s.setParams(ap, {});
        check(s.arpOn() && s.arpPoolCount() == 2, "keys held when the arp turns on join the pool");
        auto n = played(s, 2);
        s.setParams(base, {}); render(s, 3000);
        check(n == std::vector<int>({60, 64}) && !s.arpOn() && s.arpPoolCount() == 0 && s.activeVoiceCount() == 0, "turning the arp off stops it cleanly");
    }
    { // tied gate, mono voice
        VoiceParams v = ap; v.arpGate = 1.0; v.voiceMode = 1;
        Synth s; make(s, v); s.noteOn(60, 0.8f); s.noteOn(67, 0.8f);
        render(s, 5000); const int a = s.arpSoundingNote(); const int av = s.activeVoiceCount();
        render(s, 1000); const int b = s.arpSoundingNote();
        check(a == 60 && b == 67 && av == 1 && s.activeVoiceCount() == 1, "gate 100% ties the steps; mono plays one voice");
    }
    { // tempo
        Synth s; make(s, ap); s.setTempo(60); s.noteOn(60, 0.8f); s.noteOn(64, 0.8f);
        std::vector<int> st; played(s, 3, &st);
        check(st.size() == 3 && st[1] == 11025 && st[2] == 22050, "at 60 BPM 1/16 steps are 11025 samples");
    }
    { // swing in the engine
        VoiceParams v = ap; v.arpSwing = 0.5;
        Synth s; make(s, v); s.noteOn(60, 0.8f); s.noteOn(64, 0.8f);
        std::vector<int> st; played(s, 4, &st);
        check(st.size() == 4 && st[1] == 8269 && st[2] == 8269 + 2756 && st[3] == 2 * 8269 + 2756, "swing moves the odd steps late");
    }
    { // preset line
        Preset p; Preset q;
        check(p.serialize().find("\narp ") == std::string::npos, "default sound writes no arp line");
        p.voice.arpOn = true; p.voice.arpMode = arp::UpDown; p.voice.arpOctaves = 3; p.voice.arpRate = 4; p.voice.arpGate = 0.8; p.voice.arpSwing = 0.25; p.voice.arpLatch = true;
        const std::string t = p.serialize();
        check(q.parse(t) && q == p && t.find("\narp 1 2 3 4 0.8 0.25 1\n") != std::string::npos, "arp line round-trips");
        Preset r; check(r.parse(Preset().serialize() + "arp 1 99 9 99 7 3 1\n") && r.voice.arpMode == 5 && r.voice.arpOctaves == 4 && r.voice.arpRate == 6
                        && r.voice.arpGate == 1.0 && r.voice.arpSwing == 0.5, "arp line clamps");
        Preset d = p; d.voice.arpGate = 0.5; check(!(d == p), "arp fields take part in equality");
    }
    printf(g_fail ? "FAIL: arp\n" : "PASS: arp\n");
    return g_fail;
}
