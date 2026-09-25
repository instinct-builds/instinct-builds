#pragma once
// 0.32.0 Spectral Sounds: table recipes. A factory preset can describe a
// wavetable as a short recipe instead of 256 x N literal samples:
//   wtgen<o> noise <seed> <frames> <lp0> <lp1>
//       one-pole low-passed noise whose coefficient sweeps lp0 -> lp1 (0.005..1),
//       resynthesized frame by frame with the 0.31.0 texture import.
//   wtgen<o> bands <seed> <frames> <hz0> <hz1> <q>
//       noise through a resonant band-pass sweeping hz0 -> hz1 (vowel/whistle
//       textures), resynthesized the same way.
//   wtgen<o> morph <shapeA> <shapeB> <frames>
//       spectral morph between two built-in shapes (0-4).
//   wtspec<o> <formantSt> <stretch> <tiltDb> <oddEven>
//       then applies the SPECTRAL page's whole-table process.
// Recipes are deterministic (fixed seeds, no platform RNG), so every build
// renders the same table. Saving a preset writes the table itself (wt<o>).
#include "table_import.h"
#include "spectral_process.h"
#include <algorithm>
#include <cmath>
#include <sstream>
#include <string>
#include <vector>

namespace muew {

namespace recipe_detail {
inline double rnd(uint32_t& s) { s = s * 1664525u + 1013904223u; return (s >> 8) / 8388608.0 - 1.0; }
// The texture resynthesis over `frames` evenly spaced 4096-sample windows of x.
inline TableFrames resynth(const std::vector<float>& x, int frames) {
    TableFrames out;
    const double span = (double)(x.size() - 4096);
    for (int k = 0; k < frames; ++k)
        out.push_back(textureFrame(x, (size_t)std::llround(frames == 1 ? 0 : span * k / (frames - 1)), 44100.0));
    return out;
}
inline size_t lengthFor(int frames) { return 4096 + 2048 * (size_t)std::max(1, frames - 1); }
} // namespace recipe_detail

// Parses the arguments after `wtgen<o>`; empty on anything malformed.
inline TableFrames tableFromRecipe(const std::string& args) {
    using namespace recipe_detail;
    std::istringstream ls(args);
    std::string kind; ls >> kind;
    if (kind == "noise") {
        unsigned seed = 0; int n = 0; double a0 = 0, a1 = 0;
        if (!(ls >> seed >> n >> a0 >> a1) || n < 2 || n > kMaxFrames) return {};
        a0 = std::clamp(a0, 0.005, 1.0); a1 = std::clamp(a1, 0.005, 1.0);
        std::vector<float> x(lengthFor(n)); uint32_t s = seed; double y = 0;
        for (size_t i = 0; i < x.size(); ++i) {
            const double a = a0 + (a1 - a0) * i / x.size();
            y += a * (rnd(s) - y); x[i] = (float)(0.5 * y / std::sqrt(a));
        }
        return resynth(x, n);
    }
    if (kind == "bands") {
        unsigned seed = 0; int n = 0; double f0 = 0, f1 = 0, q = 0;
        if (!(ls >> seed >> n >> f0 >> f1 >> q) || n < 2 || n > kMaxFrames) return {};
        f0 = std::clamp(f0, 100.0, 12000.0); f1 = std::clamp(f1, 100.0, 12000.0); q = std::clamp(q, 0.5, 30.0);
        std::vector<float> x(lengthFor(n)); uint32_t s = seed; double lo = 0, bp = 0;
        for (size_t i = 0; i < x.size(); ++i) { // Chamberlin state-variable band-pass, exponential sweep
            const double hz = f0 * std::pow(f1 / f0, (double)i / x.size());
            const double f = 2.0 * std::sin(M_PI * std::min(hz, 11000.0) / 44100.0);
            const double hi = rnd(s) - lo - bp / q;
            bp += f * hi; lo += f * bp;
            x[i] = (float)(0.3 * bp);
        }
        return resynth(x, n);
    }
    if (kind == "morph") {
        int a = 0, b = 0, n = 0;
        if (!(ls >> a >> b >> n) || n < 2 || n > kMaxFrames) return {};
        return spectralMorph({shapeFrame(a), shapeFrame(b)}, n);
    }
    return {};
}

// Parses the arguments after `wtspec<o>`.
inline bool specFromText(const std::string& args, SpectralProcess& sp) {
    std::istringstream ls(args);
    SpectralProcess p;
    if (!(ls >> p.formantSt >> p.stretch >> p.tiltDb >> p.oddEven)) return false;
    p.formantSt = std::clamp(p.formantSt, -24.0, 24.0); p.stretch = std::clamp(p.stretch, -0.5, 0.5);
    p.tiltDb = std::clamp(p.tiltDb, -12.0, 12.0); p.oddEven = std::clamp(p.oddEven, -1.0, 1.0);
    sp = p; return true;
}

} // namespace muew
