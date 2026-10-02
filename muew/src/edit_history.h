// 0.96.0 editor-side UNDO / REDO of sound edits.
// A bounded stack of whole-state snapshots. `base` is the last committed
// state; note() commits the current state as one step when it differs.
// Callers hold note() back while a drag is in progress, so one gesture is one
// step. A preset load or an external (host) state change calls reset().
#pragma once
#include <cstddef>
#include <utility>
#include <vector>

namespace muew { namespace ui {

constexpr size_t kEditHistorySteps = 64;
constexpr size_t kEditHistoryBytes = 96u * 1024u * 1024u; // snapshots with big user tables evict sooner

template <class T>
struct EditHistory {
    struct Item { T v; size_t w; };
    std::vector<Item> past, future;
    T base{}; size_t baseW = 0; bool hasBase = false;
    size_t maxSteps = kEditHistorySteps, maxBytes = kEditHistoryBytes;

    void reset(const T& cur, size_t weight = 0) { past.clear(); future.clear(); base = cur; baseW = weight; hasBase = true; }
    // Host-side change to the same sound: keep the steps, move the baseline.
    void rebase(const T& cur, size_t weight = 0) { base = cur; baseW = weight; hasBase = true; }
    bool canUndo() const { return !past.empty(); }
    bool canRedo() const { return !future.empty(); }
    size_t undoSteps() const { return past.size(); }
    size_t redoSteps() const { return future.size(); }

    // Commit `cur` as a new step when it differs from the last committed state.
    bool note(const T& cur, size_t weight = 0) {
        if (!hasBase) { reset(cur, weight); return false; }
        if (cur == base) return false;
        past.push_back({base, baseW});
        future.clear();
        base = cur; baseW = weight;
        trim();
        return true;
    }
    // Restore the previous / next committed state into `cur`.
    bool undo(T& cur) {
        if (past.empty()) return false;
        future.push_back({base, baseW});
        base = std::move(past.back().v); baseW = past.back().w; past.pop_back();
        cur = base; return true;
    }
    bool redo(T& cur) {
        if (future.empty()) return false;
        past.push_back({base, baseW});
        base = std::move(future.back().v); baseW = future.back().w; future.pop_back();
        cur = base; return true;
    }
private:
    void trim() {
        size_t bytes = baseW; for (const auto& i : past) bytes += i.w;
        while (!past.empty() && (past.size() > maxSteps || bytes > maxBytes)) { bytes -= past.front().w; past.erase(past.begin()); }
    }
};

}} // namespace muew::ui
