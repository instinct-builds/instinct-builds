// 0.22.0 filter routing + FILTER 2 depth: 2x drive, FILTER 2 LADDER / COMB - / MORPH, per-filter MIX, parallel BALANCE.
#include "../src/filter.h"
#include "../src/layers.h"
#include "../src/preset.h"
#include "../src/synth.h"
#include "../src/ui_model.h"
#include <cstdio>
#include <cmath>
#include <vector>
using namespace muew;
static int g_fail = 0;
static void check(bool ok, const char* what) { printf("%s %s\n", ok ? "ok:  " : "FAIL:", what); if (!ok) g_fail = 1; }
// Energy of the output at frequency f (single-bin DFT) relative to the input amplitude.
static double binGain(const std::vector<float>& y, double f, double amp, double sr = 44100) {
    const int n = (int)y.size(), a = n / 2;
    double re = 0, im = 0;
    for (int i = a; i < n; ++i) { re += y[i] * std::cos(2 * M_PI * f * i / sr); im += y[i] * std::sin(2 * M_PI * f * i / sr); }
    return 2 * std::sqrt(re * re + im * im) / (n - a) / amp;
}
static double db(double g) { return 20 * std::log10(g + 1e-12); }
template <class F> static std::vector<float> run(F& f, double hz, double amp, int n = 16384) {
    std::vector<float> y(n);
    for (int i = 0; i < n; ++i) y[i] = f.process((float)(amp * std::sin(2 * M_PI * hz * i / 44100.0)));
    return y;
}

