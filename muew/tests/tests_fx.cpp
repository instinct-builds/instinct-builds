// MUEW FX rack + preset tests.
#include "../src/synth.h"
#include "../src/preset.h"
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

    // 1. Chorus changes the signal and stays bounded.
    {
        Chorus ch; ch.init(sr);
        ChorusParams p; p.enabled = true; p.rateHz = 1.0; p.depthMs = 6.0; p.baseMs = 15.0; p.mix = 0.5;
        ch.set(p);
        std::vector<float> dry(8192), wet(8192);
        double ph = 0;
        for (int i = 0; i < 8192; ++i) {
            float in = (float)std::sin(2 * M_PI * 220.0 * ph); ph += 1.0 / sr;
            float l = in, r = in;
            ch.process(l, r);
            dry[i] = in; wet[i] = l;
            if (!std::isfinite(l) || !std::isfinite(r)) { wet[i] = 99; }
        }
        double diff = 0; float peak = 0;
        for (int i = 2000; i < 8192; ++i) { diff += std::fabs(wet[i] - dry[i]); peak = std::max(peak, std::fabs(wet[i])); }
        CHECK(diff > 100.0, "chorus audibly modulates the signal");
        CHECK(peak <= 1.01f, "chorus output stays bounded");
    }

    // 2. Delay repeats at the set time.
    {
        StereoDelay d; d.init(sr);
        DelayParams p; p.enabled = true; p.timeLSec = 0.25; p.timeRSec = 0.25; p.feedback = 0.0; p.mix = 0.5;
        d.set(p);
        int total = (int)sr; // 1 second
        std::vector<float> out(total, 0.0f);
        for (int i = 0; i < total; ++i) {
            float in = (i == 0) ? 1.0f : 0.0f; // impulse
            float l = in, r = in;
            d.process(l, r);
            out[i] = l;
        }
        int peakIdx = 0; float peakV = 0;
        for (int i = 100; i < total; ++i)
            if (std::fabs(out[i]) > peakV) { peakV = std::fabs(out[i]); peakIdx = i; }
        double expected = 0.25 * sr;
        CHECK(std::fabs(peakIdx - expected) < 4, "delay echo lands at the set delay time");
        CHECK(std::fabs(peakV - 0.5) < 0.02, "echo level matches the mix setting");
    }

    // 3. Reverb tail: impulse produces an extended, decaying, finite tail.
    {
        Reverb rv; rv.init(sr);
        ReverbParams p; p.enabled = true; p.decay = 0.7; p.damping = 0.4; p.mix = 1.0;
        rv.set(p);
        int total = (int)(sr * 0.5);
        std::vector<float> out(total, 0.0f);
        for (int i = 0; i < total; ++i) {
            float in = (i == 0) ? 1.0f : 0.0f;
            float l = in, r = in;
            rv.process(l, r);
            out[i] = l;
        }
        std::vector<float> early(out.begin() + 2000, out.begin() + 6000);
        std::vector<float> late(out.end() - 8000, out.end());
        bool finite = true; for (float x : out) if (!std::isfinite(x)) finite = false;
        CHECK(finite, "reverb tail is finite");
        CHECK(rmsOf(early) > 1e-4, "reverb produces a tail after the impulse");
        CHECK(rmsOf(late) < rmsOf(early), "reverb tail decays over time");
    }

    // 4. Preset round-trip: serialize -> parse -> identical.
    {
        Preset a;
        a.voice.osc1Shape = 2; a.voice.osc2Shape = 4; a.voice.osc2Detune = 7.03;
        a.voice.osc2Level = 0.42; a.voice.filterCutoff = 987.6; a.voice.filterReso = 2.5;
        a.voice.filterMode = 3; a.voice.ampA = 0.123; a.voice.lfo1Rate = 3.33;
        a.routes = Synth::defaultRoutes();
        a.fx.chorus = {true, 0.7, 5.0, 14.0, 0.4};
        a.fx.delay = {true, 0.3, 0.45, 0.4, 0.2};
        a.fx.reverb = {true, 0.65, 0.5, 0.33};
        std::string text = a.serialize();
        Preset b;
        CHECK(b.parse(text), "preset parses");
        CHECK(a == b, "preset round-trips exactly");
        CHECK(!b.parse("garbage\n"), "preset rejects wrong magic");
    }

    // 5. Full stereo render through FX stays bounded and finite.
    {
        Synth s(16); s.init(sr);
        FXParams fx;
        fx.chorus = {true, 0.6, 6.0, 15.0, 0.35};
        fx.delay = {true, 0.28, 0.42, 0.35, 0.25};
        fx.reverb = {true, 0.55, 0.45, 0.3};
        s.setFX(fx);
        for (int n : {48, 52, 55, 60}) s.noteOn(n, 0.9f);
        std::vector<float> buf(8192 * 2);
        s.renderStereo(buf.data(), 8192);
        float peak = 0; bool finite = true;
        for (float x : buf) { peak = std::max(peak, std::fabs(x)); if (!std::isfinite(x)) finite = false; }
        CHECK(finite, "stereo FX render is finite");
        CHECK(peak <= 1.0f, "stereo FX render stays within [-1, 1]");
        CHECK(rmsOf(buf) > 0.005, "stereo FX render carries signal");
    }

    std::printf(failures ? "\n%d FAILURES\n" : "\nALL FX TESTS PASSED\n", failures);
    return failures ? 1 : 0;
}
