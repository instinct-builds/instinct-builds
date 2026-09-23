// 0.21.0 filter 1 models: SVF modes unchanged, LADDER 24, COMB +/-, MORPH, drive, keytrack, presets.
#include "../src/filter.h"
#include "../src/preset.h"
#include "../src/synth.h"
#include "../src/ui_model.h"
#include <cstdio>
#include <cmath>
using namespace muew;
static int g_fail = 0;
static void check(bool ok, const char* what) { printf("%s %s\n", ok ? "ok:  " : "FAIL:", what); if (!ok) g_fail = 1; }
static double gainAt(Filter1 f, double hz, double amp = 0.1, double sr = 44100) { // steady-state peak gain of a sine
    f.reset(); double pk = 0; const int n = 12000;
    for (int i = 0; i < n; ++i) { float y = f.process((float)(amp * std::sin(2 * M_PI * hz * i / sr))); if (i > n - 3000) pk = std::max(pk, (double)std::fabs(y)); }
    return pk / amp;
}
static double db(double g) { return 20 * std::log10(g + 1e-9); }

int main() {
    { // SVF modes are sample-identical to SVFilter with drive 0
        bool same = true;
        for (int m = 0; m < 5 && same; ++m) {
            SVFilter a; Filter1 b; a.setSampleRate(44100); b.setSampleRate(44100);
            a.setMode((SVFilter::Mode)m); b.setMode(m); b.setDrive(0);
            unsigned s = 7;
            for (int i = 0; i < 4000; ++i) {
                double c = 300 + 2000 * (i % 500) / 500.0; a.set(c, 3.0); b.set(c, 3.0);
                s = s * 1664525u + 1013904223u; float x = (float)((s >> 8) / 8388608.0 - 1.0);
                if (a.process(x) != b.process(x)) { same = false; break; }
            }
        }
        check(same, "LP/BP/HP/NOTCH/PEAK with DRIVE 0 are sample-identical to the 0.20.0 filter");
    }
    { // ladder
        Filter1 f; f.setSampleRate(44100); f.setMode(5); f.set(1000, 0.7);
        double lo = gainAt(f, 100), at4 = gainAt(f, 4000), at8 = gainAt(f, 8000);
        printf("ladder: 100 Hz %.1f dB, 4 kHz %.1f dB, 8 kHz %.1f dB\n", db(lo), db(at4), db(at8));
        check(std::fabs(db(lo)) < 3.0, "LADDER passes the lows at about unity");
        check(db(at4) < -30 && db(at8) - db(at4) < -18, "LADDER falls about 24 dB per octave above the cutoff");
        Filter1 r = f; r.set(1000, 12);
        double pk = gainAt(r, 1000, 0.05), off = gainAt(r, 300, 0.05);
        check(pk > 2.0 * off, "LADDER resonance peaks at the cutoff");
        Filter1 d = f; d.setDrive(1); d.set(1000, 12);
        double mx = 0; d.reset(); for (int i = 0; i < 20000; ++i) mx = std::max(mx, (double)std::fabs(d.process((float)std::sin(2 * M_PI * 220 * i / 44100.0))));
        check(std::isfinite(mx) && mx < 3.0, "full DRIVE into high resonance stays bounded");
    }
    { // combs
        Filter1 p; p.setSampleRate(44100); p.setMode(6); p.set(441, 8);
        Filter1 n = p; n.setMode(7); n.set(441, 8);
        double pPeak = gainAt(p, 882), pDip = gainAt(p, 661.5), nPeak = gainAt(n, 661.5), nDip = gainAt(n, 882);
        printf("comb+: 882 Hz %.1f dB, 661.5 Hz %.1f dB; comb-: 661.5 Hz %.1f dB, 882 Hz %.1f dB\n", db(pPeak), db(pDip), db(nPeak), db(nDip));
        check(pPeak > 5 * pDip, "COMB + peaks at whole multiples of the cutoff");
        check(nPeak > 5 * nDip, "COMB - peaks halfway between them");
    }
    { // morph
        Filter1 f; f.setSampleRate(44100); f.setMode(8); f.set(1000, 0.7);
        f.setMorph(0); double lpLo = gainAt(f, 100), lpHi = gainAt(f, 8000);
        f.setMorph(1); double hpLo = gainAt(f, 100), hpHi = gainAt(f, 8000);
        f.setMorph(0.5); double bpC = gainAt(f, 1000), bpLo = gainAt(f, 100);
        check(lpLo > 10 * lpHi && hpHi > 10 * hpLo, "MORPH 0 is low pass, MORPH 1 is high pass");
        check(std::fabs(db(bpC)) < 1.5 && bpLo < 0.3, "MORPH 0.5 is a unity-peak band pass");
    }
    { // keytrack through a voice: note 72 vs 48 with KEYTRACK 100% moves the cutoff two octaves
        auto bright = [](int note, double kt) {
            Preset p; p.voice.osc1Shape = 2; p.voice.osc2Level = 0; p.voice.filterCutoff = 600; p.voice.filterReso = 0.7;
            p.voice.filterMode = 5; p.voice.filterKeytrack = kt;
            Synth s; s.init(44100); s.setParams(p.voice, p.routes); s.setFX(p.fx);
            s.noteOn(note, 0.8f);
            std::vector<float> L(20000), R(20000); s.renderPlanar(L.data(), R.data(), 20000);
            double hf = 0, e = 0; for (int i = 10001; i < 20000; ++i) { hf += (L[i] - L[i - 1]) * (L[i] - L[i - 1]); e += L[i] * L[i]; }
            return hf / (e + 1e-12) / std::pow(midiToFreq(note), 2);
        };
        double r0 = bright(72, 0) / bright(48, 0), r1 = bright(72, 1) / bright(48, 1);
        printf("keytrack: brightness ratio high/low note %.3f (0%%) vs %.3f (100%%)\n", r0, r1);
        check(r1 > 1.5 * r0 && r1 > 0.75 && r1 < 1.33, "KEYTRACK 100% moves the cutoff with the note (tone stays even across two octaves)");
    }
    { // presets, destinations, names
        Preset p; p.voice.filterMode = 8; p.voice.filterDrive = 0.25; p.voice.filterKeytrack = 0.5; p.voice.filterMorph = 0.75;
        p.routes.push_back({ModRoute::Source::LFO1, ModRoute::Dest::FilterMorph, 0.5});
        std::string txt = p.serialize();
        Preset q; bool ok = q.parse(txt);
        check(ok && q == p && txt.find("\nfilterx 0.25 0.5 0.75\n") != std::string::npos, "filterx line and a FILTER MORPH route survive save and load");
        Preset d; check(d.serialize().find("filterx") == std::string::npos, "a sound without the new settings writes no filterx line");
        Preset bad; bad.parse(d.serialize() + "filterMode 42\n"); check(bad.voice.filterMode == kFilterModes - 1, "out-of-range filter modes clamp");
        check((int)ModRoute::Dest::FilterDrive == 23 && (int)ModRoute::Dest::FilterMorph == 24, "FILTER DRIVE / MORPH destinations are appended");
        check(std::string(ui::filterModeName(5)) == "LADDER 24" && std::string(ui::filterModeName(8)) == "MORPH", "new models have names");
        check(!ui::isFxDest(ModRoute::Dest::FilterDrive) && !ui::isFxDest(ModRoute::Dest::FilterMorph), "filter destinations are per-voice");
    }
    printf(g_fail ? "FAILED\n" : "ALL PASS\n");
    return g_fail;
}
