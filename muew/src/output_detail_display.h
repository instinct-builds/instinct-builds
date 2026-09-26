#pragma once
#include <algorithm>
#include <cmath>
namespace muew {
// Display-only raw block peaks plus short held peaks. The header's smoother
// is separate; 'current' here is the actual most recent rendered block.
struct OutputDetailDisplay {
    float current[2]{}, held[2]{};
    double age[2]{};
    static constexpr double kHoldSeconds = 1.0;
    void clear() { for (int i=0;i<2;++i) { current[i]=held[i]=0; age[i]=0; } }
    void update(float left, float right, double elapsed) {
        const float v[2] = {left,right};
        const double dt = std::clamp(std::isfinite(elapsed) ? elapsed : 0.0, 0.0, 0.1);
        for(int i=0;i<2;++i) {
            current[i] = std::isfinite(v[i]) ? std::clamp(v[i],0.0f,1.0f) : 0;
            if(current[i] >= held[i] + .0001f) { held[i]=current[i];age[i]=0; }
            else {
                age[i] += dt;
                if(age[i] >= kHoldSeconds) held[i] = current[i];
            }
        }
    }
    static double dbfs(float amplitude) {
        return amplitude > 0 && std::isfinite(amplitude) ? 20.0 * std::log10(std::min(amplitude,1.0f)) : -INFINITY;
    }
};
} // namespace muew
