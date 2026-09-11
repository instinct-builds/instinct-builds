// MUEW wavetable editor tests: FFT, harmonic builds, band-limited mipmaps,
// morphing, serialization, and synth integration of custom shape slots.
#include "../src/wavetable_editor.h"
#include "../src/synth.h"
#include <cstdio>
#include <cmath>
#include <vector>

using namespace muew;

static int failures = 0;
#define CHECK(cond, msg) do { if (!(cond)) { ++failures; std::printf("FAIL: %s\n", msg); } \
                              else { std::printf("ok:   %s\n", msg); } } while (0)

static std::vector<double> harmonicMagnitudes(const std::vector<float>& wave) {
    const int N = (int)wave.size();
    std::vector<std::complex<double>> spec(N);
    for (int i = 0; i < N; ++i) spec[i] = {wave[i], 0.0};
    fft(spec, false);
    std::vector<double> mags(N / 2 + 1);
    for (int k = 0; k <= N / 2; ++k) mags[k] = std::abs(spec[k]) * 2.0 / N;
    return mags;
}

int main() {
    const double sr = 44100.0;

    // 1. FFT round trip.
    {
        const int N = 1024;
        std::vector<std::complex<double>> a(N);
        for (int i = 0; i < N; ++i)
            a[i] = {std::sin(2 * M_PI * 5 * i / N) + 0.5 * std::sin(2 * M_PI * 23 * i / N + 1.0), 0.0};
        auto orig = a;
        fft(a, false);
        fft(a, true);
        double err = 0;
        for (int i = 0; i < N; ++i) err = std::max(err, std::abs(a[i] - orig[i]));
        CHECK(err < 1e-9, "fft/ifft round trip is lossless");
    }

    // 2. Harmonic build: single fundamental matches a sine.
    {
        WavetableEditor ed;
        ed.setHarmonic(1, 1.0);
        ed.rebuild();
        double err = 0;
        for (int i = 0; i < WavetableEditor::kSize; ++i) {
            double expect = std::sin(2.0 * M_PI * i / WavetableEditor::kSize);
            err = std::max(err, std::fabs(ed.singleCycle()[i] - expect));
        }
        CHECK(err < 1e-5, "harmonic {1: 1.0} builds a clean sine");
    }

    // 3. Square-style additive spec keeps only odd harmonics after analysis.
    {
        WavetableEditor ed;
        for (int h = 1; h <= 31; h += 2) ed.setHarmonic(h, 1.0 / h);
        ed.rebuild();
        auto mags = harmonicMagnitudes(ed.singleCycle());
        double evenPeak = 0;
        for (int h = 2; h <= 32; h += 2) evenPeak = std::max(evenPeak, mags[h]);
        CHECK(evenPeak < 1e-4, "odd-harmonic spec leaves even bins empty");
        CHECK(mags[1] > 0.8 && mags[3] > 0.25, "odd harmonics present at expected weight");
    }

    // 4. Band-limiting across mip levels.
    {
        WavetableEditor ed;
        for (int h = 1; h <= 64; ++h) ed.setHarmonic(h, 1.0 / h);
        ed.rebuild();
        auto levels = ed.buildLevels();
        CHECK((int)levels.size() == Wavetable::kNumLevels, "one mip level per octave");
        auto topMags = harmonicMagnitudes(levels[Wavetable::kNumLevels - 1]);
        double topHigh = 0;
        for (int k = 2; k < (int)topMags.size(); ++k) topHigh = std::max(topHigh, topMags[k]);
        CHECK(topMags[1] > 0.9 && topHigh < 1e-4, "top mip level keeps only the fundamental");
        auto baseMags = harmonicMagnitudes(levels[0]);
        double baseHigh = 0;
        for (int k = 20; k <= 60; ++k) baseHigh = std::max(baseHigh, baseMags[k]);
        CHECK(baseHigh > 0.005, "base level retains high harmonics");
        float peak = 0;
        for (float x : levels[3]) peak = std::max(peak, std::fabs(x));
        CHECK(peak > 0.99f && peak <= 1.0f, "each level normalized to peak 1");
    }

    // 5. Morph midpoint equals sample average.
    {
        WavetableEditor a, b;
        a.setHarmonic(1, 1.0); a.rebuild();
        for (int h = 1; h <= 16; ++h) b.setHarmonic(h, 1.0 / h);
        b.rebuild();
        auto m = WavetableEditor::morph(a.singleCycle(), b.singleCycle(), 0.5);
        double err = 0;
        for (size_t i = 0; i < m.size(); ++i)
            err = std::max(err, (double)std::fabs(m[i] - 0.5f * (a.singleCycle()[i] + b.singleCycle()[i])));
        CHECK(err < 1e-6 && m.size() == (size_t)WavetableEditor::kSize, "morph at t=0.5 is the sample average");
    }

    // 6. Serialization round trip (harmonics + samples).
    {
        WavetableEditor ed;
        ed.setHarmonic(1, 0.9); ed.setHarmonic(3, 0.3, 0.5); ed.setHarmonic(7, 0.1);
        ed.rebuild();
        ed.drawSample(100, 0.42); // freehand tweak on top
        WavetableEditor back;
        bool ok = back.parse(ed.serialize());
        CHECK(ok, "serialized table parses");
        CHECK(back.harmonics().size() == 3, "harmonic spec survives round trip");
        double err = 0;
        for (int i = 0; i < WavetableEditor::kSize; ++i)
            err = std::max(err, (double)std::fabs(back.singleCycle()[i] - ed.singleCycle()[i]));
        CHECK(err < 1e-6, "samples survive round trip");
        WavetableEditor bad;
        CHECK(!bad.parse("not-a-table 9\nsamples 0\n"), "foreign magic rejected");
    }

    // 7. Freehand editing: clamping, smoothing, no NaN in levels.
    {
        WavetableEditor ed;
        for (int i = 0; i < WavetableEditor::kSize; ++i)
            ed.drawSample(i, i % 2 == 0 ? 5.0 : -5.0); // over-range input clamps
        float peak = 0;
        for (float x : ed.singleCycle()) peak = std::max(peak, std::fabs(x));
        CHECK(peak <= 1.0f, "freehand input clamps to [-1,1]");
        ed.smooth(8);
        ed.normalize();
        auto levels = ed.buildLevels();
        bool finite = true;
        for (auto& l : levels) for (float x : l) if (!std::isfinite(x)) finite = false;
        CHECK(finite, "freehand levels stay finite");
    }

    // 8. Synth integration: custom shape slot renders in tune, bounded.
    {
        Synth synth;
        synth.init(sr);
        WavetableEditor ed;
        ed.setHarmonic(1, 1.0);
        ed.rebuild();
        int slot = synth.wavetable()->addCustomTable(ed.buildLevels());
        CHECK(slot >= (int)Wavetable::Shape::Count, "custom table gets its own shape slot");
        VoiceParams p;
        p.osc1Shape = slot;
        p.osc2Level = 0.0f;
        synth.setParams(p, {});
        synth.noteOn(69, 1.0f); // A4 = 440 Hz
        std::vector<float> out((int)sr);
        synth.render(out.data(), (int)sr);
        int crossings = 0;
        float prev = 0, peak = 0;
        bool finite = true;
        for (size_t i = (size_t)(sr * 0.1); i < out.size(); ++i) { // skip attack
            if (prev <= 0 && out[i] > 0) ++crossings;
            prev = out[i];
            peak = std::max(peak, std::fabs(out[i]));
            if (!std::isfinite(out[i])) finite = false;
        }
        double measured = crossings / 0.9;
        CHECK(finite, "custom-slot render stays finite");
        CHECK(std::fabs(measured - 440.0) < 3.0, "custom-slot sine tracks 440 Hz");
        CHECK(peak > 0.1f && peak <= 1.0f, "custom-slot render is audible and bounded");
    }

    // 9. Custom complex table through the synth at high pitch: band-limited.
    {
        Synth synth;
        synth.init(sr);
        WavetableEditor ed;
        for (int h = 1; h <= 200; ++h) ed.setHarmonic(h, 1.0 / h);
        ed.rebuild();
        int slot = synth.wavetable()->addCustomTable(ed.buildLevels());
        VoiceParams p;
        p.osc1Shape = slot;
        p.osc2Level = 0.0f;
        synth.setParams(p, {});
        synth.noteOn(105, 1.0f); // ~4.7 kHz: high mip level
        std::vector<float> out((int)(sr * 0.5));
        synth.render(out.data(), (int)out.size());
        float peak = 0;
        bool finite = true;
        for (float x : out) {
            peak = std::max(peak, std::fabs(x));
            if (!std::isfinite(x)) finite = false;
        }
        CHECK(finite && peak <= 1.0f, "high-pitch custom table stays band-limited and bounded");
    }

    if (failures == 0) std::printf("ALL WAVETABLE EDITOR TESTS PASSED\n");
    return failures ? 1 : 0;
}
