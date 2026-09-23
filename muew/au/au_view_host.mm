// au_view_host.mm - CI proof that the MUEW AU editor works the way a DAW
// uses it: find the installed component, ask it for kAudioUnitProperty_CocoaUI,
// load the view class from the component bundle, embed the view in a window,
// then drive it with real mouse events and check the AU follows.
//   1. host selects Chrome Motion  -> editor must follow (host -> editor)
//   2. click the header "next" arrow -> AU must report Rising Tide (editor -> AU)
//   3. drag the cutoff knob up      -> AU holds an edited Rising Tide with a
//                                      higher cutoff and no factory number; the
//                                      drag reaches the AU as the Cutoff
//                                      parameter with begin/end gestures, the
//                                      events a DAW records automation from
//   4. host automates Cutoff, Resonance and Warp A -> the open editor shows
//                                      the automated values
//   5. drag the header Macro 1 knob -> AU parameter 12 moves (automatable)
//   6. save a user preset, host switches away, click User chip + the saved
//      row -> the AU holds the saved sound under its own name
// The window stays up long enough for the workflow to screenshot it.
#import <AppKit/AppKit.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AudioToolbox/AudioUnitUtilities.h>
#if __has_include(<AudioToolbox/AUCocoaUIView.h>)
#import <AudioToolbox/AUCocoaUIView.h>
#else
#import <AudioUnit/AUCocoaUIView.h>
#endif
#include "MUEWProperties.h"
#include "preset.h"
#include "au_params.h"
#include <cstdio>
#include <cmath>
#include <string>

static AudioUnit gUnit = nullptr;
static int gFailures = 0;
static int gBegin = 0, gEnd = 0, gValue = 0;
static float gLastValue = 0;

static void Check(bool ok, const char* what) {
    printf("%s %s\n", ok ? "ok:  " : "FAIL:", what);
    fflush(stdout);
    if (!ok) ++gFailures;
}

static SInt32 PresetNumber() {
    AUPreset p{}; UInt32 size = sizeof(p);
    if (AudioUnitGetProperty(gUnit, kAudioUnitProperty_PresentPreset, kAudioUnitScope_Global, 0, &p, &size) != noErr) return -99;
    if (p.presetName) CFRelease(p.presetName);
    return p.presetNumber;
}

static bool State(muew::Preset& out) {
    CFStringRef str = nullptr; UInt32 size = sizeof(str);
    if (AudioUnitGetProperty(gUnit, kMUEWProperty_PresetState, kAudioUnitScope_Global, 0, &str, &size) != noErr || !str) return false;
    NSString* ns = (__bridge_transfer NSString*)str;
    return out.parse(std::string(ns.UTF8String ?: ""));
}

static std::string PresetNameNow() {
    AUPreset p{}; UInt32 size = sizeof(p);
    if (AudioUnitGetProperty(gUnit, kAudioUnitProperty_PresentPreset, kAudioUnitScope_Global, 0, &p, &size) != noErr) return "";
    std::string n;
    if (p.presetName) { n = [(__bridge NSString*)p.presetName UTF8String] ?: ""; CFRelease(p.presetName); }
    return n;
}

static void SelectPreset(SInt32 n) {
    AUPreset sel{n, nullptr};
    AudioUnitSetProperty(gUnit, kAudioUnitProperty_PresentPreset, kAudioUnitScope_Global, 0, &sel, sizeof(sel));
}

static NSEvent* Mouse(NSEventType type, NSPoint p, NSWindow* w) {
    return [NSEvent mouseEventWithType:type location:p modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime
                          windowNumber:w.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
}

static void After(double seconds, dispatch_block_t block) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
}

