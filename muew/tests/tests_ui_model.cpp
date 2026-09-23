// tests_ui_model.cpp - the instrument UI model: knobs map onto real engine
// fields and invert, previews come from the engine oscillator, and the
// browser filter drives the same factory bank the AU exposes.
#include "../src/ui_model.h"
#include <cstdio>

using namespace muew;
static int g_fail = 0;
static void check(bool c, const std::string& n) { printf("%s %s\n", c ? "ok:  " : "FAIL:", n.c_str()); if (!c) ++g_fail; }

int main() {
    VoiceParams p;
    bool inv = true;
    for (int k = 0; k < ui::KnobCount; ++k)
        for (double n : {0.0, 0.13, 0.5, 0.77, 1.0}) {
            ui::setKnob(p, k, n);
            if (std::fabs(ui::knobValue(p, k) - n) > 1e-9) inv = false;
        }
    check(inv, "every knob maps to its field and back");
    ui::setKnob(p, ui::Cutoff, 1.0);
    check(p.filterCutoff == 18000.0, "cutoff knob top is 18 kHz");
    ui::setKnob(p, ui::Detune, 0.5);
    check(std::fabs(p.osc2Detune) < 1e-12, "detune knob center is 0 semitones");
    ui::setKnob(p, ui::MsegTime, 0.0);
    check(p.mseg1Seconds == 0.05, "MSEG time knob bottom is 50 ms");
    check(ui::knobReadout(p, ui::MsegTime) == "50 ms", "readout formats time");

    Wavetable table;
    auto clean = ui::waveform(table, 2, 0, 0.0, 256);
    auto sync = ui::waveform(table, 2, 1, 0.8, 256);
    auto fold = ui::waveform(table, 0, 6, 0.9, 256);
    bool finite = true; double diff = 0, peak = 0;
    for (int i = 0; i < 256; ++i) {
        finite = finite && std::isfinite(clean[i]) && std::isfinite(sync[i]) && std::isfinite(fold[i]);
        diff += std::fabs(clean[i] - sync[i]); peak = std::max(peak, (double)std::fabs(fold[i]));
    }
    check(finite, "waveform previews are finite");
    check(diff > 10.0, "sync warp visibly changes the preview");
    check(peak <= 1.01, "fold preview stays in range");

    std::set<std::string> favs;
    check((int)ui::visiblePresets({}, favs).size() == kFactoryPresetCount, "browser shows the full bank");
    auto pads = ui::visiblePresets({"Pad", "", false}, favs);
    bool allPad = !pads.empty();
    for (int i : pads) allPad = allPad && factoryPresets()[i].info.category == "Pad";
    check(allPad, "Pad chip shows only pads");
    check(ui::indexOfSlug("night-bloom") >= 8 && ui::indexOfSlug("pluck") == 3, "slugs resolve to AU numbers");
    check(ui::indexOfName("Night Bloom") == ui::indexOfSlug("night-bloom") && ui::indexOfName("Nope") == -1,
          "display names resolve to factory numbers");
    favs.insert("laser-drop");
    auto f = ui::visiblePresets({"", "", true}, favs);
    check(f.size() == 1 && f[0] == ui::indexOfSlug("laser-drop"), "favorites view");

    // Every preset has a displayable name, category and routes with names.
    bool names = true;
    for (const auto& pr : factoryPresets()) {
        for (const auto& r : pr.routes)
            if (std::string(ui::sourceName(r.source)) == "?" || std::string(ui::destName(r.dest)) == "?") names = false;
        if (std::string(ui::warpName(pr.voice.osc1WarpMode)) == "?" || std::string(ui::shapeName(pr.voice.osc1Shape)) == "CUSTOM") names = false;
    }
    check(names, "every factory route, shape and warp has a display name");

    if (g_fail == 0) { printf("\nALL UI MODEL TESTS PASSED\n"); return 0; }
    printf("\n%d UI MODEL TEST(S) FAILED\n", g_fail); return 1;
}
