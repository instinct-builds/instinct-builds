// 0.96.0 editor UNDO / REDO model: snapshot stack, cap, redo invalidation, boundaries.
#include "../src/edit_history.h"
#include "../src/preset.h"
#include "../src/factory_bank.h"
#include <cstdio>
using namespace muew;
static int failures = 0;
static void ck(bool ok, const char* msg) { printf("%s %s\n", ok ? "ok:" : "FAIL:", msg); failures += !ok; }
int main() {
    ui::EditHistory<int> h;
    ck(!h.canUndo() && !h.canRedo(), "a fresh history has nothing to undo or redo");
    h.reset(0);
    int cur = 0;
    ck(!h.note(0) && !h.canUndo(), "an unchanged state is not a step");
    cur = 1; ck(h.note(cur), "a change commits one step"); cur = 2; h.note(cur); cur = 3; h.note(cur);
    ck(h.undoSteps() == 3, "three edits are three steps");
    ck(h.undo(cur) && cur == 2 && h.undo(cur) && cur == 1 && h.undo(cur) && cur == 0 && !h.undo(cur) && cur == 0, "undo walks back to the loaded state and stops");
    ck(h.redo(cur) && cur == 1 && h.redo(cur) && cur == 2 && h.redo(cur) && cur == 3 && !h.redo(cur) && cur == 3, "redo walks forward to the newest state and stops");
    h.undo(cur); h.undo(cur); ck(cur == 1 && h.canRedo(), "undo twice from the newest state");
    cur = 9; ck(h.note(cur) && !h.canRedo() && h.undoSteps() == 2, "a new edit after undo discards the redo branch");
    ck(h.undo(cur) && cur == 1 && h.undo(cur) && cur == 0, "history after the branch is consistent");
    h.reset(5); ck(!h.canUndo() && !h.canRedo(), "reset (preset load or external state) clears both stacks");
    ui::EditHistory<int> cap; cap.reset(0);
    for (int i = 1; i <= 100; ++i) { cur = i; cap.note(cur); }
    ck(cap.undoSteps() == 64, "history is capped at 64 steps");
    int n = 0; while (cap.undo(cur)) ++n;
    ck(n == 64 && cur == 36, "the oldest steps fall off, the newest 64 remain");
    ui::EditHistory<int> mem; mem.maxBytes = 100; mem.reset(0, 40);
    for (int i = 1; i <= 6; ++i) { cur = i; mem.note(cur, 40); }
    ck(mem.undoSteps() == 1, "snapshots with heavy tables evict sooner (byte bound)");
    cur = 7; mem.note(cur, 40); ck(mem.canUndo(), "the newest step always survives");
    Preset a = factoryPresets()[0], b = a; b.voice.osc2Level = 0.9;
    ui::EditHistory<Preset> ph; ph.reset(a);
    Preset c = b; ck(ph.note(c) && ph.undo(c) && c == a && ph.redo(c) && c == b, "whole presets round-trip through undo and redo");
    Preset d = b; d.routes.push_back({ModRoute::Source::Macro1, ModRoute::Dest::Osc1Level, 0.5});
    ck(ph.note(d) && ph.undo(c) && c == b && !(c == d), "a matrix edit is its own step");
    printf("%s\n", failures ? "EDIT HISTORY 96 FAILED" : "ALL EDIT HISTORY 96 TESTS PASSED"); return failures ? 1 : 0;
}
