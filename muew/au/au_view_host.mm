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
        After(5.5, ^{ SelectPreset(34); }); // host switches to Fold Screamer (unison + distortion/EQ/compressor)
        After(5.8, ^{
            CGFloat t = view.bounds.size.height - 100;
            NSPoint pip = NSMakePoint(46 + 6 + 4 * 13 + 6.5, t - 142); // osc A unison pip 5
            [view mouseDown:Mouse(NSEventTypeLeftMouseDown, pip, w)];
            [view mouseUp:Mouse(NSEventTypeLeftMouseUp, pip, w)];
            NSPoint wk = NSMakePoint(250, t - 192); // WIDTH knob: drag down 30 pt = -20%
            [view mouseDown:Mouse(NSEventTypeLeftMouseDown, wk, w)];
            [view mouseDragged:Mouse(NSEventTypeLeftMouseDragged, NSMakePoint(wk.x, wk.y - 15), w)];
            [view mouseDragged:Mouse(NSEventTypeLeftMouseDragged, NSMakePoint(wk.x, wk.y - 30), w)];
            [view mouseUp:Mouse(NSEventTypeLeftMouseUp, NSMakePoint(wk.x, wk.y - 30), w)];
            CGFloat cardH = (t - 286 - 44 - 58 - 6) / 2;
            NSPoint dr = NSMakePoint(468 + 26, 58 + cardH + 6 + 27); // DISTORTION drive ring: up 30 pt = +20%
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
            NSPoint badge = NSMakePoint(304 + 2 * 25 + 11.5, 216 + 7.5); // LFO3 source badge
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
            // New slot n is on page (n-1)/4, row (n-1)%4. Drag its amount bar handle right 30 pt (+0.4 of full scale).
            int row = (int)((n - 1) % 4);
            double amt0 = n ? mid.routes[n - 1].amount / 5.0 : 0;
            NSPoint h = NSMakePoint(44 + 28 + 75 + amt0 * 75, 190 - row * 44 + 4 + 7);
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
        After(9.0, ^{
            printf(gFailures ? "FAIL: AU editor host test\n" : "PASS: AU editor hosted; host->editor, editor->AU, automation, macros, user presets, unison, FX rack, mod matrix, wavetable editor and filter 2 + sub page\n");
            fflush(stdout);
            exit(gFailures ? 1 : 0);
        });
        [app run];
    }
    return 0;
}
