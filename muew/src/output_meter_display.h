#pragma once
#include <algorithm>
#include <cmath>
namespace muew {
struct OutputMeterDisplay {
    float left = 0, right = 0, drive = 0;
    double satAge = 1;
    // UI-only ballistics. A 200ms SAT linger catches short real saturation,
    // without claiming the DAW's downstream output has clipped.
    void update(float l, float r, float d, double dt) {
        dt = std::clamp(dt, 0.0, 0.10);
        auto fall = [dt](float old, float val) { return std::max(val, old * (float)std::exp(-dt / 0.25)); };
        l = std::isfinite(l) ? std::clamp(l, 0.0f, 1.0f) : 0;
        r = std::isfinite(r) ? std::clamp(r, 0.0f, 1.0f) : 0;
        d = std::isfinite(d) ? std::max(d, 0.0f) : 0;
        left = fall(left, l); right = fall(right, r);
        drive = d;
        satAge = d >= 1.0f ? 0.0 : std::min(1.0, satAge + dt);
    }
    bool saturated() const { return satAge < .2; }
    void clear() { left = right = drive = 0; satAge = 1; }
};
}
