#pragma once
// MUEW 0.37.0: four non-destructive-until-clicked, per-frame spectral tools.
// The editor owns the undo step; these pure transforms never alter other frames.
#include "custom_table.h"
#include <algorithm>
#include <cmath>
#include <complex>
#include <vector>

namespace muew {

enum class FrameTool { Focus, Blur, Align, Flip };

inline Frame spectralFrameTool(const Frame& frame, FrameTool tool) {
    if (frame.size() != kFrameSize) return frame;
    constexpr int H = kFrameSize / 2;
    const auto src = frameSpectrum(frame);
    std::vector<std::complex<double>> dst(kFrameSize);
    double peak = 0;
    for (int k = 1; k < H; ++k) peak = std::max(peak, std::abs(src[k]));
    if (peak < 1e-12) return frame; // silence remains silence
    for (int k = 1; k < H; ++k) {
        const double mag = std::abs(src[k]);
        std::complex<double> v = src[k];
        switch (tool) {
        case FrameTool::Focus: { // soft gate below 18% of the loudest partial
            double g = std::clamp((mag / peak - 0.04) / 0.14, 0.0, 1.0);
            v *= g * g * (3.0 - 2.0 * g);
            break;
        }
        case FrameTool::Blur: { // reflected five-tap spectral magnitude smoothing
            auto at = [&](int j) { return std::abs(src[std::clamp(j, 1, H - 1)]); };
            double m = (at(k - 2) + 2 * at(k - 1) + 3 * mag + 2 * at(k + 1) + at(k + 2)) / 9.0;
            v = std::polar(m, mag > 1e-12 ? std::arg(v) : -M_PI / 2);
            break;
        }
        case FrameTool::Align: // sine-phase all active partials: sharper, phase-coherent cycle
            v = std::complex<double>(0.0, -mag);
            break;
        case FrameTool::Flip: // conjugation reverses time, while retaining all partial magnitudes
            v = std::conj(v);
            break;
        }
        dst[k] = v;
        dst[kFrameSize - k] = std::conj(v); // real-valued waveform
    }
    // The editor's normal frame controls use peak normalization too.
    fft(dst, true);
    Frame out(kFrameSize);
    float p = 0;
    for (int i = 0; i < kFrameSize; ++i) {
        out[i] = (float)dst[i].real(); p = std::max(p, std::fabs(out[i]));
    }
    if (p > 0) for (float& x : out) x /= p;
    return out;
}

} // namespace muew
