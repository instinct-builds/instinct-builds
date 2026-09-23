#pragma once
#include <algorithm>
#include <cmath>

namespace muew {

// 0.16.0 route response curve: power shaping of |x| in 0..1 with the sign
// kept, so bipolar sources bend symmetrically. c > 0 starts slow (exp),
// c < 0 starts fast (log). c == 0 returns x untouched (bit-exact).
inline double routeCurve(double x, double c) {
    if (c == 0.0) return x;
    c = std::clamp(c, -1.0, 1.0);
    double a = std::min(std::fabs(x), 1.0);
    double y = c > 0 ? std::pow(a, 1.0 + 3.0 * c) : 1.0 - std::pow(1.0 - a, 1.0 - 3.0 * c);
    return x < 0 ? -y : y;
}

} // namespace muew
