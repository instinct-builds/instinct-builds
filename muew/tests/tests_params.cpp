// Parameter map tests: ranges, round trips and agreement with the editor knobs.
#include "../src/au_params.h"
#include "../src/ui_model.h"
#include <cassert>
#include <cstdio>
#include <algorithm>
#include <vector>

using namespace muew;

static int failures = 0;
#define CHECK(c) do { if (!(c)) { std::printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #c); ++failures; } } while (0)

int main() {
    static_assert(params::Count == 38 && params::ReverbSize == 36 && params::CompUpward == 37 && params::HyperMix == 34 && params::FilterFxCutoff == 35 && params::ArpGate == 32 && params::ArpSwing == 33 && params::GlideTime == 30 && params::UnisonBlend == 31 && params::PhaserMix == 28 && params::FlangerMix == 29 && params::Filter2Reso == 27 && params::SubLevel == 23 && params::WtPosA == 21 && params::CompAmount == 20, "parameter IDs are append-only");
    CHECK(params::Macro1 == 12 && params::ReverbMix == 11);
    CHECK(params::UnisonDetuneA == 16 && params::UnisonWidth == 18 && params::DistDrive == 19 && params::CompAmount == 20);
    CHECK(ui::knobParam(ui::UniDetuneA) == 16 && ui::knobParam(ui::UniDetuneB) == 17 && ui::knobParam(ui::Width) == 18);
    CHECK((int)params::WarpA == (int)ui::WarpA && (int)params::MsegTime == (int)ui::MsegTime);
    // Knob params cover the same range as the editor knobs.
    for (int k = 0; k < ui::KnobCount; ++k) {
        ui::Range r = ui::knobRange(k);
        int id = ui::knobParam(k);
        const auto& d = params::def(id);
        double scale = d.unit == params::Percent ? 100.0 : 1.0;
        CHECK(std::fabs(d.lo - r.lo * scale) < 1e-9 && std::fabs(d.hi - r.hi * scale) < 1e-9);
        CHECK(d.log == r.log);
        Preset p = factoryPresets()[3];
        CHECK(&params::field(p, id) == &ui::knobField(p.voice, k));
    }
    // Every factory preset's values sit inside the published ranges; set/get round-trips.
    for (const auto& fp : factoryPresets()) {
        for (int id = 0; id < params::Count; ++id) {
            double v = params::get(fp, id);
            CHECK(v >= params::def(id).lo && v <= params::def(id).hi);
            Preset p = fp;
            double mid = (params::def(id).lo + params::def(id).hi) / 2;
            params::set(p, id, mid);
            CHECK(std::fabs(params::get(p, id) - mid) < 1e-9);
            // Changing one parameter leaves the rest of the sound alone.
            for (int o = 0; o < params::Count; ++o)
                if (o != id) CHECK(params::get(p, o) == params::get(fp, o));
        }
    }
    // Clamping and non-finite input.
    Preset p = factoryPresets()[0];
    params::set(p, params::Cutoff, 1e9);
    CHECK(params::get(p, params::Cutoff) == 18000.0);
    params::set(p, params::ReverbMix, -5);
    CHECK(p.fx.reverb.mix == 0.0);
    params::set(p, params::Detune, NAN);
    CHECK(params::get(p, params::Detune) == -24.0);
    // Percent params map onto 0..1 fields.
    params::set(p, params::OscMix, 25);
    CHECK(std::fabs(p.voice.osc2Level - 0.25) < 1e-12);
    // Parameter edits survive preset serialization.
    Preset q; CHECK(q.parse(p.serialize()));
    for (int id = 0; id < params::Count; ++id) CHECK(std::fabs(params::get(q, id) - params::get(p, id)) < 1e-6 * std::max(1.0, params::get(p, id)));
    CHECK(params::defaultValue(params::Cutoff) == params::get(factoryPresets()[7], params::Cutoff));
    // Macros: silent at 0 (factory sound unchanged), audible when turned.
    auto brightness = [](const Preset& pr) {
        Synth syn(4); syn.init(44100); syn.setParams(pr.voice, pr.routes); syn.setFX(FXParams{});
        syn.noteOn(48, 0.9f);
        std::vector<float> l(44100 / 2), r(l.size());
        syn.renderPlanar(l.data(), r.data(), (int)l.size());
        double tot = 0, hf = 0;
        for (size_t i = 2205; i < l.size(); ++i) { tot += l[i] * l[i]; double d = l[i] - l[i - 1]; hf += d * d; }
        return tot > 0 ? hf / tot : 0.0;
    };
    auto rms = [](const Preset& pr) {
        Synth syn(4); syn.init(44100); syn.setParams(pr.voice, pr.routes); syn.setFX(FXParams{});
        syn.noteOn(48, 0.9f);
        std::vector<float> l(22050), r(l.size());
        syn.renderPlanar(l.data(), r.data(), (int)l.size());
        return l;
    };
    Preset dark = factoryPresets()[ui::indexOfSlug("warm-pad")];
    Preset stripped = dark;
    stripped.routes.erase(std::remove_if(stripped.routes.begin(), stripped.routes.end(),
        [](const ModRoute& rt) { return (int)rt.source >= (int)ModRoute::Source::Macro1; }), stripped.routes.end());
    CHECK(rms(dark) == rms(stripped)); // macro routes add exactly nothing at 0
    // Every factory preset carries the six standard macro routes (0.7.0
    // presets add Spread -> unison routes on top) with the macros at 0.
    const int stdRoutes[6][2] = {{5, 2}, {6, 5}, {6, 6}, {7, 4}, {8, 1}, {8, 3}};
    for (const auto& fp : factoryPresets()) {
        int found = 0;
        for (const auto& sr : stdRoutes)
            for (const auto& rt : fp.routes) if ((int)rt.source == sr[0] && (int)rt.dest == sr[1]) { ++found; break; }
        CHECK(found == 6 && fp.voice.macros[0] == 0 && fp.voice.macros[3] == 0);
    }
    Preset bright = dark; params::set(bright, params::Macro1, 100);
    double b0 = brightness(dark), b1 = brightness(bright);
    std::printf("macro 1 (Bright) on Warm Pad: brightness %.4f -> %.4f\n", b0, b1);
    CHECK(b1 > b0 * 2);
    Preset warped = dark; params::set(warped, params::Macro2, 100);
    CHECK(rms(warped) != rms(dark));
    if (failures) { std::printf("%d failure(s)\n", failures); return 1; }
    std::printf("params tests passed (%d parameters)\n", (int)params::Count);
    return 0;
}
