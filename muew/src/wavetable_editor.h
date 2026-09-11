// wavetable_editor.h - custom wavetable creation for MUEW: harmonic
// (additive) specification, freehand sample editing, morphing, and
// band-limited mipmap generation via an in-repo radix-2 FFT. Tables plug
// straight into the synth as extra shape slots. Zero dependencies, C++17.
#pragma once
#include "wavetable.h"
#include <complex>
#include <iomanip>
#include <map>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

namespace muew {

// Iterative radix-2 FFT. invert=false: time -> frequency; invert=true:
// frequency -> time (with 1/N normalization).
inline void fft(std::vector<std::complex<double>>& a, bool invert) {
    const size_t n = a.size();
    for (size_t i = 1, j = 0; i < n; ++i) { // bit-reversal permutation
        size_t bit = n >> 1;
        for (; j & bit; bit >>= 1) j ^= bit;
        j ^= bit;
        if (i < j) std::swap(a[i], a[j]);
    }
    for (size_t len = 2; len <= n; len <<= 1) {
        double ang = 2.0 * M_PI / static_cast<double>(len) * (invert ? 1.0 : -1.0);
        std::complex<double> wlen(std::cos(ang), std::sin(ang));
        for (size_t i = 0; i < n; i += len) {
            std::complex<double> w(1.0);
            for (size_t j = 0; j < len / 2; ++j) {
                auto u = a[i + j];
                auto v = a[i + j + len / 2] * w;
                a[i + j] = u + v;
                a[i + j + len / 2] = u - v;
                w *= wlen;
            }
        }
    }
    if (invert) for (auto& x : a) x /= static_cast<double>(n);
}

// One mipmap level per octave from any single-cycle wave: each level keeps
// only the harmonics that octave can represent (same band-limit scheme as
// the built-in shapes), then normalizes peak to 1.
inline std::vector<std::vector<float>> buildMipmapLevels(const std::vector<float>& singleCycle) {
    const int N = Wavetable::kTableSize;
    std::vector<std::complex<double>> spectrum(N);
    for (int i = 0; i < N; ++i) spectrum[i] = {static_cast<double>(singleCycle[i]), 0.0};
    fft(spectrum, false);

    std::vector<std::vector<float>> levels(Wavetable::kNumLevels);
    for (int lvl = 0; lvl < Wavetable::kNumLevels; ++lvl) {
        int maxHarmonic = 1 << (Wavetable::kNumLevels - 1 - lvl);
        if (maxHarmonic > N / 2) maxHarmonic = N / 2;
        std::vector<std::complex<double>> band = spectrum;
        for (int k = 0; k < N; ++k) {
            int harmonic = std::min(k, N - k); // bins above N/2 are negative frequencies
            if (harmonic > maxHarmonic) band[k] = {0.0, 0.0};
        }
        fft(band, true);
        levels[lvl].resize(N);
        float peak = 0.0f;
        for (int i = 0; i < N; ++i) {
            levels[lvl][i] = static_cast<float>(band[i].real());
            peak = std::max(peak, std::fabs(levels[lvl][i]));
        }
        if (peak > 0.0f) for (auto& x : levels[lvl]) x /= peak;
    }
    return levels;
}

// The editor: additive harmonics, freehand samples, morphing, serialization.
class WavetableEditor {
public:
    static constexpr int kSize = Wavetable::kTableSize;

    WavetableEditor() : wave_(kSize, 0.0f) {}

    // --- harmonic (additive) mode ---
    void setHarmonic(int n, double amplitude, double phase = 0.0) {
        if (n >= 1 && n <= kSize / 2) harmonics_[n] = {amplitude, phase};
    }
    void removeHarmonic(int n) { harmonics_.erase(n); }
    void clearHarmonics() { harmonics_.clear(); }
    const std::map<int, std::pair<double, double>>& harmonics() const { return harmonics_; }

    // Rebuilds the single-cycle wave from the harmonic spec.
    void rebuild() {
        std::fill(wave_.begin(), wave_.end(), 0.0f);
        for (const auto& [n, ap] : harmonics_) {
            for (int i = 0; i < kSize; ++i) {
                double ph = static_cast<double>(i) / kSize;
                wave_[i] += static_cast<float>(ap.first * std::sin(2.0 * M_PI * n * ph + ap.second));
            }
        }
        normalize();
    }

    // --- freehand mode ---
    void drawSample(int i, double value) {
        if (i >= 0 && i < kSize) wave_[i] = static_cast<float>(std::max(-1.0, std::min(1.0, value)));
    }
    void smooth(int passes) {
        for (int p = 0; p < passes; ++p) {
            auto w = wave_;
            for (int i = 0; i < kSize; ++i) {
                int prev = (i + kSize - 1) % kSize, next = (i + 1) % kSize;
                wave_[i] = 0.25f * w[prev] + 0.5f * w[i] + 0.25f * w[next];
            }
        }
    }
    void normalize() {
        float peak = 0.0f;
        for (float x : wave_) peak = std::max(peak, std::fabs(x));
        if (peak > 0.0f) for (auto& x : wave_) x /= peak;
    }

    const std::vector<float>& singleCycle() const { return wave_; }
    std::vector<std::vector<float>> buildLevels() const { return buildMipmapLevels(wave_); }

    // Crossfade two single-cycle waves (same size); t=0 -> a, t=1 -> b.
    static std::vector<float> morph(const std::vector<float>& a, const std::vector<float>& b, double t) {
        std::vector<float> out(std::min(a.size(), b.size()));
        for (size_t i = 0; i < out.size(); ++i)
            out[i] = static_cast<float>(a[i] * (1.0 - t) + b[i] * t);
        return out;
    }

    // Flat key/value text, like the preset format. Exact round-trip.
    static constexpr const char* kMagic = "muew-wavetable 1";
    std::string serialize() const {
        std::ostringstream o;
        o << kMagic << "\n";
        o << "harmonics " << harmonics_.size() << "\n";
        o << std::setprecision(17);
        for (const auto& [n, ap] : harmonics_)
            o << "harmonic " << n << " " << ap.first << " " << ap.second << "\n";
        o << "samples " << wave_.size() << "\n";
        o << std::setprecision(9);
        for (size_t i = 0; i < wave_.size(); ++i)
            o << wave_[i] << (i + 1 == wave_.size() ? "\n" : " ");
        return o.str();
    }

    bool parse(const std::string& text) {
        std::istringstream in(text);
        std::string line;
        if (!std::getline(in, line) || line != kMagic) return false;
        std::map<int, std::pair<double, double>> newHarmonics;
        std::vector<float> newWave;
        while (std::getline(in, line)) {
            std::istringstream ls(line);
            std::string key;
            ls >> key;
            if (key == "harmonics") {
                size_t n;
                ls >> n; // advisory count
            } else if (key == "harmonic") {
                int n;
                double amp, phase;
                ls >> n >> amp >> phase;
                newHarmonics[n] = {amp, phase};
            } else if (key == "samples") {
                size_t n;
                ls >> n;
                newWave.reserve(n);
                std::string values;
                while (newWave.size() < n && std::getline(in, values)) {
                    std::istringstream vs(values);
                    float v;
                    while (vs >> v) newWave.push_back(v);
                }
                if (newWave.size() != n) return false;
            }
        }
        if (newWave.size() != kSize) return false;
        harmonics_ = newHarmonics;
        wave_ = newWave;
        return true;
    }

private:
    std::map<int, std::pair<double, double>> harmonics_; // n -> (amplitude, phase)
    std::vector<float> wave_;
};

} // namespace muew
