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
//   7. host selects Fold Screamer; click unison pip 5 on osc A, drag the
//      WIDTH knob and the distortion DRIVE ring, click the All chip -> the
//      AU holds 5 voices, parameter 18 (width) and 19 (drive) moved
//   8. 0.11.0 full browser: open it, Import a file (Imported bank), pick the
//      'dark' character tag, rate row 2 with the info stars, sort by RATING
//      -> the rated preset moves to row 1
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
#include "ui_model.h"
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

static void Click(NSView* view, NSWindow* w, NSPoint p) {
    [view mouseDown:Mouse(NSEventTypeLeftMouseDown, p, w)];
    [view mouseUp:Mouse(NSEventTypeLeftMouseUp, p, w)];
}

static void Snapshot(NSView* view, const char* env, const char* what) {
    const char* png = getenv(env);
    if (!png || !*png) return;
    NSBitmapImageRep* rep = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
    NSData* d = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    Check(d.length > 10000 && [d writeToFile:[NSString stringWithUTF8String:png] atomically:YES], what);
    fflush(stdout);
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
        After(5.5, ^{ SelectPreset(34); }); // host switches to Fold Screamer (unison + distortion/EQ/compressor)
        After(5.8, ^{
            CGFloat t = view.bounds.size.height - 100;
            NSPoint pip = NSMakePoint(46 + 6 + 4 * 13 + 6.5, t - 128); // osc A unison pip 5 (strip moved up for the 0.19.0 warp slots)
            [view mouseDown:Mouse(NSEventTypeLeftMouseDown, pip, w)];
            [view mouseUp:Mouse(NSEventTypeLeftMouseUp, pip, w)];
            NSPoint wk = NSMakePoint(250, t - 192); // WIDTH knob: drag down 30 pt = -20%
            [view mouseDown:Mouse(NSEventTypeLeftMouseDown, wk, w)];
            [view mouseDragged:Mouse(NSEventTypeLeftMouseDragged, NSMakePoint(wk.x, wk.y - 15), w)];
            [view mouseDragged:Mouse(NSEventTypeLeftMouseDragged, NSMakePoint(wk.x, wk.y - 30), w)];
            [view mouseUp:Mouse(NSEventTypeLeftMouseUp, NSMakePoint(wk.x, wk.y - 30), w)];
            CGFloat cardH = (t - 286 - 44 - 58 - 6) / 2;
            NSPoint dr = NSMakePoint(468 + 19, 58 + cardH + 6 + 24); // DISTORTION drive ring (chain slot 1): up 30 pt = +20%
            [view mouseDown:Mouse(NSEventTypeLeftMouseDown, dr, w)];
            [view mouseDragged:Mouse(NSEventTypeLeftMouseDragged, NSMakePoint(dr.x, dr.y + 15), w)];
            [view mouseDragged:Mouse(NSEventTypeLeftMouseDragged, NSMakePoint(dr.x, dr.y + 30), w)];
            [view mouseUp:Mouse(NSEventTypeLeftMouseUp, NSMakePoint(dr.x, dr.y + 30), w)];
            NSPoint all = NSMakePoint(835, t - 81); // All chip, so the list shows the edited factory sound
            [view mouseDown:Mouse(NSEventTypeLeftMouseDown, all, w)];
            [view mouseUp:Mouse(NSEventTypeLeftMouseUp, all, w)];
            AudioUnitParameterValue wv = 0, dv = 0;
            AudioUnitGetParameter(gUnit, muew::params::UnisonWidth, kAudioUnitScope_Global, 0, &wv);
            AudioUnitGetParameter(gUnit, muew::params::DistDrive, kAudioUnitScope_Global, 0, &dv);
            muew::Preset st;
            bool ok = State(st);
            printf("Fold Screamer edited: osc A %d voices, width %.1f%%, drive %.1f%% (sound %.2f / %.2f)\n",
                   st.voice.osc1Unison, wv, dv, st.voice.uniWidth, st.fx.dist.drive);
            Check(ok && st.info.name == "Fold Screamer" && st.voice.osc1Unison == 5, "unison pip click set 5 voices in the AU's sound");
            Check(wv > 30 && wv < 50 && std::fabs(st.voice.uniWidth - wv / 100.0) < 1e-3, "WIDTH knob drag reached the AU as parameter 18");
            Check(dv > 45 && dv < 65 && std::fabs(st.fx.dist.drive - dv / 100.0) < 1e-3 && st.fx.dist.enabled,
                  "distortion DRIVE ring drag reached the AU as parameter 19");
            fflush(stdout);
        });
        After(6.1, ^{ // 0.8.0 mod matrix: drag LFO 3 onto CUTOFF, set its depth, sync it to the host tempo
            CGFloat t = view.bounds.size.height - 100;
            muew::Preset before;
            State(before);
            NSPoint badge = NSMakePoint(304 + 2 * 19 + 8.75, 216 + 7.5); // LFO3 source badge
            NSPoint cut = NSMakePoint(536, t - 94);                      // CUTOFF knob
            [view mouseDown:Mouse(NSEventTypeLeftMouseDown, badge, w)];
            [view mouseDragged:Mouse(NSEventTypeLeftMouseDragged, NSMakePoint(450, 300), w)];
            [view mouseDragged:Mouse(NSEventTypeLeftMouseDragged, cut, w)];
            [view mouseUp:Mouse(NSEventTypeLeftMouseUp, cut, w)];
            muew::Preset mid;
            bool ok1 = State(mid);
            size_t n = mid.routes.size();
            Check(ok1 && n == before.routes.size() + 1 && mid.routes[n - 1].source == muew::ModRoute::Source::LFO3
                  && mid.routes[n - 1].dest == muew::ModRoute::Dest::FilterCutoff,
                  "dragging the LFO 3 badge onto CUTOFF added an LFO 3 -> cutoff route in the AU");
            // New slot n is on page (n-1)/4, row (n-1)%4. Drag its amount bar handle right 30 pt (+0.4 of full scale, 75 pt per scale).
            int row = (int)((n - 1) % 4);
            double amt0 = n ? mid.routes[n - 1].amount / 5.0 : 0;
            NSPoint h = NSMakePoint(44 + 28 + 59 + amt0 * 59, 190 - row * 44 + 4 + 7); // 118 pt bar since 0.16.0
            [view mouseDown:Mouse(NSEventTypeLeftMouseDown, h, w)];
            [view mouseDragged:Mouse(NSEventTypeLeftMouseDragged, NSMakePoint(h.x + 15, h.y), w)];
            [view mouseDragged:Mouse(NSEventTypeLeftMouseDragged, NSMakePoint(h.x + 30, h.y), w)];
            [view mouseUp:Mouse(NSEventTypeLeftMouseUp, NSMakePoint(h.x + 30, h.y), w)];
            // LFO 3 is selected: SYNC on (1/4), then drag RATE up 30 pt to step the division to 1/16.
            CGFloat fw = (148 - 8) / 3.0;
            NSPoint sync = NSMakePoint(304 + 2 * (fw + 4) + fw / 2, 87), rate = NSMakePoint(304 + (fw + 4) + fw / 2, 87);
            [view mouseDown:Mouse(NSEventTypeLeftMouseDown, sync, w)];
            [view mouseUp:Mouse(NSEventTypeLeftMouseUp, sync, w)];
            [view mouseDown:Mouse(NSEventTypeLeftMouseDown, rate, w)];
            [view mouseDragged:Mouse(NSEventTypeLeftMouseDragged, NSMakePoint(rate.x, rate.y + 15), w)];
            [view mouseDragged:Mouse(NSEventTypeLeftMouseDragged, NSMakePoint(rate.x, rate.y + 30), w)];
            [view mouseUp:Mouse(NSEventTypeLeftMouseUp, NSMakePoint(rate.x, rate.y + 30), w)];
            muew::Preset st;
            bool ok = State(st);
            double a = ok && st.routes.size() == n ? st.routes[n - 1].amount : 0;
            printf("matrix: %zu routes, LFO 3 -> cutoff %.2f oct, LFO 3 sync %d, page shows slots %zu-%zu\n",
                   st.routes.size(), a, st.voice.lfoSync[2], (n - 1) / 4 * 4 + 1, (n - 1) / 4 * 4 + 4);
            Check(ok && std::fabs(a - 3.25) < 0.05, "amount bar drag set the route depth (+1.25 -> +3.25 oct)");
            Check(ok && st.voice.lfoSync[2] == 5, "LFO 3 SYNC + RATE drag stored 1/16 in the AU's sound");
            fflush(stdout);
        });
        After(6.5, ^{ // 0.9.0 wavetable editor: open it on OSC A, draw, duplicate the frame, edit a harmonic
            CGFloat t = view.bounds.size.height - 100;
            NSPoint disp = NSMakePoint(46 + 95, t - 80);                 // OSC A display (above the WT POS bar)
            [view mouseDown:Mouse(NSEventTypeLeftMouseDown, disp, w)];
            [view mouseUp:Mouse(NSEventTypeLeftMouseUp, disp, w)];
            CGFloat mid = t - 184 + 69, amp = 138 * .42;                  // canvas centre line and full scale
            NSPoint s0 = NSMakePoint(100, mid + .5 * amp), s1 = NSMakePoint(200, mid + .5 * amp), s2 = NSMakePoint(300, mid - .8 * amp);
            [view mouseDown:Mouse(NSEventTypeLeftMouseDown, s0, w)];
            [view mouseDragged:Mouse(NSEventTypeLeftMouseDragged, s1, w)];
            [view mouseDragged:Mouse(NSEventTypeLeftMouseDragged, s2, w)];
            [view mouseUp:Mouse(NSEventTypeLeftMouseUp, s2, w)];
            muew::Preset drawn;
            bool ok1 = State(drawn);
            int i70 = 70;                                                 // inside the flat +0.5 part of the stroke
            Check(ok1 && drawn.voice.osc1Shape == muew::kCustomShape && drawn.tables[0].size() == 1
                  && std::fabs(drawn.tables[0][0][i70] - 0.5) < 0.02,
                  "clicking OSC A opened the editor and the drawn stroke reached the AU's user table");
            NSPoint dup = NSMakePoint(40 + 51 + 24, t - 250 + 10);        // DUP
            [view mouseDown:Mouse(NSEventTypeLeftMouseDown, dup, w)];
            [view mouseUp:Mouse(NSEventTypeLeftMouseUp, dup, w)];
            NSPoint harm = NSMakePoint(298 + 50 + 23, t - 32 + 8);        // HARM tab
            [view mouseDown:Mouse(NSEventTypeLeftMouseDown, harm, w)];
            [view mouseUp:Mouse(NSEventTypeLeftMouseUp, harm, w)];
            NSPoint h5 = NSMakePoint(40 + 4.5 * (408 / 32.0), t - 184 + 16 + (138 - 26) * .9); // harmonic 5 at 90%
            [view mouseDown:Mouse(NSEventTypeLeftMouseDown, h5, w)];
            [view mouseUp:Mouse(NSEventTypeLeftMouseUp, h5, w)];
            muew::Preset st;
            bool ok = State(st);
            std::vector<double> hs = ok && st.tables[0].size() == 2 ? muew::frameHarmonics(st.tables[0][1], 8) : std::vector<double>(8, 0.0);
            printf("wavetable: shape %d, %zu frames, WT POS A %.2f, frame 2 harmonic 5 at %.2f\n",
                   st.voice.osc1Shape, st.tables[0].size(), st.voice.osc1WtPos, hs[4]);
            Check(ok && st.tables[0].size() == 2 && std::fabs(st.voice.osc1WtPos - 1.0) < 1e-6 && st.tables[0][0] != st.tables[0][1],
                  "DUP added a second frame and moved WT POS onto it");
            Check(hs[4] > 0.8, "harmonic bar click raised harmonic 5 of the new frame");
            fflush(stdout);
        });
        After(6.8, ^{ // 0.10.0 FILTER 2 + SUB page: open it, enable filter 2, go parallel, raise the sub
            CGFloat t = view.bounds.size.height - 100;
            muew::Preset before;
            State(before);
            NSPoint tab = NSMakePoint(556 + 46, t - 29 + 8);             // FILTER 2 + SUB tab
            [view mouseDown:Mouse(NSEventTypeLeftMouseDown, tab, w)];
            [view mouseUp:Mouse(NSEventTypeLeftMouseUp, tab, w)];
            NSPoint disp = NSMakePoint(686 + 43, t - 138 + 50);          // filter 2 display: cycles the type
            for (int i = 0; i < 5; ++i) {                                 // OFF -> LP -> BP -> HP -> COMB -> FORMANT
                [view mouseDown:Mouse(NSEventTypeLeftMouseDown, disp, w)];
                [view mouseUp:Mouse(NSEventTypeLeftMouseUp, disp, w)];
            }
            NSPoint par = NSMakePoint(686 + 5 + 39 + 18, t - 138 + 10);  // PAR
            [view mouseDown:Mouse(NSEventTypeLeftMouseDown, par, w)];
            [view mouseUp:Mouse(NSEventTypeLeftMouseUp, par, w)];
            NSPoint sub = NSMakePoint(536, t - 200);                      // SUB knob (page 2, attack's spot)
            [view mouseDown:Mouse(NSEventTypeLeftMouseDown, sub, w)];
            [view mouseDragged:Mouse(NSEventTypeLeftMouseDragged, NSMakePoint(sub.x, sub.y + 45), w)];
            [view mouseDragged:Mouse(NSEventTypeLeftMouseDragged, NSMakePoint(sub.x, sub.y + 90), w)];
            [view mouseUp:Mouse(NSEventTypeLeftMouseUp, NSMakePoint(sub.x, sub.y + 90), w)];
            muew::Preset st;
            bool ok = State(st);
            AudioUnitParameterValue sp = -1;
            AudioUnitGetParameter(gUnit, muew::params::SubLevel, kAudioUnitScope_Global, 0, &sp);
            printf("filter 2: type %d routing %d, sub %.2f (param 23 = %.1f), attack kept %.4f -> %.4f\n",
                   st.voice.filter2Type, st.voice.filterRouting, st.voice.subLevel, sp, before.voice.ampA, st.voice.ampA);
            Check(ok && st.voice.filter2Type == 5 && st.voice.filterRouting == 1, "FILTER 2 display clicks chose FORMANT, PAR set parallel routing");
            Check(ok && st.voice.subLevel > 0.5 && std::fabs(sp - st.voice.subLevel * 100) < 0.5 && st.voice.ampA == before.voice.ampA,
                  "SUB knob drag on page 2 reached the AU as parameter 23 without touching ATTACK");
            fflush(stdout);
        });
        After(6.9, ^{ // 0.13.0 FX chain: drag PHASER from slot 7 to slot 2, switch it on, raise its mix
            CGFloat t = view.bounds.size.height - 100;
            CGFloat h = (t - 286 - 44 - 58 - 6) / 2;
            NSPoint from = NSMakePoint(468 + 2 * 78 + 30, 58 + h - 26);         // PHASER card body (bottom row, 3rd)
            NSPoint to = NSMakePoint(468 + 1 * 78 + 30, 58 + h + 6 + h - 26);   // CHORUS card (top row, 2nd)
            [view mouseDown:Mouse(NSEventTypeLeftMouseDown, from, w)];
            [view mouseDragged:Mouse(NSEventTypeLeftMouseDragged, NSMakePoint((from.x + to.x) / 2, (from.y + to.y) / 2), w)];
            [view mouseDragged:Mouse(NSEventTypeLeftMouseDragged, to, w)];
            [view mouseUp:Mouse(NSEventTypeLeftMouseUp, to, w)];
            Click(view, w, NSMakePoint(468 + 78 + 70 - 11, 58 + h + 6 + h - 13)); // its LED, now in slot 2
            NSPoint ring = NSMakePoint(468 + 78 + 19, 58 + h + 6 + 24);          // its MIX ring: up 30 pt = +20%
            [view mouseDown:Mouse(NSEventTypeLeftMouseDown, ring, w)];
            [view mouseDragged:Mouse(NSEventTypeLeftMouseDragged, NSMakePoint(ring.x, ring.y + 15), w)];
            [view mouseDragged:Mouse(NSEventTypeLeftMouseDragged, NSMakePoint(ring.x, ring.y + 30), w)];
            [view mouseUp:Mouse(NSEventTypeLeftMouseUp, NSMakePoint(ring.x, ring.y + 30), w)];
            muew::Preset st;
            bool ok = State(st);
            AudioUnitParameterValue pm = -1;
            AudioUnitGetParameter(gUnit, muew::params::PhaserMix, kAudioUnitScope_Global, 0, &pm);
            std::string ord;
            for (int i = 0; i < muew::kFxUnits; ++i) ord += std::string(i ? " " : "") + muew::fxUnitName(st.fx.order.slot[i]);
            printf("fx chain: %s; phaser %s, mix %.2f (param 28 = %.1f)\n", ord.c_str(), st.fx.phaser.enabled ? "on" : "off", st.fx.phaser.mix, pm);
            Check(ok && ord == "dist phaser chorus delay comp reverb eq flanger", "dragging the PHASER card moved it to chain slot 2 in the AU state");
            Check(ok && st.fx.phaser.enabled && pm > 60 && pm < 80 && std::fabs(st.fx.phaser.mix - pm / 100.0) < 1e-3,
                  "PHASER LED and MIX ring reached the AU (parameter 28)");
            fflush(stdout);
        });
        After(6.95, ^{ // 0.14.0 FX detail editor: open PHASER, set DEPTH; open DELAY, sync L to 1/8, set FEEDBACK
            CGFloat t = view.bounds.size.height - 100;
            CGFloat h = (t - 286 - 44 - 58 - 6) / 2;
            auto card = [&](int slot) { return NSMakePoint(468 + (slot % 4) * 78 + 50, (slot < 4 ? 58 + h + 6 : 58) + h - 35); };
            auto bar = [&](int row, double n) { return NSMakePoint(36 + 12 + 92 + 196 * n, 48 + 200 - 58 - 24 * row + 10); };
            Click(view, w, card(1));                      // PHASER (moved to slot 2 above)
            Click(view, w, bar(1, 0.9));                  // DEPTH -> 90%
            Click(view, w, card(3));                      // DELAY
            for (int i = 0; i < 4; ++i) Click(view, w, bar(1, 0.75)); // SYNC L: FREE -> 1/1 -> 1/2 -> 1/4 -> 1/8
            NSPoint fb = bar(4, 0.3);                     // FEEDBACK: press at 28%, drag to 63%
            [view mouseDown:Mouse(NSEventTypeLeftMouseDown, fb, w)];
            [view mouseDragged:Mouse(NSEventTypeLeftMouseDragged, bar(4, 0.5), w)];
            [view mouseDragged:Mouse(NSEventTypeLeftMouseDragged, bar(4, 0.6 / 0.95), w)];
            [view mouseUp:Mouse(NSEventTypeLeftMouseUp, bar(4, 0.6 / 0.95), w)];
            muew::Preset st;
            bool ok = State(st);
            printf("fx detail: phaser depth %.2f, delay sync L %d (%s), feedback %.2f\n", st.fx.phaser.depth, st.fx.delay.syncL,
                   muew::ui::syncName(st.fx.delay.syncL), st.fx.delay.feedback);
            Check(ok && std::fabs(st.fx.phaser.depth - 0.9) < 0.01, "PHASER detail DEPTH slider reached the AU's sound");
            Check(ok && st.fx.delay.syncL == 4 && std::fabs(st.fx.delay.feedback - 0.6) < 0.01,
                  "DELAY detail: SYNC L stepped to 1/8 and the FEEDBACK drag reached the AU's sound");
            // One snapshot per unit panel, in chain order, then leave DELAY open.
            const char* pre = getenv("MUEW_FXDETAIL_PREFIX");
            if (pre && *pre) {
                for (int s = 0; s < muew::kFxUnits; ++s) {
                    Click(view, w, card(s));
                    std::string f = std::string(pre) + muew::fxUnitName(st.fx.order.slot[s]) + ".png";
                    setenv("MUEW_FXDETAIL_ONE", f.c_str(), 1);
                    Snapshot(view, "MUEW_FXDETAIL_ONE", ("detail panel snapshot: " + std::string(muew::fxUnitName(st.fx.order.slot[s]))).c_str());
                }
                Click(view, w, card(3));
            }
            fflush(stdout);
        });
        After(6.97, ^{ // 0.15.0 FX LFOs: drop FX LFO 1 on FLANGER, FX LFO 2 on DELAY; shape and sync them
            CGFloat t = view.bounds.size.height - 100;
            CGFloat h = (t - 286 - 44 - 58 - 6) / 2;
            auto card = [&](int slot) { return NSMakePoint(468 + (slot % 4) * 78 + 50, (slot < 4 ? 58 + h + 6 : 58) + h - 35); };
            auto badge = [&](int i) { return NSMakePoint(304 + (i % 8) * 19 + 8.75, (i < 8 ? 216 : 198) + 7.5); };
            auto dropOn = [&](NSPoint from, NSPoint to) {
                [view mouseDown:Mouse(NSEventTypeLeftMouseDown, from, w)];
                [view mouseDragged:Mouse(NSEventTypeLeftMouseDragged, NSMakePoint((from.x + to.x) / 2, (from.y + to.y) / 2), w)];
                [view mouseDragged:Mouse(NSEventTypeLeftMouseDragged, to, w)];
                [view mouseUp:Mouse(NSEventTypeLeftMouseUp, to, w)];
            };
            CGFloat fw = (148 - 8) / 3.0;
            NSPoint shape = NSMakePoint(304 + fw / 2, 87), sync = NSMakePoint(304 + 2 * (fw + 4) + fw / 2, 87);
            muew::Preset before;
            State(before);
            if (getenv("MUEW_FXDETAIL_PREFIX") && *getenv("MUEW_FXDETAIL_PREFIX"))
                Click(view, w, NSMakePoint(36 + 424 - 20, 48 + 200 - 17));     // close the DELAY detail left open above
            Click(view, w, NSMakePoint(468 + 3 * 78 + 70 - 11, 58 + h - 13)); // FLANGER LED (slot 8) on
            dropOn(badge(13), card(7));                                         // FX LFO 1 -> FLANGER
            Click(view, w, shape);                                              // sine -> triangle
            dropOn(badge(14), card(3));                                         // FX LFO 2 -> DELAY
            Click(view, w, shape); Click(view, w, shape); Click(view, w, shape); // sine -> square
            Click(view, w, sync);                                               // FREE -> 1/4
            Snapshot(view, "MUEW_FXLFO_MOD_PNG", "FX LFO modulator snapshot written");
            Click(view, w, card(7));                                            // FLANGER detail: purple LFO range on DEPTH
            Snapshot(view, "MUEW_FXLFO1_PNG", "FX LFO 1 range on FLANGER snapshot written");
            Click(view, w, card(3));                                            // DELAY detail stays open for the editor snapshot
            muew::Preset st;
            bool ok = State(st);
            size_t n = st.routes.size();
            using S = muew::ModRoute::Source; using D = muew::ModRoute::Dest;
            bool r1 = false, r2 = false;
            for (const auto& r : st.routes) { r1 |= r.source == S::FxLfo1 && r.dest == D::FxFlangerDepth; r2 |= r.source == S::FxLfo2 && r.dest == D::FxDelayFeedback; }
            printf("fx lfos: %zu routes (+%zu), lfo1 shape %d %.2f Hz sync %d, lfo2 shape %d sync %d (%s), flanger %s\n", n, n - before.routes.size(),
                   st.fx.lfo[0].shape, st.fx.lfo[0].rateHz, st.fx.lfo[0].sync, st.fx.lfo[1].shape, st.fx.lfo[1].sync,
                   muew::ui::syncName(st.fx.lfo[1].sync), st.fx.flanger.enabled ? "on" : "off");
            Check(ok && r1 && r2 && n == before.routes.size() + 2, "dropping FXL1 on FLANGER and FXL2 on DELAY added both routes in the AU");
            Check(ok && st.fx.flanger.enabled && st.fx.lfo[0].shape == 1 && st.fx.lfo[1].shape == 3 && st.fx.lfo[1].sync == 3,
                  "FX LFO shape and sync fields reached the AU's sound");
            muew::Preset back;
            Check(ok && back.parse(st.serialize()) && back == st && st.serialize().find("\nfxlfo ") != std::string::npos,
                  "the AU state saves the FX LFOs with the sound");
            fflush(stdout);
        });
        After(6.98, ^{ // 0.16.0 route curves + aux: bend and aux-scale routes on page 4 (FX LFOs) and page 1
            CGFloat t = view.bounds.size.height - 100;
            CGFloat h = (t - 286 - 44 - 58 - 6) / 2;
            auto card = [&](int slot) { return NSMakePoint(468 + (slot % 4) * 78 + 50, (slot < 4 ? 58 + h + 6 : 58) + h - 35); };
            auto badge = [&](int i) { return NSMakePoint(304 + (i % 8) * 19 + 8.75, (i < 8 ? 216 : 198) + 7.5); };
            auto curve = [&](int row) { return NSMakePoint(44 + 151 + 10, 190 - row * 44 + 4 + 7); };
            auto aux = [&](int row) { return NSMakePoint(44 + 174 + 13, 190 - row * 44 + 4 + 7); };
            auto drag = [&](NSPoint from, NSPoint to) {
                [view mouseDown:Mouse(NSEventTypeLeftMouseDown, from, w)];
                [view mouseDragged:Mouse(NSEventTypeLeftMouseDragged, NSMakePoint((from.x + to.x) / 2, (from.y + to.y) / 2), w)];
                [view mouseDragged:Mouse(NSEventTypeLeftMouseDragged, to, w)];
                [view mouseUp:Mouse(NSEventTypeLeftMouseUp, to, w)];
            };
            Click(view, w, NSMakePoint(36 + 424 - 20, 48 + 200 - 17));  // close the DELAY detail (open since the FX LFO step)
            Click(view, w, NSMakePoint(172 + 3 * 30 + 14, 234 + 7));    // page 13-16
            NSPoint c0 = curve(0);
            drag(c0, NSMakePoint(c0.x, c0.y + 30));                    // slot 13 (FX LFO 1 -> FL DEPTH): EXP 50%
            drag(badge(14), aux(0));                                   // x FX LFO 2
            drag(badge(9), aux(1));                                    // slot 14 (FX LFO 2 -> DELAY FB) x MACRO 1
            Snapshot(view, "MUEW_ROUTEAUX_PNG", "route curve/aux page 4 snapshot written");
            Click(view, w, NSMakePoint(172 + 14, 234 + 7));            // page 1-4
            drag(c0, NSMakePoint(c0.x, c0.y - 24));                    // slot 1: LOG 40%
            drag(badge(8), aux(0));                                    // x VELOCITY
            Snapshot(view, "MUEW_ROUTECURVE_PNG", "route curve/aux page 1 snapshot written");
            muew::Preset st;
            bool ok = State(st);
            using S = muew::ModRoute::Source;
            bool sized = ok && st.routes.size() >= 14;
            printf("route curves: slot13 curve %.2f aux %d, slot14 aux %d, slot1 curve %.2f aux %d (%s)\n",
                   sized ? st.routes[12].curve : 0.0, sized ? st.routes[12].aux : -9, sized ? st.routes[13].aux : -9,
                   sized ? st.routes[0].curve : 0.0, sized ? st.routes[0].aux : -9,
                   sized ? muew::ui::curveReadout(st.routes[0].curve).c_str() : "?");
            Check(sized && std::fabs(st.routes[12].curve - 0.5) < 0.02 && std::fabs(st.routes[0].curve + 0.4) < 0.02,
                  "curve glyph drags bent slot 13 to EXP 50% and slot 1 to LOG 40% in the AU's sound");
            Check(sized && st.routes[12].aux == (int)S::FxLfo2 && st.routes[13].aux == (int)S::Macro1 && st.routes[0].aux == (int)S::Velocity,
                  "dropping badges on AUX chips set FX LFO 2, MACRO 1 and VELOCITY as aux sources");
            muew::Preset back;
            Check(ok && back.parse(st.serialize()) && back == st && st.serialize().find(" aux ") != std::string::npos,
                  "the AU state saves route curves and aux sources");
            Click(view, w, card(3));                                   // DELAY detail back open for the editor snapshot
            fflush(stdout);
        });
        After(6.99, ^{ // 0.17.0 MSEG editor: open MSEG 2, add points, bend a segment, LOOP + sync, then route it to CUTOFF
            CGFloat t = view.bounds.size.height - 100;
            CGFloat h = (t - 286 - 44 - 58 - 6) / 2;
            auto card = [&](int slot) { return NSMakePoint(468 + (slot % 4) * 78 + 50, (slot < 4 ? 58 + h + 6 : 58) + h - 35); };
            auto badge = [&](int i) { return NSMakePoint(304 + (i % 8) * 19 + 8.75, (i < 8 ? 216 : 198) + 7.5); };
            auto canvas = [&](double tt, double v) { return NSMakePoint(50 + 396 * tt, 152 + 54 * v); }; // canvas y 94..210 since 0.18.0
            auto drag = [&](NSPoint from, NSPoint to) {
                [view mouseDown:Mouse(NSEventTypeLeftMouseDown, from, w)];
                [view mouseDragged:Mouse(NSEventTypeLeftMouseDragged, NSMakePoint((from.x + to.x) / 2, (from.y + to.y) / 2), w)];
                [view mouseDragged:Mouse(NSEventTypeLeftMouseDragged, to, w)];
                [view mouseUp:Mouse(NSEventTypeLeftMouseUp, to, w)];
            };
            Click(view, w, NSMakePoint(36 + 424 - 20, 48 + 200 - 17));   // close the DELAY detail
            Click(view, w, badge(7));                                    // select MS2
            Click(view, w, NSMakePoint(304 + 74, 122 + 29));             // its preview opens the MSEG editor
            Click(view, w, NSMakePoint(36 + 12 + 2 * 58 + 27, 48 + 18.5)); // LOOP
            Click(view, w, canvas(0.25, -1));                            // add a point at 1/4, bottom
            Click(view, w, canvas(0.75, 1));                             // add a point at 3/4, top
            NSPoint seg = canvas(0.075, 0.5);                            // bend handle of segment 1 (0 -> 0.15)
            drag(seg, NSMakePoint(seg.x, seg.y + 30));                   // up 30 pt: LOG 50%
            Click(view, w, NSMakePoint(36 + 381 + 15.5, 48 + 18.5));     // SYNC (1/4)
            Snapshot(view, "MUEW_MSEG_PNG", "MSEG 2 editor snapshot written");
            muew::Preset st;
            bool ok = State(st);
            const auto& v = st.voice;
            bool pts = ok && v.mseg2Points.size() == 6 && std::fabs(v.mseg2Points[2].time - 0.25) < 1e-9 && std::fabs(v.mseg2Points[2].value + 1) < 1e-3
                       && std::fabs(v.mseg2Points[4].time - 0.75) < 1e-9 && std::fabs(v.mseg2Points[4].value - 1) < 1e-3;
            printf("mseg 2: %zu points, seg 1 curve %.2f, mode %d, sync %d (%s)\n", v.mseg2Points.size(), v.mseg2Points.empty() ? 0.0 : v.mseg2Points[0].curve,
                   v.mseg2Mode, v.mseg2Sync, muew::ui::syncName(v.mseg2Sync));
            Check(pts, "canvas clicks added MSEG 2 points at 1/4 (-1) and 3/4 (+1) in the AU's sound");
            Check(ok && std::fabs(v.mseg2Points[0].curve + 0.5) < 0.03 && v.mseg2Mode == 2 && v.mseg2Sync == 3,
                  "bend handle, LOOP and SYNC reached the AU's sound");
            Click(view, w, NSMakePoint(36 + 424 - 20, 48 + 200 - 17));   // close the editor
            Click(view, w, NSMakePoint(492 + 30, t - 29 + 8));           // FILTER 1 page
            size_t n0 = st.routes.size();
            drag(badge(7), NSMakePoint(536, t - 94));                    // MS2 -> CUTOFF
            muew::Preset st2;
            bool ok2 = State(st2);
            Check(ok2 && st2.routes.size() == n0 + 1 && st2.routes.back().source == muew::ModRoute::Source::MSEG2
                  && st2.routes.back().dest == muew::ModRoute::Dest::FilterCutoff, "dragging the MS2 badge onto CUTOFF added an MSEG 2 route");
            muew::Preset back;
            Check(ok2 && back.parse(st2.serialize()) && back == st2 && st2.serialize().find("\nmseg2 ") != std::string::npos,
                  "the AU state saves MSEG 2 with the sound");
            Click(view, w, NSMakePoint(556 + 46, t - 29 + 8));           // back to FILTER 2 + SUB
            Click(view, w, card(3));                                     // DELAY detail for the editor snapshot
            fflush(stdout);
        });
        After(6.995, ^{ // 0.18.0 LFO editor: draw LFO 3's cycle, bend it, FREE, PHASE 90 degrees, RISE
            CGFloat t = view.bounds.size.height - 100;
            CGFloat h = (t - 286 - 44 - 58 - 6) / 2;
            auto card = [&](int slot) { return NSMakePoint(468 + (slot % 4) * 78 + 50, (slot < 4 ? 58 + h + 6 : 58) + h - 35); };
            auto badge = [&](int i) { return NSMakePoint(304 + (i % 8) * 19 + 8.5, (i < 8 ? 216 : 198) + 7.5); };
            auto canvas = [&](double tt, double v) { return NSMakePoint(50 + 396 * tt, 152 + 54 * v); };
            auto drag = [&](NSPoint from, NSPoint to) {
                [view mouseDown:Mouse(NSEventTypeLeftMouseDown, from, w)];
                [view mouseDragged:Mouse(NSEventTypeLeftMouseDragged, NSMakePoint((from.x + to.x) / 2, (from.y + to.y) / 2), w)];
                [view mouseDragged:Mouse(NSEventTypeLeftMouseDragged, to, w)];
                [view mouseUp:Mouse(NSEventTypeLeftMouseUp, to, w)];
            };
            Click(view, w, NSMakePoint(36 + 424 - 20, 48 + 200 - 17));   // close the DELAY detail
            Click(view, w, badge(2));                                    // select LFO3
            Click(view, w, NSMakePoint(304 + 74, 122 + 29));             // its preview opens the LFO editor
            Click(view, w, canvas(0.5, 1));                              // add a point at 1/2, top
            Click(view, w, canvas(0.875, 0.5));                          // add a point at 7/8, +0.5
            NSPoint seg = canvas(0.625, 0);                              // bend handle of segment 3 (1/2 -> 3/4, falling)
            drag(seg, NSMakePoint(seg.x, seg.y - 30));                   // down 30 pt: LOG 50%
            Click(view, w, NSMakePoint(36 + 12 + 44 + 21, 48 + 18.5));   // FREE
            NSPoint ph = NSMakePoint(36 + 104 + 23, 48 + 18.5), ri = NSMakePoint(36 + 104 + 96 + 23, 48 + 18.5);
            drag(ph, NSMakePoint(ph.x, ph.y + 37.5));                    // PHASE +0.25 -> 90 degrees
            drag(ri, NSMakePoint(ri.x, ri.y + 75));                      // RISE to mid-range (about 0.26 s)
            Snapshot(view, "MUEW_LFO_PNG", "LFO 3 editor snapshot written");
            muew::Preset st;
            bool ok = State(st);
            const auto& v = st.voice;
            const auto& lp = v.lfoPoints[2];
            printf("lfo 3: custom %d, %zu points, seg 3 curve %.2f, free %d, phase %.3f, rise %.3f s\n", (int)v.lfoCustom[2], lp.size(),
                   lp.size() > 2 ? lp[2].curve : 0.0, (int)v.lfoFree[2], v.lfoPhase[2], v.lfoRise[2]);
            bool pts = ok && lp.size() == 6 && std::fabs(lp[2].time - 0.5) < 1e-9 && std::fabs(lp[2].value - 1) < 1e-3
                       && std::fabs(lp[4].time - 0.875) < 1e-9 && std::fabs(lp[4].value - 0.5) < 1e-3;
            Check(pts && v.lfoCustom[2], "canvas clicks drew LFO 3 points at 1/2 (+1) and 7/8 (+0.5) and turned CUSTOM on in the AU's sound");
            Check(ok && std::fabs(lp[2].curve + 0.5) < 0.03 && v.lfoFree[2] && std::fabs(v.lfoPhase[2] - 0.25) < 1e-9 && v.lfoRise[2] > 0.2 && v.lfoRise[2] < 0.33,
                  "bend handle, FREE, PHASE 90 and RISE reached the AU's sound");
            muew::Preset back;
            std::string txt = ok ? st.serialize() : "";
            Check(ok && back.parse(txt) && back == st && txt.find("\nlfox 2 1 ") != std::string::npos && txt.find("\nlfopts 2 6 ") != std::string::npos,
                  "the AU state saves the drawn LFO 3 with the sound");
            Click(view, w, NSMakePoint(36 + 424 - 20, 48 + 200 - 17));   // close the editor
            Click(view, w, card(3));                                     // DELAY detail for the editor snapshot
            fflush(stdout);
        });
        After(6.997, ^{ // 0.19.0 warp depth: OSC A WARP 2 = REMAP at 50% with a drawn curve, OSC B WARP 2 = FM B
            CGFloat t = view.bounds.size.height - 100;
            CGFloat h = (t - 286 - 44 - 58 - 6) / 2;
            auto card = [&](int slot) { return NSMakePoint(468 + (slot % 4) * 78 + 50, (slot < 4 ? 58 + h + 6 : 58) + h - 35); };
            auto canvas = [&](double tt, double v) { return NSMakePoint(50 + 396 * tt, 152 + 54 * v); };
            muew::Preset before;
            bool ok0 = State(before);
            Click(view, w, NSMakePoint(36 + 424 - 20, 48 + 200 - 17));   // close the DELAY detail
            Click(view, w, NSMakePoint(400 + 24, t - 32 + 8.5));         // DONE: the 0.9.0 wavetable editor still covers the OSC panel
            Click(view, w, NSMakePoint(46 + 96 + 15, t - 149));          // OSC A slot 2 back arrow: CLEAN -> REMAP
            for (int i = 0; i < 7; ++i) Click(view, w, NSMakePoint(252 + 96 + 61, t - 149)); // OSC B slot 2 forward x7: FM B
            NSPoint a0 = NSMakePoint(46 + 96 + 67 + 3, t - 149);        // OSC A slot 2 amount bar (24 pt = 100%)
            [view mouseDown:Mouse(NSEventTypeLeftMouseDown, a0, w)];
            [view mouseDragged:Mouse(NSEventTypeLeftMouseDragged, NSMakePoint(a0.x + 6, a0.y), w)];
            [view mouseDragged:Mouse(NSEventTypeLeftMouseDragged, NSMakePoint(a0.x + 12, a0.y), w)];
            [view mouseUp:Mouse(NSEventTypeLeftMouseUp, NSMakePoint(a0.x + 12, a0.y), w)];
            NSPoint b0 = NSMakePoint(252 + 96 + 67 + 3, t - 149);       // OSC B slot 2 amount: +9 pt = 37.5%
            [view mouseDown:Mouse(NSEventTypeLeftMouseDown, b0, w)];
            [view mouseDragged:Mouse(NSEventTypeLeftMouseDragged, NSMakePoint(b0.x + 9, b0.y), w)];
            [view mouseUp:Mouse(NSEventTypeLeftMouseUp, NSMakePoint(b0.x + 9, b0.y), w)];
            Click(view, w, NSMakePoint(46 + 190 - 84 + 20, t - 49 - 17 + 6.5)); // OSC A CURVE chip opens the REMAP editor
            Click(view, w, canvas(0.25, 0.5));                           // add a point at 1/4 -> +0.5
            Click(view, w, canvas(0.75, -0.5));                          // add a point at 3/4 -> -0.5 (a fold)
            Snapshot(view, "MUEW_WARP_PNG", "OSC warp slots + REMAP editor snapshot written");
            muew::Preset st;
            bool ok = State(st);
            const auto& v = st.voice;
            const auto& rp = v.remapPoints[0];
            printf("warp 2: A mode %d amt %.3f, B mode %d amt %.3f; remap A %zu points\n", v.osc1Warp2Mode, v.osc1Warp2, v.osc2Warp2Mode, v.osc2Warp2, rp.size());
            Check(ok0 && ok && before.voice.osc1Warp2Mode == 0 && v.osc1Warp2Mode == 10 && v.osc2Warp2Mode == 7,
                  "warp slot arrows set OSC A WARP 2 to REMAP and OSC B WARP 2 to FM B in the AU's sound");
            Check(ok && std::fabs(v.osc1Warp2 - 0.5) < 0.02 && std::fabs(v.osc2Warp2 - 0.375) < 0.02, "WARP 2 amount bars reached the AU's sound");
            bool pts = ok && rp.size() == 4 && std::fabs(rp[1].time - 0.25) < 1e-9 && std::fabs(rp[1].value - 0.5) < 1e-3
                       && std::fabs(rp[2].time - 0.75) < 1e-9 && std::fabs(rp[2].value + 0.5) < 1e-3;
            Check(pts, "CURVE chip opened the REMAP editor and canvas clicks drew OSC A's curve in the AU's sound");
            muew::Preset back;
            std::string txt = ok ? st.serialize() : "";
            Check(ok && back.parse(txt) && back == st && txt.find("\nwarpx 10 ") != std::string::npos && txt.find("\nremap 0 4 ") != std::string::npos,
                  "the AU state saves both warp slots and the REMAP curve with the sound");
            Click(view, w, NSMakePoint(36 + 424 - 20, 48 + 200 - 17));   // close the editor
            Click(view, w, card(3));                                     // DELAY detail for the editor snapshot
            Click(view, w, NSMakePoint(46 + 95, t - 80));                // reopen OSC A's wavetable editor, as the snapshot showed before
            fflush(stdout);
        });
        After(7.0, ^{ // Snapshot the hosted editor itself (independent of screen capture timing).
            Snapshot(view, "MUEW_VIEW_PNG", "editor snapshot written after the scripted edits");
        });
        After(7.2, ^{ // 0.11.0 full browser: open it, import a file, filter by a character tag, rate, sort by rating
            CGFloat t = view.bounds.size.height - 100;
            Click(view, w, NSMakePoint(view.bounds.size.width - 76 + 23, t - 26 + 8)); // FULL pill on the compact browser
            muew::Preset mine;
            State(mine);
            mine.info.name = "Harness Import"; mine.info.author = "Sam"; mine.info.description = "Brought in with Import.";
            NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"muew-harness-import.muew"];
            [[NSString stringWithUTF8String:mine.serialize().c_str()] writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
            typedef BOOL (*ImportFn)(id, SEL, NSString*);
            SEL sel = NSSelectorFromString(@"importPresetFile:");
            BOOL imported = [view respondsToSelector:sel] && ((ImportFn)[view methodForSelector:sel])(view, sel, path);
            muew::Preset st;
            Check(imported && State(st) && st.info.name == "Harness Import" && st.info.author == "Sam" && PresetNumber() < 0,
                  "Import put the file in the Imported bank and loaded it into the AU");
            Click(view, w, NSMakePoint(125, t - 80 + 9));             // BANK: All banks
            Click(view, w, NSMakePoint(81, t - 404 + 9));             // CHARACTER: dark
            Click(view, w, NSMakePoint(400, t - 62 - 40 + 9));        // table row 2
            SInt32 second = PresetNumber();
            Click(view, w, NSMakePoint(728 + 3 * 20 + 10, t - 104 + 10)); // info pane: 4 stars
            NSUserDefaults* d = [[NSUserDefaults alloc] initWithSuiteName:@"co.instinct.muew"];
            NSNumber* stars = [d dictionaryForKey:@"MUEWRatings"][@"sub-bass"];
            printf("browser: row 2 under 'dark' is preset %d, rating stored %d\n", (int)second, stars ? stars.intValue : 0);
            Check(second == 6 && stars.intValue == 4, "dark tag lists Sub Bass second; the info stars rated it 4");
            Click(view, w, NSMakePoint(650, t - 62 + 10));            // RATING column header
            Click(view, w, NSMakePoint(400, t - 62 - 40 + 9));        // row 2 after the sort
            SInt32 afterSortRow2 = PresetNumber();
            Click(view, w, NSMakePoint(400, t - 62 - 20 + 9));        // row 1 after the sort
            SInt32 afterSortRow1 = PresetNumber();
            printf("browser: sorted by rating, row 1 = %d, row 2 = %d\n", (int)afterSortRow1, (int)afterSortRow2);
            Check(afterSortRow1 == 6 && afterSortRow2 == 4, "RATING sort put the rated Sub Bass above Punchy Bass");
            fflush(stdout);
        });
        After(8.6, ^{
            Snapshot(view, "MUEW_BROWSER_PNG", "full browser snapshot written");
        });
        After(9.0, ^{
            printf(gFailures ? "FAIL: AU editor host test\n" : "PASS: AU editor hosted; host->editor, editor->AU, automation, macros, user presets, unison, FX rack + chain reorder + detail editor, mod matrix, wavetable editor, filter 2 + sub page and full browser\n");
            fflush(stdout);
            exit(gFailures ? 1 : 0);
        });
        [app run];
    }
    return 0;
}
