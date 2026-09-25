#pragma once
#include <algorithm>
#include <cmath>
namespace muew {
// This reports only MUEW's own final output and pre-master drive. It cannot
// know whether a DAW or audio interface clips after the plugin.
struct OutputMeter {
    float left = 0, right = 0, drive = 0;
    void clear() { left = right = drive = 0; }
    void sample(float preL, float preR, float postL, float postR) {
        if (std::isfinite(preL) && std::isfinite(preR))
            drive = std::max(drive, std::max(std::fabs(preL), std::fabs(preR)) * 1.6f);
        if (std::isfinite(postL)) left = std::max(left, std::fabs(postL));
        if (std::isfinite(postR)) right = std::max(right, std::fabs(postR));
    }
    void merge(const OutputMeter& other) {
        left = std::max(left, other.left); right = std::max(right, other.right); drive = std::max(drive, other.drive);
    }
    bool softSaturating() const { return drive >= 1.0f; } // tanh knee, not hard clipping
};
}
