// au_view_host.mm - CI proof that the MUEW AU editor works the way a DAW
// uses it: find the installed component, ask it for kAudioUnitProperty_CocoaUI,
// load the view class from the component bundle, embed the view in a window,
// then drive it with real mouse events and check the AU follows.
//   1. host selects Chrome Motion  -> editor must follow (host -> editor)
//   2. click the header "next" arrow -> AU must report Rising Tide (editor -> AU)
//   3. drag the cutoff knob up      -> AU holds an edited Rising Tide with a
//                                      higher cutoff and no factory number
// The window stays up long enough for the workflow to screenshot it.
#import <AppKit/AppKit.h>
#import <AudioToolbox/AudioToolbox.h>
#if __has_include(<AudioToolbox/AUCocoaUIView.h>)
#import <AudioToolbox/AUCocoaUIView.h>
#else
#import <AudioUnit/AUCocoaUIView.h>
#endif
#include "MUEWProperties.h"
#include "preset.h"
#include <cstdio>
#include <string>

static AudioUnit gUnit = nullptr;
static int gFailures = 0;

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
            fflush(stdout);
        });
        After(9.0, ^{
            printf(gFailures ? "FAIL: AU editor host test\n" : "PASS: AU editor hosted, host->editor and editor->AU sync\n");
            fflush(stdout);
            exit(gFailures ? 1 : 0);
        });
        [app run];
    }
    return 0;
}
