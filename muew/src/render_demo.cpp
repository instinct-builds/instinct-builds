// MUEW demo render: a short original phrase rendered through the synth engine
// to prove the DSP core end-to-end. Output: out/muew-demo.wav
#include "synth.h"
#include "preset.h"
#include "wav_writer.h"
#include <cstdio>
#include <vector>

using namespace muew;

int main() {
    const int sr = 44100;
    const double seconds = 7.0;
    const int total = static_cast<int>(sr * seconds);

    Synth synth(16);
    synth.init(sr);

    VoiceParams p;
    p.osc1Shape = 2;            // saw
    p.osc2Shape = 1;            // triangle, an octave-and-fifth flavor
    p.osc2Detune = 19.0;
    p.osc2Level = 0.35;
    p.filterCutoff = 1200.0;
    p.filterReso = 1.2;
    p.ampA = 0.004; p.ampD = 0.25; p.ampS = 0.7; p.ampR = 0.45;
    p.modA = 0.01; p.modD = 0.35; p.modS = 0.2; p.modR = 0.3;
    p.lfo1Rate = 5.5;
    synth.setParams(p, Synth::defaultRoutes());

    // FX on for this render: chorus + ping-pong-ish delay + reverb.
    FXParams fx;
    fx.chorus = {true, 0.6, 6.0, 15.0, 0.35};
    fx.delay = {true, 0.28, 0.42, 0.35, 0.22};
    fx.reverb = {true, 0.55, 0.45, 0.28};
    synth.setFX(fx);

    // Original phrase: A-minor-ish arpeggio, then a chord.
    struct Event { double t; int note; float vel; bool on; };
    std::vector<Event> events;
    const int arp[] = {57, 60, 64, 69, 72, 69, 64, 60};
    double t = 0.1;
    for (int rep = 0; rep < 2; ++rep) {
        for (int n : arp) {
            events.push_back({t, n, 0.9f, true});
            events.push_back({t + 0.22, n, 0.0f, false});
            t += 0.25;
        }
    }
    t += 0.3;
    for (int n : {57, 60, 64, 71}) events.push_back({t, n, 0.8f, true});
    for (int n : {57, 60, 64, 71}) events.push_back({t + 2.0, n, 0.0f, false});

    std::vector<float> buffer(total * 2, 0.0f); // interleaved stereo
    size_t ev = 0;
    const int block = 128;
    for (int pos = 0; pos < total; pos += block) {
        double now = static_cast<double>(pos) / sr;
        while (ev < events.size() && events[ev].t <= now) {
            if (events[ev].on) synth.noteOn(events[ev].note, events[ev].vel);
            else synth.noteOff(events[ev].note);
            ++ev;
        }
        int frames = std::min(block, total - pos);
        synth.renderStereo(buffer.data() + pos * 2, frames);
    }

    float peak = 0.0f;
    double rms = 0.0;
    for (float s : buffer) { peak = std::max(peak, std::fabs(s)); rms += s * s; }
    rms = std::sqrt(rms / buffer.size());

    const char* path = "out/muew-demo.wav";
    if (!writeWav(path, buffer, sr, 2)) { std::fprintf(stderr, "write failed\n"); return 1; }
    std::printf("rendered %s (%.1fs, peak %.3f, RMS %.3f)\n", path, seconds, peak, rms);
    return 0;
}
