#pragma once
#include <algorithm>
#include <cmath>
#include <vector>

namespace muew {

// Per-voice multi-stage envelope generator. Points use normalized time (0..1)
// and value (-1..1). Optional loop indices turn any span into a repeating
// shape; one-shot mode holds the final value.
class MSEG {
public:
    struct Point { double time = 0.0, value = 0.0; };

    void setSampleRate(double sr) { sr_ = std::max(1.0, sr); }
    void setRate(double seconds) { seconds_ = std::max(0.001, seconds); }
    void setPoints(std::vector<Point> points) {
        if (points.size() < 2) points = {{0.0, 0.0}, {1.0, 1.0}};
        std::sort(points.begin(), points.end(), [](const Point& a, const Point& b) { return a.time < b.time; });
        points.front().time = 0.0; points.back().time = 1.0;
        for (auto& p : points) p.value = std::clamp(p.value, -1.0, 1.0);
        points_ = std::move(points);
    }
    void setLoop(int startPoint, int endPoint, bool enabled) {
        loopStart_ = startPoint; loopEnd_ = endPoint; loop_ = enabled;
    }
    size_t pointCount() const { return points_.size(); }
    void reset() { phase_ = 0.0; released_ = false; }
    void release() { released_ = true; }

    float process() {
        const double v = valueAt(phase_);
        phase_ += 1.0 / (seconds_ * sr_);
        if (loop_ && !released_ && validLoop()) {
            const double a = points_[loopStart_].time, b = points_[loopEnd_].time;
            if (phase_ > b) phase_ = a + std::fmod(phase_ - a, std::max(1e-9, b - a));
        } else phase_ = std::min(1.0, phase_);
        return static_cast<float>(v);
    }

    double valueAt(double t) const {
        t = std::clamp(t, 0.0, 1.0);
        for (size_t i = 1; i < points_.size(); ++i) {
            if (t <= points_[i].time) {
                const auto& a = points_[i - 1]; const auto& b = points_[i];
                const double f = (t - a.time) / std::max(1e-9, b.time - a.time);
                return a.value + (b.value - a.value) * f;
            }
        }
        return points_.back().value;
    }

private:
    bool validLoop() const { return loopStart_ >= 0 && loopEnd_ > loopStart_ && loopEnd_ < (int)points_.size(); }
    double sr_ = 44100.0, seconds_ = 1.0, phase_ = 0.0;
    int loopStart_ = 0, loopEnd_ = 1;
    bool loop_ = false, released_ = false;
    std::vector<Point> points_{{0.0, 0.0}, {0.15, 1.0}, {0.55, -0.3}, {1.0, 0.0}};
};

} // namespace muew
