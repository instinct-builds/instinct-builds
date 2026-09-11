// MUEW DSP core tests — no framework, plain asserts with readable output.
#include "../src/synth.h"
#include "../src/wav_writer.h"
#include <cstdio>
#include <cmath>
#include <vector>

using namespace muew;

static int failures = 0;
#define CHECK(cond, msg) do { if (!(cond)) { ++failures; std::printf("FAIL: %s\n", msg); } \
                              else { std::printf("ok:   %s\n", msg); } } while (0)

static double rmsOf(const std::vector<float>& v) {
    double s = 0; for (float x : v) s += x * x;
    return std::sqrt(s / v.size());
}

int main() {
    const double sr = 44100.0;
    Wavetable table;

    // 1. Oscillator frequency accuracy: zero crossings of a 440 Hz sine.
    {
        Oscillator osc;
        osc.setSampleRate(sr); osc.setTable(&table);
        osc.setFrequency(440.0); osc.setShape(0);
        int crossings = 0; float prev = 0;
        for (int i = 0; i < (int)sr; ++i) {
            float x = osc.process();
            if (prev <= 0 && x > 0) ++crossings;
            prev = x;
        }
        CHECK(std::abs(crossings - 440) <= 1, "sine oscillator tracks 440 Hz");
    }

    // 2. Band-limiting: very high-pitched saw stays bounded and finite.
    {
        Oscillator osc;
        osc.setSampleRate(sr); osc.setTable(&table);
        osc.setFrequency(12000.0); osc.setShape(2);
        float peak = 0; bool finite = true;
        for (int i = 0; i < (int)sr; ++i) {
            float x = osc.process();
            peak = std::max(peak, std::fabs(x));
            if (!std::isfinite(x)) finite = false;
        }
        CHECK(finite, "high-frequency saw stays finite");
        CHECK(peak <= 1.01f, "high-frequency saw stays bounded (band-limited)");
    }

    // 3. Filter: lowpass passes low freq, attenuates high freq.
    {
        auto renderSine = [&](double freq, double cutoff) {
            SVFilter f; f.setSampleRate(sr); f.setMode(SVFilter::Mode::Lowpass);
            f.set(cutoff, 0.707);
            std::vector<float> out((int)(sr * 0.5));
            double ph = 0;
            for (auto& s : out) {
                float in = (float)std::sin(2 * M_PI * ph); ph += freq / sr;
                s = f.process(in);
            }
            return rmsOf(std::vector<float>(out.begin() + (int)(sr * 0.25), out.end()));
        };
        double low = renderSine(100.0, 300.0);
        double high = renderSine(6000.0, 300.0);
        CHECK(low > 0.5, "lowpass passes 100 Hz at 300 Hz cutoff");
        CHECK(high < low * 0.1, "lowpass strongly attenuates 6 kHz at 300 Hz cutoff");
    }

    // 4. ADSR timing: attack reaches 1, sustain holds, release ends idle.
    {
        Envelope e; e.setSampleRate(sr); e.set(0.1, 0.1, 0.5, 0.1);
        e.noteOn();
        for (int i = 0; i < (int)(0.1 * sr); ++i) e.process();
        CHECK(e.level() >= 0.99, "attack reaches full level");
        for (int i = 0; i < (int)(0.02 * sr); ++i) e.process();
        for (int i = 0; i < (int)(0.15 * sr); ++i) e.process();
        CHECK(std::abs(e.level() - 0.5) < 0.02, "sustain holds at 0.5");
        double held = e.level();
        for (int i = 0; i < (int)(0.1 * sr); ++i) e.process();
        CHECK(std::abs(e.level() - held) < 1e-6, "sustain is steady");
        e.noteOff();
        for (int i = 0; i < (int)(0.3 * sr); ++i) e.process();
        CHECK(!e.isActive() && e.level() == 0.0, "release ends silent and idle");
    }

    // 5. Polyphony and voice stealing.
    {
        Synth s(8); s.init(sr);
        for (int n = 40; n < 60; ++n) s.noteOn(n, 1.0f);
        std::vector<float> buf(512);
        s.render(buf.data(), (int)buf.size());
        CHECK(s.activeVoiceCount() == 8, "voice stealing caps at max voices");
        s.noteOff(50);
        for (int i = 0; i < 10; ++i) s.render(buf.data(), (int)buf.size());
        bool ok = true;
        for (float x : buf) if (!std::isfinite(x)) ok = false;
        CHECK(ok, "rendered audio is finite under full polyphony");
    }

    // 6. Master soft clip keeps output within [-1, 1].
    {
        Synth s(16); s.init(sr);
        for (int n = 36; n < 96; n += 3) s.noteOn(n, 1.0f);
        std::vector<float> buf(4096);
        s.render(buf.data(), (int)buf.size());
        float peak = 0; for (float x : buf) peak = std::max(peak, std::fabs(x));
        CHECK(peak <= 1.0f, "soft clip bounds master output");
        CHECK(rmsOf(buf) > 0.01, "synth actually produces signal");
    }

    // 7. Modulation: mod env -> cutoff sweep changes timbre (RMS differs over time).
    {
        Synth s(4); s.init(sr);
        VoiceParams p; p.filterCutoff = 400.0; p.modA = 0.001; p.modD = 0.5; p.modS = 0.0;
        s.setParams(p, {{ModRoute::Source::ModEnv, ModRoute::Dest::FilterCutoff, 3.0}});
        s.noteOn(60, 1.0f);
        std::vector<float> a((int)(0.05 * sr)), b((int)(0.05 * sr));
        std::vector<float> skip((int)(0.02 * sr));
        s.render(a.data(), (int)a.size());
        s.render(skip.data(), (int)skip.size());
        for (int i = 0; i < (int)(0.4 * sr); ++i) { float x; s.render(&x, 1); }
        s.render(b.data(), (int)b.size());
        CHECK(rmsOf(a) > rmsOf(b) * 1.5, "mod env cutoff sweep changes brightness over time");
    }

    std::printf(failures ? "\n%d FAILURES\n" : "\nALL TESTS PASSED\n", failures);
    return failures ? 1 : 0;
}
// --- appended in phase 1.5: FX + preset tests live in tests_fx.cpp ---
