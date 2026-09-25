// MUEWEditorView.h - the MUEW instrument editor, shared by the standalone
// app and the Audio Unit's Cocoa view. The view never touches the engine
// directly: every preset load or knob edit goes through MUEWEditorHost, which
// the standalone binds to its own synth and the AU binds to AU properties.
#pragma once
#import <AppKit/AppKit.h>
#include "ui_model.h"
#include "spectral_process.h"
#include "table_history.h"
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
    int warpAmtDrag;  // 0.19.0: oscillator whose WARP 2 amount bar is being dragged, -1 none
    int filterXDrag;  // 0.21.0: FILTER 1 DRIVE / KEYTRACK / MORPH (0-2) or 0.22.0 F1 MIX / F2 MIX / BALANCE / F2 MORPH (3-6) bar being dragged, -1 none
    muew::Performance perfShown; // 0.24.0 live MIDI performance (AU meters)
    int perfNote;
    bool perfSustain;
    // 0.25.0 ARP page: GATE (0) / SWING (1) pill being dragged (-1 none), and the arp as the AU last played it.
    int arpDrag;
    bool arpLiveOn;
    int arpLiveIndex, arpLiveNote, arpLiveStep, arpLivePoolN;
    int arpLivePool[8];
    // 0.26.0 step pattern lane: cell being velocity-dragged (-1 none), the AU's live cell and host lock.
    int patDrag, arpLivePatCell;
    bool arpLiveLocked;
    // 0.30.0 Engine HQ header meter (fed by the host at ~30 Hz).
    int engVoices, engLimit;
    float engCpu;
    bool engRender;
    int voiceDrag;   // 0.23.0 voice strip: GLIDE (0) or BLEND (1) bar being dragged, -1 none
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
    // 0.31.0 SPECTRAL page: pending whole-table process (APPLY writes it into the table) and the bar being dragged.
    muew::SpectralProcess wtSpec;
    int wtSpecDrag;
    muew::TableHistory wtHistory[2]; // 0.32.0 WT editor undo/redo, one per oscillator
    // 0.33.0 per-oscillator A/B compare: A = the oscillator as the preset loaded it
    // (table, morph target, morph amount), B = the edit. wtCmpA is the oscillator
    // showing A (-1 = none); the edit waits in the hold slots meanwhile.
    muew::TableFrames wtCmpRef[2], wtCmpHold[2];
    muew::SpectralProcess wtCmpRefMs[2], wtCmpHoldMs[2];
    double wtCmpRefAmt[2], wtCmpHoldAmt[2];
    bool wtCmpHas[2];
    // 0.35.0 live morph meter (from the engine, -1 = nothing sounding) and the
    // processed table the main OSC display blends toward, cached per oscillator.
    float liveMorph[2];
    muew::TableFrames morphCacheIn[2], morphCacheOut[2];
    muew::SpectralProcess morphCacheSpec[2];
    // 0.36.0 per-voice morph ghosts (highest first) and the SPEC page's A snapshot flag.
    float voiceMorph[2][8];
    int voiceMorphN[2];
    bool wtCmpSnap[2];
    int wtCmpA;
    // 0.10.0: FILTER panel page (0 = FILTER 1 + AMP, 1 = FILTER 2 + SUB/NOISE, 2 = ARP since 0.25.0).
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
// 0.24.0: live MIDI performance values for the WHL / AT / PB / KEY previews.
- (void)showPerformance:(const muew::Performance&)p note:(int)note sustain:(bool)sus;
// 0.25.0: the arp as the AU is playing it, for the ARP page's step display.
- (void)showArpOn:(bool)on pool:(const int*)pool count:(int)n index:(int)index note:(int)note step:(int)step;
- (void)showArpPatCell:(int)cell locked:(bool)locked; // 0.26.0
- (void)showEngineVoices:(int)active limit:(int)limit cpu:(float)cpu render:(bool)render; // 0.30.0
- (void)showLiveMorphA:(float)a b:(float)b; // 0.35.0
- (void)showVoiceMorph:(const float*)a count:(int)na b:(const float*)b count:(int)nb; // 0.36.0
- (std::vector<double>)ghostMorphs:(int)o; // 0.36.0
@end
