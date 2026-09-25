// MUEW 0.37.0: three timbres from one original table, edited one frame at a time.
#include "synth.h"
#include "frame_tools.h"
#include "wav_writer.h"
#include <algorithm>
#include <cmath>
#include <cstdio>
using namespace muew;

int main(int argc, char** argv) {
    const char* path = argc > 1 ? argv[1] : "out/MUEW-0.37.0-frame-tools-demo.wav";
    constexpr int sr = 44100, block = 128;
    TableFrames frames{shapeFrame(2), shapeFrame(2), shapeFrame(2), shapeFrame(2)};
    frames[1] = spectralFrameTool(frames[1], FrameTool::Focus);
    frames[2] = spectralFrameTool(frames[2], FrameTool::Blur);
    frames[3] = spectralFrameTool(spectralFrameTool(frames[3], FrameTool::Align), FrameTool::Flip);
    Synth s(16); s.init(sr); s.setTables(frames, {});
    VoiceParams v; v.osc1Shape = kCustomShape; v.osc2Level = 0; v.filterCutoff = 9500; v.ampA = .01; v.ampR = .13;
    s.setParams(v, {});
    std::vector<float> out;
    const int notes[4] = {48, 52, 55, 60};
    for (int scene = 0; scene < 4; ++scene) {
        v.osc1WtPos = scene / 3.0; s.setParams(v, {});
        for (int n = 0; n < 4; ++n) {
            s.noteOn(notes[n], .75f);
            for (int pos = 0; pos < (int)(sr * .33); pos += block) {
                float buf[block * 2]{}; s.renderStereo(buf, block); out.insert(out.end(), buf, buf + block * 2);
            }
            s.noteOff(notes[n]);
            for (int pos = 0; pos < (int)(sr * .07); pos += block) {
                float buf[block * 2]{}; s.renderStereo(buf, block); out.insert(out.end(), buf, buf + block * 2);
            }
        }
    }
    float peak = 0; for (float x : out) peak = std::max(peak, std::fabs(x));
    if (!writeWav(path, out, sr, 2)) return 1;
    printf("MUEW frame tools: original, FOCUS, BLUR, ALIGN+FLIP; %.2f s, peak %.3f; %s\n", out.size() / (2.0 * sr), peak, path);
    return 0;
}
