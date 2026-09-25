#pragma once
// MUEW 0.38.0: inclusive frame ranges and one atomic spectral batch edit.
#include "frame_tools.h"
#include <algorithm>

namespace muew {
struct FrameRange {
    int anchor = -1, end = -1;
    bool active(int count) const { return count > 0 && anchor >= 0 && end >= 0; }
    int first(int count) const { return active(count) ? std::clamp(std::min(anchor, end), 0, count - 1) : -1; }
    int last(int count) const { return active(count) ? std::clamp(std::max(anchor, end), 0, count - 1) : -1; }
    bool contains(int index, int count) const { return active(count) && index >= first(count) && index <= last(count); }
    void clear() { anchor = end = -1; }
    void select(int at, int count, bool extend) {
        if (count <= 0) { clear(); return; }
        at = std::clamp(at, 0, count - 1);
        if (!extend) { clear(); return; }
        if (anchor < 0) anchor = at; // normally supplied by the editor's previously selected frame
        end = at;
    }
};

// Returns whether anything changed. Invalid/empty ranges and identity edits
// consume no history. The caller takes one table snapshot before committing.
inline bool applyFrameRange(TableFrames& table, const FrameRange& range, FrameTool tool) {
    if (!range.active((int)table.size())) return false;
    bool changed = false;
    for (int i = range.first((int)table.size()); i <= range.last((int)table.size()); ++i) {
        Frame next = spectralFrameTool(table[i], tool);
        if (next != table[i]) { table[i] = std::move(next); changed = true; }
    }
    return changed;
}
} // namespace muew
