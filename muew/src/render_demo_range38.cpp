// MUEW 0.38.0: one original 16-frame table, inclusive middle-frame batch edit.
#include "synth.h"
#include "frame_range.h"
#include "wav_writer.h"
#include <algorithm>
#include <cmath>
#include <cstdio>
using namespace muew;
int main(int argc, char** argv) {
    const char* path = argc > 1 ? argv[1] : "out/MUEW-0.38.0-frame-range-demo.wav";
    constexpr int sr = 44100, block = 128;
    TableFrames frames(16, shapeFrame(2));
    // Original evolving wave: tame the upper partials progressively across the table.
    for (int i = 0; i < 16; ++i) smoothFrame(frames[i], i / 4);
    FrameRange range; range.anchor = 4; range.end = 11;
    TableFrames before = frames;
    if (!applyFrameRange(frames, range, FrameTool::Focus)) return 1;
    for (int i = 0; i < 16; ++i)
        if ((i < 4 || i > 11) && before[i] != frames[i]) return 2;
    Synth s(16); s.init(sr); s.setTables(frames, {});
    VoiceParams v; v.osc1Shape = kCustomShape; v.osc2Level = 0; v.filterCutoff = 11000; v.ampA = .015; v.ampR = .12;
    s.setParams(v, {});
    std::vector<float> out;
    const int notes[4] = {48, 55, 60, 64};
    for (int scene = 0; scene < 4; ++scene) {
        v.osc1WtPos = (scene == 0 ? 1 : scene == 1 ? 5 : scene == 2 ? 10 : 14) / 15.0;
        s.setParams(v, {});
        for (int n : notes) {
            s.noteOn(n, .8f);
            for (int pos = 0; pos < (int)(sr * .30); pos += block) {
                float buf[block * 2]{}; s.renderStereo(buf, block); out.insert(out.end(), buf, buf + block * 2);
            }
            s.noteOff(n);
            for (int pos = 0; pos < (int)(sr * .08); pos += block) {
                float buf[block * 2]{}; s.renderStereo(buf, block); out.insert(out.end(), buf, buf + block * 2);
            }
        }
    }
    float peak = 0; for (float x : out) peak = std::max(peak, std::fabs(x));
    if (!writeWav(path, out, sr, 2)) return 3;
    printf("MUEW range demo: outside/middle/middle/outside; %.2f s, peak %.3f; %s\n", out.size() / (2.0 * sr), peak, path);
    return 0;
}
