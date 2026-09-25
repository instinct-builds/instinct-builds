// MUEW 0.32.0 Spectral Sounds + Undo: table recipes in factory presets and
// the WT editor's undo/redo history.
#include "../src/preset.h"
#include "../src/factory_bank.h"
#include "../src/table_history.h"
#include <cmath>
#include <cstdio>
#include <string>
using namespace muew;

static int g_fail = 0;
static void check(bool c, const std::string& n) { printf("%s %s\n", c ? "ok:  " : "FAIL:", n.c_str()); if (!c) ++g_fail; }

int main() {
    // ---- Recipes ----
    TableFrames a = tableFromRecipe("noise 101 32 0.9 0.03"), b = tableFromRecipe("noise 101 32 0.9 0.03");
    check(a.size() == 32 && a == b, "noise recipe: 32 frames, identical on every parse");
    check(frameCentroid(a.front()) > 2.0 * frameCentroid(a.back()), "noise recipe follows its sweep: bright first, dark last");
    TableFrames c = tableFromRecipe("bands 303 16 350 2600 6");
    check(c.size() == 16 && frameCentroid(c.back()) > frameCentroid(c.front()), "bands recipe sweeps its resonance upward");
    TableFrames m = tableFromRecipe("morph 2 3 8");
    check(m.size() == 8 && m.front() == shapeFrame(2) && m.back() == shapeFrame(3), "morph recipe keeps its key shapes at the ends");
    check(tableFromRecipe("noise 1 1 0.5 0.5").empty() && tableFromRecipe("bogus 1 2 3").empty() && tableFromRecipe("bands 1 99 100 200 1").empty(),
          "malformed recipes give no table");
    bool norm = true; for (const auto& f : a) { float pk = 0; for (float v : f) pk = std::max(pk, std::fabs(v)); norm &= std::fabs(pk - 1.0f) < 1e-4; }
    check(norm, "recipe frames are normalized");

    // wtspec applies after the table, whatever the line order.
    Preset p1, p2;
    p1.parse("muew-preset 2\nname X\nosc1Shape 5\nwtgen1 morph 2 3 8\nwtspec1 7 0 -3 0\n");
    p2.parse("muew-preset 2\nname X\nosc1Shape 5\nwtspec1 7 0 -3 0\nwtgen1 morph 2 3 8\n");
    SpectralProcess sp; sp.formantSt = 7; sp.tiltDb = -3;
    check(p1.tables[0] == processTable(tableFromRecipe("morph 2 3 8"), sp) && p1.tables[0] == p2.tables[0], "wtspec processes the generated table in either line order");
    Preset rt; rt.parse(p1.serialize());
    check(rt.tables[0] == p1.tables[0], "saving writes the table itself and reloads it exactly");

    // ---- Factory bank ----
    const auto& bank = factoryPresets();
    check(kFactoryPresetCount >= 104, "factory bank keeps the 104 presets (80 + 24 appended in 0.32.0)");
    int tex = 0; bool tables = true, custom = true, deep = true;
    for (int i = 80; i < (int)bank.size(); ++i) {
        tables &= !bank[i].tables[0].empty();
        custom &= bank[i].voice.osc1Shape == kCustomShape;
        deep &= bank[i].tables[0].size() >= 8;
        tex += bank[i].info.category == "Texture";
    }
    check(tables && custom && deep, "every new preset plays a generated table of 8+ frames on OSC A");
    check(tex >= 10, "10+ new presets land in the browser's Texture category");

    // ---- Undo / redo ----
    TableHistory h; TableFrames t{shapeFrame(2)}; int fr = 0;
    check(!h.canUndo() && !h.canRedo() && !h.undo(t, fr), "a fresh history has nothing to undo");
    const TableFrames t0 = t;
    h.push(t, fr, "ADD"); t.push_back(shapeFrame(3)); fr = 1;
    const TableFrames t1 = t;
    h.push(t, fr, "APPLY"); t = processTable(t, sp);
    check(h.undoDepth() == 2 && h.undoLabel() == "APPLY", "each edit pushes one level, labelled");
    check(h.undo(t, fr) && t == t1 && fr == 1, "undo restores the table and selected frame before APPLY");
    check(h.undo(t, fr) && t == t0 && fr == 0, "a second undo steps back past + ADD");
    check(h.redo(t, fr) && t == t1 && h.redo(t, fr) && t == processTable(t1, sp), "redo replays both edits");
    h.undo(t, fr); h.push(t, fr, "SMOOTH"); smoothFrame(t[fr], 2);
    check(!h.canRedo(), "a new edit clears the redo side");
    for (int i = 0; i < 100; ++i) h.push(t, fr, "DRAW");
    check(h.undoDepth() == TableHistory::kLevels, "history keeps the newest 48 levels");
    h.push(TableFrames{shapeFrame(0), shapeFrame(1)}, 5, "DELETE");
    TableFrames u = t; int uf = 0; h.undo(u, uf);
    check(uf == 1, "a restored frame index is clamped into the restored table");

    if (g_fail) { printf("%d FAILED\n", g_fail); return 1; }
    printf("ALL SPECTRAL32 TESTS PASSED\n");
    return 0;
}
