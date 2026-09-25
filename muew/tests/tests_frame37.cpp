// MUEW 0.37.0: per-frame spectral operations, undo, and preset state.
#include "../src/frame_tools.h"
#include "../src/table_history.h"
#include "../src/preset.h"
#include "../src/factory_bank.h"
#include <cmath>
#include <cstdio>
using namespace muew;
static int fail = 0;
static void check(bool ok, const char* what) { printf("%s %s\n", ok ? "ok:  " : "FAIL:", what); fail += !ok; }
static double difference(const Frame& a, const Frame& b) {
    double d = 0; for (int i = 0; i < kFrameSize; ++i) d += std::fabs(a[i] - b[i]); return d / kFrameSize;
}
int main() {
    Frame sine = shapeFrame(0), saw = shapeFrame(2), silence(kFrameSize, 0);
    for (FrameTool tool : {FrameTool::Focus, FrameTool::Blur, FrameTool::Align, FrameTool::Flip}) {
        check(spectralFrameTool(silence, tool) == silence, "silence is unchanged");
        Frame out = spectralFrameTool(saw, tool);
        float peak = 0; bool finite = out.size() == kFrameSize;
        for (float v : out) { finite &= std::isfinite(v); peak = std::max(peak, std::fabs(v)); }
        check(finite && std::fabs(peak - 1) < 1e-5, "tool produces a finite peak-normalized cycle");
    }
    Frame focus = spectralFrameTool(saw, FrameTool::Focus);
    auto a = frameHarmonics(saw, 100), b = frameHarmonics(focus, 100);
    int weakened = 0; for (int k = 0; k < 100; ++k) if (a[k] > .01 && a[k] < .17 && b[k] < a[k] * .9) ++weakened;
    check(weakened > 5, "FOCUS gates quiet partials relative to the strong ones");
    Frame one = sine;
    check(difference(spectralFrameTool(one, FrameTool::Blur), one) > .01, "BLUR spreads a sine's spectrum to neighbouring harmonics");
    Frame aligned = spectralFrameTool(saw, FrameTool::Align);
    auto sp = frameSpectrum(aligned);
    bool phase = true; for (int k = 1; k < 32; ++k) phase &= std::fabs(sp[k].real()) < .001 * std::max(1.0, std::abs(sp[k]));
    check(phase, "ALIGN puts all partials on sine phase");
    Frame flip = spectralFrameTool(saw, FrameTool::Flip);
    auto before = frameHarmonics(saw, 100), after = frameHarmonics(flip, 100);
    bool magnitudes = true; for (int k = 0; k < 100; ++k) magnitudes &= std::fabs(before[k] - after[k]) < .0001;
    check(magnitudes && difference(flip, saw) > .05, "FLIP reverses the cycle but keeps partial magnitudes");
    TableFrames t{shapeFrame(0), saw, shapeFrame(3)}; TableFrames original = t;
    TableHistory history; int frame = 1;
    history.push(t, frame, "FOCUS"); t[frame] = focus;
    check(t[0] == original[0] && t[2] == original[2] && t[1] != original[1], "tool touches the selected frame only");
    history.push(t, frame, "BLUR"); t[frame] = spectralFrameTool(t[frame], FrameTool::Blur);
    TableFrames edited = t;
    check(history.undo(t, frame) && t[1] == focus && frame == 1 && history.undoLabel() == "FOCUS", "undo BLUR keeps the earlier FOCUS");
    check(history.undo(t, frame) && t == original && history.redo(t, frame) && history.redo(t, frame) && t == edited,
          "undo and redo replay both frame operations exactly");
    Preset p; p.tables[0] = edited; p.voice.osc1Shape = kCustomShape;
    Preset restored; check(restored.parse(p.serialize()) && restored.tables[0] == edited, "session state preserves edited frames exactly");
    printf("%s\n", fail ? "FRAME37 FAILED" : "ALL FRAME37 TESTS PASSED"); return fail ? 1 : 0;
}
