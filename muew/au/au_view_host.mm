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
#include "frame_tools.h"
#include "partial_edit.h"
#include "partial_view.h"
#include "partial_brush.h"
#include "spectral_clipboard.h"
#include "au_params.h"
#include "ui_model.h"
#include "spectral_process.h"
#include <cstdio>
#include <cmath>
#include <string>
#include <vector>

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

// 0.24.0: render a block so the AU applies queued MIDI and publishes its performance values.
static bool RenderBlock(UInt32 frames = 512) {
    static Float64 sampleTime = 0;
    std::vector<float> l(frames), r(frames);
    AudioBufferList* b = (AudioBufferList*)calloc(1, sizeof(AudioBufferList) + sizeof(AudioBuffer));
    b->mNumberBuffers = 2;
    b->mBuffers[0] = {1, static_cast<UInt32>(frames * sizeof(float)), l.data()};
    b->mBuffers[1] = {1, static_cast<UInt32>(frames * sizeof(float)), r.data()};
    AudioUnitRenderActionFlags flags = 0; AudioTimeStamp ts{}; ts.mFlags = kAudioTimeStampSampleTimeValid; ts.mSampleTime = sampleTime;
    const bool ok = AudioUnitRender(gUnit, &flags, &ts, 0, frames, b) == noErr;
    sampleTime += frames; free(b); return ok;
}
static std::string PerfText(NSView* view) {
    SEL sel = NSSelectorFromString(@"muewPerformanceText");
    if (![view respondsToSelector:sel]) return "";
    NSString* s = [view valueForKey:@"muewPerformanceText"];
    return s.UTF8String ?: "";
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
            NSPoint dr = NSMakePoint(468 + 28, 58 + cardH + 6 + 36); // DISTORTION drive ring (chain slot 1): up 30 pt = +20%
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
            NSPoint harm = NSMakePoint(258 + 35 + 16, t - 32 + 8);        // HARM tab (0.31.0: four tabs, 35 pt pitch)
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
            NSPoint from = NSMakePoint(468 + 1 * 62 + 20, 58 + h - 25);         // PHASER card body (bottom row, 2nd)
            NSPoint to = NSMakePoint(468 + 1 * 62 + 20, 58 + h + 6 + h - 25);   // CHORUS card (top row, 2nd)
            [view mouseDown:Mouse(NSEventTypeLeftMouseDown, from, w)];
            [view mouseDragged:Mouse(NSEventTypeLeftMouseDragged, NSMakePoint((from.x + to.x) / 2, (from.y + to.y) / 2), w)];
            [view mouseDragged:Mouse(NSEventTypeLeftMouseDragged, to, w)];
            [view mouseUp:Mouse(NSEventTypeLeftMouseUp, to, w)];
            Click(view, w, NSMakePoint(468 + 62 + 56 - 9, 58 + h + 6 + h - 11)); // its LED, now in slot 2
            NSPoint ring = NSMakePoint(468 + 62 + 28, 58 + h + 6 + 36);          // its MIX ring: up 30 pt = +20%
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
            Check(ok && ord == "dist phaser chorus delay comp reverb eq flanger hyper filterfx", "dragging the PHASER card moved it to chain slot 2 in the AU state");
            Check(ok && st.fx.phaser.enabled && pm > 60 && pm < 80 && std::fabs(st.fx.phaser.mix - pm / 100.0) < 1e-3,
                  "PHASER LED and MIX ring reached the AU (parameter 28)");
            fflush(stdout);
        });
        After(6.95, ^{ // 0.14.0 FX detail editor: open PHASER, set DEPTH; open DELAY, sync L to 1/8, set FEEDBACK
            CGFloat t = view.bounds.size.height - 100;
            CGFloat h = (t - 286 - 44 - 58 - 6) / 2;
            auto card = [&](int slot) { return NSMakePoint(468 + (slot % 5) * 62 + 20, (slot < 5 ? 58 + h + 6 : 58) + h - 25); }; // 0.27.0: 5 x 2 rack
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
            auto card = [&](int slot) { return NSMakePoint(468 + (slot % 5) * 62 + 20, (slot < 5 ? 58 + h + 6 : 58) + h - 25); }; // 0.27.0: 5 x 2 rack
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
            Click(view, w, NSMakePoint(468 + 2 * 62 + 56 - 9, 58 + h - 11)); // FLANGER LED (slot 8) on
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
            auto card = [&](int slot) { return NSMakePoint(468 + (slot % 5) * 62 + 20, (slot < 5 ? 58 + h + 6 : 58) + h - 25); }; // 0.27.0: 5 x 2 rack
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
            auto card = [&](int slot) { return NSMakePoint(468 + (slot % 5) * 62 + 20, (slot < 5 ? 58 + h + 6 : 58) + h - 25); }; // 0.27.0: 5 x 2 rack
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
            auto card = [&](int slot) { return NSMakePoint(468 + (slot % 5) * 62 + 20, (slot < 5 ? 58 + h + 6 : 58) + h - 25); }; // 0.27.0: 5 x 2 rack
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
            auto card = [&](int slot) { return NSMakePoint(468 + (slot % 5) * 62 + 20, (slot < 5 ? 58 + h + 6 : 58) + h - 25); }; // 0.27.0: 5 x 2 rack
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
        After(6.999, ^{ // 0.20.0 wavetable depth: spectral MORPH the 2-frame table, import a pitched AIFF, pick a frame in 3D
            CGFloat t = view.bounds.size.height - 100;
            muew::Preset two;
            bool ok0 = State(two);
            Click(view, w, NSMakePoint(40 + 3 * 51 + 24, t - 250 + 10)); // MORPH: 2 key frames -> 8 spectral frames
            muew::Preset m8;
            bool ok1 = State(m8);
            Check(ok0 && ok1 && two.tables[0].size() == 2 && m8.tables[0].size() == 8 && m8.tables[0][0] == two.tables[0][0]
                  && m8.tables[0][7] == two.tables[0][1], "MORPH rebuilt OSC A's 2 key frames as 8 spectral frames with the keys at the ends");
            // A 1.5 s saw at 146.83 Hz (48 kHz, 16-bit AIFF) whose brightness sweeps from 2 to 40 harmonics.
            const double rate = 48000, hz = 146.83;
            const size_t n = (size_t)(1.5 * rate);
            std::vector<unsigned char> a;
            auto be = [&](uint32_t v, int k) { for (int i = k - 1; i >= 0; --i) a.push_back((v >> (8 * i)) & 255); };
            auto tag = [&](const char* t4) { a.insert(a.end(), t4, t4 + 4); };
            tag("FORM"); be((uint32_t)(4 + 26 + 16 + n * 2), 4); tag("AIFF");
            tag("COMM"); be(18, 4); be(1, 2); be((uint32_t)n, 4); be(16, 2);
            int ex; double mt = std::frexp(rate, &ex); uint64_t mant = (uint64_t)std::ldexp(mt, 64);
            be((uint32_t)(ex - 1 + 16383), 2); be((uint32_t)(mant >> 32), 4); be((uint32_t)mant, 4);
            tag("SSND"); be((uint32_t)(8 + n * 2), 4); be(0, 4); be(0, 4);
            double ph = 0;
            for (size_t i = 0; i < n; ++i) {
                double nh = 2 + 38 * (double)i / n, sm = 0;
                for (int k = 1; k <= 40; ++k) { double g = std::clamp(nh - k + 1, 0.0, 1.0); if (g > 0) sm += g * std::sin(ph * k) / k; }
                be((uint16_t)(int16_t)std::lround(std::clamp(0.5 * sm, -1.0, 1.0) * 32767), 2);
                ph += 2 * M_PI * hz / rate;
            }
            NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"muew-harness-sweep.aiff"];
            [[NSData dataWithBytes:a.data() length:a.size()] writeToFile:path atomically:YES];
            typedef BOOL (*ImportFn)(id, SEL, NSString*);
            SEL sel = NSSelectorFromString(@"importTableFile:");
            BOOL imported = [view respondsToSelector:sel] && ((ImportFn)[view methodForSelector:sel])(view, sel, path);
            muew::Preset im;
            bool ok2 = State(im);
            printf("import: %d, OSC A shape %d, %zu frames, WT POS %.3f\n", (int)imported, im.voice.osc1Shape, im.tables[0].size(), im.voice.osc1WtPos);
            Check(imported && ok2 && im.tables[0].size() == 64 && im.voice.osc1Shape == muew::kCustomShape && im.voice.osc1WtPos == 0,
                  "IMPORT sliced the pitched AIFF into 64 frames of OSC A's table in the AU");
            Click(view, w, NSMakePoint(258 + 2 * 35 + 16, t - 32 + 8.5));  // 3D tab (0.31.0 geometry)
            const double d = 40.0 / 63, rw = 408 * .6, rh = 138 * .34;       // frame 41's row in the stack
            NSPoint row = NSMakePoint(40 + 14 + d * (408 - rw - 28) + rw / 2, t - 184 + 18 + d * (138 - rh - 30) + rh / 2);
            Click(view, w, row);
            Snapshot(view, "MUEW_WT3D_PNG", "3D wavetable view snapshot written");
            muew::Preset st;
            bool ok = State(st);
            printf("3D pick: WT POS %.4f (frame %.1f)\n", st.voice.osc1WtPos, st.voice.osc1WtPos * 63 + 1);
            Check(ok && std::fabs(st.voice.osc1WtPos - 40.0 / 63) < 1e-6, "clicking frame 41's row in the 3D view moved WT POS onto it");
            muew::Preset back;
            std::string txt = ok ? st.serialize() : "";
            Check(ok && back.parse(txt) && back == st && txt.find("\nwt1 64 ") != std::string::npos, "the AU state saves the 64-frame table");
            fflush(stdout);
        });
        After(6.9992, ^{ // 0.31.0 SPECTRAL page: FORMANT +12 and TILT -6 on the imported 64-frame table, preview, APPLY
            CGFloat t = view.bounds.size.height - 100;
            const CGFloat top = t - 46; // canvas top edge
            muew::Preset st0; const bool ok0 = State(st0);
            Click(view, w, NSMakePoint(258 + 3 * 35 + 16, t - 32 + 8.5));      // SPEC tab
            Click(view, w, NSMakePoint(40 + 272 + 44 + 22, top - 22 + 3));      // FORMANT bar at +50%: +12 st
            Click(view, w, NSMakePoint(40 + 272 + 44 - 22, top - 22 - 44 + 3)); // TILT bar at -50%: -6 dB/oct
            auto specText = [&]() -> std::string {
                NSString* s2 = [view respondsToSelector:NSSelectorFromString(@"muewSpecText")] ? [view valueForKey:@"muewSpecText"] : @"";
                return s2.UTF8String ?: "";
            };
            const std::string before = specText();
            Snapshot(view, "MUEW_SPEC_PNG", "SPECTRAL page snapshot written");
            Check(before.find("mode=3 formant=12.0 stretch=0.00 tilt=-6.0 oddeven=0.00 frames=64") != std::string::npos, "SPECTRAL bars set FORMANT +12 st and TILT -6 dB");
            muew::Preset mid; const bool ok1 = State(mid);
            Check(ok0 && ok1 && mid.tables[0] == st0.tables[0], "the preview leaves the AU's table untouched until APPLY");
            Click(view, w, NSMakePoint(40 + 272 + 30, t - 184 + 8 + 9));       // APPLY
            muew::Preset st; const bool ok2 = State(st);
            muew::SpectralProcess sp; sp.formantSt = 12; sp.tiltDb = -6;
            const double want = ok0 && st0.tables[0].size() > 32 ? muew::frameCentroid(muew::processFrame(st0.tables[0][32], sp)) : 0;
            const double got = ok2 && st.tables[0].size() > 32 ? muew::frameCentroid(st.tables[0][32]) : -1;
            const std::string after = specText();
            printf("spectral31: %s -> %s; frame 33 centroid %.3f (expected %.3f)\n", before.c_str(), after.c_str(), got, want);
            Check(ok2 && st.tables[0].size() == 64 && std::fabs(got - want) < 0.02 * want + 0.01, "APPLY processed all 64 frames in the AU's table");
            Check(after.find("formant=0.0 stretch=0.00 tilt=0.0 oddeven=0.00") != std::string::npos, "APPLY clears the pending process");
            // 0.32.0 undo / redo: the header arrows step back to the imported table and forward to the processed one.
            auto histText = [&]() -> std::string {
                NSString* s3 = [view respondsToSelector:NSSelectorFromString(@"muewHistoryText")] ? [view valueForKey:@"muewHistoryText"] : @"";
                return s3.UTF8String ?: "";
            };
            const std::string h0 = histText();
            Click(view, w, NSMakePoint(224 + 7.5, t - 32 + 8.5));             // UNDO
            muew::Preset un; const bool ok3 = State(un);
            const std::string h1 = histText();
            Snapshot(view, "MUEW_UNDO_PNG", "undo snapshot written");
            Click(view, w, NSMakePoint(224 + 18 + 7.5, t - 32 + 8.5));        // REDO
            muew::Preset re; const bool ok4 = State(re);
            const std::string h2 = histText();
            printf("undo32: %s | after UNDO %s | after REDO %s\n", h0.c_str(), h1.c_str(), h2.c_str());
            Check(h0.find("last=APPLY") != std::string::npos, "APPLY is the newest step in the WT history");
            Check(ok3 && un.tables[0] == st0.tables[0], "UNDO restores the table from before APPLY in the AU");
            Check(ok4 && re.tables[0] == st.tables[0], "REDO puts the processed table back");
            Check(h2.find("redo=0") != std::string::npos, "REDO empties the redo side again");
            Click(view, w, NSMakePoint(258 + 2 * 35 + 16, t - 32 + 8.5));      // back to the 3D tab for the steps that follow
            fflush(stdout);
        });
        After(6.9993, ^{ // 0.33.0 live SPEC morph: TILT -9 as OSC A's morph target, MORPH bar at 60%, then A / B compare
            CGFloat t = view.bounds.size.height - 100;
            const CGFloat top = t - 46, cvy = t - 184; // canvas top and bottom edges
            auto morphText = [&]() -> std::string {
                NSString* s4 = [view respondsToSelector:NSSelectorFromString(@"muewMorphText")] ? [view valueForKey:@"muewMorphText"] : @"";
                return s4.UTF8String ?: "";
            };
            Click(view, w, NSMakePoint(258 + 3 * 35 + 16, t - 32 + 8.5));      // SPEC tab
            Click(view, w, NSMakePoint(40 + 272 + 44 - 33, top - 22 - 44 + 3)); // TILT bar at -75%: -9 dB/oct
            muew::Preset b0; const bool ok0 = State(b0);
            Click(view, w, NSMakePoint(40 + 214 + 26, cvy + 8 + 9));           // TO MORPH
            muew::Preset b1; const bool ok1 = State(b1);
            int wired = 0;
            for (const auto& r : b1.routes) if (r.dest == muew::ModRoute::Dest::Osc1SpecMorph && r.source == muew::ModRoute::Source::Macro2) ++wired;
            Check(ok0 && ok1 && b1.voice.osc1MorphSpec.tiltDb == -9 && b1.tables[0] == b0.tables[0] && wired == 1,
                  "TO MORPH stored TILT -9 as OSC A's morph target, kept the table and wired the WARP macro in the AU");
            Click(view, w, NSMakePoint(40 + 272 + 0.6 * 60, cvy + 33 + 3));    // MORPH bar at 60% (0.34.0: 60 wide)
            Click(view, w, NSMakePoint(40 + 337 + 30, cvy + 29.5 + 6.5));      // 0.34.0 driver chip, right half: WARP -> LFO 1
            muew::Preset b2; const bool ok2 = State(b2);
            int lfoRoutes = 0;
            for (const auto& r : b2.routes) if (r.dest == muew::ModRoute::Dest::Osc1SpecMorph && r.source == muew::ModRoute::Source::LFO1 && r.amount == 0.5) ++lfoRoutes;
            Check(ok2 && lfoRoutes == 1 && muew::ui::morphDriverRoute(b2, 0) >= 0, "the driver chip moved OSC A's morph route from the WARP macro to LFO 1 at half depth");
            muew::Preset pa = b2; muew::params::set(pa, muew::params::SpecMorphA, 25);
            Check(pa.voice.osc1SpecMorph == 0.25 && std::fabs(muew::params::get(b2, muew::params::SpecMorphA) - 60) < 1.1, "SPEC MORPH A is AU parameter 38 over the same amount");
            AudioUnitParameterValue smA = -1;
            AudioUnitGetParameter(gUnit, muew::params::SpecMorphA, kAudioUnitScope_Global, 0, &smA);
            printf("param38: %.1f\n", smA);
            Check(std::fabs(smA - 60) < 1.1, "the AU publishes the MORPH bar's 60% on parameter 38");
            const std::string m2 = morphText();
            Snapshot(view, "MUEW_MORPH_PNG", "SPEC morph snapshot written");
            printf("morph33: %s\n", m2.c_str());
            Check(ok2 && std::fabs(b2.voice.osc1SpecMorph - 0.6) < 0.011, "the MORPH bar set OSC A's morph amount to 60% in the AU");
            Click(view, w, NSMakePoint(134 + 7, t - 32 + 8.5));               // A
            muew::Preset ca; const bool ok3 = State(ca);
            const std::string ma = morphText();
            Snapshot(view, "MUEW_COMPARE_PNG", "A / B compare snapshot written");
            Click(view, w, NSMakePoint(134 + 15 + 7, t - 32 + 8.5));          // B
            muew::Preset cb; const bool ok4 = State(cb);
            printf("compare33: A %s | B %s\n", ma.c_str(), morphText().c_str());
            Check(ok3 && ma.find("cmp=A") != std::string::npos && !(ca.tables[0] == b2.tables[0]) && ca.voice.osc1MorphSpec.isIdentity(),
                  "A plays OSC A as the preset loaded it: the original table and no morph target");
            Check(ok4 && cb.tables[0] == b2.tables[0] && cb.voice.osc1MorphSpec == b2.voice.osc1MorphSpec && cb.voice.osc1SpecMorph == b2.voice.osc1SpecMorph,
                  "B puts the edited table, morph target and amount back");
            muew::Preset rt; const std::string txt = ok4 ? cb.serialize() : "";
            Check(ok4 && rt.parse(txt) && rt == cb && txt.find("\nmorphspec1 0 0 -9 0\n") != std::string::npos, "the AU state saves the morph target");
            Click(view, w, NSMakePoint(258 + 2 * 35 + 16, t - 32 + 8.5));      // back to the 3D tab for the steps that follow
            fflush(stdout);
        });
        After(6.9994, ^{ // 0.35.0 live morph view: WARP drives OSC A's morph, a held chord plays it at 70%, the editor follows the engine
            CGFloat t = view.bounds.size.height - 100;
            const CGFloat cvy = t - 184;
            Click(view, w, NSMakePoint(258 + 3 * 35 + 16, t - 32 + 8.5));      // SPEC tab
            muew::Preset s0; State(s0);
            for (int i = 0; i < 12 && s0.routes.size() && muew::ui::morphDriverRoute(s0, 0) >= 0 && s0.routes[muew::ui::morphDriverRoute(s0, 0)].source != muew::ModRoute::Source::Macro2; ++i) {
                Click(view, w, NSMakePoint(40 + 337 + 4, cvy + 29.5 + 6.5));   // driver chip, left edge: step back toward WARP
                State(s0);
            }
            const int dri = muew::ui::morphDriverRoute(s0, 0);
            Check(dri >= 0 && s0.routes[dri].source == muew::ModRoute::Source::Macro2 && s0.routes[dri].amount == 1.0, "the chip's left edge stepped the driver back to WARP at full depth");
            AudioUnitSetParameter(gUnit, muew::params::SpecMorphA, kAudioUnitScope_Global, 0, 20.0f, 0); // base 20% (parameter 38)
            AudioUnitSetParameter(gUnit, muew::params::Macro2, kAudioUnitScope_Global, 0, 50.0f, 0);     // WARP 50%: live 70%
            MusicDeviceMIDIEvent(gUnit, 0x90, 48, 100, 0); MusicDeviceMIDIEvent(gUnit, 0x90, 55, 100, 0); MusicDeviceMIDIEvent(gUnit, 0x90, 60, 100, 0);
            for (int i = 0; i < 6; ++i) RenderBlock();
            typedef void (*SyncFn)(id, SEL, BOOL);
            SEL sync = NSSelectorFromString(@"syncFromAU:");
            if ([view respondsToSelector:sync]) ((SyncFn)[view methodForSelector:sync])(view, sync, YES);
            SEL follow = NSSelectorFromString(@"muewFollowPerformance");
            if ([view respondsToSelector:follow]) ((void (*)(id, SEL))[view methodForSelector:follow])(view, follow);
            [view display];
            NSString* lt = [view respondsToSelector:NSSelectorFromString(@"muewLiveMorphText")] ? [view valueForKey:@"muewLiveMorphText"] : @"";
            const std::string live = lt.UTF8String ?: "";
            MUEWPerformance pf{}; UInt32 sz = sizeof(pf);
            const bool got = AudioUnitGetProperty(gUnit, kMUEWProperty_Performance, kAudioUnitScope_Global, 0, &pf, &sz) == noErr;
            Snapshot(view, "MUEW_LIVEMORPH_PNG", "live morph snapshot written");
            printf("livemorph35: %s; engine meter %.3f / %.3f\n", live.c_str(), pf.specMorph[0], pf.specMorph[1]);
            Check(got && std::fabs(pf.specMorph[0] - 0.7f) < 0.01f && pf.specMorph[1] <= 0.0f, "the engine reports OSC A playing its morph at 70% (20% base + WARP 50%), OSC B none");
            Check(live.find("live=0.70/") != std::string::npos && live.find("shown=0.70/") != std::string::npos, "the editor shows the engine's live 70% morph");
            MusicDeviceMIDIEvent(gUnit, 0x80, 48, 0, 0); MusicDeviceMIDIEvent(gUnit, 0x80, 55, 0, 0); MusicDeviceMIDIEvent(gUnit, 0x80, 60, 0, 0);
            AudioUnitSetParameter(gUnit, muew::params::Macro2, kAudioUnitScope_Global, 0, 0.0f, 0);
            for (int i = 0; i < 4; ++i) RenderBlock();
            Click(view, w, NSMakePoint(258 + 2 * 35 + 16, t - 32 + 8.5));      // back to the 3D tab for the steps that follow
            fflush(stdout);
        });
        After(6.99945, ^{ // 0.36.0 morph everywhere: per-voice ghosts on both main OSC displays, the matrix row meter, SNAP A on the SPEC page
            muew::Preset keep; const bool kept = State(keep);
            muew::Preset g = keep;
            if (g.tables[0].empty()) for (int f = 0; f < 4; ++f) g.tables[0].push_back(muew::shapeFrame(2));
            g.tables[1] = g.tables[0];
            g.voice.osc1Shape = muew::kCustomShape; g.voice.osc2Shape = muew::kCustomShape; g.voice.osc2Level = 0.7;
            muew::SpectralProcess sp; sp.tiltDb = -12; sp.formantSt = 5;
            muew::ui::clearSpecMorph(g, 0); muew::ui::clearSpecMorph(g, 1);
            while (g.routes.size() > 12) g.routes.pop_back();
            muew::ui::setSpecMorphTarget(g, 0, sp); muew::ui::setSpecMorphTarget(g, 1, sp);
            g.voice.osc1SpecMorph = 0.2; g.voice.osc2SpecMorph = 0.45; g.voice.macros[1] = 0;
            g.voice.arpOn = false; g.voice.voiceMode = 0; g.voice.polyVoices = std::max(g.voice.polyVoices, 8); // three separate voices
            muew::ModRoute vr; vr.source = muew::ModRoute::Source::Velocity; vr.dest = muew::ModRoute::Dest::Osc1SpecMorph; vr.amount = 0.6;
            g.routes.insert(g.routes.begin(), vr);                           // row 01: VELOCITY -> OSC A MORPH, on the visible page
            NSString* gs = [NSString stringWithUTF8String:g.serialize().c_str()];
            CFStringRef gcf = (__bridge CFStringRef)gs;
            const bool set = AudioUnitSetProperty(gUnit, kMUEWProperty_PresetState, kAudioUnitScope_Global, 0, &gcf, sizeof(gcf)) == noErr;
            AudioUnitSetParameter(gUnit, muew::params::Macro2, kAudioUnitScope_Global, 0, 0.0f, 0);
            typedef void (*SyncFn)(id, SEL, BOOL);
            SEL sync = NSSelectorFromString(@"syncFromAU:");
            if ([view respondsToSelector:sync]) ((SyncFn)[view methodForSelector:sync])(view, sync, YES);
            NSNumber* keptPage = [view valueForKey:@"matrixPage"];
            [view setValue:@0 forKey:@"matrixPage"];                          // matrix page 1-4, where row 01 sits
            NSNumber* keptFx = [view valueForKey:@"fxDetail"];
            [view setValue:@(-1) forKey:@"fxDetail"];                         // close the FX detail panel so the matrix shows
            SEL closeEd = NSSelectorFromString(@"muewCloseTableEditor");
            if ([view respondsToSelector:closeEd]) ((void (*)(id, SEL))[view methodForSelector:closeEd])(view, closeEd);
            MusicDeviceMIDIEvent(gUnit, 0x90, 48, 32, 0); MusicDeviceMIDIEvent(gUnit, 0x90, 55, 70, 0); MusicDeviceMIDIEvent(gUnit, 0x90, 60, 121, 0);
            for (int i = 0; i < 6; ++i) RenderBlock();
            SEL follow = NSSelectorFromString(@"muewFollowPerformance");
            if ([view respondsToSelector:follow]) ((void (*)(id, SEL))[view methodForSelector:follow])(view, follow);
            [view display];
            MUEWPerformance pf{}; UInt32 sz = sizeof(pf);
            const bool got = AudioUnitGetProperty(gUnit, kMUEWProperty_Performance, kAudioUnitScope_Global, 0, &pf, &sz) == noErr;
            NSString* lt = [view respondsToSelector:NSSelectorFromString(@"muewLiveMorphText")] ? [view valueForKey:@"muewLiveMorphText"] : @"";
            const std::string live = lt.UTF8String ?: "";
            Snapshot(view, "MUEW_MORPHMAIN_PNG", "morph-everywhere main display snapshot written");
            printf("morph36: %s; engine A %u voices %.3f %.3f %.3f, B %u voices %.3f\n", live.c_str(), pf.voiceMorphCount[0], pf.voiceMorph[0][0], pf.voiceMorph[0][1], pf.voiceMorph[0][2],
                   pf.voiceMorphCount[1], pf.voiceMorph[1][0]);
            const float ea = 0.2f + 0.6f * 121 / 127.0f, eb = 0.2f + 0.6f * 70 / 127.0f, ec = 0.2f + 0.6f * 32 / 127.0f;
            Check(kept && set, "the AU accepts a two-oscillator sound with two full 64-frame tables through the preset state (0.36.0 fix1: over 1 MB worst-case UTF-8)");
            Check(got && pf.voiceMorphCount[0] == 3 && std::fabs(pf.voiceMorph[0][0] - ea) < 0.02f && std::fabs(pf.voiceMorph[0][1] - eb) < 0.02f && std::fabs(pf.voiceMorph[0][2] - ec) < 0.02f,
                  "the engine reports OSC A's three voices at their velocity-spread morphs, highest first");
            Check(got && pf.voiceMorphCount[1] == 3 && std::fabs(pf.specMorph[1] - 0.45f) < 0.01f, "the engine meters OSC B at 45% on its three voices");
            Check(live.find("voices=3/3") != std::string::npos && live.find("shown=0.77/0.45") != std::string::npos, "the editor shows 77% on OSC A and 45% on OSC B");
            Check(live.find("ghosts=A:0.53,0.35 B:") != std::string::npos && live.find("B:") + 2 == live.size(), "OSC A draws two ghost voices; OSC B, with every voice alike, none");
            // SPEC page: ghosts on the preview and MORPH row, then SNAP A captures this state for the compare.
            SEL openEd = NSSelectorFromString(@"muewOpenTableEditorA");
            if ([view respondsToSelector:openEd]) ((void (*)(id, SEL))[view methodForSelector:openEd])(view, openEd);
            CGFloat t = view.bounds.size.height - 100;
            Click(view, w, NSMakePoint(258 + 3 * 35 + 16, t - 32 + 8.5));      // SPEC tab
            Click(view, w, NSMakePoint(40 + 8 + 196 - 42 + 18, t - 184 + 138 - 8 - 16 + 6)); // SNAP A
            [view display];
            Snapshot(view, "MUEW_MORPHSNAP_PNG", "SPEC ghosts + SNAP snapshot written");
            AudioUnitSetParameter(gUnit, muew::params::SpecMorphA, kAudioUnitScope_Global, 0, 60.0f, 0); // move the amount after the snapshot
            if ([view respondsToSelector:sync]) ((SyncFn)[view methodForSelector:sync])(view, sync, YES);
            Click(view, w, NSMakePoint(134 + 7, t - 32 + 8.5));             // A
            NSString* ma = [view respondsToSelector:NSSelectorFromString(@"muewMorphText")] ? [view valueForKey:@"muewMorphText"] : @"";
            Click(view, w, NSMakePoint(149 + 7, t - 32 + 8.5));             // B
            NSString* mb = [view respondsToSelector:NSSelectorFromString(@"muewMorphText")] ? [view valueForKey:@"muewMorphText"] : @"";
            printf("snap36: A %s | B %s\n", ma.UTF8String ?: "", mb.UTF8String ?: "");
            Check(std::string(ma.UTF8String ?: "").find("cmp=A") != std::string::npos && std::string(ma.UTF8String ?: "").find("amount=0.20") != std::string::npos,
                  "after SNAP A, A plays the snapshot's 20% amount");
            Check(std::string(mb.UTF8String ?: "").find("cmp=B") != std::string::npos && std::string(mb.UTF8String ?: "").find("amount=0.60") != std::string::npos,
                  "B returns to the 60% edit made after the snapshot");
            MusicDeviceMIDIEvent(gUnit, 0x80, 48, 0, 0); MusicDeviceMIDIEvent(gUnit, 0x80, 55, 0, 0); MusicDeviceMIDIEvent(gUnit, 0x80, 60, 0, 0);
            for (int i = 0; i < 4; ++i) RenderBlock();
            if (kept) { // put the earlier sound back for the steps that follow
                NSString* ks = [NSString stringWithUTF8String:keep.serialize().c_str()];
                CFStringRef kcf = (__bridge CFStringRef)ks;
                AudioUnitSetProperty(gUnit, kMUEWProperty_PresetState, kAudioUnitScope_Global, 0, &kcf, sizeof(kcf));
                if ([view respondsToSelector:sync]) ((SyncFn)[view methodForSelector:sync])(view, sync, YES);
            }
            if (keptPage) [view setValue:keptPage forKey:@"matrixPage"];
            if (keptFx) [view setValue:keptFx forKey:@"fxDetail"];
            if ([view respondsToSelector:openEd]) ((void (*)(id, SEL))[view methodForSelector:openEd])(view, openEd);
            Click(view, w, NSMakePoint(258 + 2 * 35 + 16, t - 32 + 8.5));      // back to the 3D tab
            fflush(stdout);
        });
        After(6.99946, ^{ // 0.37.0: selected-frame spectral chips, host persistence, undo/redo
            CGFloat top = view.bounds.size.height - 100;
            Click(view, w, NSMakePoint(258 + 3 * 35 + 16, top - 32 + 8.5)); // SPEC tab
            muew::Preset before; bool ok0 = State(before);
            Check(ok0 && before.tables[0].size() > 32, "frame tools start with the 64-frame table");
            if (!ok0 || before.tables[0].size() <= 32) { fflush(stdout); return; }
            // Select the known bright imported frame, making FOCUS and BLUR measurable.
            SEL frameSel = NSSelectorFromString(@"selectTableFrame:");
            if ([view respondsToSelector:frameSel]) ((void (*)(id, SEL, int))[view methodForSelector:frameSel])(view, frameSel, 32);
            bool selected = State(before);
            const int frame = 32;
            Check(selected && std::fabs(before.voice.osc1WtPos - 32.0 / 63) < .001, "the editor selected frame 33 for spectral tools");
            // Click the same chips a person uses, not a private harness method.
            Click(view, w, NSMakePoint(40 + 8 + 4 + 22, top - 184 + 8 + 43 + 7));      // FOCUS
            Click(view, w, NSMakePoint(40 + 8 + 4 + 47 + 22, top - 184 + 8 + 43 + 7)); // BLUR
            muew::Preset changed; bool ok1 = State(changed);
            SEL histSel = NSSelectorFromString(@"muewHistoryText");
            NSString* history = [view respondsToSelector:histSel] ? [view valueForKey:@"muewHistoryText"] : @"";
            printf("frame37: frame %d, %s\n", frame + 1, history.UTF8String ?: "");
            bool neighbours = ok1 && changed.tables[0].size() == before.tables[0].size();
            if (neighbours) for (int i = 0; i < (int)changed.tables[0].size(); ++i)
                if (i != frame) neighbours &= changed.tables[0][i] == before.tables[0][i];
            Check(neighbours && changed.tables[0][frame] != before.tables[0][frame], "FOCUS and BLUR modify one frame, leaving the rest byte-identical in the AU");
            Check(std::string(history.UTF8String ?: "").find("last=BLUR") != std::string::npos, "frame tools are labelled undo steps");
            Snapshot(view, "MUEW_FRAME37_PNG", "selected-frame spectral chips snapshot written");
            Click(view, w, NSMakePoint(224 + 7.5, top - 32 + 8.5)); // undo BLUR
            muew::Preset once; bool ok2 = State(once);
            Check(ok2 && once.tables[0][frame] == muew::spectralFrameTool(before.tables[0][frame], muew::FrameTool::Focus), "UNDO restores the earlier FOCUS frame");
            Click(view, w, NSMakePoint(224 + 7.5, top - 32 + 8.5)); // undo FOCUS
            muew::Preset again; bool ok3 = State(again);
            Check(ok3 && again.tables[0] == before.tables[0], "second UNDO restores the original table");
            Click(view, w, NSMakePoint(224 + 18 + 7.5, top - 32 + 8.5));
            Click(view, w, NSMakePoint(224 + 18 + 7.5, top - 32 + 8.5));
            muew::Preset redone; bool ok4 = State(redone);
            Check(ok4 && redone.tables[0] == changed.tables[0], "two REDO steps restore the edited table");
            // Restore the earlier sound and 3D page so older harness steps retain their preconditions.
            NSString* text = [NSString stringWithUTF8String:before.serialize().c_str()];
            CFStringRef cf = (__bridge CFStringRef)text;
            AudioUnitSetProperty(gUnit, kMUEWProperty_PresetState, kAudioUnitScope_Global, 0, &cf, sizeof(cf));
            SEL sync = NSSelectorFromString(@"syncFromAU:");
            if ([view respondsToSelector:sync]) ((void (*)(id, SEL, BOOL))[view methodForSelector:sync])(view, sync, YES);
            Click(view, w, NSMakePoint(258 + 2 * 35 + 16, top - 32 + 8.5));
            fflush(stdout);
        });
        After(6.99947, ^{ // 0.38.0: shift-select a frame range, apply FOCUS once, undo/redo as one batch
            CGFloat top = view.bounds.size.height - 100;
            muew::Preset before; bool ok0 = State(before);
            Check(ok0 && before.tables[0].size() == 64, "range tools begin with the 64-frame AU sound");
            if (!ok0 || before.tables[0].size() != 64) { fflush(stdout); return; }
            Click(view, w, NSMakePoint(258 + 3 * 35 + 16, top - 32 + 8.5)); // SPEC
            NSPoint a = NSMakePoint(40 + 3 * 25.5 + 11, top - 220 + 14);
            NSPoint b = NSMakePoint(40 + 9 * 25.5 + 11, top - 220 + 14);
            Click(view, w, a); // anchor frame 14
            [view mouseDown:[NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:b modifierFlags:NSEventModifierFlagShift
                timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:w.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1]];
            [view mouseUp:[NSEvent mouseEventWithType:NSEventTypeLeftMouseUp location:b modifierFlags:NSEventModifierFlagShift
                timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:w.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1]];
            muew::Preset selected; bool ok1 = State(selected);
            NSString* range = [view respondsToSelector:NSSelectorFromString(@"muewRangeText")] ? [view valueForKey:@"muewRangeText"] : @"";
            printf("range38: %s\n", range.UTF8String ?: "");
            Check(ok1 && std::string(range.UTF8String ?: "").find("14-39") != std::string::npos, "shift-click selected frames 14 through 39");
            Snapshot(view, "MUEW_RANGE38_PNG", "range highlight snapshot written");
            Click(view, w, NSMakePoint(40 + 8 + 4 + 22, top - 184 + 8 + 43 + 7)); // FOCUS on the range
            muew::Preset changed; bool ok2 = State(changed);
            NSString* hist = [view respondsToSelector:NSSelectorFromString(@"muewHistoryText")] ? [view valueForKey:@"muewHistoryText"] : @"";
            const int first = (int)std::lround(3 * 63.0 / 15), last = (int)std::lround(9 * 63.0 / 15);
            bool exact = ok2 && changed.tables[0].size() == selected.tables[0].size();
            int modified = 0;
            if (exact) for (int i = 0; i < 64; ++i) {
                const auto& orig = selected.tables[0][i];
                const auto want = i >= first && i <= last ? muew::spectralFrameTool(orig, muew::FrameTool::Focus) : orig;
                exact &= changed.tables[0][i] == want;
                modified += changed.tables[0][i] != orig;
            }
            Check(exact && modified > 2, "FOCUS processes precisely the inclusive range, leaving outside frames intact");
            Check(std::string(hist.UTF8String ?: "").find("last=FOCUS RANGE") != std::string::npos, "the batch creates one labelled undo step");
            Click(view, w, NSMakePoint(224 + 7.5, top - 32 + 8.5));
            muew::Preset undone; bool ok3 = State(undone);
            Check(ok3 && undone.tables[0] == selected.tables[0], "one UNDO restores all selected frames");
            Click(view, w, NSMakePoint(224 + 18 + 7.5, top - 32 + 8.5));
            muew::Preset redone; bool ok4 = State(redone);
            Check(ok4 && redone.tables[0] == changed.tables[0], "one REDO reapplies the entire range");
            NSString* text = [NSString stringWithUTF8String:before.serialize().c_str()];
            CFStringRef cf = (__bridge CFStringRef)text;
            AudioUnitSetProperty(gUnit, kMUEWProperty_PresetState, kAudioUnitScope_Global, 0, &cf, sizeof(cf));
            SEL sync = NSSelectorFromString(@"syncFromAU:");
            if ([view respondsToSelector:sync]) ((void (*)(id, SEL, BOOL))[view methodForSelector:sync])(view, sync, YES);
            Click(view, w, a); // clear range via ordinary click
            Click(view, w, NSMakePoint(258 + 2 * 35 + 16, top - 32 + 8.5)); // 3D
            fflush(stdout);
        });
        After(6.99948, ^{ // 0.39.0: click a spectral partial and its gain, then undo/redo in the AU
            CGFloat top = view.bounds.size.height - 100;
            muew::Preset before; bool ok0 = State(before);
            Check(ok0 && before.tables[0].size() == 64, "partial editor begins with the 64-frame sound");
            if (!ok0 || before.tables[0].size() != 64) { fflush(stdout); return; }
            Click(view, w, NSMakePoint(258 + 3 * 35 + 16, top - 32 + 8.5)); // SPEC
            // Select frame 33, then partial 4 in the spectrum (32 equal bars).
            SEL frameSel = NSSelectorFromString(@"selectTableFrame:");
            if ([view respondsToSelector:frameSel]) ((void (*)(id, SEL, int))[view methodForSelector:frameSel])(view, frameSel, 32);
            muew::Preset selected; bool ok1 = State(selected);
            Click(view, w, NSMakePoint(40 + 8 + 4 + 3.5 * (188.0/32), top - 184 + 8 + 4 + 12));
            NSString* pt = [view respondsToSelector:NSSelectorFromString(@"muewPartialText")] ? [view valueForKey:@"muewPartialText"] : @"";
            printf("partial39: %s\n", pt.UTF8String ?: "");
            Check(std::string(pt.UTF8String ?: "").find("h=4") != std::string::npos, "clicking the spectrum selects harmonic four");
            Snapshot(view, "MUEW_PARTIAL39_PNG", "partial selection snapshot written");
            Click(view, w, NSMakePoint(40 + 8 + 196 - 51 + 24 + 11, top - 184 + 8 + 30 + 5.5)); // +3 dB
            muew::Preset changed; bool ok2 = State(changed);
            NSString* hist = [view respondsToSelector:NSSelectorFromString(@"muewHistoryText")] ? [view valueForKey:@"muewHistoryText"] : @"";
            bool exact = ok1 && ok2 && changed.tables[0].size() == selected.tables[0].size();
            if (exact) for (int i = 0; i < 64; ++i) {
                auto want = selected.tables[0][i];
                if (i == 32) muew::gainPartial(want, 4, 3);
                exact &= changed.tables[0][i] == want;
            }
            Check(exact && changed.tables[0][32] != selected.tables[0][32], "AU +3 dB changes only harmonic four of frame 33");
            Check(std::string(hist.UTF8String ?: "").find("last=PARTIAL") != std::string::npos, "one partial click makes a labelled undo step");
            Click(view, w, NSMakePoint(224 + 7.5, top - 32 + 8.5));
            muew::Preset undone; bool ok3 = State(undone);
            Check(ok3 && undone.tables[0] == selected.tables[0], "UNDO restores the entire pre-edit table");
            Click(view, w, NSMakePoint(224 + 18 + 7.5, top - 32 + 8.5));
            muew::Preset redone; bool ok4 = State(redone);
            Check(ok4 && redone.tables[0] == changed.tables[0], "REDO reapplies the partial edit");
            NSString* text = [NSString stringWithUTF8String:before.serialize().c_str()];
            CFStringRef cf = (__bridge CFStringRef)text;
            AudioUnitSetProperty(gUnit, kMUEWProperty_PresetState, kAudioUnitScope_Global, 0, &cf, sizeof(cf));
            SEL sync = NSSelectorFromString(@"syncFromAU:");
            if ([view respondsToSelector:sync]) ((void (*)(id, SEL, BOOL))[view methodForSelector:sync])(view, sync, YES);
            Click(view, w, NSMakePoint(258 + 2 * 35 + 16, top - 32 + 8.5)); // 3D for older harness steps
            fflush(stdout);
        });
        After(6.99949, ^{ // 0.40.0: expanded spectrum, high partial, controlled CREATE and undo
            CGFloat top = view.bounds.size.height - 100;
            muew::Preset before; bool ok0 = State(before);
            Check(ok0 && before.tables[0].size() == 64, "expanded spectrum starts from the 64-frame sound");
            if (!ok0 || before.tables[0].size() != 64) { fflush(stdout); return; }
            Click(view, w, NSMakePoint(258 + 3 * 35 + 16, top - 32 + 8.5)); // SPEC
            SEL frameSel = NSSelectorFromString(@"selectTableFrame:");
            if ([view respondsToSelector:frameSel]) ((void (*)(id, SEL, int))[view methodForSelector:frameSel])(view, frameSel, 32);
            Click(view, w, NSMakePoint(40 + 8 + 124 + 10, top - 184 + 8 + 30 + 5.5)); // expand
            Click(view, w, NSMakePoint(40 + 8 + 4 + 3 * 48 + 22, top - 184 + 8 + 43 + 7)); // page 97-127
            NSString* viewText = [view respondsToSelector:NSSelectorFromString(@"muewPartialText")] ? [view valueForKey:@"muewPartialText"] : @"";
            printf("partial40: %s\n", viewText.UTF8String ?: "");
            Check(std::string(viewText.UTF8String ?: "").find("h=97") != std::string::npos &&
                  std::string(viewText.UTF8String ?: "").find("large=1") != std::string::npos, "expanded view navigates to page 97-127");
            Click(view, w, NSMakePoint(40 + 8 + 4 + 30.5 * (188.0/32), top - 184 + 8 + 63 + 25)); // harmonic 127
            NSString* selected = [view respondsToSelector:NSSelectorFromString(@"muewPartialText")] ? [view valueForKey:@"muewPartialText"] : @"";
            Check(std::string(selected.UTF8String ?: "").find("h=127") != std::string::npos, "last bin selects harmonic 127");
            Snapshot(view, "MUEW_PARTIAL40_PNG", "expanded 127-harmonic view snapshot written");
            muew::Preset prior; bool ok1 = State(prior);
            // The imported test frame may contain tiny high-frequency energy. Use a deterministic
            // sine frame so CREATE has a known silent partial without changing the factory bank.
            if (ok1) {
                prior.tables[0][32] = muew::shapeFrame(0);
                NSString* text = [NSString stringWithUTF8String:prior.serialize().c_str()];
                CFStringRef cf = (__bridge CFStringRef)text;
                AudioUnitSetProperty(gUnit, kMUEWProperty_PresetState, kAudioUnitScope_Global, 0, &cf, sizeof(cf));
                SEL sync = NSSelectorFromString(@"syncFromAU:");
                if ([view respondsToSelector:sync]) ((void (*)(id, SEL, BOOL))[view methodForSelector:sync])(view, sync, YES);
            }
            Click(view, w, NSMakePoint(40 + 8 + 75 + 23, top - 184 + 8 + 30 + 5.5)); // explicit CREATE
            muew::Preset created; bool ok2 = State(created);
            bool exact = ok1 && ok2 && created.tables[0].size() == prior.tables[0].size();
            if (exact) for (int i = 0; i < 64; ++i) {
                auto want = prior.tables[0][i];
                if (i == 32) muew::seedPartial(want, 127);
                exact &= created.tables[0][i] == want;
            }
            Check(exact && created.tables[0][32] != prior.tables[0][32], "CREATE seeds only H127 of frame 33 at -24 dB");
            Click(view, w, NSMakePoint(224 + 7.5, top - 32 + 8.5));
            muew::Preset undone; bool ok3 = State(undone);
            Check(ok3 && undone.tables[0] == prior.tables[0], "UNDO removes created partial");
            Click(view, w, NSMakePoint(224 + 18 + 7.5, top - 32 + 8.5));
            muew::Preset redone; bool ok4 = State(redone);
            Check(ok4 && redone.tables[0] == created.tables[0], "REDO restores created partial");
            NSString* resetText = [NSString stringWithUTF8String:before.serialize().c_str()];
            CFStringRef reset = (__bridge CFStringRef)resetText;
            AudioUnitSetProperty(gUnit, kMUEWProperty_PresetState, kAudioUnitScope_Global, 0, &reset, sizeof(reset));
            SEL sync = NSSelectorFromString(@"syncFromAU:");
            if ([view respondsToSelector:sync]) ((void (*)(id, SEL, BOOL))[view methodForSelector:sync])(view, sync, YES);
            Click(view, w, NSMakePoint(40 + 8 + 124 + 10, top - 184 + 8 + 30 + 5.5)); // collapse
            Click(view, w, NSMakePoint(258 + 2 * 35 + 16, top - 32 + 8.5)); // 3D
            fflush(stdout);
        });
        After(6.999495, ^{ // 0.41.0: Option-drag H4 to H8 over a selected frame range, one undo step
            CGFloat top = view.bounds.size.height - 100;
            muew::Preset before; bool ok0 = State(before);
            Check(ok0 && before.tables[0].size() == 64, "brush gesture starts with the 64-frame sound");
            if (!ok0 || before.tables[0].size() != 64) { fflush(stdout); return; }
            Click(view, w, NSMakePoint(258 + 3 * 35 + 16, top - 32 + 8.5)); // SPEC
            Click(view, w, NSMakePoint(40 + 8 + 124 + 10, top - 184 + 8 + 30 + 5.5)); // expand
            Click(view, w, NSMakePoint(40 + 8 + 4 + 22, top - 184 + 8 + 43 + 7)); // page 1-32
            NSString* pageText = [view respondsToSelector:NSSelectorFromString(@"muewPartialText")] ? [view valueForKey:@"muewPartialText"] : @"";
            Check(std::string(pageText.UTF8String ?: "").find("page=0 large=1") != std::string::npos,
                  "brush starts on expanded harmonic page 1-32");
            NSPoint a = NSMakePoint(40 + 3 * 25.5 + 11, top - 220 + 14);
            NSPoint b = NSMakePoint(40 + 9 * 25.5 + 11, top - 220 + 14);
            Click(view, w, a);
            auto event = [&](NSEventType kind, NSPoint p, NSEventModifierFlags flags) -> NSEvent* {
                return [NSEvent mouseEventWithType:kind location:p modifierFlags:flags
                    timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:w.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
            };
            [view mouseDown:event(NSEventTypeLeftMouseDown, b, NSEventModifierFlagShift)];
            [view mouseUp:event(NSEventTypeLeftMouseUp, b, NSEventModifierFlagShift)];
            muew::Preset selected; bool ok1 = State(selected);
            NSString* range = [view respondsToSelector:NSSelectorFromString(@"muewRangeText")] ? [view valueForKey:@"muewRangeText"] : @"";
            Check(ok1 && std::string(range.UTF8String ?: "").find("14-39") != std::string::npos, "brush range spans frames 14-39");
            const CGFloat bx = 40 + 8 + 4, by = top - 184 + 8 + 63;
            // Paint two harmonic positions. The brush interpolates H5-7 and replays from the baseline.
            NSPoint p0 = NSMakePoint(bx + 3.5 * 188.0 / 32, by + 12); // H4, around -36 dB
            NSPoint p1 = NSMakePoint(bx + 7.5 * 188.0 / 32, by + 24); // H8, around -23 dB
            [view mouseDown:event(NSEventTypeLeftMouseDown, p0, NSEventModifierFlagOption)];
            [view mouseDragged:event(NSEventTypeLeftMouseDragged, p1, NSEventModifierFlagOption)];
            NSString* brushed = [view respondsToSelector:NSSelectorFromString(@"muewPartialText")] ? [view valueForKey:@"muewPartialText"] : @"";
            Check(std::string(brushed.UTF8String ?: "").find("h=8") != std::string::npos,
                  "stroke reaches harmonic eight");
            Snapshot(view, "MUEW_BRUSH41_PNG", "brush before/after snapshot written");
            [view mouseUp:event(NSEventTypeLeftMouseUp, p1, NSEventModifierFlagOption)];
            muew::Preset changed; bool ok2 = State(changed);
            NSString* hist = [view respondsToSelector:NSSelectorFromString(@"muewHistoryText")] ? [view valueForKey:@"muewHistoryText"] : @"";
            bool outside = ok1 && ok2 && changed.tables[0].size() == selected.tables[0].size();
            int insideChanged = 0;
            if (outside) for (int i = 0; i < 64; ++i) {
                if (i < 13 || i > 38) outside &= changed.tables[0][i] == selected.tables[0][i];
                else insideChanged += changed.tables[0][i] != selected.tables[0][i];
            }
            Check(outside && insideChanged > 4, "brush changes multiple frames in range, none outside");
            Check(std::string(hist.UTF8String ?: "").find("last=BRUSH RANGE") != std::string::npos, "one gesture is one labelled history step");
            Click(view, w, NSMakePoint(224 + 7.5, top - 32 + 8.5));
            muew::Preset undone; bool ok3 = State(undone);
            Check(ok3 && undone.tables[0] == selected.tables[0], "one UNDO removes the whole brush stroke");
            Click(view, w, NSMakePoint(224 + 18 + 7.5, top - 32 + 8.5));
            muew::Preset redone; bool ok4 = State(redone);
            Check(ok4 && redone.tables[0] == changed.tables[0], "one REDO restores the whole brush stroke");
            NSString* resetText = [NSString stringWithUTF8String:before.serialize().c_str()];
            CFStringRef reset = (__bridge CFStringRef)resetText;
            AudioUnitSetProperty(gUnit, kMUEWProperty_PresetState, kAudioUnitScope_Global, 0, &reset, sizeof(reset));
            SEL sync = NSSelectorFromString(@"syncFromAU:");
            if ([view respondsToSelector:sync]) ((void (*)(id, SEL, BOOL))[view methodForSelector:sync])(view, sync, YES);
            Click(view, w, a); // clear range
            Click(view, w, NSMakePoint(40 + 8 + 124 + 10, top - 184 + 8 + 30 + 5.5)); // collapse
            Click(view, w, NSMakePoint(258 + 2 * 35 + 16, top - 32 + 8.5)); // 3D
            fflush(stdout);
        });
        After(6.999497, ^{ // 0.42.0: full edge falloff over frames 14-39, isolated and atomic
            CGFloat top = view.bounds.size.height - 100;
            muew::Preset before; bool ok0 = State(before);
            Check(ok0 && before.tables[0].size() == 64, "falloff begins with the 64-frame sound");
            if (!ok0 || before.tables[0].size() != 64) { fflush(stdout); return; }
            Click(view, w, NSMakePoint(258 + 3 * 35 + 16, top - 32 + 8.5)); // SPEC
            Click(view, w, NSMakePoint(40 + 8 + 124 + 10, top - 184 + 8 + 30 + 5.5)); // expand
            Click(view, w, NSMakePoint(40 + 8 + 4 + 22, top - 184 + 8 + 43 + 7)); // page 1-32
            NSPoint a = NSMakePoint(40 + 3 * 25.5 + 11, top - 220 + 14);
            NSPoint b = NSMakePoint(40 + 9 * 25.5 + 11, top - 220 + 14);
            Click(view, w, a);
            auto event = [&](NSEventType kind, NSPoint p, NSEventModifierFlags flags) -> NSEvent* {
                return [NSEvent mouseEventWithType:kind location:p modifierFlags:flags
                    timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:w.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
            };
            [view mouseDown:event(NSEventTypeLeftMouseDown, b, NSEventModifierFlagShift)];
            [view mouseUp:event(NSEventTypeLeftMouseUp, b, NSEventModifierFlagShift)];
            NSString* range = [view respondsToSelector:NSSelectorFromString(@"muewRangeText")] ? [view valueForKey:@"muewRangeText"] : @"";
            Check(std::string(range.UTF8String ?: "").find("14-39") != std::string::npos, "falloff range is frames 14-39");
            const NSPoint taper = NSMakePoint(40 + 72 + 74, top - 184 + 14 + 3);
            Click(view, w, taper); // EDGE 100%, no sound mutation
            NSString* edge = [view respondsToSelector:NSSelectorFromString(@"muewBrushTaperText")] ? [view valueForKey:@"muewBrushTaperText"] : @"";
            Check(std::string(edge.UTF8String ?: "").find("edge=1.00") != std::string::npos,
                  "EDGE control reaches 100 percent");
            muew::Preset baseline; bool ok1 = State(baseline);
            const CGFloat bx = 40 + 8 + 4, by = top - 184 + 8 + 63;
            NSPoint p0 = NSMakePoint(bx + 3.5 * 188.0 / 32, by + 12);
            NSPoint p1 = NSMakePoint(bx + 7.5 * 188.0 / 32, by + 24);
            [view mouseDown:event(NSEventTypeLeftMouseDown, p0, NSEventModifierFlagOption)];
            [view mouseDragged:event(NSEventTypeLeftMouseDragged, p1, NSEventModifierFlagOption)];
            Snapshot(view, "MUEW_TAPER42_PNG", "falloff strength preview snapshot written");
            [view mouseUp:event(NSEventTypeLeftMouseUp, p1, NSEventModifierFlagOption)];
            muew::Preset changed; bool ok2 = State(changed);
            bool exact = ok1 && ok2 && baseline.tables[0].size() == 64 && changed.tables[0].size() == 64;
            int middle = 0;
            if (exact) for (int i = 0; i < 64; ++i) {
                if (i < 13 || i > 38 || i == 13 || i == 38) exact &= changed.tables[0][i] == baseline.tables[0][i];
                if (i >= 20 && i <= 31) middle += changed.tables[0][i] != baseline.tables[0][i];
            }
            Check(exact && middle > 4, "falloff keeps outside and edges bit-identical, edits center");
            muew::PartialBrush expected; expected.line(4, -48 + std::round((12.0 / 40.0) * 60.0 * 2) / 2,
                                                       8, -48 + std::round((24.0 / 40.0) * 60.0 * 2) / 2);
            auto want = baseline.tables[0]; muew::FrameRange rr{13, 38};
            muew::applyBrushTable(want, rr, 38, expected, 1);
            Check(ok2 && want == changed.tables[0], "AU brush matches exact deterministic tapered range result");
            NSString* hist = [view respondsToSelector:NSSelectorFromString(@"muewHistoryText")] ? [view valueForKey:@"muewHistoryText"] : @"";
            Check(std::string(hist.UTF8String ?: "").find("last=BRUSH RANGE") != std::string::npos,
                  "tapered gesture is one undo step");
            Click(view, w, NSMakePoint(224 + 7.5, top - 32 + 8.5));
            muew::Preset undone; bool ok3 = State(undone);
            Check(ok3 && undone.tables[0] == baseline.tables[0], "one UNDO removes whole tapered stroke");
            Click(view, w, NSMakePoint(224 + 18 + 7.5, top - 32 + 8.5));
            muew::Preset redone; bool ok4 = State(redone);
            Check(ok4 && redone.tables[0] == changed.tables[0], "one REDO restores whole tapered stroke");
            NSString* resetText = [NSString stringWithUTF8String:before.serialize().c_str()];
            CFStringRef reset = (__bridge CFStringRef)resetText;
            AudioUnitSetProperty(gUnit, kMUEWProperty_PresetState, kAudioUnitScope_Global, 0, &reset, sizeof(reset));
            SEL sync = NSSelectorFromString(@"syncFromAU:");
            if ([view respondsToSelector:sync]) ((void (*)(id, SEL, BOOL))[view methodForSelector:sync])(view, sync, YES);
            Click(view, w, NSMakePoint(40 + 72, top - 184 + 14 + 3)); // reset EDGE to the uniform default for later tests
            Click(view, w, a); // clear range
            Click(view, w, NSMakePoint(40 + 8 + 124 + 10, top - 184 + 8 + 30 + 5.5)); // collapse
            Click(view, w, NSMakePoint(258 + 2 * 35 + 16, top - 32 + 8.5)); // 3D
            fflush(stdout);
        });
        After(6.999498, ^{ // 0.43.0 spectral profile copy, preview and blend to a tapered range
            CGFloat top = view.bounds.size.height - 100;
            muew::Preset before; bool ok0 = State(before);
            Check(ok0 && before.tables[0].size() == 64, "profile test begins with 64-frame sound");
            if (!ok0 || before.tables[0].size() != 64) { fflush(stdout); return; }
            muew::Preset setup = before;
            muew::gainPartial(setup.tables[0][0], 4, -18);
            muew::gainPartial(setup.tables[0][0], 8, 9);
            NSString* setupText = [NSString stringWithUTF8String:setup.serialize().c_str()];
            CFStringRef setupRef = (__bridge CFStringRef)setupText;
            AudioUnitSetProperty(gUnit, kMUEWProperty_PresetState, kAudioUnitScope_Global, 0, &setupRef, sizeof(setupRef));
            SEL sync = NSSelectorFromString(@"syncFromAU:");
            if ([view respondsToSelector:sync]) ((void (*)(id, SEL, BOOL))[view methodForSelector:sync])(view, sync, YES);
            Click(view, w, NSMakePoint(258 + 3 * 35 + 16, top - 32 + 8.5)); // SPEC
            Click(view, w, NSMakePoint(40 + 8 + 124 + 10, top - 184 + 8 + 30 + 5.5)); // expand
            Click(view, w, NSMakePoint(40 + 8 + 4 + 22, top - 184 + 8 + 43 + 7)); // page 1-32
            NSPoint source = NSMakePoint(40 + 11, top - 220 + 14);
            NSPoint a = NSMakePoint(40 + 3 * 25.5 + 11, top - 220 + 14);
            NSPoint b = NSMakePoint(40 + 9 * 25.5 + 11, top - 220 + 14);
            Click(view, w, source);
            Click(view, w, NSMakePoint(40 + 26, top - 278 + 7)); // COPY
            NSString* copied = [view respondsToSelector:NSSelectorFromString(@"muewProfileText")] ? [view valueForKey:@"muewProfileText"] : @"";
            Check(std::string(copied.UTF8String ?: "").find("valid=1 source=1") != std::string::npos,
                  "profile clipboard captured frame one");
            Click(view, w, a);
            auto event = [&](NSEventType kind, NSPoint p, NSEventModifierFlags flags) -> NSEvent* {
                return [NSEvent mouseEventWithType:kind location:p modifierFlags:flags
                    timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:w.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
            };
            [view mouseDown:event(NSEventTypeLeftMouseDown, b, NSEventModifierFlagShift)];
            [view mouseUp:event(NSEventTypeLeftMouseUp, b, NSEventModifierFlagShift)];
            NSString* range = [view respondsToSelector:NSSelectorFromString(@"muewRangeText")] ? [view valueForKey:@"muewRangeText"] : @"";
            Check(std::string(range.UTF8String ?: "").find("14-39") != std::string::npos, "profile range is 14-39");
            // Keep the selected range, but audition from an interior frame where EDGE strength is nonzero.
            SEL frameSel = NSSelectorFromString(@"selectTableFrame:");
            if ([view respondsToSelector:frameSel]) ((void (*)(id, SEL, int))[view methodForSelector:frameSel])(view, frameSel, 25);
            NSString* rangeAfter = [view respondsToSelector:NSSelectorFromString(@"muewRangeText")] ? [view valueForKey:@"muewRangeText"] : @"";
            Check(std::string(rangeAfter.UTF8String ?: "").find("14-39") != std::string::npos,
                  "preview frame 26 retains selected 14-39 range");
            Click(view, w, NSMakePoint(40 + 72 + 74, top - 184 + 14 + 3)); // EDGE 100%
            Click(view, w, NSMakePoint(310 + 50, top - 274 + 3)); // BLEND 50%
            Click(view, w, NSMakePoint(40 + 56 + 26, top - 278 + 7)); // PREVIEW
            NSString* preview = [view respondsToSelector:NSSelectorFromString(@"muewProfileText")] ? [view valueForKey:@"muewProfileText"] : @"";
            Check(std::string(preview.UTF8String ?: "").find("preview=1 create=0 blend=0.50") != std::string::npos,
                  "profile preview at half blend leaves silent-bin creation off");
            muew::Preset baseline; bool ok1 = State(baseline);
            Snapshot(view, "MUEW_CLIP43_PNG", "spectral profile preview snapshot written");
            muew::Preset still; bool okPreview = State(still);
            Check(ok1 && okPreview && still.tables[0] == baseline.tables[0], "preview leaves AU table untouched");
            muew::SpectralClipboard previewProfile; previewProfile.capture(setup.tables[0][0], 0);
            auto innerPreview = baseline.tables[0][25];
            Check(muew::applySpectralProfile(innerPreview, previewProfile, .5, false) &&
                  innerPreview != baseline.tables[0][25], "interior preview has a real, audible spectral difference");
            Click(view, w, NSMakePoint(40 + 2 * 56 + 26, top - 278 + 7)); // PASTE
            muew::Preset changed; bool ok2 = State(changed);
            muew::SpectralClipboard expected; expected.capture(setup.tables[0][0], 0);
            auto want = baseline.tables[0]; muew::FrameRange rr{13, 38};
            muew::applySpectralProfileTable(want, rr, 38, expected, .5, 1, false);
            Check(ok2 && changed.tables[0] == want && changed.tables[0][0] == baseline.tables[0][0] &&
                  changed.tables[0][13] == baseline.tables[0][13] && changed.tables[0][38] == baseline.tables[0][38] &&
                  changed.tables[0][25] != baseline.tables[0][25],
                  "AU profile paste matches exact tapered blend, preserving outside and edges");
            NSString* history = [view respondsToSelector:NSSelectorFromString(@"muewHistoryText")] ? [view valueForKey:@"muewHistoryText"] : @"";
            Check(std::string(history.UTF8String ?: "").find("last=PROFILE RANGE") != std::string::npos,
                  "profile paste records one labelled undo step");
            Click(view, w, NSMakePoint(224 + 7.5, top - 32 + 8.5));
            muew::Preset undone; bool ok3 = State(undone);
            Check(ok3 && undone.tables[0] == baseline.tables[0], "one UNDO removes the range paste");
            Click(view, w, NSMakePoint(224 + 18 + 7.5, top - 32 + 8.5));
            muew::Preset redone; bool ok4 = State(redone);
            Check(ok4 && redone.tables[0] == changed.tables[0], "one REDO restores the range paste");
            NSString* resetText = [NSString stringWithUTF8String:before.serialize().c_str()];
            CFStringRef reset = (__bridge CFStringRef)resetText;
            AudioUnitSetProperty(gUnit, kMUEWProperty_PresetState, kAudioUnitScope_Global, 0, &reset, sizeof(reset));
            if ([view respondsToSelector:sync]) ((void (*)(id, SEL, BOOL))[view methodForSelector:sync])(view, sync, YES);
            Click(view, w, NSMakePoint(40 + 72, top - 184 + 14 + 3)); // EDGE zero
            Click(view, w, a); // clear range
            Click(view, w, NSMakePoint(40 + 8 + 124 + 10, top - 184 + 8 + 30 + 5.5)); // collapse
            Click(view, w, NSMakePoint(258 + 2 * 35 + 16, top - 32 + 8.5)); // 3D
            fflush(stdout);
        });
        After(6.999499, ^{ // 0.44.0: copy spectrum, Shift-drag H4-H16, compare and range paste
            CGFloat top = view.bounds.size.height - 100;
            muew::Preset before; bool ok0 = State(before);
            Check(ok0 && before.tables[0].size() == 64, "profile-span test begins with 64-frame sound");
            if (!ok0 || before.tables[0].size() != 64) { fflush(stdout); return; }
            muew::Preset setup = before;
            muew::gainPartial(setup.tables[0][0], 4, -18);
            muew::gainPartial(setup.tables[0][0], 8, 9);
            NSString* setupText = [NSString stringWithUTF8String:setup.serialize().c_str()];
            CFStringRef setupRef = (__bridge CFStringRef)setupText;
            AudioUnitSetProperty(gUnit, kMUEWProperty_PresetState, kAudioUnitScope_Global, 0, &setupRef, sizeof(setupRef));
            SEL sync = NSSelectorFromString(@"syncFromAU:");
            if ([view respondsToSelector:sync]) ((void (*)(id, SEL, BOOL))[view methodForSelector:sync])(view, sync, YES);
            Click(view, w, NSMakePoint(258 + 3 * 35 + 16, top - 32 + 8.5)); // SPEC
            Click(view, w, NSMakePoint(40 + 8 + 124 + 10, top - 184 + 8 + 30 + 5.5)); // expand
            Click(view, w, NSMakePoint(40 + 8 + 4 + 22, top - 184 + 8 + 43 + 7)); // page 1-32
            Click(view, w, NSMakePoint(40 + 11, top - 220 + 14)); // source frame one
            Click(view, w, NSMakePoint(40 + 26, top - 278 + 7)); // COPY
            NSPoint a = NSMakePoint(40 + 3 * 25.5 + 11, top - 220 + 14);
            NSPoint b = NSMakePoint(40 + 9 * 25.5 + 11, top - 220 + 14);
            Click(view, w, a);
            auto event = [&](NSEventType kind, NSPoint p, NSEventModifierFlags flags) -> NSEvent* {
                return [NSEvent mouseEventWithType:kind location:p modifierFlags:flags
                    timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:w.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
            };
            [view mouseDown:event(NSEventTypeLeftMouseDown, b, NSEventModifierFlagShift)];
            [view mouseUp:event(NSEventTypeLeftMouseUp, b, NSEventModifierFlagShift)];
            SEL frameSel = NSSelectorFromString(@"selectTableFrame:");
            if ([view respondsToSelector:frameSel]) ((void (*)(id, SEL, int))[view methodForSelector:frameSel])(view, frameSel, 25);
            Click(view, w, NSMakePoint(40 + 72 + 74, top - 184 + 14 + 3)); // EDGE 100%
            Click(view, w, NSMakePoint(310 + 75, top - 274 + 3)); // BLEND 75%
            const CGFloat bx = 40 + 8 + 4, by = top - 184 + 8 + 63;
            NSPoint h4 = NSMakePoint(bx + 3.5 * 188.0 / 32, by + 12);
            NSPoint h16 = NSMakePoint(bx + 15.5 * 188.0 / 32, by + 12);
            [view mouseDown:event(NSEventTypeLeftMouseDown, h4, NSEventModifierFlagShift)];
            [view mouseDragged:event(NSEventTypeLeftMouseDragged, h16, NSEventModifierFlagShift)];
            [view mouseUp:event(NSEventTypeLeftMouseUp, h16, NSEventModifierFlagShift)];
            NSString* span = [view respondsToSelector:NSSelectorFromString(@"muewProfileText")] ? [view valueForKey:@"muewProfileText"] : @"";
            Check(std::string(span.UTF8String ?: "").find("span=4-16") != std::string::npos &&
                  std::string(span.UTF8String ?: "").find("blend=0.75") != std::string::npos,
                  "Shift-drag selects only H4-H16 at 75 percent blend");
            Click(view, w, NSMakePoint(40 + 56 + 26, top - 278 + 7)); // PREVIEW
            muew::Preset baseline; bool ok1 = State(baseline);
            Snapshot(view, "MUEW_SPAN44_PNG", "dual-spectrum selected-span preview snapshot written");
            muew::Preset afterPreview; bool okPreview = State(afterPreview);
            Check(ok1 && okPreview && afterPreview.tables[0] == baseline.tables[0], "span preview leaves AU sound unchanged");
            Click(view, w, NSMakePoint(40 + 2 * 56 + 26, top - 278 + 7)); // PASTE
            muew::Preset changed; bool ok2 = State(changed);
            muew::SpectralClipboard expected; expected.capture(setup.tables[0][0], 0); expected.span(4,16);
            auto want = baseline.tables[0]; muew::FrameRange rr{13,38};
            muew::applySpectralProfileTable(want, rr, 25, expected, .75, 1, false);
            Check(ok2 && want == changed.tables[0] && changed.tables[0][13] == baseline.tables[0][13] &&
                  changed.tables[0][38] == baseline.tables[0][38] && changed.tables[0][25] != baseline.tables[0][25],
                  "span paste exactly matches tapered range and preserves untouched edges");
            auto baseSpec = muew::frameSpectrum(baseline.tables[0][25]);
            auto editSpec = muew::frameSpectrum(changed.tables[0][25]);
            double scale = std::abs(editSpec[1])/std::abs(baseSpec[1]);
            bool otherBins = true;
            for (int h=1;h<=muew::kEditablePartials;++h) if(h<4||h>16)
                otherBins &= std::abs(editSpec[h]-baseSpec[h]*scale)<.003*std::max(1.0,std::abs(editSpec[h]));
            Check(otherBins, "all harmonics outside H4-H16 preserve relative levels and phases");
            NSString* history = [view respondsToSelector:NSSelectorFromString(@"muewHistoryText")] ? [view valueForKey:@"muewHistoryText"] : @"";
            Check(std::string(history.UTF8String ?: "").find("last=PROFILE RANGE") != std::string::npos, "span paste has one history step");
            Click(view, w, NSMakePoint(224 + 7.5, top - 32 + 8.5));
            muew::Preset undone; bool ok3 = State(undone);
            Check(ok3 && undone.tables[0] == baseline.tables[0], "one UNDO removes span paste");
            Click(view, w, NSMakePoint(224 + 18 + 7.5, top - 32 + 8.5));
            muew::Preset redone; bool ok4 = State(redone);
            Check(ok4 && redone.tables[0] == changed.tables[0], "one REDO restores span paste");
            NSString* resetText = [NSString stringWithUTF8String:before.serialize().c_str()];
            CFStringRef reset = (__bridge CFStringRef)resetText;
            AudioUnitSetProperty(gUnit, kMUEWProperty_PresetState, kAudioUnitScope_Global, 0, &reset, sizeof(reset));
            if ([view respondsToSelector:sync]) ((void (*)(id, SEL, BOOL))[view methodForSelector:sync])(view, sync, YES);
            Click(view, w, NSMakePoint(40 + 72, top - 184 + 14 + 3)); // EDGE zero
            Click(view, w, a); // clear range
            Click(view, w, NSMakePoint(40 + 8 + 124 + 10, top - 184 + 8 + 30 + 5.5)); // collapse
            Click(view, w, NSMakePoint(258 + 2 * 35 + 16, top - 32 + 8.5)); // 3D
            fflush(stdout);
        });
        After(6.9994997, ^{ // 0.47.0: carry selected span across page 1/page 2 seam
            CGFloat top = view.bounds.size.height - 100;
            muew::Preset before; bool ok0 = State(before);
            Check(ok0 && before.tables[0].size() == 64, "profile-span test begins with 64-frame sound");
            if (!ok0 || before.tables[0].size() != 64) { fflush(stdout); return; }
            muew::Preset setup = before;
            // Force clear high-bin levels on every frame. seedPartial only
            // fills truly silent bins; numerically nonzero FFT residue would
            // leave some source/destination spectra unfit for visual proof.
            for (int i = 0; i < (int)setup.tables[0].size(); ++i)
                for (int h = 28; h <= 38; ++h)
                    muew::setFrameHarmonic(setup.tables[0][i], h, .07 + (h % 4) * .01);
            muew::setFrameHarmonic(setup.tables[0][0], 29, .018);
            muew::setFrameHarmonic(setup.tables[0][0], 35, .24);
            NSString* setupText = [NSString stringWithUTF8String:setup.serialize().c_str()];
            CFStringRef setupRef = (__bridge CFStringRef)setupText;
            AudioUnitSetProperty(gUnit, kMUEWProperty_PresetState, kAudioUnitScope_Global, 0, &setupRef, sizeof(setupRef));
            SEL sync = NSSelectorFromString(@"syncFromAU:");
            if ([view respondsToSelector:sync]) ((void (*)(id, SEL, BOOL))[view methodForSelector:sync])(view, sync, YES);
            Click(view, w, NSMakePoint(258 + 3 * 35 + 16, top - 32 + 8.5)); // SPEC
            Click(view, w, NSMakePoint(40 + 8 + 124 + 10, top - 184 + 8 + 30 + 5.5)); // expand
            Click(view, w, NSMakePoint(40 + 8 + 4 + 22, top - 184 + 8 + 43 + 7)); // page 1-32
            Click(view, w, NSMakePoint(40 + 11, top - 220 + 14)); // source frame one
            Click(view, w, NSMakePoint(40 + 26, top - 278 + 7)); // COPY
            NSPoint a = NSMakePoint(40 + 3 * 25.5 + 11, top - 220 + 14);
            NSPoint b = NSMakePoint(40 + 9 * 25.5 + 11, top - 220 + 14);
            Click(view, w, a);
            auto event = [&](NSEventType kind, NSPoint p, NSEventModifierFlags flags) -> NSEvent* {
                return [NSEvent mouseEventWithType:kind location:p modifierFlags:flags
                    timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:w.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
            };
            [view mouseDown:event(NSEventTypeLeftMouseDown, b, NSEventModifierFlagShift)];
            [view mouseUp:event(NSEventTypeLeftMouseUp, b, NSEventModifierFlagShift)];
            SEL frameSel = NSSelectorFromString(@"selectTableFrame:");
            if ([view respondsToSelector:frameSel]) ((void (*)(id, SEL, int))[view methodForSelector:frameSel])(view, frameSel, 25);
            Click(view, w, NSMakePoint(40 + 72 + 74, top - 184 + 14 + 3)); // EDGE 100%
            Click(view, w, NSMakePoint(310 + 75, top - 274 + 3)); // BLEND 75%
            const CGFloat bx = 40 + 8 + 4, by = top - 184 + 8 + 63;
            NSPoint h28 = NSMakePoint(bx + 27.5 * 188.0 / 32, by + 12);
            NSPoint page2 = NSMakePoint(40 + 8 + 4 + 48 + 22, top - 184 + 8 + 43 + 7);
            NSPoint h38 = NSMakePoint(bx + 5.5 * 188.0 / 32, by + 12);
            [view mouseDown:event(NSEventTypeLeftMouseDown, h28, NSEventModifierFlagShift)];
            [view mouseDragged:event(NSEventTypeLeftMouseDragged, page2, NSEventModifierFlagShift)];
            NSString* crossing = [view respondsToSelector:NSSelectorFromString(@"muewProfileText")] ? [view valueForKey:@"muewProfileText"] : @"";
            Check(std::string(crossing.UTF8String ?: "").find("span=28-33") != std::string::npos,
                  "page chip carries anchored span to H33 across page boundary");
            NSString* pageText = [view respondsToSelector:NSSelectorFromString(@"muewPartialText")] ? [view valueForKey:@"muewPartialText"] : @"";
            Check(std::string(pageText.UTF8String ?: "").find("page=1 large=1") != std::string::npos,
                  "page 2 viewport follows drag handoff");
            [view mouseDragged:event(NSEventTypeLeftMouseDragged, h38, NSEventModifierFlagShift)];
            [view mouseUp:event(NSEventTypeLeftMouseUp, h38, NSEventModifierFlagShift)];
            NSString* span = [view respondsToSelector:NSSelectorFromString(@"muewProfileText")] ? [view valueForKey:@"muewProfileText"] : @"";
            Check(std::string(span.UTF8String ?: "").find("span=28-38") != std::string::npos &&
                  std::string(span.UTF8String ?: "").find("blend=0.75") != std::string::npos,
                  "Shift-drag selects H28-H38 across two pages at 75 percent blend");
            Click(view, w, NSMakePoint(40 + 56 + 26, top - 278 + 7)); // PREVIEW
            muew::Preset baseline; bool ok1 = State(baseline);
            Snapshot(view, "MUEW_PAGE47_PNG", "second-page segment preview snapshot written");
            muew::Preset afterPreview; bool okPreview = State(afterPreview);
            Check(ok1 && okPreview && afterPreview.tables[0] == baseline.tables[0], "span preview leaves AU sound unchanged");
            // Switch back to page one after preview: the absolute span must
            // survive navigation and show its first-page portion.
            Click(view, w, NSMakePoint(40 + 8 + 4 + 22, top - 184 + 8 + 43 + 7));
            NSString* stillSpan = [view respondsToSelector:NSSelectorFromString(@"muewProfileText")] ? [view valueForKey:@"muewProfileText"] : @"";
            Check(std::string(stillSpan.UTF8String ?: "").find("span=28-38") != std::string::npos,
                  "page switch retains full absolute span");
            Snapshot(view, "MUEW_PAGE47_FIRST_PNG", "first-page segment preview snapshot written");
            Click(view, w, NSMakePoint(40 + 2 * 56 + 26, top - 278 + 7)); // PASTE
            muew::Preset changed; bool ok2 = State(changed);
            muew::SpectralClipboard expected; expected.capture(setup.tables[0][0], 0); expected.span(28,38);
            auto want = baseline.tables[0]; muew::FrameRange rr{13,38};
            muew::applySpectralProfileTable(want, rr, 25, expected, .75, 1, false);
            const auto highBefore = muew::frameSpectrum(baseline.tables[0][25]);
            const auto highAfter = muew::frameSpectrum(changed.tables[0][25]);
            const double h35Before = std::abs(highBefore[35]/highBefore[1]);
            const double h35After = std::abs(highAfter[35]/highAfter[1]);
            Check(ok2 && h35Before > 0.005 && std::abs(h35After-h35Before) > 0.005,
                  "seeded H35 on page 2 is visible and changes on transfer");
            Check(ok2 && want == changed.tables[0] && changed.tables[0][13] == baseline.tables[0][13] &&
                  changed.tables[0][38] == baseline.tables[0][38] && changed.tables[0][25] != baseline.tables[0][25],
                  "page-spanning paste matches tapered range and preserves untouched edges");
            auto baseSpec = muew::frameSpectrum(baseline.tables[0][25]);
            auto editSpec = muew::frameSpectrum(changed.tables[0][25]);
            double scale = std::abs(editSpec[1])/std::abs(baseSpec[1]);
            bool otherBins = true;
            for (int h=1;h<=muew::kEditablePartials;++h) if(h<28||h>38)
                otherBins &= std::abs(editSpec[h]-baseSpec[h]*scale)<.003*std::max(1.0,std::abs(editSpec[h]));
            Check(otherBins, "all harmonics outside H28-H38 preserve relative levels and phases");
            NSString* history = [view respondsToSelector:NSSelectorFromString(@"muewHistoryText")] ? [view valueForKey:@"muewHistoryText"] : @"";
            Check(std::string(history.UTF8String ?: "").find("last=PROFILE RANGE") != std::string::npos, "page-spanning paste has one history step");
            Click(view, w, NSMakePoint(224 + 7.5, top - 32 + 8.5));
            muew::Preset undone; bool ok3 = State(undone);
            Check(ok3 && undone.tables[0] == baseline.tables[0], "one UNDO removes page-spanning paste");
            Click(view, w, NSMakePoint(224 + 18 + 7.5, top - 32 + 8.5));
            muew::Preset redone; bool ok4 = State(redone);
            Check(ok4 && redone.tables[0] == changed.tables[0], "one REDO restores page-spanning paste");
            NSString* resetText = [NSString stringWithUTF8String:before.serialize().c_str()];
            CFStringRef reset = (__bridge CFStringRef)resetText;
            AudioUnitSetProperty(gUnit, kMUEWProperty_PresetState, kAudioUnitScope_Global, 0, &reset, sizeof(reset));
            if ([view respondsToSelector:sync]) ((void (*)(id, SEL, BOOL))[view methodForSelector:sync])(view, sync, YES);
            Click(view, w, NSMakePoint(40 + 72, top - 184 + 14 + 3)); // EDGE zero
            Click(view, w, a); // clear range
            Click(view, w, NSMakePoint(40 + 8 + 124 + 10, top - 184 + 8 + 30 + 5.5)); // collapse
            Click(view, w, NSMakePoint(258 + 2 * 35 + 16, top - 32 + 8.5)); // 3D
            fflush(stdout);
        });
        After(6.9994995, ^{ // 0.45.0: feathered H4-H16 transfer, source/destination/proposal overlay
            CGFloat top = view.bounds.size.height - 100;
            muew::Preset before; bool ok0 = State(before);
            Check(ok0 && before.tables[0].size() == 64, "feathered span test begins with 64-frame sound");
            if (!ok0 || before.tables[0].size() != 64) { fflush(stdout); return; }
            muew::Preset setup = before;
            muew::gainPartial(setup.tables[0][0], 4, -18);
            muew::gainPartial(setup.tables[0][0], 8, 9);
            muew::gainPartial(setup.tables[0][0], 17, 12);
            NSString* setupText = [NSString stringWithUTF8String:setup.serialize().c_str()];
            CFStringRef setupRef = (__bridge CFStringRef)setupText;
            AudioUnitSetProperty(gUnit, kMUEWProperty_PresetState, kAudioUnitScope_Global, 0, &setupRef, sizeof(setupRef));
            SEL sync = NSSelectorFromString(@"syncFromAU:");
            if ([view respondsToSelector:sync]) ((void (*)(id, SEL, BOOL))[view methodForSelector:sync])(view, sync, YES);
            Click(view, w, NSMakePoint(258 + 3 * 35 + 16, top - 32 + 8.5)); // SPEC
            Click(view, w, NSMakePoint(40 + 8 + 124 + 10, top - 184 + 8 + 30 + 5.5)); // expand
            Click(view, w, NSMakePoint(40 + 8 + 4 + 22, top - 184 + 8 + 43 + 7)); // page 1-32
            Click(view, w, NSMakePoint(40 + 11, top - 220 + 14)); // source frame one
            Click(view, w, NSMakePoint(40 + 26, top - 278 + 7)); // COPY
            NSPoint a = NSMakePoint(40 + 3 * 25.5 + 11, top - 220 + 14);
            NSPoint b = NSMakePoint(40 + 9 * 25.5 + 11, top - 220 + 14);
            Click(view, w, a);
            auto event = [&](NSEventType kind, NSPoint p, NSEventModifierFlags flags) -> NSEvent* {
                return [NSEvent mouseEventWithType:kind location:p modifierFlags:flags
                    timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:w.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
            };
            [view mouseDown:event(NSEventTypeLeftMouseDown, b, NSEventModifierFlagShift)];
            [view mouseUp:event(NSEventTypeLeftMouseUp, b, NSEventModifierFlagShift)];
            SEL frameSel = NSSelectorFromString(@"selectTableFrame:");
            if ([view respondsToSelector:frameSel]) ((void (*)(id, SEL, int))[view methodForSelector:frameSel])(view, frameSel, 25);
            Click(view, w, NSMakePoint(40 + 72 + 74, top - 184 + 14 + 3)); // EDGE 100%
            Click(view, w, NSMakePoint(310 + 75, top - 274 + 3)); // BLEND 75%
            const CGFloat bx = 40 + 8 + 4, by = top - 184 + 8 + 63;
            NSPoint h4 = NSMakePoint(bx + 3.5 * 188.0 / 32, by + 12);
            NSPoint h16 = NSMakePoint(bx + 15.5 * 188.0 / 32, by + 12);
            [view mouseDown:event(NSEventTypeLeftMouseDown, h4, NSEventModifierFlagShift)];
            [view mouseDragged:event(NSEventTypeLeftMouseDragged, h16, NSEventModifierFlagShift)];
            [view mouseUp:event(NSEventTypeLeftMouseUp, h16, NSEventModifierFlagShift)];
            Click(view, w, NSMakePoint(310 + 37.5, top - 296 + 3)); // FEATHER 3 harmonics
            NSString* span = [view respondsToSelector:NSSelectorFromString(@"muewProfileText")] ? [view valueForKey:@"muewProfileText"] : @"";
            Check(std::string(span.UTF8String ?: "").find("span=4-16 feather=3") != std::string::npos,
                  "H4-H16 span has three-bin feather ramp");
            Click(view, w, NSMakePoint(40 + 56 + 26, top - 278 + 7)); // PREVIEW
            muew::Preset baseline; bool ok1 = State(baseline);
            Snapshot(view, "MUEW_FEATHER45_PNG", "feathered dual-spectrum preview snapshot written");
            muew::Preset afterPreview; bool okPreview = State(afterPreview);
            Check(ok1 && okPreview && afterPreview.tables[0] == baseline.tables[0], "feather preview leaves AU state untouched");
            Click(view, w, NSMakePoint(40 + 2 * 56 + 26, top - 278 + 7)); // PASTE
            muew::Preset changed; bool ok2 = State(changed);
            muew::SpectralClipboard expected; expected.capture(setup.tables[0][0], 0); expected.span(4,16);expected.feather=3;
            auto want = baseline.tables[0]; muew::FrameRange rr{13,38};
            muew::applySpectralProfileTable(want, rr, 25, expected, .75, 1, false);
            Check(ok2 && want == changed.tables[0] && changed.tables[0][13] == baseline.tables[0][13] &&
                  changed.tables[0][38] == baseline.tables[0][38] && changed.tables[0][25] != baseline.tables[0][25],
                  "feathered AU paste matches exact tapered range with untouched endpoints");
            const auto orig=muew::frameSpectrum(baseline.tables[0][25]), altered=muew::frameSpectrum(changed.tables[0][25]);
            const double scale=std::abs(altered[1])/std::abs(orig[1]);
            bool otherBins=true;for(int h=20;h<=muew::kEditablePartials;++h)
                otherBins &= std::abs(altered[h]-orig[h]*scale)<.003*std::max(1.0,std::abs(altered[h]));
            Check(otherBins, "outside feathered span, partial ratios and phases stay unchanged");
            NSString* history = [view respondsToSelector:NSSelectorFromString(@"muewHistoryText")] ? [view valueForKey:@"muewHistoryText"] : @"";
            Check(std::string(history.UTF8String ?: "").find("last=PROFILE RANGE") != std::string::npos,
                  "feathered range paste is one undo step");
            Click(view, w, NSMakePoint(224 + 7.5, top - 32 + 8.5));
            muew::Preset undone; bool ok3 = State(undone);
            Check(ok3 && undone.tables[0] == baseline.tables[0], "one UNDO removes feathered paste");
            Click(view, w, NSMakePoint(224 + 18 + 7.5, top - 32 + 8.5));
            muew::Preset redone; bool ok4 = State(redone);
            Check(ok4 && redone.tables[0] == changed.tables[0], "one REDO restores feathered paste");
            NSString* resetText = [NSString stringWithUTF8String:before.serialize().c_str()];
            CFStringRef reset = (__bridge CFStringRef)resetText;
            AudioUnitSetProperty(gUnit, kMUEWProperty_PresetState, kAudioUnitScope_Global, 0, &reset, sizeof(reset));
            if ([view respondsToSelector:sync]) ((void (*)(id, SEL, BOOL))[view methodForSelector:sync])(view, sync, YES);
            Click(view, w, NSMakePoint(40 + 72, top - 184 + 14 + 3)); // EDGE zero
            Click(view, w, a); // clear range
            Click(view, w, NSMakePoint(40 + 8 + 124 + 10, top - 184 + 8 + 30 + 5.5)); // collapse
            Click(view, w, NSMakePoint(258 + 2 * 35 + 16, top - 32 + 8.5)); // 3D
            fflush(stdout);
        });
        After(6.9994996, ^{ // 0.46.0: reverse the selected source span with preserved feather and range
            CGFloat top = view.bounds.size.height - 100;
            muew::Preset before; bool ok0 = State(before);
            Check(ok0 && before.tables[0].size() == 64, "feathered span test begins with 64-frame sound");
            if (!ok0 || before.tables[0].size() != 64) { fflush(stdout); return; }
            muew::Preset setup = before;
            muew::gainPartial(setup.tables[0][0], 4, -22);
            muew::gainPartial(setup.tables[0][0], 8, -8);
            muew::gainPartial(setup.tables[0][0], 16, 14);
            muew::gainPartial(setup.tables[0][0], 17, 12);
            NSString* setupText = [NSString stringWithUTF8String:setup.serialize().c_str()];
            CFStringRef setupRef = (__bridge CFStringRef)setupText;
            AudioUnitSetProperty(gUnit, kMUEWProperty_PresetState, kAudioUnitScope_Global, 0, &setupRef, sizeof(setupRef));
            SEL sync = NSSelectorFromString(@"syncFromAU:");
            if ([view respondsToSelector:sync]) ((void (*)(id, SEL, BOOL))[view methodForSelector:sync])(view, sync, YES);
            Click(view, w, NSMakePoint(258 + 3 * 35 + 16, top - 32 + 8.5)); // SPEC
            Click(view, w, NSMakePoint(40 + 8 + 124 + 10, top - 184 + 8 + 30 + 5.5)); // expand
            Click(view, w, NSMakePoint(40 + 8 + 4 + 22, top - 184 + 8 + 43 + 7)); // page 1-32
            Click(view, w, NSMakePoint(40 + 11, top - 220 + 14)); // source frame one
            Click(view, w, NSMakePoint(40 + 26, top - 278 + 7)); // COPY
            NSPoint a = NSMakePoint(40 + 3 * 25.5 + 11, top - 220 + 14);
            NSPoint b = NSMakePoint(40 + 9 * 25.5 + 11, top - 220 + 14);
            Click(view, w, a);
            auto event = [&](NSEventType kind, NSPoint p, NSEventModifierFlags flags) -> NSEvent* {
                return [NSEvent mouseEventWithType:kind location:p modifierFlags:flags
                    timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:w.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
            };
            [view mouseDown:event(NSEventTypeLeftMouseDown, b, NSEventModifierFlagShift)];
            [view mouseUp:event(NSEventTypeLeftMouseUp, b, NSEventModifierFlagShift)];
            SEL frameSel = NSSelectorFromString(@"selectTableFrame:");
            if ([view respondsToSelector:frameSel]) ((void (*)(id, SEL, int))[view methodForSelector:frameSel])(view, frameSel, 25);
            Click(view, w, NSMakePoint(40 + 72 + 74, top - 184 + 14 + 3)); // EDGE 100%
            Click(view, w, NSMakePoint(310 + 75, top - 274 + 3)); // BLEND 75%
            const CGFloat bx = 40 + 8 + 4, by = top - 184 + 8 + 63;
            NSPoint h4 = NSMakePoint(bx + 3.5 * 188.0 / 32, by + 12);
            NSPoint h16 = NSMakePoint(bx + 15.5 * 188.0 / 32, by + 12);
            [view mouseDown:event(NSEventTypeLeftMouseDown, h4, NSEventModifierFlagShift)];
            [view mouseDragged:event(NSEventTypeLeftMouseDragged, h16, NSEventModifierFlagShift)];
            [view mouseUp:event(NSEventTypeLeftMouseUp, h16, NSEventModifierFlagShift)];
            Click(view, w, NSMakePoint(310 + 37.5, top - 296 + 3)); // FEATHER 3 harmonics
            Click(view, w, NSMakePoint(40 + 34, top - 300 + 8)); // REVERSE
            NSString* span = [view respondsToSelector:NSSelectorFromString(@"muewProfileText")] ? [view valueForKey:@"muewProfileText"] : @"";
            Check(std::string(span.UTF8String ?: "").find("span=4-16 feather=3 reverse=1") != std::string::npos,
                  "REVERSE is armed for H4-H16 with three-bin feather");
            Click(view, w, NSMakePoint(40 + 56 + 26, top - 278 + 7)); // PREVIEW
            muew::Preset baseline; bool ok1 = State(baseline);
            Snapshot(view, "MUEW_REVERSE46_PNG", "reversed source-profile preview snapshot written");
            muew::Preset afterPreview; bool okPreview = State(afterPreview);
            Check(ok1 && okPreview && afterPreview.tables[0] == baseline.tables[0], "reverse preview leaves AU state untouched");
            Click(view, w, NSMakePoint(40 + 2 * 56 + 26, top - 278 + 7)); // PASTE
            muew::Preset changed; bool ok2 = State(changed);
            muew::SpectralClipboard expected; expected.capture(setup.tables[0][0], 0); expected.span(4,16);expected.feather=3; expected.reverse=true;
            auto want = baseline.tables[0]; muew::FrameRange rr{13,38};
            muew::applySpectralProfileTable(want, rr, 25, expected, .75, 1, false);
            Check(ok2 && want == changed.tables[0] && changed.tables[0][13] == baseline.tables[0][13] &&
                  changed.tables[0][38] == baseline.tables[0][38] && changed.tables[0][25] != baseline.tables[0][25],
                  "reversed AU paste matches exact tapered range with untouched endpoints");
            auto normal = baseline.tables[0]; muew::SpectralClipboard straight = expected;
            straight.reverse = false; muew::applySpectralProfileTable(normal, rr, 25, straight, .75, 1, false);
            const auto normSpec = muew::frameSpectrum(normal[25]);
            const auto revSpec = muew::frameSpectrum(changed.tables[0][25]);
            // The source may still slope downward after boosting H16: reversal's
            // direction follows its captured ratios, not an assumed brighter H4.
            const double sourceShift = expected.sourceRatio(4) - straight.sourceRatio(4);
            const double editedShift = std::abs(revSpec[4]/revSpec[1]) - std::abs(normSpec[4]/normSpec[1]);
            printf("reverse H4 source shift %.6f, normalized result shift %.6f\n", sourceShift, editedShift);
            Check(ok2 && normal[25] != changed.tables[0][25] &&
                std::abs(sourceShift) > 1e-6 && sourceShift * editedShift > 1e-9,
                "reverse H4 transfer follows reflected source ratio in the audible edited frame");
            const auto orig=muew::frameSpectrum(baseline.tables[0][25]), altered=muew::frameSpectrum(changed.tables[0][25]);
            const double scale=std::abs(altered[1])/std::abs(orig[1]);
            bool otherBins=true;for(int h=20;h<=muew::kEditablePartials;++h)
                otherBins &= std::abs(altered[h]-orig[h]*scale)<.003*std::max(1.0,std::abs(altered[h]));
            Check(otherBins, "reverse preserves partial ratios and phases beyond the feather");
            NSString* history = [view respondsToSelector:NSSelectorFromString(@"muewHistoryText")] ? [view valueForKey:@"muewHistoryText"] : @"";
            Check(std::string(history.UTF8String ?: "").find("last=PROFILE RANGE") != std::string::npos,
                  "reverse range paste is one undo step");
            Click(view, w, NSMakePoint(224 + 7.5, top - 32 + 8.5));
            muew::Preset undone; bool ok3 = State(undone);
            Check(ok3 && undone.tables[0] == baseline.tables[0], "one UNDO removes reverse paste");
            Click(view, w, NSMakePoint(224 + 18 + 7.5, top - 32 + 8.5));
            muew::Preset redone; bool ok4 = State(redone);
            Check(ok4 && redone.tables[0] == changed.tables[0], "one REDO restores reverse paste");
            NSString* resetText = [NSString stringWithUTF8String:before.serialize().c_str()];
            CFStringRef reset = (__bridge CFStringRef)resetText;
            AudioUnitSetProperty(gUnit, kMUEWProperty_PresetState, kAudioUnitScope_Global, 0, &reset, sizeof(reset));
            if ([view respondsToSelector:sync]) ((void (*)(id, SEL, BOOL))[view methodForSelector:sync])(view, sync, YES);
            Click(view, w, NSMakePoint(40 + 72, top - 184 + 14 + 3)); // EDGE zero
            Click(view, w, a); // clear range
            Click(view, w, NSMakePoint(40 + 8 + 124 + 10, top - 184 + 8 + 30 + 5.5)); // collapse
            Click(view, w, NSMakePoint(258 + 2 * 35 + 16, top - 32 + 8.5)); // 3D
            fflush(stdout);
        });
        After(6.9995, ^{ // 0.21.0 filter depth: step FILTER 1 to LADDER 24 with the model arrows, set DRIVE and KEYTRACK on their bars
            CGFloat t = view.bounds.size.height - 100;
            Click(view, w, NSMakePoint(492 + 30, t - 29 + 8.5));             // FILTER 1 tab
            muew::Preset st0;
            bool ok0 = State(st0);
            for (int i = 0; i < 9 && ok0 && st0.voice.filterMode != 5; ++i) {
                Click(view, w, NSMakePoint(676 + 94 - 8, t - 29 + 8.5));      // model right arrow
                ok0 = State(st0);
            }
            Check(ok0 && st0.voice.filterMode == 5, "the FILTER 1 model arrows reached LADDER 24 in the AU's sound");
            Click(view, w, NSMakePoint(676 + 8, t - 29 + 8.5));                // left arrow: back one model
            muew::Preset back1;
            bool ok1 = State(back1);
            Click(view, w, NSMakePoint(676 + 94 - 8, t - 29 + 8.5));          // right arrow: LADDER 24 again
            Check(ok1 && back1.voice.filterMode == 4, "the left arrow stepped the model back to PEAK");
            Click(view, w, NSMakePoint(494 + 0.45 * 88, t - 167 + 6.5));       // DRIVE bar at 45%
            Click(view, w, NSMakePoint(494 + 94 + 0.75 * 88, t - 167 + 6.5));  // KEYTRACK bar at 75%
            Snapshot(view, "MUEW_FILTER_PNG", "FILTER 1 panel snapshot written");
            muew::Preset st;
            bool ok = State(st);
            printf("filter 1: model %d, drive %.3f, keytrack %.3f, morph %.3f\n", st.voice.filterMode, st.voice.filterDrive, st.voice.filterKeytrack, st.voice.filterMorph);
            Check(ok && st.voice.filterMode == 5 && std::fabs(st.voice.filterDrive - 0.45) < 0.01 && std::fabs(st.voice.filterKeytrack - 0.75) < 0.01,
                  "the DRIVE and KEYTRACK bars set 45% / 75% on LADDER 24 in the AU");
            muew::Preset rt;
            std::string txt = ok ? st.serialize() : "";
            Check(ok && rt.parse(txt) && rt == st && txt.find("\nfilterx ") != std::string::npos && txt.find("\nfilterMode 5\n") != std::string::npos,
                  "the AU state saves the filter model, drive and keytrack");
            fflush(stdout);
        });
        After(6.9997, ^{ // 0.22.0 filter routing: FILTER 2 to LADDER 24 by clicking its display, PARALLEL, F2 MIX 60%, BALANCE 30%
            CGFloat t = view.bounds.size.height - 100;
            Click(view, w, NSMakePoint(556 + 46, t - 29 + 8.5));             // FILTER 2 + SUB tab
            muew::Preset st0;
            bool ok0 = State(st0);
            for (int i = 0; i < 9 && ok0 && st0.voice.filter2Type != 6; ++i) {
                Click(view, w, NSMakePoint(686 + 43, t - 138 + 55));           // the F2 display steps the type
                ok0 = State(st0);
            }
            Check(ok0 && st0.voice.filter2Type == 6, "clicking the FILTER 2 display reached LADDER 24 in the AU's sound");
            Click(view, w, NSMakePoint(686 + 5 + 39 + 18.5, t - 138 + 4 + 6.5)); // PAR
            Click(view, w, NSMakePoint(494 + 71 + 0.6 * 67, t - 167 + 6.5));      // F2 MIX bar at 60%
            Click(view, w, NSMakePoint(494 + 142 + 0.3 * 67, t - 167 + 6.5));     // BALANCE bar at 30%
            // 0.51.0 noise character and color on the same page, without touching NOISE TONE.
            muew::Preset beforeNoise; State(beforeNoise);
            for (int i = 0; i < 2; ++i) Click(view, w, NSMakePoint(666 + 25, t - 190 + 7)); // CLASSIC -> AIR -> GRAIN
            Click(view, w, NSMakePoint(666 + 37, t - 209 + 7)); // COLOR 74%
            muew::Preset noiseState; bool noiseOk = State(noiseState);
            Check(noiseOk && noiseState.voice.noiseCharacter == 2 && std::fabs(noiseState.voice.noiseColor - .74) < .02 &&
                  noiseState.voice.noiseTone == beforeNoise.voice.noiseTone &&
                  noiseState.serialize().find("\nnoisex 2 0.74\n") != std::string::npos,
                  "GRAIN/COLOR reached AU and left old NOISE TONE untouched");
            // 0.52.0 matrix route proof: read an LFO 1 -> NOISE COLOR state,
            // paint its matrix row and FILTER 2 control in the same hosted frame.
            muew::Preset routed=noiseState;
            muew::ModRoute colorRoute; colorRoute.source=muew::ModRoute::Source::LFO1;
            colorRoute.dest=muew::ModRoute::Dest::NoiseColor; colorRoute.amount=.65;
            if (routed.routes.empty()) routed.routes.push_back(colorRoute);
            else routed.routes[0]=colorRoute; // factory matrix may already occupy all 16 slots
            CFStringRef colorText=CFStringCreateWithCString(kCFAllocatorDefault,routed.serialize().c_str(),kCFStringEncodingUTF8);
            bool installed=colorText && AudioUnitSetProperty(gUnit,kMUEWProperty_PresetState,kAudioUnitScope_Global,0,&colorText,sizeof(colorText))==noErr;
            if(colorText) CFRelease(colorText);
            muew::Preset colorState; bool recalled=State(colorState);
            Check(installed && recalled && !colorState.routes.empty() && colorState.routes[0].dest==muew::ModRoute::Dest::NoiseColor &&
                  colorState.serialize().find("\nroute 0 32 0.65")!=std::string::npos,
                  "LFO 1 to NOISE COLOR route reached the AU and retained destination 32");
            SEL colorSync=NSSelectorFromString(@"syncFromAU:");
            if ([view respondsToSelector:colorSync]) ((void (*)(id, SEL, BOOL))[view methodForSelector:colorSync])(view,colorSync,YES);
            [view setValue:@0 forKey:@"matrixPage"];
            [view setValue:@(-1) forKey:@"fxDetail"];
            [view setValue:@(-1) forKey:@"msegEdit"];
            SEL closeColor=NSSelectorFromString(@"muewCloseTableEditor");
            if ([view respondsToSelector:closeColor]) ((void (*)(id, SEL))[view methodForSelector:closeColor])(view,closeColor);
            Snapshot(view, "MUEW_NOISE52_PNG", "NOISE COLOR matrix route snapshot written");
            Snapshot(view, "MUEW_NOISE51_PNG", "noise character panel snapshot written");
            Snapshot(view, "MUEW_FILTER2_PNG", "FILTER 2 routing panel snapshot written");
            muew::Preset st;
            bool ok = State(st);
            printf("filter 2: type %d, routing %d, f1 mix %.3f, f2 mix %.3f, balance %.3f\n", st.voice.filter2Type, st.voice.filterRouting,
                   st.voice.filter1Mix, st.voice.filter2Mix, st.voice.filterBalance);
            Check(ok && st.voice.filterRouting == 1 && std::fabs(st.voice.filter2Mix - 0.6) < 0.01 && std::fabs(st.voice.filterBalance - 0.3) < 0.01
                  && st.voice.filter1Mix == 1.0, "PAR, F2 MIX 60% and BALANCE 30% reached the AU");
            muew::Preset rt;
            std::string txt = ok ? st.serialize() : "";
            Check(ok && rt.parse(txt) && rt == st && txt.find("\nfilterr 1 0.6") != std::string::npos, "the AU state saves the filter routing");
            fflush(stdout);
        });
        After(6.9998, ^{ // 0.23.0 voice strip: LEGATO, 8 voices, GLIDE 500 ms (LEGATO glide), RANDOM phase, BLEND 40%
            CGFloat t = view.bounds.size.height - 100;
            Click(view, w, NSMakePoint(400 + 24, t - 32 + 8.5));   // DONE: the wavetable editor from the 3D step still covers the OSC panel
            muew::Preset before;
            bool ok0 = State(before);
            Click(view, w, NSMakePoint(231 + 30, t - 28 + 7.5));                          // voices > : 16 stays 16 (max)
            for (int i = 0; i < 8; ++i) Click(view, w, NSMakePoint(231 + 6, t - 28 + 7.5)); // voices < x8: 8
            Click(view, w, NSMakePoint(189 + 19, t - 28 + 7.5));               // LEGATO
            Click(view, w, NSMakePoint(271 + 0.5 * 78, t - 28 + 7.5));                  // GLIDE bar at 50% = 500 ms
            Click(view, w, NSMakePoint(352 + 13, t - 28 + 7.5));                        // glide ALL -> LEG
            Click(view, w, NSMakePoint(381 + 15, t - 28 + 7.5));                        // PHASE SPRD -> RAND
            Click(view, w, NSMakePoint(414 + 0.4 * 42, t - 28 + 7.5));                  // BLEND 40%
            // Add a unison stack on OSC A so the strip has something to act on in the shot.
            Click(view, w, NSMakePoint(46 + 6 + 4 * 13 + 6.5, t - 137 + 9));            // OSC A unison: 5 voices (so the strip acts on a stack)
            Snapshot(view, "MUEW_VOICE_PNG", "voice strip snapshot written");
            muew::Preset st;
            bool ok = State(st);
            AudioUnitParameterValue gv = -1, bv = -1;
            AudioUnitGetParameter(gUnit, muew::params::GlideTime, kAudioUnitScope_Global, 0, &gv);
            AudioUnitGetParameter(gUnit, muew::params::UnisonBlend, kAudioUnitScope_Global, 0, &bv);
            printf("voice: mode %d, voices %d, glide %.3f s (param %.3f), legato glide %d, phase %d, blend %.3f (param %.1f), unison A %d\n",
                   st.voice.voiceMode, st.voice.polyVoices, st.voice.glideTime, gv, st.voice.glideLegato ? 1 : 0, st.voice.uniPhase, st.voice.uniBlend, bv, st.voice.osc1Unison);
            Check(ok && st.voice.voiceMode == 2 && st.voice.polyVoices == 8 && std::fabs(st.voice.glideTime - 0.5) < 0.01 && st.voice.glideLegato
                  && st.voice.uniPhase == 1 && std::fabs(st.voice.uniBlend - 0.4) < 0.01 && st.voice.osc1Unison == 5,
                  "LEGATO, 8 voices, GLIDE 500 ms LEG, RAND phase and BLEND 40% reached the AU's sound");
            Check(std::fabs(gv - 0.5) < 0.01 && std::fabs(bv - 40) < 1, "Glide Time and Unison Blend AU parameters follow the strip");
            muew::Preset rt;
            std::string txt = ok ? st.serialize() : "";
            Check(ok && rt.parse(txt) && rt == st && txt.find("\nvoice 2 8 0.5") != std::string::npos, "the AU state saves the voice settings");
            // Back to POLY 16, no glide, SPRD and the original BLEND / unison so later steps hear the sound as before.
            Click(view, w, NSMakePoint(133 + 13, t - 28 + 7.5));
            for (int i = 0; i < 8; ++i) Click(view, w, NSMakePoint(231 + 32, t - 28 + 7.5));
            Click(view, w, NSMakePoint(271 + 0.5, t - 28 + 7.5));
            Click(view, w, NSMakePoint(352 + 13, t - 28 + 7.5));
            Click(view, w, NSMakePoint(381 + 15, t - 28 + 7.5));
            Click(view, w, NSMakePoint(414 + before.voice.uniBlend * 42, t - 28 + 7.5));   // BLEND as it was
            Click(view, w, NSMakePoint(46 + 6 + (std::max(1, before.voice.osc1Unison) - 1) * 13 + 6.5, t - 137 + 9)); // OSC A unison as it was
            muew::Preset back;
            Check(ok0 && State(back) && back.voice.voiceMode == 0 && back.voice.polyVoices == 16 && back.voice.glideTime == 0 && !back.voice.glideLegato
                  && back.voice.uniPhase == 0 && std::fabs(back.voice.uniBlend - before.voice.uniBlend) < 0.01 && back.voice.osc1Unison == before.voice.osc1Unison
                  && back.serialize().find("\nvoice ") == std::string::npos,
                  "the strip returns to the defaults and the voice line disappears");
            fflush(stdout);
        });
        __block bool perfRendered = false;
        After(7.02, ^{ // 0.24.0 MIDI performance: wheel, channel aftertouch, bend up and a held C4 with the pedal down
            MusicDeviceMIDIEvent(gUnit, 0xB0, 64, 127, 0);      // sustain down
            MusicDeviceMIDIEvent(gUnit, 0x90, 72, 100, 0);      // C4 (note 72)
            MusicDeviceMIDIEvent(gUnit, 0xB0, 1, 90, 0);        // mod wheel 90
            MusicDeviceMIDIEvent(gUnit, 0xD0, 70, 0, 0);        // channel aftertouch 70
            MusicDeviceMIDIEvent(gUnit, 0xE0, 0x00, 0x60, 0);   // bend 0x3000 of 0x3fff: +0.5
            MusicDeviceMIDIEvent(gUnit, 0x80, 72, 0, 0);        // key up: the pedal holds it
            perfRendered = RenderBlock() && RenderBlock();
            // Let the editor's 30 Hz timer read the performance property (timers fire inside this wait).
            for (int i = 0; i < 50 && PerfText(view).find("note=72") == std::string::npos; ++i)
                [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
            MUEWPerformance pf{}; UInt32 size = sizeof(pf);
            const bool got = AudioUnitGetProperty(gUnit, kMUEWProperty_Performance, kAudioUnitScope_Global, 0, &pf, &size) == noErr;
            printf("perf: AU wheel %.3f at %.3f bend %.3f note %d sustain %d\n", pf.wheel, pf.aftertouch, pf.bend, (int)pf.lastNote, (int)pf.sustain);
            Check(perfRendered && got && std::fabs(pf.wheel - 90 / 127.0f) < 0.01f && std::fabs(pf.aftertouch - 70 / 127.0f) < 0.01f
                  && std::fabs(pf.bend - 0.5f) < 0.01f && pf.lastNote == 72 && pf.sustain == 1,
                  "the AU reports wheel 90, aftertouch 70, bend +0.5, note 72 and the pedal from MIDI");
            // An LFO / MSEG editor or FX detail panel left open by earlier steps covers the matrix: close it (both share the close box).
            printf("perf: overlays before %s\n", PerfText(view).c_str());
            for (int i = 0; i < 2 && PerfText(view).find("overlay=-1/-1") == std::string::npos; ++i) Click(view, w, NSMakePoint(440, 231));
            Click(view, w, NSMakePoint(304 + 2 * 19 + 8.75, 180 + 7.5));                 // PB badge (third row)
            for (int i = 0; i < 10; ++i) Click(view, w, NSMakePoint(384 + 58, 180 + 7.5)); // BEND > x10: +-12
            std::string txt = PerfText(view);
            printf("perf: editor %s\n", txt.c_str());
            Check(txt.find("sel=PB wheel=0.709 at=0.551 bend=0.500 note=72 sustain=1 range=12 overlay=-1/-1") == 0,
                  "the editor shows the live wheel, aftertouch, bend, note and pedal with PB selected and BEND +-12");
            muew::Preset st;
            Check(State(st) && st.voice.bendRange == 12 && st.serialize().find("\nperf 12\n") != std::string::npos,
                  "BEND +-12 reached the AU and its saved state");
            Snapshot(view, "MUEW_PERF_PNG", "performance snapshot written");
            // Back to rest: range 2, controls centred, pedal up, notes off.
            for (int i = 0; i < 10; ++i) Click(view, w, NSMakePoint(384 + 4, 180 + 7.5));
            MusicDeviceMIDIEvent(gUnit, 0xB0, 1, 0, 0);
            MusicDeviceMIDIEvent(gUnit, 0xD0, 0, 0, 0);
            MusicDeviceMIDIEvent(gUnit, 0xE0, 0x00, 0x40, 0);
            MusicDeviceMIDIEvent(gUnit, 0xB0, 64, 0, 0);
            MusicDeviceMIDIEvent(gUnit, 0xB0, 123, 0, 0);
            RenderBlock();
            MUEWPerformance rest{}; size = sizeof(rest);
            muew::Preset st2;
            Check(AudioUnitGetProperty(gUnit, kMUEWProperty_Performance, kAudioUnitScope_Global, 0, &rest, &size) == noErr
                  && rest.wheel == 0 && rest.aftertouch == 0 && rest.bend == 0 && rest.sustain == 0
                  && State(st2) && st2.voice.bendRange == 2 && st2.serialize().find("\nperf ") == std::string::npos,
                  "controls return to rest and BEND +-2 drops the perf line");
            fflush(stdout);
        });
        After(7.04, ^{ // 0.25.0 ARP page: ARP ON, UP/DN, 2 octaves, LATCH, GATE 62%, SWING 62%; hold C E G and let go
            CGFloat t = view.bounds.size.height - 100;
            SEL arpSel = NSSelectorFromString(@"muewArpText");
            auto arpText = [&]() -> std::string { if (![view respondsToSelector:arpSel]) return ""; NSString* a = [view valueForKey:@"muewArpText"]; return a.UTF8String ?: ""; };
            Click(view, w, NSMakePoint(638 + 17, t - 29 + 8.5));          // ARP tab
            Click(view, w, NSMakePoint(492 + 22, t - 58 + 9));            // ARP ON
            Click(view, w, NSMakePoint(542 + 2 * 38 + 18, t - 58 + 9));   // UP/DN
            Click(view, w, NSMakePoint(492 + 74 - 6, t - 84 + 9));        // OCT > : 2
            Click(view, w, NSMakePoint(666 + 27, t - 84 + 9));            // LATCH
            Click(view, w, NSMakePoint(492 + 0.6 * 135, t - 108 + 8));    // GATE at 60% of the pill: 62%
            Click(view, w, NSMakePoint(633 + 0.5 * 135, t - 108 + 8));    // SWING at 50%: 0.25 (62%)
            muew::Preset st;
            const bool ok = State(st);
            AudioUnitParameterValue gv = -1, sv = -1;
            AudioUnitGetParameter(gUnit, muew::params::ArpGate, kAudioUnitScope_Global, 0, &gv);
            AudioUnitGetParameter(gUnit, muew::params::ArpSwing, kAudioUnitScope_Global, 0, &sv);
            printf("arp: on %d mode %d oct %d rate %d gate %.2f (param %.1f) swing %.2f (param %.1f) latch %d\n", st.voice.arpOn ? 1 : 0, st.voice.arpMode,
                   st.voice.arpOctaves, st.voice.arpRate, st.voice.arpGate, gv, st.voice.arpSwing, sv, st.voice.arpLatch ? 1 : 0);
            Check(ok && st.voice.arpOn && st.voice.arpMode == 2 && st.voice.arpOctaves == 2 && st.voice.arpRate == 3 && std::fabs(st.voice.arpGate - 0.62) < 1e-6
                  && std::fabs(st.voice.arpSwing - 0.25) < 1e-6 && st.voice.arpLatch && st.serialize().find("\narp 1 2 2 3 0.62 0.25 1\n") != std::string::npos,
                  "ARP ON, UP/DN, 2 OCT, LATCH, GATE 62% and SWING reached the AU's sound");
            Check(std::fabs(gv - 62) < 0.01 && std::fabs(sv - 25) < 0.01, "Arp Gate and Arp Swing AU parameters follow the page");
            // 0.26.0 step pattern + host sync: PATTERN on, LEN 16 -> 8, step 2 at half velocity,
            // step 3 REST (kind strip once), step 5 TIE (twice), HOST SYNC on (no transport here: free clock).
            {
                auto cellX = [](int i) { return 492 + (i + 0.5) * (276.0 / 16); };
                Click(view, w, NSMakePoint(492 + 31, t - 205 + 9));                        // PATTERN
                for (int i = 0; i < 8; ++i) Click(view, w, NSMakePoint(560 + 10, t - 205 + 9)); // LEN <
                Click(view, w, NSMakePoint(492 + (276.0 / 16) + 3, t - 246 + 11 + 0.5 * (37 - 14)));     // step 2 velocity 50%, left of chance hit zone
                Click(view, w, NSMakePoint(cellX(2), t - 246 + 4));                         // step 3 -> REST
                Click(view, w, NSMakePoint(cellX(4), t - 246 + 4));                         // step 5 -> REST
                Click(view, w, NSMakePoint(cellX(4), t - 246 + 4));                         //        -> TIE
                // 0.48.0 top badges: step 1 -> x3, step 2 -> x4. TIE/REST retain x1.
                for (int i = 0; i < 2; ++i) Click(view, w, NSMakePoint(cellX(0), t - 246 + 33));
                for (int i = 0; i < 3; ++i) Click(view, w, NSMakePoint(cellX(1), t - 246 + 33));
                // 0.49.0 lower badge: first ON -> +1, second ON -> -1. TIE has no octave change.
                Click(view, w, NSMakePoint(cellX(0), t - 246 + 14));
                Click(view, w, NSMakePoint(cellX(1), t - 246 + 14));
                Click(view, w, NSMakePoint(cellX(1), t - 246 + 14));
                // 0.50.0 center badges: step 1 -> 75%, step 2 -> 50%; LIVE remains off for fixed playback.
                Click(view, w, NSMakePoint(cellX(0), t - 246 + 23));
                Click(view, w, NSMakePoint(cellX(1), t - 246 + 23));
                Click(view, w, NSMakePoint(cellX(1), t - 246 + 23));
                Click(view, w, NSMakePoint(636 + 31, t - 205 + 9));                         // HOST SYNC
                muew::Preset ps;
                const bool okp = State(ps);
                const auto& pv = ps.voice;
                printf("arp pattern: sync %d on %d len %d vel2 %d kinds %d%d%d%d%d; editor %s\n", pv.clockSync ? 1 : 0, pv.arpPatOn ? 1 : 0, pv.arpPatLen, pv.arpPatVel[1],
                       pv.arpPatKind[0], pv.arpPatKind[1], pv.arpPatKind[2], pv.arpPatKind[3], pv.arpPatKind[4], arpText().c_str());
                Check(okp && pv.clockSync && pv.arpPatOn && pv.arpPatLen == 8 && pv.arpPatVel[1] == 64 && pv.arpPatKind[1] == 0 && pv.arpPatKind[2] == 1
                      && pv.arpPatKind[4] == 2 && pv.arpPatKind[3] == 0 && ps.serialize().find("\narpx 1 1 8 127 0 64 0 127 1 127 0 127 2 ") != std::string::npos,
                      "PATTERN, LEN, step velocity, REST, TIE and HOST SYNC reached the AU's sound");
                Check(arpText().find(" sync=1 locked=0 pat=1 len=8 ") != std::string::npos && arpText().find("steps=O127/x3/o+1,O64/x4/o-1,R127/x1/o+0,O127/x1/o+0,T127/x1/o+0,") != std::string::npos,
                      "the ARP page reports the pattern and ratchets; no transport = free clock");
                Check(okp && pv.arpPatRatchet[0] == 3 && pv.arpPatRatchet[1] == 4 && pv.arpPatRatchet[2] == 1 &&
                      ps.serialize().find("\narpr 3 4 1 1 1 ") != std::string::npos,
                      "step badges set x3/x4, REST keeps x1, and arpr state reaches AU");
                Check(okp && pv.arpPatOctave[0] == 1 && pv.arpPatOctave[1] == -1 && pv.arpPatOctave[4] == 0 &&
                      ps.serialize().find("\narpo 1 -1 0 0 0 ") != std::string::npos,
                      "lower badges set +1/-1 octave, TIE remains neutral, arpo reaches AU");
                Check(okp && pv.arpPatChance[0] == 75 && pv.arpPatChance[1] == 50 && pv.arpPatChance[4] == 100 &&
                      !pv.arpChanceLive && ps.serialize().find("\narpc 0 75 50 100 100 100 ") != std::string::npos &&
                      arpText().find("chanceLive=0 chances=75,50,100,100,100,") != std::string::npos,
                      "center badges set chance, TIE remains 100, arpc state reaches AU");
                Click(view, w, NSMakePoint(733 + 17, t - 205 + 9)); // LIVE opt-in
                muew::Preset liveState;
                Check(State(liveState) && liveState.voice.arpChanceLive &&
                      liveState.serialize().find("\narpc 1 75 50 100 100 100 ") != std::string::npos &&
                      arpText().find("chanceLive=1 chances=75,50,100,100,100,") != std::string::npos,
                      "LIVE opt-in changes the AU state without changing chance badges");
            }
            for (int k : {60, 64, 67}) MusicDeviceMIDIEvent(gUnit, 0x90, k, 100, 0);
            for (int k : {60, 64, 67}) MusicDeviceMIDIEvent(gUnit, 0x80, k, 0, 0);   // LATCH keeps them
            for (int i = 0; i < 40; ++i) RenderBlock();   // 20480 samples: 3-4 steps
            for (int i = 0; i < 50 && arpText().find("live=1 pool=60,64,67") == std::string::npos; ++i)
                [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
            // Stop between steps with a note sounding so the shot shows the playing step.
            for (int i = 0; i < 40; ++i) {
                MUEWPerformance pf{}; UInt32 size = sizeof(pf);
                AudioUnitGetProperty(gUnit, kMUEWProperty_Performance, kAudioUnitScope_Global, 0, &pf, &size);
                if (pf.arpNote >= 0 && pf.arpIndex >= 3) break;
                RenderBlock(256);
            }
            for (int i = 0; i < 10; ++i) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
            MUEWPerformance pf{}; UInt32 size = sizeof(pf);
            AudioUnitGetProperty(gUnit, kMUEWProperty_Performance, kAudioUnitScope_Global, 0, &pf, &size);
            const std::string txt = arpText();
            printf("arp: AU on %u pool %d step %d index %d note %d; editor %s\n", (unsigned)pf.arpOn, (int)pf.poolCount, (int)pf.arpStep, (int)pf.arpIndex, (int)pf.arpNote, txt.c_str());
            Check(pf.arpOn == 1 && pf.poolCount == 3 && pf.arpStep >= 3 && pf.arpNote >= 60 && txt.find("page=2 on=1 mode=UP/DN oct=2 rate=1/16 gate=0.62 swing=0.25 latch=1 live=1 pool=60,64,67") == 0,
                  "the latched chord plays; the ARP page shows the AU's pool and step");
            Snapshot(view, "MUEW_CHANCE50_PNG", "ARP chance pattern snapshot written");
            Snapshot(view, "MUEW_OCTAVE49_PNG", "ARP octave pattern snapshot written");
            Snapshot(view, "MUEW_RATCHET48_PNG", "ARP ratchet pattern snapshot written");
            Snapshot(view, "MUEW_ARP_PNG", "ARP page snapshot written");
            // Back: LATCH off (drops the released keys), ARP OFF, FILTER 1 page.
            {   // pattern cell follows the AU while it plays
                MUEWPerformance q{}; UInt32 qs = sizeof(q);
                AudioUnitGetProperty(gUnit, kMUEWProperty_Performance, kAudioUnitScope_Global, 0, &q, &qs);
                const std::string at = arpText();
                printf("arp pattern live: AU cell %d locked %u; editor %s\n", (int)q.arpPatCell, (unsigned)q.hostLocked, at.c_str());
                Check(q.arpPatCell >= 0 && q.arpPatCell < 8 && q.hostLocked == 0 && at.find(" cell=" + std::to_string(q.arpPatCell) + " ") != std::string::npos,
                      "the pattern lane highlights the AU's current cell");
            }
            Click(view, w, NSMakePoint(492 + 31, t - 205 + 9));   // PATTERN off
            Click(view, w, NSMakePoint(636 + 31, t - 205 + 9));   // HOST SYNC off
            Click(view, w, NSMakePoint(666 + 27, t - 84 + 9));
            Click(view, w, NSMakePoint(492 + 22, t - 58 + 9));
            RenderBlock();
            muew::Preset back;
            Check(State(back) && !back.voice.arpOn && !back.voice.arpLatch, "ARP OFF and LATCH off reached the AU");
            Click(view, w, NSMakePoint(492 + 30, t - 29 + 8.5));
            MusicDeviceMIDIEvent(gUnit, 0xB0, 123, 0, 0);
            RenderBlock();
            fflush(stdout);
        });
        After(7.06, ^{ // 0.27.0 FX depth: HYPER / DIMENSION and FILTER FX pages (chain slots 9 and 10)
            CGFloat t = view.bounds.size.height - 100;
            CGFloat h = (t - 286 - 44 - 58 - 6) / 2;
            auto card = [&](int slot) { return NSMakePoint(468 + (slot % 5) * 62 + 20, (slot < 5 ? 58 + h + 6 : 58) + h - 25); };
            auto bar = [&](int row, double n) { return NSMakePoint(36 + 12 + 62 + 100 * n, 48 + 200 - 52 - 17 * row + 8); }; // compact rows (fix1: 17 pt pitch)
            const NSPoint toggle = NSMakePoint(36 + 424 - 84 + 23, 48 + 200 - 25 + 8);
            muew::Preset st0; State(st0);
            const int hs = st0.fx.order.slotOf(muew::FxHyper), fs = st0.fx.order.slotOf(muew::FxFilter);
            Click(view, w, card(hs));                 // HYPER page (replaces whatever detail was open)
            Click(view, w, toggle);                   // ON
            Click(view, w, bar(1, 0.8));              // DETUNE 80%
            Click(view, w, bar(2, 0.6));              // DIMENSION 60%
            Click(view, w, bar(3, 0.5));              // MIX 50% (parameter 34)
            RenderBlock();
            Snapshot(view, "MUEW_HYPER_PNG", "HYPER / DIMENSION page snapshot written");
            Click(view, w, card(fs));                 // FILTER FX page
            Click(view, w, toggle);                   // ON
            Click(view, w, bar(0, 0.75));             // MODE > : BAND PASS
            Click(view, w, bar(1, 0.5));              // CUTOFF at mid-sweep of 40 Hz..18 kHz: ~849 Hz (parameter 35)
            Click(view, w, bar(2, 0.6));              // RESONANCE 60%
            Click(view, w, bar(4, 0.4));              // SWEEP 40%
            Click(view, w, bar(6, 0.75));             // SYNC > : first synced value
            RenderBlock();
            Snapshot(view, "MUEW_FILTERFX_PNG", "FILTER FX page snapshot written");
            muew::Preset st;
            const bool ok = State(st);
            AudioUnitParameterValue hm = -1, fc = -1;
            AudioUnitGetParameter(gUnit, muew::params::HyperMix, kAudioUnitScope_Global, 0, &hm);
            AudioUnitGetParameter(gUnit, muew::params::FilterFxCutoff, kAudioUnitScope_Global, 0, &fc);
            const auto& hy = st.fx.hyper; const auto& ff = st.fx.filter;
            printf("fx27: hyper on %d det %.2f dim %.2f mix %.2f (param 34 = %.1f); filter on %d mode %d cutoff %.0f (param 35 = %.0f) reso %.2f sweep %.2f sync %d\n",
                   hy.enabled ? 1 : 0, hy.detune, hy.dimension, hy.mix, hm, ff.enabled ? 1 : 0, ff.mode, ff.cutoffHz, fc, ff.reso, ff.lfoDepth, ff.lfoSync);
            Check(ok && hy.enabled && std::fabs(hy.detune - 0.8) < 0.01 && std::fabs(hy.dimension - 0.6) < 0.01 && std::fabs(hy.mix - 0.5) < 0.01
                  && std::fabs(hm - 50) < 1.0, "HYPER page: ON, DETUNE, DIMENSION and MIX reached the AU (parameter 34)");
            Check(ok && ff.enabled && ff.mode == 1 && ff.cutoffHz > 800 && ff.cutoffHz < 900 && std::fabs(fc - ff.cutoffHz) < 1.0
                  && std::fabs(ff.reso - 0.6) < 0.01 && std::fabs(ff.lfoDepth - 0.4) < 0.01 && ff.lfoSync == 1,
                  "FILTER FX page: ON, BAND PASS, CUTOFF, RESONANCE, SWEEP and SYNC reached the AU (parameter 35)");
            Check(ok && st.serialize().find("\nhyper 1 ") != std::string::npos && st.serialize().find("\nfilterfx 1 1 ") != std::string::npos,
                  "the AU state saves hyper and filterfx lines");
            // Leave both units off (settings kept) and the DELAY detail open as before.
            Click(view, w, toggle);
            Click(view, w, card(hs)); Click(view, w, toggle);
            Click(view, w, card(st0.fx.order.slotOf(muew::FxDelay)));
            muew::Preset back;
            Check(State(back) && !back.fx.hyper.enabled && !back.fx.filter.enabled && back.fx.filter.cutoffHz == ff.cutoffHz,
                  "HYPER and FILTER FX switch off from their pages and keep their settings");
            fflush(stdout);
        });
        After(7.08, ^{ // 0.28.0 Space + Dynamics: REVERB (HALL) and COMP (MULTIBAND) pages
            CGFloat t = view.bounds.size.height - 100;
            CGFloat h = (t - 286 - 44 - 58 - 6) / 2;
            auto card = [&](int slot) { return NSMakePoint(468 + (slot % 5) * 62 + 20, (slot < 5 ? 58 + h + 6 : 58) + h - 25); };
            auto bar = [&](int row, double n) { return NSMakePoint(36 + 12 + 62 + 100 * n, 48 + 200 - 52 - 17 * row + 8); };
            const NSPoint toggle = NSMakePoint(36 + 424 - 84 + 23, 48 + 200 - 25 + 8);
            muew::Preset st0; State(st0);
            const int rs = st0.fx.order.slotOf(muew::FxReverb), cs = st0.fx.order.slotOf(muew::FxComp);
            Click(view, w, card(rs));                 // REVERB page
            if (!st0.fx.reverb.enabled) Click(view, w, toggle);
            Click(view, w, bar(0, 0.5));              // MODE: HALL (middle segment)
            Click(view, w, bar(1, 0.6));              // DECAY
            Click(view, w, bar(3, 0.16));             // PRE-DELAY 40 ms
            Click(view, w, bar(4, 0.8));              // SIZE 80% (parameter 36)
            Click(view, w, bar(7, 0.35));             // MIX 35%
            RenderBlock();
            Snapshot(view, "MUEW_REVERB_PNG", "REVERB page snapshot written");
            Click(view, w, card(cs));                 // COMP page
            if (!st0.fx.comp.enabled) Click(view, w, toggle);
            Click(view, w, bar(0, 0.75));             // MODE: MULTIBAND (right segment)
            Click(view, w, bar(1, 0.6));              // AMOUNT 60%
            Click(view, w, bar(2, 0.7));              // UPWARD 70% (parameter 37)
            Click(view, w, bar(4, 0.75));             // LOW +6 dB
            Click(view, w, bar(6, 0.625));            // HIGH +3 dB
            RenderBlock();
            Snapshot(view, "MUEW_COMP_PNG", "COMP page snapshot written");
            muew::Preset st;
            const bool ok = State(st);
            AudioUnitParameterValue rsz = -1, cup = -1;
            AudioUnitGetParameter(gUnit, muew::params::ReverbSize, kAudioUnitScope_Global, 0, &rsz);
            AudioUnitGetParameter(gUnit, muew::params::CompUpward, kAudioUnitScope_Global, 0, &cup);
            const auto& rv = st.fx.reverb; const auto& cp = st.fx.comp;
            printf("fx28: reverb on %d mode %d decay %.2f pre %.1f size %.2f (param 36 = %.1f) mix %.2f; comp on %d mode %d amount %.2f up %.2f (param 37 = %.1f) low %.1f high %.1f\n",
                   rv.enabled ? 1 : 0, rv.mode, rv.decay, rv.preDelayMs, rv.size, rsz, rv.mix, cp.enabled ? 1 : 0, cp.mode, cp.amount, cp.upward, cup, cp.lowDb, cp.highDb);
            Check(ok && rv.enabled && rv.mode == 1 && std::fabs(rv.preDelayMs - 40.0) < 1.0 && std::fabs(rv.size - 0.8) < 0.01 && std::fabs(rsz - 80) < 1.0
                  && std::fabs(rv.mix - 0.35) < 0.01, "REVERB page: HALL, PRE-DELAY, SIZE and MIX reached the AU (parameter 36)");
            Check(ok && cp.enabled && cp.mode == 1 && std::fabs(cp.amount - 0.6) < 0.01 && std::fabs(cp.upward - 0.7) < 0.01 && std::fabs(cup - 70) < 1.0
                  && std::fabs(cp.lowDb - 6.0) < 0.2 && std::fabs(cp.highDb - 3.0) < 0.2,
                  "COMP page: MULTIBAND, AMOUNT, UPWARD, LOW and HIGH reached the AU (parameter 37)");
            Check(ok && st.serialize().find("\nreverbx 1 ") != std::string::npos && st.serialize().find("\ncompx 1 ") != std::string::npos,
                  "the AU state saves reverbx and compx lines");
            // Put both units back as they were (classic modes, previous on/off) and reopen the DELAY detail.
            Click(view, w, bar(0, 0.25));             // COMP MODE: ONE-KNOB
            if (!st0.fx.comp.enabled) Click(view, w, toggle);
            Click(view, w, card(rs));
            Click(view, w, bar(0, 0.15));             // REVERB MODE: CLASSIC
            if (!st0.fx.reverb.enabled) Click(view, w, toggle);
            Click(view, w, card(st0.fx.order.slotOf(muew::FxDelay)));
            muew::Preset back;
            Check(State(back) && back.fx.reverb.mode == 0 && back.fx.comp.mode == 0 && back.fx.reverb.enabled == st0.fx.reverb.enabled
                  && back.fx.comp.enabled == st0.fx.comp.enabled && back.fx.reverb.size == rv.size,
                  "REVERB and COMP return to CLASSIC / ONE-KNOB from their pages and keep their settings");
            fflush(stdout);
        });
        After(7.09, ^{ // 0.29.0 Quality: DIST QUALITY HQ 4X row and the MULTIBAND AUTO GAIN pill
            CGFloat t = view.bounds.size.height - 100;
            CGFloat h = (t - 286 - 44 - 58 - 6) / 2;
            auto card = [&](int slot) { return NSMakePoint(468 + (slot % 5) * 62 + 20, (slot < 5 ? 58 + h + 6 : 58) + h - 25); };
            auto wide = [&](int row, double n) { return NSMakePoint(36 + 12 + 92 + 196 * n, 48 + 200 - 58 - 24 * row + 10); }; // full-width rows
            auto bar = [&](int row, double n) { return NSMakePoint(36 + 12 + 62 + 100 * n, 48 + 200 - 52 - 17 * row + 8); };  // compact rows
            const NSPoint toggle = NSMakePoint(36 + 424 - 84 + 23, 48 + 200 - 25 + 8);
            const NSPoint pill = NSMakePoint(36 + 274 + 138 - 66 + 30, 48 + 26 + 136 - 14 + 6.5);
            muew::Preset st0; State(st0);
            const int ds = st0.fx.order.slotOf(muew::FxDist), cs = st0.fx.order.slotOf(muew::FxComp);
            Click(view, w, card(ds));                 // DIST page
            if (!st0.fx.dist.enabled) Click(view, w, toggle);
            Click(view, w, wide(0, 0.5));             // MODE: FOLD
            Click(view, w, wide(1, 0.7));             // DRIVE 70%
            Click(view, w, wide(3, 0.75));            // QUALITY: HQ 4X
            RenderBlock();
            Snapshot(view, "MUEW_DISTHQ_PNG", "DIST HQ page snapshot written");
            Click(view, w, card(cs));                 // COMP page
            if (!st0.fx.comp.enabled) Click(view, w, toggle);
            Click(view, w, bar(0, 0.75));             // MODE: MULTIBAND
            Click(view, w, bar(1, 0.8));              // AMOUNT 80%
            Click(view, w, pill);                     // AUTO GAIN on
            RenderBlock();
            Snapshot(view, "MUEW_AUTOGAIN_PNG", "COMP AUTO GAIN snapshot written");
            muew::Preset st;
            const bool ok = State(st);
            printf("quality29: dist on %d mode %d drive %.2f quality %d; comp mode %d amount %.2f makeup %d\n", st.fx.dist.enabled ? 1 : 0,
                   st.fx.dist.mode, st.fx.dist.drive, st.fx.dist.quality, st.fx.comp.mode, st.fx.comp.amount, st.fx.comp.makeup);
            Check(ok && st.fx.dist.enabled && st.fx.dist.mode == 1 && std::fabs(st.fx.dist.drive - 0.7) < 0.01 && st.fx.dist.quality == 1,
                  "DIST page: FOLD, DRIVE and QUALITY HQ 4X reached the AU");
            Check(ok && st.fx.comp.mode == 1 && std::fabs(st.fx.comp.amount - 0.8) < 0.01 && st.fx.comp.makeup == 1,
                  "COMP page: the AUTO GAIN pill reached the AU");
            Check(ok && st.serialize().find("\ndistx 1\n") != std::string::npos, "the AU state saves the distx line");
            // Put everything back and reopen the DELAY detail.
            Click(view, w, pill);                     // AUTO GAIN off
            Click(view, w, bar(0, 0.25));             // ONE-KNOB
            Click(view, w, bar(1, st0.fx.comp.amount));
            if (!st0.fx.comp.enabled) Click(view, w, toggle);
            Click(view, w, card(ds));
            Click(view, w, wide(3, 0.25));            // QUALITY: STANDARD
            Click(view, w, wide(0, (st0.fx.dist.mode + 0.5) / 3.0));
            Click(view, w, wide(1, st0.fx.dist.drive));
            if (!st0.fx.dist.enabled) Click(view, w, toggle);
            Click(view, w, card(st0.fx.order.slotOf(muew::FxDelay)));
            muew::Preset back;
            Check(State(back) && back.fx.dist.quality == 0 && back.fx.comp.makeup == 0 && back.fx.comp.mode == 0
                  && back.fx.dist.mode == st0.fx.dist.mode && back.fx.dist.enabled == st0.fx.dist.enabled && back.fx.comp.enabled == st0.fx.comp.enabled,
                  "DIST and COMP return to STANDARD / ONE-KNOB from their pages");
            fflush(stdout);
        });
        After(7.0, ^{ // Snapshot the hosted editor itself (independent of screen capture timing).
            Snapshot(view, "MUEW_VIEW_PNG", "editor snapshot written after the scripted edits");
        });
        After(7.12, ^{ // 0.30.0 Engine HQ: header QUALITY pill on, a chord for the voice meter
            const NSPoint hqPill = NSMakePoint(268 + 7 + 14, view.bounds.size.height - 66 + 21 + 6.5);
            Click(view, w, hqPill);
            MusicDeviceMIDIEvent(gUnit, 0x90, 60, 100, 0); MusicDeviceMIDIEvent(gUnit, 0x90, 64, 100, 0); MusicDeviceMIDIEvent(gUnit, 0x90, 67, 100, 0);
            for (int i = 0; i < 8; ++i) RenderBlock();
        });
        After(7.17, ^{
            const NSPoint hqPill = NSMakePoint(268 + 7 + 14, view.bounds.size.height - 66 + 21 + 6.5);
            RenderBlock();
            SEL follow = NSSelectorFromString(@"muewFollowPerformance");
            if ([view respondsToSelector:follow]) ((void (*)(id, SEL))[view methodForSelector:follow])(view, follow);
            [view display];
            Snapshot(view, "MUEW_ENGINE_PNG", "Engine HQ header snapshot written");
            NSString* et = [view respondsToSelector:NSSelectorFromString(@"muewEngineText")] ? [view valueForKey:@"muewEngineText"] : @"";
            Float64 lat = -1; UInt32 sz = sizeof(lat);
            AudioUnitGetProperty(gUnit, kAudioUnitProperty_Latency, kAudioUnitScope_Global, 0, &lat, &sz);
            muew::Preset st; const bool ok = State(st);
            printf("hq30: %s; AU oscq %d; latency %.2f samples\n", et.UTF8String ?: "", st.voice.oscQuality, lat * 44100.0);
            Check(ok && st.voice.oscQuality == 1 && st.serialize().find("\noscq 1\n") != std::string::npos, "header HQ pill: QUALITY HQ reached the AU and its state");
            Check(std::fabs(lat * 44100.0 - 7.5) < 0.01 || std::fabs(lat * 44100.0 - 30.0) < 0.01, "the AU reports the HQ latency to the host");
            Check([et rangeOfString:@"hq=1 voices="].location != NSNotFound && [et rangeOfString:@"voices=0/"].location == NSNotFound,
                  "header meter shows the held chord's voices");
            MusicDeviceMIDIEvent(gUnit, 0x80, 60, 0, 0); MusicDeviceMIDIEvent(gUnit, 0x80, 64, 0, 0); MusicDeviceMIDIEvent(gUnit, 0x80, 67, 0, 0);
            Click(view, w, hqPill); // back to STANDARD
            muew::Preset back;
            Check(State(back) && back.voice.oscQuality == 0, "header HQ pill returns to STANDARD");
            fflush(stdout);
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
            printf(gFailures ? "FAIL: AU editor host test\n" : "PASS: AU editor hosted; host->editor, editor->AU, automation, macros, user presets, unison, FX rack + chain reorder + detail editor, mod matrix, wavetable editor, filter 2 + sub page, MIDI performance, arpeggiator and full browser\n");
            fflush(stdout);
            exit(gFailures ? 1 : 0);
        });
        [app run];
    }
    return 0;
}
