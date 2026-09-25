// MUEW 0.38.0: inclusive range selection and atomic spectral batch edits.
#include "../src/frame_range.h"
#include "../src/table_history.h"
#include "../src/preset.h"
#include "../src/factory_bank.h"
#include <cstdio>
using namespace muew;
static int bad = 0;
static void check(bool ok, const char* text) { printf("%s %s\n", ok ? "ok:  " : "FAIL:", text); bad += !ok; }
int main() {
    FrameRange r;
    check(!r.active(64) && !r.contains(4, 64), "no accidental range on fresh editor");
    r.anchor = 7; r.select(3, 16, true);
    check(r.first(16) == 3 && r.last(16) == 7 && r.contains(5, 16) && !r.contains(2, 16), "reverse shift selection includes both endpoints");
    r.select(10, 16, true);
    check(r.first(16) == 7 && r.last(16) == 10, "a second shift selection retains the original anchor");
    r.select(2, 16, false);
    check(!r.active(16), "ordinary click clears the range");
    r.anchor = 12; r.select(99, 16, true);
    check(r.first(16) == 12 && r.last(16) == 15 && r.contains(14, 16), "range clamps to the table's final frame");
    TableFrames t{shapeFrame(2), shapeFrame(2), shapeFrame(2), shapeFrame(2), shapeFrame(2)};
    TableFrames original = t;
    r.anchor = 1; r.end = 3;
    TableHistory h; int frame = 3;
    TableFrames candidate = t;
    check(applyFrameRange(candidate, r, FrameTool::Focus), "batch tool detects an edit");
    h.push(t, frame, "FOCUS RANGE"); t = candidate;
    check(t[0] == original[0] && t[4] == original[4] && t[1] != original[1] && t[2] != original[2] && t[3] != original[3], "inclusive range transforms only selected frames");
    check(h.undoDepth() == 1 && h.undoLabel() == "FOCUS RANGE", "batch consumes exactly one labelled undo step");
    check(h.undo(t, frame) && t == original && h.redo(t, frame) && t == candidate, "one undo restores the entire range; redo restores the batch");
    FrameRange off;
    check(!applyFrameRange(t, off, FrameTool::Blur), "empty selection is a no-op");
    TableFrames quiet(5, Frame(kFrameSize, 0));
    check(!applyFrameRange(quiet, r, FrameTool::Focus), "identity batch is a no-op");
    Preset p; p.voice.osc1Shape = kCustomShape; p.tables[0] = t;
    Preset loaded; check(loaded.parse(p.serialize()) && loaded.tables[0] == t, "AU state preserves the full edited table");
    puts(bad ? "RANGE38 FAILED" : "ALL RANGE38 TESTS PASSED"); return bad ? 1 : 0;
}
