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

    // ---- 0.26.0 host bar grid ----
    {
        double st, ln;
        check(arp::gridStep(0.0, 3, 0) == 0 && arp::gridStep(0.26, 3, 0, &st, &ln) == 1 && std::fabs(st - 0.25) < 1e-12 && std::fabs(ln - 0.25) < 1e-12
              && arp::gridStep(4.0, 3, 0) == 16 && arp::gridStep(-0.1, 3, 0) == -1, "grid steps follow the host beat (1/16)");
        check(arp::gridStep(0.3, 3, 0.5, &st, &ln) == 0 && arp::gridStep(0.38, 3, 0.5, &st, &ln) == 1 && std::fabs(st - 0.375) < 1e-12 && std::fabs(ln - 0.125) < 1e-12,
              "swung grid: even steps 75%, odd steps 25% of a pair");
    }
    // Render with the host calling setTransport every 512 samples from `beat0`.
    auto hostRun = [](Synth& s, double beat0, int samples, bool playing, std::vector<int>* starts, std::vector<int>* notes) {
        for (int t = 0; t < samples; t += 512) {
            s.setTransport(beat0 + t * 120.0 / 60.0 / 44100.0, playing);
            for (int i = 0; i < 512 && t + i < samples; ++i) {
                render(s, 1);
                if (s.arpPosition() == 1) { if (starts) starts->push_back(t + i); if (notes) notes->push_back(s.arpSoundingNote()); }
            }
        }
    };
    VoiceParams sp = ap; sp.clockSync = true;
    {
        Synth s; make(s, sp); s.setTransport(0.1, true); s.noteOn(60, 0.8f); s.noteOn(64, 0.8f);
        std::vector<int> st, nt; hostRun(s, 0.1, 44100, true, &st, &nt);
        // First step at once (60% of it left), then every grid line: beat 0.25 = sample 3307.5
        bool grid = st.size() >= 8 && st[0] == 0;
        for (size_t i = 1; grid && i < 8; ++i) grid = std::abs(st[i] - (int)std::llround((0.25 * i - 0.1) * 22050)) <= 1;
        printf("sync starts: "); for (size_t i = 0; i < 6 && i < st.size(); ++i) printf("%d ", st[i]); printf("\n");
        check(s.hostLocked() && grid && nt.size() >= 4 && nt[0] == 60 && nt[1] == 64 && nt[2] == 60, "clock sync: steps land on the host's 1/16 lines, not on the key press");
        check(st.size() == 8 || std::abs((int)st.size() - 8) <= 1, "no double steps across host block updates");
    }
    {
        Synth s; make(s, sp); s.setTransport(0.22, true); s.noteOn(60, 0.8f);
        std::vector<int> st; hostRun(s, 0.22, 8000, true, &st, nullptr);
        check(!st.empty() && std::abs(st[0] - (int)std::llround(0.03 * 22050)) <= 1, "a key pressed in the last quarter of a step waits for the next grid line");
    }
    {
        Synth a; make(a, sp); Synth b; make(b, ap);
        a.noteOn(60, 0.8f); b.noteOn(60, 0.8f);
        std::vector<int> sa, sb; hostRun(a, 3.3, 30000, false, &sa, nullptr);
        played(b, (int)sa.size(), &sb);
        check(!a.hostLocked() && sa == sb, "transport stopped: the free clock runs exactly as without sync");
    }
    {
        Synth s; make(s, sp); s.setTransport(7.0, true); s.noteOn(60, 0.8f);
        std::vector<int> st; hostRun(s, 7.0, 44100, true, &st, nullptr);
        const int before = (int)st.size();
        s.setTransport(0.0, false); std::vector<int> st2; played(s, 3, &st2);
        check(before > 4 && st2.size() == 3 && !s.hostLocked(), "stopping the transport falls back to the free clock without a stall");
    }
    // ---- 0.26.0 step pattern ----
    {
        VoiceParams v = ap; v.arpPatOn = true; v.arpPatLen = 4; v.arpGate = 0.5;
        v.arpPatKind[0] = arp::StepOn; v.arpPatKind[1] = arp::StepTie; v.arpPatKind[2] = arp::StepRest; v.arpPatKind[3] = arp::StepOn;
        v.arpPatVel[3] = 40;
        Synth s; make(s, v); s.noteOn(60, 1.0f); s.noteOn(64, 1.0f); s.noteOn(67, 1.0f);
        std::vector<int> nt, cells;
        for (int t = 0; t < 44100 && nt.size() < 8; ++t) {
            render(s, 1);
            if (s.arpPosition() == 1) { nt.push_back(s.arpSoundingNote()); cells.push_back(s.arpPatternStep()); }
            if (s.arpPosition() == 5000 && nt.size() == 1) check(s.arpSoundingNote() == 60, "a step before a TIE holds past its gate");
        }
        printf("pattern: "); for (size_t i = 0; i < nt.size(); ++i) printf("%d[%d] ", nt[i], cells[i]); printf("\n");
        check(nt == std::vector<int>({60, 60, -1, 64, 67, 67, -1, 60}), "ON / TIE / REST / ON: ties hold, rests are silent and do not use up notes");
        check(cells == std::vector<int>({0, 1, 2, 3, 0, 1, 2, 3}), "pattern cell follows the step");
        // velocity: step 3 (vel 40) quieter than step 0 (127)
        Synth q; make(q, v); q.noteOn(60, 1.0f);
        std::vector<float> L(44100), R(44100); q.renderPlanar(L.data(), R.data(), 44100);
        auto peak = [&](int a, int b) { float m = 0; for (int i = a; i < b; ++i) m = std::max(m, std::fabs(L[i])); return m; };
        const float p0 = peak(0, 2700), p3 = peak(16540, 16540 + 2700);
        printf("pattern velocity peaks %.3f %.3f\n", p0, p3);
        check(p3 < p0 * 0.8f && p3 > 0.01f, "step velocity scales the note");
    }
    {
        VoiceParams v = ap; v.arpPatOn = true; v.arpPatLen = 3; v.clockSync = true;
        Synth s; make(s, v); s.setTransport(0.0, true); s.noteOn(60, 0.8f);
        std::vector<int> nt; hostRun(s, 0.0, 44100, true, nullptr, &nt);
        Synth s2; make(s2, v); s2.setTransport(0.5, true); s2.noteOn(60, 0.8f);
        render(s2, 1); const int cell = s2.arpPatternStep();
        check(cell == 2 % 3, "synced pattern cells count from the host bar (beat 0.5 = step 2)");
    }
    // ---- 0.26.0 LFO phase lock ----
    {
        VoiceParams v = base; v.clockSync = true; v.lfoFree[0] = true; v.lfoSync[0] = 3; // 1 beat per cycle
        Synth s; make(s, v); s.setTransport(2.25, true); s.noteOn(60, 0.8f);
        const double ph0 = s.voice(0).lfoPhaseOf(0);
        std::vector<float> L(512), R(512); s.renderPlanar(L.data(), R.data(), 512);
        s.setTransport(2.25 + 512 * 2.0 / 44100.0 + 0.5, true); // host jumped half a beat
        const double ph1 = s.voice(0).lfoPhaseOf(0);
        printf("lfo lock %.4f %.4f\n", ph0, ph1);
        check(std::fabs(ph0 - 0.25) < 1e-9 && std::fabs(ph1 - std::fmod(0.25 + 512 * 2.0 / 44100.0 + 0.5, 1.0)) < 1e-9, "synced FREE LFO takes its phase from the host beat");
        VoiceParams w = v; w.clockSync = false;
        Synth f; make(f, w); f.setTransport(2.25, true); f.noteOn(60, 0.8f);
        check(!f.hostLocked() && std::fabs(f.voice(0).lfoPhaseOf(0) - 0.25) > 1e-6, "clock sync off: LFO phases ignore the host");
        FXParams fx; fx.lfo[0].sync = 2; // 2 beats per cycle
        Synth r; make(r, v); r.setFX(fx); r.setTransport(5.0, true);
        check(std::fabs(r.fx_.rackLfoPhase(0) - 0.5) < 1e-9, "synced rack LFO locks to the host beat");
    }
    {
        Preset p; Preset q;
        check(p.serialize().find("\narpx ") == std::string::npos, "default sound writes no arpx line");
        p.voice.clockSync = true; p.voice.arpPatOn = true; p.voice.arpPatLen = 5; p.voice.arpPatVel[4] = 33; p.voice.arpPatKind[2] = arp::StepTie;
        const std::string t = p.serialize();
        check(q.parse(t) && q == p && t.find("\narpx 1 1 5 127 0 127 0 127 2 127 0 33 0") != std::string::npos, "arpx line round-trips");
        Preset r; check(r.parse(Preset().serialize() + "arpx 1 1 99 0 9 300 1\n") && r.voice.arpPatLen == 16 && r.voice.arpPatVel[0] == 1 && r.voice.arpPatKind[0] == 2
                        && r.voice.arpPatVel[1] == 127 && r.voice.arpPatKind[1] == 1 && r.voice.arpPatVel[2] == 127, "arpx line clamps and tolerates short lines");
        Preset d = p; d.voice.arpPatVel[4] = 34; check(!(d == p), "pattern takes part in equality");
    }
    printf(g_fail ? "FAIL: arp\n" : "PASS: arp\n");
    return g_fail;
}
