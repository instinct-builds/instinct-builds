#pragma once
// 0.32.0 WT editor undo/redo: snapshots of one oscillator's table taken
// before each edit (DRAW or HARM stroke, + ADD, DUP, DELETE, MORPH, SMOOTH,
// NORMAL, IMPORT, SPECTRAL APPLY). Undo restores the table and the frame
// that was selected; a new edit clears the redo side. Tables are at most
// 64 x 256 floats, so 48 levels cost well under 4 MB per oscillator.
#include "custom_table.h"
#include <string>
#include <vector>

namespace muew {

struct TableState { TableFrames table; int frame = 0; std::string label; };

class TableHistory {
public:
    static constexpr int kLevels = 48;
    // Call before an edit with the state it is about to change.
    void push(const TableFrames& t, int frame, const std::string& label) {
        undo_.push_back({t, frame, label});
        if ((int)undo_.size() > kLevels) undo_.erase(undo_.begin());
        redo_.clear();
    }
    bool canUndo() const { return !undo_.empty(); }
    bool canRedo() const { return !redo_.empty(); }
    const std::string& undoLabel() const { static const std::string none; return undo_.empty() ? none : undo_.back().label; }
    const std::string& redoLabel() const { static const std::string none; return redo_.empty() ? none : redo_.back().label; }
    // Swap the current table for the previous one; false when there is none.
    bool undo(TableFrames& t, int& frame) { return step(undo_, redo_, t, frame); }
    bool redo(TableFrames& t, int& frame) { return step(redo_, undo_, t, frame); }
    void clear() { undo_.clear(); redo_.clear(); }
    int undoDepth() const { return (int)undo_.size(); }
    int redoDepth() const { return (int)redo_.size(); }
private:
    static bool step(std::vector<TableState>& from, std::vector<TableState>& to, TableFrames& t, int& frame) {
        if (from.empty()) return false;
        TableState s = std::move(from.back()); from.pop_back();
        to.push_back({t, frame, s.label});
        t = std::move(s.table); frame = std::clamp(s.frame, 0, std::max(0, (int)t.size() - 1));
        return true;
    }
    std::vector<TableState> undo_, redo_;
};

} // namespace muew
