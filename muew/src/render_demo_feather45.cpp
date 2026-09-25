// MUEW 0.45.0: copied H4-H16 profile with three-bin harmonic feather and frame-range taper.
#include "synth.h"
#include "spectral_clipboard.h"
#include "wav_writer.h"
#include <algorithm>
#include <cmath>
#include <cstdio>
using namespace muew;
int main(int argc, char** argv) {
    const char* path = argc > 1 ? argv[1] : "out/MUEW-0.45.0-span-feather-demo.wav";
    constexpr int sr = 44100, block = 128;
    TableFrames frames(16, shapeFrame(2));
    for (int i = 0; i < 16; ++i) smoothFrame(frames[i], i / 5);
    TableFrames before = frames;
    Frame source = frames[0]; gainPartial(source, 4, -18); gainPartial(source, 8, 9);
    SpectralClipboard profile;
    if (!profile.capture(source, 0)) return 1;
    profile.span(4,16);
    profile.feather = 3;
    FrameRange range{3, 12};
    if (!applySpectralProfileTable(frames, range, 7, profile, .8, 1, false)) return 2;
    if (frames[0] != before[0] || frames[15] != before[15] ||
        frames[3] != before[3] || frames[12] != before[12] || frames[7] == before[7]) return 3;
    Synth s(16); s.init(sr); s.setTables(frames, {});
    VoiceParams v; v.osc1Shape = kCustomShape; v.osc2Level = 0;
    v.filterCutoff = 12000; v.ampA = .012; v.ampR = .13; s.setParams(v, {});
    std::vector<float> out;
    const int notes[] = {48, 55, 60, 64};
    const int positions[] = {1, 4, 8, 14};
    for (int scene = 0; scene < 4; ++scene) {
        v.osc1WtPos = positions[scene] / 15.0; s.setParams(v, {});
        for (int n : notes) {
            s.noteOn(n, .8f);
            for (int pos = 0; pos < (int)(sr * .28); pos += block) {
                float buf[block * 2]{}; s.renderStereo(buf, block); out.insert(out.end(), buf, buf + block * 2);
            }
            s.noteOff(n);
            for (int pos = 0; pos < (int)(sr * .09); pos += block) {
                float buf[block * 2]{}; s.renderStereo(buf, block); out.insert(out.end(), buf, buf + block * 2);
            }
        }
    }
    float peak = 0; for (float x : out) peak = std::max(peak, std::fabs(x));
    if (!writeWav(path, out, sr, 2)) return 3;
    printf("MUEW feather demo: original / range edge / soft span center / original; %.2f s, peak %.3f; %s\n", out.size() / (2.0 * sr), peak, path);
    return 0;
}
