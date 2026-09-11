// Renders a short phrase twice: built-in saw vs a custom editor-built
// "hollow" table (odd harmonics + light 2nd), to out/muew-custom-wt-demo.wav
// and out/muew-custom-wt-saw.wav for comparison.
#include "synth.h"
#include "wavetable_editor.h"
#include "wav_writer.h"
#include <cstdio>

using namespace muew;

static void renderPhrase(Synth& synth, const char* path) {
    const double sr = 44100.0;
    const int notes[] = {57, 60, 64, 69, 67, 64, 60, 57};
    std::vector<float> pcm;
    for (int n = 0; n < 8; ++n) {
        synth.noteOn(notes[n], 0.9f);
        std::vector<float> buf((int)(sr * 0.22) * 2);
        synth.renderStereo(buf.data(), (int)(sr * 0.22));
        pcm.insert(pcm.end(), buf.begin(), buf.end());
        synth.noteOff(notes[n]);
        std::vector<float> tail((int)(sr * 0.08) * 2);
        synth.renderStereo(tail.data(), (int)(sr * 0.08));
        pcm.insert(pcm.end(), tail.begin(), tail.end());
    }
    writeWav(path, pcm, sr, 2);
    std::printf("wrote %s (%zu frames)\n", path, pcm.size() / 2);
}

int main() {
    const double sr = 44100.0;

    Synth saw;
    saw.init(sr);
    VoiceParams sp;
    sp.osc1Shape = 2; // Saw
    sp.osc2Level = 0.0f;
    saw.setParams(sp, {});
    renderPhrase(saw, "out/muew-custom-wt-saw.wav");

    Synth hollow;
    hollow.init(sr);
    WavetableEditor ed;
    for (int h = 1; h <= 25; h += 2) ed.setHarmonic(h, 1.0 / h);
    ed.setHarmonic(2, 0.15); // a breath of even harmonic
    ed.rebuild();
    int slot = hollow.wavetable()->addCustomTable(ed.buildLevels());
    VoiceParams hp;
    hp.osc1Shape = slot;
    hp.osc2Level = 0.0f;
    hollow.setParams(hp, {});
    renderPhrase(hollow, "out/muew-custom-wt-demo.wav");
    return 0;
}
