// render_preset.cpp - render a factory-bank preset through an original
// phrase to prove the preset actually sounds. Usage:
//   muew-render-preset <preset-name|path> [out.wav] [presets-dir]
#include "synth.h"
#include "preset.h"
#include "preset_bank.h"
#include "wav_writer.h"
#include <cstdio>
#include <cstring>
#include <vector>

using namespace muew;

int main(int argc, char** argv) {
    if (argc < 2) {
        std::fprintf(stderr, "usage: muew-render-preset <preset-name|path> [out.wav] [presets-dir]\n");
        return 1;
    }
    const char* what = argv[1];
    const char* presetsDir = argc >= 4 ? argv[3] : "presets";

    Preset preset;
    std::string name;
    std::string err;
    if (std::strchr(what, '/') || std::strstr(what, ".muew")) {
        std::ifstream f(what);
        if (!f) { std::fprintf(stderr, "cannot read %s\n", what); return 1; }
        std::ostringstream ss; ss << f.rdbuf();
        if (!preset.parse(ss.str())) { std::fprintf(stderr, "parse failed: %s\n", what); return 1; }
        name = what;
    } else {
        PresetBank bank;
        if (!bank.loadDir(presetsDir, err)) { std::fprintf(stderr, "%s\n", err.c_str()); return 1; }
        const NamedPreset* np = bank.get(what);
        if (!np) {
            std::fprintf(stderr, "no preset named '%s'. Bank has:\n", what);
            for (const auto& n : bank.names()) std::fprintf(stderr, "  %s\n", n.c_str());
            return 1;
        }
        preset = np->preset;
        name = np->name;
    }

    const int sr = 44100;
    const double seconds = 6.0;
    const int total = (int)(sr * seconds);
    Synth synth(16);
    synth.init(sr);
    synth.setParams(preset.voice, preset.routes);
    synth.setFX(preset.fx);

    // Original phrase: root-fifth-octave figure, then a held minor triad.
    struct Event { double t; int note; float vel; bool on; };
    std::vector<Event> events;
    const int fig[] = {45, 52, 57, 52};
    double t = 0.1;
    for (int rep = 0; rep < 3; ++rep)
        for (int n : fig) {
            events.push_back({t, n, 0.85f, true});
            events.push_back({t + 0.26, n, 0.0f, false});
            t += 0.3;
        }
    t += 0.2;
    for (int n : {57, 60, 64}) events.push_back({t, n, 0.8f, true});
    for (int n : {57, 60, 64}) events.push_back({t + 1.8, n, 0.0f, false});

    std::vector<float> buffer(total * 2, 0.0f);
    size_t ev = 0;
    const int block = 128;
    for (int pos = 0; pos < total; pos += block) {
        double now = (double)pos / sr;
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

    std::string out = argc >= 3 ? argv[2] : ("out/" + name + "-demo.wav");
    if (!writeWav(out.c_str(), buffer, sr, 2)) { std::fprintf(stderr, "write failed\n"); return 1; }
    std::printf("rendered %s from preset '%s' (%.1fs, peak %.3f, RMS %.3f)\n",
                out.c_str(), name.c_str(), seconds, peak, rms);
    return 0;
}
