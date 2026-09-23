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
}
- (void)loadPresetIndex:(int)i;
// Show a sound that came from the engine side (host recall, host preset menu)
// without echoing it back to the engine.
- (void)adoptPreset:(const muew::Preset&)p index:(int)index edited:(bool)wasEdited;
// Saves the current sound as a user preset and selects it (the + Save button
// after its name prompt). Returns NO if the file could not be written.
- (BOOL)saveUserPresetNamed:(NSString*)name;
@end
