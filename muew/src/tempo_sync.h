#pragma once

namespace muew {

// Tempo-sync divisions: beats per cycle (LFOs) or per repeat (delay).
// Index 0 is free-running. Append only (stored in presets).
constexpr int kSyncCount = 10;
inline double syncBeats(int i) {
    static const double b[kSyncCount] = {0, 4, 2, 1, 0.5, 0.25, 2.0 / 3.0, 1.0 / 3.0, 1.5, 8};
    return (i > 0 && i < kSyncCount) ? b[i] : 0.0;
}

} // namespace muew