int main() {
    @autoreleasepool {
        NSApplication* app = [NSApplication sharedApplication];
        app.activationPolicy = NSApplicationActivationPolicyRegular;

        AudioComponentDescription desc{kAudioUnitType_MusicDevice, 'Muew', 'Inst', 0, 0};
        AudioComponent comp = AudioComponentFindNext(nullptr, &desc);
        if (!comp || AudioComponentInstanceNew(comp, &gUnit) != noErr || AudioUnitInitialize(gUnit) != noErr) {
            printf("FAIL: open MUEW AU\n"); return 1;
        }
        SelectPreset(29); // Laser Drop

        AudioUnitCocoaViewInfo info{}; UInt32 size = sizeof(info);
        if (AudioUnitGetProperty(gUnit, kAudioUnitProperty_CocoaUI, kAudioUnitScope_Global, 0, &info, &size) != noErr) {
            printf("FAIL: AU has no Cocoa UI\n"); return 1;
        }
        NSURL* bundleURL = (__bridge_transfer NSURL*)info.mCocoaAUViewBundleLocation;
        NSString* className = (__bridge_transfer NSString*)info.mCocoaAUViewClass[0];
        NSBundle* bundle = [NSBundle bundleWithURL:bundleURL];
        [bundle load];
        Class factoryClass = [bundle classNamed:className];
        Check(factoryClass != nil, "view factory class loads from the component bundle");
        Check([factoryClass conformsToProtocol:@protocol(AUCocoaUIBase)], "factory conforms to AUCocoaUIBase");
        if (!factoryClass) return 1;
        id<AUCocoaUIBase> factory = [[factoryClass alloc] init];
        NSView* view = [factory uiViewForAudioUnit:gUnit withSize:NSMakeSize(1000, 680)];
        Check(view != nil && view.frame.size.width >= 1000, "factory returns the 1000x680 editor");
        if (!view) return 1;

        NSWindow* w = [[NSWindow alloc] initWithContentRect:view.frame
                                                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                    backing:NSBackingStoreBuffered defer:NO];
        w.title = @"MUEW - Audio Unit editor (hosted)";
        w.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        w.contentView = view;
        [w center];
        [w makeKeyAndOrderFront:nil];
        [app activateIgnoringOtherApps:YES];

        // Listen for the cutoff parameter the way a DAW's automation recorder does.
        AUEventListenerRef listener = nullptr;
        AUEventListenerCreateWithDispatchQueue(&listener, 0.0f, 0.0f, dispatch_get_main_queue(),
            ^(void*, const AudioUnitEvent* ev, UInt64, AudioUnitParameterValue value) {
                if (ev->mEventType == kAudioUnitEvent_BeginParameterChangeGesture) ++gBegin;
                else if (ev->mEventType == kAudioUnitEvent_EndParameterChangeGesture) ++gEnd;
                else if (ev->mEventType == kAudioUnitEvent_ParameterValueChange) { ++gValue; gLastValue = value; }
            });
        Check(listener != nullptr, "automation listener attached");
        for (AudioUnitEventType t : {kAudioUnitEvent_BeginParameterChangeGesture, kAudioUnitEvent_EndParameterChangeGesture,
                                     kAudioUnitEvent_ParameterValueChange}) {
            AudioUnitEvent ev{};
            ev.mEventType = t;
            ev.mArgument.mParameter = AudioUnitParameter{gUnit, (AudioUnitParameterID)muew::params::Cutoff, kAudioUnitScope_Global, 0};
            if (listener) AUEventListenerAddEventType(listener, nullptr, &ev);
        }

        After(1.0, ^{ SelectPreset(27); }); // host picks Chrome Motion
        After(2.0, ^{
            // Header "next" arrow (view coordinates == window coordinates here).
            NSPoint next = NSMakePoint(681, view.bounds.size.height - 47);
            [view mouseDown:Mouse(NSEventTypeLeftMouseDown, next, w)];
            [view mouseUp:Mouse(NSEventTypeLeftMouseUp, next, w)];
            Check(PresetNumber() == 28, "editor followed the host to Chrome Motion, and its next arrow set the AU to Rising Tide");
        });
        After(2.6, ^{
            muew::Preset before; State(before);
            NSPoint knob = NSMakePoint(536, view.bounds.size.height - 100 - 94); // CUTOFF
            [view mouseDown:Mouse(NSEventTypeLeftMouseDown, knob, w)];
            [view mouseDragged:Mouse(NSEventTypeLeftMouseDragged, NSMakePoint(knob.x, knob.y + 30), w)];
            [view mouseDragged:Mouse(NSEventTypeLeftMouseDragged, NSMakePoint(knob.x, knob.y + 60), w)];
            [view mouseUp:Mouse(NSEventTypeLeftMouseUp, NSMakePoint(knob.x, knob.y + 60), w)];
            muew::Preset after;
            bool ok = State(after);
            Check(ok && after.info.name == "Rising Tide" && after.voice.filterCutoff > before.voice.filterCutoff * 1.5,
                  "cutoff drag in the editor changed the AU's sound");
            Check(PresetNumber() == -1, "edited sound is reported as a custom preset");
            printf("cutoff %.1f Hz -> %.1f Hz\n", before.voice.filterCutoff, after.voice.filterCutoff);
            AudioUnitParameterValue pv = 0;
            AudioUnitGetParameter(gUnit, muew::params::Cutoff, kAudioUnitScope_Global, 0, &pv);
            Check(std::fabs(pv - after.voice.filterCutoff) < 0.01 * after.voice.filterCutoff,
                  "the AU's Cutoff parameter matches the edited sound");
            fflush(stdout);
        });
        After(3.2, ^{
            printf("automation events from the drag: begin %d, value %d, end %d, last %.1f Hz\n", gBegin, gValue, gEnd, gLastValue);
            Check(gBegin == 1 && gEnd == 1 && gValue >= 1, "knob drag announced to the host as a parameter gesture (automation-recordable)");
        });
        After(3.4, ^{
            // Host automation playback.
            AudioUnitSetParameter(gUnit, muew::params::Cutoff, kAudioUnitScope_Global, 0, 900.0f, 0);
            AudioUnitSetParameter(gUnit, muew::params::Resonance, kAudioUnitScope_Global, 0, 5.0f, 0);
            AudioUnitSetParameter(gUnit, muew::params::WarpA, kAudioUnitScope_Global, 0, 70.0f, 0);
        });
        After(4.0, ^{
            NSString* shown = [view respondsToSelector:NSSelectorFromString(@"muewDisplayedState")]
                ? [view valueForKey:@"muewDisplayedState"] : nil;
            muew::Preset p;
            bool ok = shown && p.parse(std::string(shown.UTF8String ?: ""));
            printf("editor shows cutoff %.1f Hz, resonance %.2f, warp A %.0f%%\n",
                   p.voice.filterCutoff, p.voice.filterReso, p.voice.osc1Warp * 100);
            Check(ok && std::fabs(p.voice.filterCutoff - 900) < 0.5 && std::fabs(p.voice.filterReso - 5.0) < 1e-3
                     && std::fabs(p.voice.osc1Warp - 0.70) < 1e-4 && p.info.name == "Rising Tide",
                  "host automation reached the open editor (cutoff, resonance, warp A)");
            fflush(stdout);
        });
        After(4.3, ^{
            NSPoint m1 = NSMakePoint(772, view.bounds.size.height - 38); // header MACRO 1 (BRIGHT)
            [view mouseDown:Mouse(NSEventTypeLeftMouseDown, m1, w)];
            [view mouseDragged:Mouse(NSEventTypeLeftMouseDragged, NSMakePoint(m1.x, m1.y + 30), w)];
            [view mouseDragged:Mouse(NSEventTypeLeftMouseDragged, NSMakePoint(m1.x, m1.y + 60), w)];
            [view mouseUp:Mouse(NSEventTypeLeftMouseUp, NSMakePoint(m1.x, m1.y + 60), w)];
            AudioUnitParameterValue mv = 0;
            AudioUnitGetParameter(gUnit, muew::params::Macro1, kAudioUnitScope_Global, 0, &mv);
            muew::Preset st; State(st);
            printf("macro 1 after drag: parameter %.1f%%, sound %.2f\n", mv, st.voice.macros[0]);
            Check(mv > 30 && mv < 50 && std::fabs(st.voice.macros[0] - mv / 100.0) < 1e-3,
                  "macro knob drag reached the AU as parameter 12 and the sound");
            fflush(stdout);
        });
        After(4.6, ^{
            SEL save = NSSelectorFromString(@"saveUserPresetNamed:");
            BOOL ok = NO;
            if ([view respondsToSelector:save]) {
                BOOL (*fn)(id, SEL, NSString*) = (BOOL (*)(id, SEL, NSString*))[view methodForSelector:save];
                ok = fn(view, save, @"CI Riser");
            }
            Check(ok && PresetNameNow() == "CI Riser" && PresetNumber() == -1, "saved user preset is what the host shows");
            fflush(stdout);
        });
        After(4.9, ^{ SelectPreset(3); }); // host switches to Pluck
        After(5.2, ^{
            CGFloat t = view.bounds.size.height - 100;
            NSPoint userChip = NSMakePoint(835, t - 156 + 9);
            [view mouseDown:Mouse(NSEventTypeLeftMouseDown, userChip, w)];
            [view mouseUp:Mouse(NSEventTypeLeftMouseUp, userChip, w)];
            NSPoint firstRow = NSMakePoint(850, t - 172 - 9);
            [view mouseDown:Mouse(NSEventTypeLeftMouseDown, firstRow, w)];
            [view mouseUp:Mouse(NSEventTypeLeftMouseUp, firstRow, w)];
            muew::Preset st;
            bool ok = State(st);
            printf("after User chip + row: host shows '%s', cutoff %.1f Hz, macro 1 %.2f\n",
                   PresetNameNow().c_str(), st.voice.filterCutoff, st.voice.macros[0]);
            Check(ok && st.info.name == "CI Riser" && PresetNameNow() == "CI Riser" && std::fabs(st.voice.filterCutoff - 900) < 0.5
                     && st.voice.macros[0] > 0.3, "User chip lists the saved preset and loading it restores the sound");
            fflush(stdout);
        });
        After(9.0, ^{
            printf(gFailures ? "FAIL: AU editor host test\n" : "PASS: AU editor hosted; host->editor, editor->AU, automation, macros and user presets\n");
            fflush(stdout);
            exit(gFailures ? 1 : 0);
        });
        [app run];
    }
    return 0;
}
