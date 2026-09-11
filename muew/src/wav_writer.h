#pragma once
#include <cstdint>
#include <cstdio>
#include <vector>
#include <cmath>

namespace muew {

// Minimal 16-bit mono PCM WAV writer.
inline bool writeWav(const char* path, const std::vector<float>& samples, int sampleRate,
                     int channels = 1) {
    FILE* f = std::fopen(path, "wb");
    if (!f) return false;
    uint32_t dataSize = static_cast<uint32_t>(samples.size() * 2);
    uint32_t riffSize = 36 + dataSize;
    auto w16 = [&](uint16_t v) { std::fwrite(&v, 2, 1, f); };
    auto w32 = [&](uint32_t v) { std::fwrite(&v, 4, 1, f); };
    std::fwrite("RIFF", 1, 4, f); w32(riffSize);
    std::fwrite("WAVE", 1, 4, f);
    std::fwrite("fmt ", 1, 4, f); w32(16); w16(1); w16((uint16_t)channels);
    w32(static_cast<uint32_t>(sampleRate));
    w32(static_cast<uint32_t>(sampleRate * channels * 2));
    w16(static_cast<uint16_t>(channels * 2)); w16(16);
    std::fwrite("data", 1, 4, f); w32(dataSize);
    for (float s : samples) {
        float c = std::fmax(-1.0f, std::fmin(1.0f, s));
        w16(static_cast<uint16_t>(static_cast<int16_t>(c * 32767.0f)));
    }
    std::fclose(f);
    return true;
}

} // namespace muew
