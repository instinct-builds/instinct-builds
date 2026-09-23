// MUEWEditorView.h - the MUEW instrument editor, shared by the standalone
// app and the Audio Unit's Cocoa view. The view never touches the engine
// directly: every preset load or knob edit goes through MUEWEditorHost, which
// the standalone binds to its own synth and the AU binds to AU properties.
#pragma once
#import <AppKit/AppKit.h>
#include "ui_model.h"
#include <set>
#include <string>
#include <vector>

// Each binary gets its own Objective-C class name so a host process that
// loads the AU never sees a class clash.
#ifndef MUEW_EDITOR_CLASS
#define MUEW_EDITOR_CLASS MUEWEditorView
#endif
#define MUEWEditorView MUEW_EDITOR_CLASS

struct MUEWEditorHost {
    virtual ~MUEWEditorHost() {}
    // factoryIndex is the bank/AU number the sound came from (-1 for user
    // presets and anything else outside the factory bank);
    // edited is true once a knob has changed it.
    virtual void applyPreset(const muew::Preset& p, int factoryIndex, bool edited) = 0;
    // Knob edits. A host that publishes parameters (the AU) takes the edit as
    // a parameter change so the DAW can record automation, and returns true;
    // otherwise the editor falls back to applyPreset. Ids are muew::params
    // IDs (ui::knobParam). Gestures bracket a drag.
    virtual bool editParameter(int, const muew::Preset&) { return false; }
    virtual void parameterGesture(int, bool /*begin*/) {}
    virtual bool playsNotes() const { return false; }
    virtual void noteOn(int, float) {}
    virtual void noteOff(int) {}
};

@interface MUEWEditorView : NSView <NSSearchFieldDelegate> {
@public
    MUEWEditorHost* host; // not owned
    muew::Preset current;
    int currentIndex;
    bool edited;
    muew::PresetFilter filter;
    int chip;
    std::set<std::string> favorites;
    std::vector<int> visible;
    int scroll;
    muew::Wavetable table;
    NSInteger dragKnob;
    NSPoint dragStart;
    double dragValue;
    int octave;
    NSSearchField* search;
    // 0.8.0 mod matrix: visible page (4 slots each), selected modulator
    // (index into ui::matrixSources), source badge being dragged onto a knob,
    // route amount / modulator field being dragged.
    int matrixPage;
    int modSel;
    int dragSource;
    NSPoint dragPoint;
    int dropKnob;
    int dropFx;
    int dropAux;     // 0.16.0: route slot whose AUX chip is under a dragged badge, -1 none
    int curveDrag;   // 0.16.0: route slot whose curve is being bent, -1 none
    // 0.17.0 MSEG editor: open MSEG (0/1; 2-5 = LFO 1-4 since 0.18.0; -1 closed), snap grid, and the point,
    // segment curve or loop edge being dragged (-1 none).
    int msegEdit;
    int msegGrid;
    int msegPt;
    int msegSeg;
    int msegLoopEdge;
    int lfoXDrag;    // 0.18.0 LFO editor: PHASE/DELAY/RISE pill being dragged (0-2), -1 none
    int routeDrag;
    int modFieldDrag;
    // 0.13.0 FX chain: card slot being dragged to a new place (-1 = none)
    // and the slot it would land in.
    int fxMove;
    int fxDrop;
    // 0.14.0 FX detail editor: open unit (FxUnit id, -1 = closed) and the
    // slider row being dragged (-1 = none).
    int fxDetail;
    int fxRowDrag;
    // 0.9.0 wavetable editor: oscillator being edited (-1 = closed), the
    // selected frame, draw (0) or harmonic (1) mode, the last stroke point,
    // and the oscillator whose WT POS bar is being dragged (-1 = none).
    int wtEdit;
    int wtFrame;
    int wtMode;
    int wtLastIdx;
    double wtLastVal;
    bool wtDrawing;
    int wtPosDrag;
    // 0.10.0: FILTER panel page (0 = FILTER 1 + AMP, 1 = FILTER 2 + SUB/NOISE).
    int filterPage;
    // 0.11.0 full browser: open flag, sort order (ui::SortMode), star
    // ratings by slug, and the table scroll offset.
    bool browserOpen;
    int sortMode;
    muew::ui::Ratings ratings;
    int bscroll;
}
- (void)loadPresetIndex:(int)i;
// Show a sound that came from the engine side (host recall, host preset menu)
// without echoing it back to the engine.
- (void)adoptPreset:(const muew::Preset&)p index:(int)index edited:(bool)wasEdited;
// Saves the current sound as a user preset and selects it (the + Save button
// after its name prompt). Returns NO if the file could not be written.
- (BOOL)saveUserPresetNamed:(NSString*)name;
// 0.11.0: open or close the full preset browser, and bring a .muew file into
// the Imported bank (the browser's Import button after its file panel).
- (void)setBrowserOpen:(bool)open;
- (BOOL)importPresetFile:(NSString*)path;
@end