int main() {
    { // 2x drive: a loud 14 kHz tone through DRIVE aliases far less than at 1x (0.21.0 path)
        auto alias = [](bool os) {
            Filter1 f; f.setSampleRate(44100); f.setMode(0); f.setDrive(0.6); f.setOversample(os); f.set(18000, 0.7);
            std::vector<float> y = run(f, 14000, 0.8);
            // 3rd harmonic 42 kHz folds to 2.1 kHz; 5th (70 kHz) folds to 18.2 kHz -> check the 2.1 kHz fold
            return binGain(y, 44100 - 3 * 14000, 0.8);
        };
        double a1 = alias(false), a2 = alias(true);
        printf("drive alias at 2.1 kHz: 1x %.1f dB, 2x %.1f dB\n", db(a1), db(a2));
        check(db(a2) < db(a1) - 20, "2x oversampled DRIVE cuts the folded 3rd harmonic by more than 20 dB");
        Filter1 f; f.setSampleRate(44100); f.setMode(0); f.setDrive(0.6); f.setOversample(true); f.set(18000, 0.7);
        Filter1 f1 = f; f1.setOversample(false);
        double g = binGain(run(f, 200, 0.05), 200, 0.05), g1 = binGain(run(f1, 200, 0.05), 200, 0.05);
        printf("drive gain at 200 Hz: 1x %.2f dB, 2x %.2f dB\n", db(g1), db(g));
        check(std::fabs(db(g) - db(g1)) < 0.2, "2x DRIVE keeps the 1x tone and level in the audio band");
        Filter1 z; z.setSampleRate(44100); z.setMode(2); z.setOversample(false); z.set(500, 2);
        SVFilter s; s.setSampleRate(44100); s.setMode(SVFilter::Mode::Highpass); s.set(500, 2);
        bool same = true; unsigned r = 3;
        for (int i = 0; i < 3000 && same; ++i) { r = r * 1664525u + 1013904223u; float x = (float)((r >> 8) / 8388608.0 - 1.0); same = z.process(x) == s.process(x); }
        check(same, "without DRIVE the SVF modes stay sample-identical (no oversampling)");
    }
    { // FILTER 2 new types
        auto f2 = [](int t, double c, double q) { Filter2 f; f.setSampleRate(44100); f.setType(t); f.set(c, q); return f; };
        Filter2 lad = f2(6, 1000, 0.7);
        double lo = binGain(run(lad, 100, 0.1), 100, 0.1); lad.reset();
        double hi = binGain(run(lad, 4000, 0.1), 4000, 0.1);
        printf("F2 ladder: 100 Hz %.1f dB, 4 kHz %.1f dB\n", db(lo), db(hi));
        check(std::fabs(db(lo)) < 3 && db(hi) < -30, "FILTER 2 LADDER 24 is a steep low pass");
        Filter2 cn = f2(7, 441, 6);
        double half = binGain(run(cn, 661.5, 0.1), 661.5, 0.1); cn.reset();
        double whole = binGain(run(cn, 882, 0.1), 882, 0.1);
        check(half > 5 * whole, "FILTER 2 COMB - peaks halfway between multiples of the cutoff");
        Filter2 m = f2(8, 1000, 0.7); m.setMorph(0);
        double mlo = binGain(run(m, 100, 0.1), 100, 0.1); m.reset(); m.setMorph(1);
        double mhi = binGain(run(m, 100, 0.1), 100, 0.1);
        check(mlo > 0.8 && mhi < 0.1, "FILTER 2 MORPH moves from low pass (0) to high pass (1)");
        check(std::string(ui::filter2TypeName(6)) == "LADDER 24" && std::string(ui::filter2TypeName(7)) == "COMB -" && std::string(ui::filter2TypeName(8)) == "MORPH",
              "FILTER 2 type names");
    }
    { // voice routing: MIX and BALANCE
        auto render = [](VoiceParams v, std::vector<ModRoute> routes = {}) {
            Synth s; s.init(44100); s.setParams(v, routes); FXParams fx; s.setFX(fx);
            s.noteOn(45, 0.8f);
            std::vector<float> L(12000), R(12000); s.renderPlanar(L.data(), R.data(), 12000);
            return L;
        };
        VoiceParams base; base.osc1Shape = 2; base.osc2Level = 0; base.filterCutoff = 300; base.filterReso = 0.7;
        base.filter2Type = 3; base.filter2Cutoff = 3000; base.filter2Reso = 0.7; base.ampA = 0.001;
        auto rms = [](const std::vector<float>& x) { double e = 0; for (size_t i = 6000; i < x.size(); ++i) e += x[i] * x[i]; return std::sqrt(e / (x.size() - 6000)); };
        auto same = [](const std::vector<float>& a, const std::vector<float>& b) { return a == b; };
        VoiceParams dflt = base; dflt.filterRouting = 1;
        VoiceParams halfBal = dflt; halfBal.filterBalance = 0.5;
        check(same(render(dflt), render(halfBal)), "BALANCE 50% is the 0.10.0 parallel mix exactly");
        VoiceParams b0 = dflt; b0.filterBalance = 0; VoiceParams b1 = dflt; b1.filterBalance = 1;
        VoiceParams only1 = base; only1.filter2Type = 0;
        check(same(render(b0), render(only1)), "BALANCE 0% plays filter 1 alone");
        VoiceParams open = base; open.filter2Type = 0; open.filterCutoff = 300; open.filter1Mix = 0;
        auto hf = [](const std::vector<float>& x) { double e = 0; for (size_t i = 6001; i < x.size(); ++i) e += (x[i] - x[i - 1]) * (x[i] - x[i - 1]); return e; };
        auto mixHalf = base; mixHalf.filter2Type = 0; mixHalf.filter1Mix = 0.5;
        double hOpen = hf(render(open)), hHalf = hf(render(mixHalf)), hWet = hf(render(only1));
        printf("filter 1 MIX: high-frequency energy dry %.3g, 50%% %.3g, wet %.3g\n", hOpen, hHalf, hWet);
        check(hOpen > 10 * hWet && hHalf > hWet && hHalf < hOpen, "filter 1 MIX blends the dry oscillator back in");
        VoiceParams w2 = base; w2.filter2Mix = 0;
        check(same(render(w2), render(only1)), "filter 2 MIX 0% in series equals filter 2 off");
        double r1 = rms(render(b1)), rh = rms(render(dflt)); (void)rh;
        check(r1 > 0 && rms(render(b1)) != rms(render(b0)), "BALANCE 100% plays filter 2 alone (differs from 0%)");
        { // oversampling latency is lined up: MIX 50% with DRIVE doesn't notch where the 15-sample delay would cancel (~1.47 kHz)
            VoiceParams sv = base; sv.osc1Shape = 0; sv.filter2Type = 0; sv.filterMode = 0; sv.filterCutoff = 18000; sv.filterDrive = 0.3;
            auto tone = [&](double mix) { VoiceParams q = sv; q.filter1Mix = mix;
                Synth s; s.init(44100); s.setParams(q, {}); FXParams fx; s.setFX(fx); s.noteOn(90, 0.5f);
                std::vector<float> L(12000), R(12000); s.renderPlanar(L.data(), R.data(), 12000); return L; };
            double dry = rms(tone(0)), half = rms(tone(0.5)), wet = rms(tone(1));
            printf("1.48 kHz sine through DRIVE 30%%: dry %.4f, MIX 50%% %.4f, wet %.4f\n", dry, half, wet);
            check(half > 0.9 * std::min(dry, wet), "MIX 50% on an oversampled filter blends without a latency notch");
            VoiceParams pv = base; pv.filterRouting = 1; pv.filterMode = 5; pv.filter2Type = 1; pv.filter2Cutoff = 18000; pv.filterCutoff = 18000; pv.osc1Shape = 0;
            auto ptone = [&](int f2t) { VoiceParams q = pv; q.filter2Type = f2t;
                Synth s; s.init(44100); s.setParams(q, {}); FXParams fx; s.setFX(fx); s.noteOn(90, 0.5f);
                std::vector<float> L(12000), R(12000); s.renderPlanar(L.data(), R.data(), 12000); return L; };
            double both = rms(ptone(1)), one = rms(ptone(0));
            printf("parallel LADDER (2x) + LOW PASS (1x) at 1.48 kHz: %.4f vs filter 1 alone %.4f\n", both, one);
            check(both > 0.8 * one, "PARALLEL lines a 2x filter up with a 1x filter (no cancellation)");
        }
        std::vector<ModRoute> mr = {{ModRoute::Source::LFO1, ModRoute::Dest::FilterBalance, 0.5}};
        auto withRoute = render(dflt, mr);
        check(!same(withRoute, render(dflt)), "an F BALANCE route moves the parallel mix");
    }
    { // presets + destinations
        Preset p; p.voice.filter1Mix = 0.25; p.voice.filter2Mix = 0.5; p.voice.filterBalance = 0.75; p.voice.filter2Morph = 0.125; p.voice.filter2Type = 8;
        p.routes.push_back({ModRoute::Source::LFO2, ModRoute::Dest::Filter2Morph, 0.5});
        std::string txt = p.serialize();
        Preset q; bool ok = q.parse(txt);
        check(ok && q == p && txt.find("\nfilterr 0.25 0.5 0.75 0.125\n") != std::string::npos, "filterr line and an F2 MORPH route survive save and load");
        Preset d; check(d.serialize().find("filterr") == std::string::npos, "default routing writes no filterr line");
        check((int)ModRoute::Dest::Filter2Morph == 25 && (int)ModRoute::Dest::FilterBalance == 26, "F2 MORPH / F BALANCE destinations are appended");
        check(!ui::isFxDest(ModRoute::Dest::Filter2Morph) && !ui::isFxDest(ModRoute::Dest::FilterBalance), "the new destinations are per-voice");
    }
    printf(g_fail ? "FAILED\n" : "ALL PASS\n");
    return g_fail;
}
