// MUEWAUView.mm - Cocoa editor for the MUEW Audio Unit. Hosts such as
// Ableton Live ask the AU for kAudioUnitProperty_CocoaUI, load this class
// from the component bundle, and embed the returned view in the plugin
// window. The view is the same editor the standalone app uses, bound to the
// AU through its preset properties instead of an in-process synth.
#import <AppKit/AppKit.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AudioToolbox/AudioUnitUtilities.h>
#if __has_include(<AudioToolbox/AUCocoaUIView.h>)
#import <AudioToolbox/AUCocoaUIView.h>
#else
#import <AudioUnit/AUCocoaUIView.h>
#endif
#import "MUEWEditorView.h"
#include "MUEWProperties.h"
#include "au_params.h"
#include <string>

using namespace muew;

namespace {

bool ReadAUState(AudioUnit au, Preset& out, SInt32& number, UInt32& generation) {
    CFStringRef str = nullptr;
    UInt32 size = sizeof(str);
    if (AudioUnitGetProperty(au, kMUEWProperty_PresetState, kAudioUnitScope_Global, 0, &str, &size) != noErr || !str)
        return false;
    NSString* ns = (__bridge_transfer NSString*)str; // we own the returned string
    if (!out.parse(std::string(ns.UTF8String ?: ""))) return false;
    AUPreset p{}; size = sizeof(p);
    number = -1;
    if (AudioUnitGetProperty(au, kAudioUnitProperty_PresentPreset, kAudioUnitScope_Global, 0, &p, &size) == noErr) {
        number = p.presetNumber;
        if (p.presetName) CFRelease(p.presetName);
    }
    size = sizeof(generation);
    generation = 0;
    AudioUnitGetProperty(au, kMUEWProperty_StateGeneration, kAudioUnitScope_Global, 0, &generation, &size);
    return true;
}

UInt32 ReadGeneration(AudioUnit au) {
    UInt32 g = 0, size = sizeof(g);
    AudioUnitGetProperty(au, kMUEWProperty_StateGeneration, kAudioUnitScope_Global, 0, &g, &size);
    return g;
}

// Sends editor actions to the AU. Factory loads go through PresentPreset so
// the host shows the preset name; edits send the full sound.
struct AUEditorHost : MUEWEditorHost {
    AudioUnit au;
    UInt32 seenGeneration = 0;
    explicit AUEditorHost(AudioUnit unit) : au(unit) {}
    void applyPreset(const Preset& p, int factoryIndex, bool edited) override {
        if (!edited && factoryIndex >= 0) {
            AUPreset sel{factoryIndex, nullptr};
            AudioUnitSetProperty(au, kAudioUnitProperty_PresentPreset, kAudioUnitScope_Global, 0, &sel, sizeof(sel));
        } else {
            NSString* text = [NSString stringWithUTF8String:p.serialize().c_str()];
            CFStringRef str = (__bridge CFStringRef)text;
            AudioUnitSetProperty(au, kMUEWProperty_PresetState, kAudioUnitScope_Global, 0, &str, sizeof(str));
            if (!edited) { // a user preset: show its name in the host
                NSString* name = [NSString stringWithUTF8String:p.info.name.c_str()] ?: @"";
                AUPreset named{-1, (__bridge CFStringRef)name};
                AudioUnitSetProperty(au, kAudioUnitProperty_PresentPreset, kAudioUnitScope_Global, 0, &named, sizeof(named));
            }
        }
        seenGeneration = ReadGeneration(au);
    }
    // Knob drags become AU parameter changes, announced to the host so Live
    // records automation and moves any mapped controls.
    bool editParameter(int id, const Preset& p) override {
        if (!params::valid(id)) return false;
        AudioUnitParameter param{au, static_cast<AudioUnitParameterID>(id), kAudioUnitScope_Global, 0};
        AUParameterSet(nullptr, nullptr, &param, static_cast<AudioUnitParameterValue>(params::get(p, id)), 0);
        seenGeneration = ReadGeneration(au);
        return true;
    }
    void parameterGesture(int id, bool begin) override {
        if (!params::valid(id)) return;
        AudioUnitEvent e{};
        e.mEventType = begin ? kAudioUnitEvent_BeginParameterChangeGesture : kAudioUnitEvent_EndParameterChangeGesture;
        e.mArgument.mParameter = AudioUnitParameter{au, static_cast<AudioUnitParameterID>(id), kAudioUnitScope_Global, 0};
        AUEventListenerNotify(nullptr, nullptr, &e);
    }
};

} // namespace

// Owns the AU binding and follows host-side changes (host preset menu,
// project recall) by watching the AU's state generation.
@interface MUEWAUEditorContainer_0_23 : MUEWEditorView {
@public
    AUEditorHost* auHost;
    NSTimer* follow;
}
@end

@implementation MUEWAUEditorContainer_0_23
- (void)syncFromAU:(BOOL)force {
    if (!auHost) return;
    UInt32 g = ReadGeneration(auHost->au);
    if (!force && g == auHost->seenGeneration) return;
    Preset p; SInt32 number = -1; UInt32 gen = 0;
    if (!ReadAUState(auHost->au, p, number, gen)) return;
    auHost->seenGeneration = gen;
    const ui::Library& lib = ui::library();
    int index = number;
    bool wasEdited = false;
    if (index < 0) {
        // Not a factory number: a saved user preset (unchanged) or an edit
        // that keeps its origin's name for reset and stepping.
        index = lib.indexOfName(p.info.name);
        wasEdited = !(index >= 0 && lib.isUser(index) && lib.at(index) == p);
    }
    [self adoptPreset:p index:index edited:wasEdited];
}
// The sound the editor is showing, as preset text (read by the CI harness
// through KVC to prove host automation reaches the open editor).
- (NSString*)muewDisplayedState {
    return [NSString stringWithUTF8String:current.serialize().c_str()];
}
- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    [follow invalidate];
    follow = nil;
    if (self.window && auHost) {
        __weak MUEWAUEditorContainer_0_23* weakSelf = self;
        // 30 Hz: host automation moves the knobs smoothly. Only the generation
        // number is read unless the sound actually changed.
        follow = [NSTimer scheduledTimerWithTimeInterval:1.0 / 30.0 repeats:YES block:^(NSTimer* t) {
            [weakSelf syncFromAU:NO];
        }];
    }
}
- (void)dealloc {
    [follow invalidate];
    delete auHost;
}
@end

@interface MUEWViewFactory_0_23 : NSObject <AUCocoaUIBase>
@end

@implementation MUEWViewFactory_0_23
- (unsigned)interfaceVersion { return 0; }
- (NSString*)description { return @"MUEW Editor"; }
- (NSView*)uiViewForAudioUnit:(AudioUnit)inAudioUnit withSize:(NSSize)inPreferredSize {
    (void)inPreferredSize; // fixed-size editor
    MUEWAUEditorContainer_0_23* v = [[MUEWAUEditorContainer_0_23 alloc] initWithFrame:NSMakeRect(0, 0, 1000, 680)];
    v->auHost = new AUEditorHost(inAudioUnit);
    v->host = v->auHost;
    [v syncFromAU:YES];
    return v;
}
@end
