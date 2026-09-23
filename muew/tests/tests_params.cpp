// Parameter map tests: ranges, round trips and agreement with the editor knobs.
#include "../src/au_params.h"
#include "../src/ui_model.h"
#include <cassert>
#include <cstdio>

using namespace muew;

static int failures = 0;
#define CHECK(c) do { if (!(c)) { std::printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #c); ++failures; } } while (0)

int main() {
    static_assert(params::Count == 12, "parameter IDs are append-only");
    CHECK((int)params::WarpA == (int)ui::WarpA && (int)params::MsegTime == (int)ui::MsegTime);
    // Knob params cover the same range as the editor knobs.
    for (int k = 0; k < ui::KnobCount; ++k) {
        ui::Range r = ui::knobRange(k);
        const auto& d = params::def(k);
        double scale = d.unit == params::Percent ? 100.0 : 1.0;
        CHECK(std::fabs(d.lo - r.lo * scale) < 1e-9 && std::fabs(d.hi - r.hi * scale) < 1e-9);
        CHECK(d.log == r.log);
        Preset p = factoryPresets()[3];
        CHECK(&params::field(p, k) == &ui::knobField(p.voice, k));
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
    if (failures) { std::printf("%d failure(s)\n", failures); return 1; }
    std::printf("params tests passed (%d parameters)\n", (int)params::Count);
    return 0;
}
