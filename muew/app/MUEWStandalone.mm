// MUEWStandalone.mm - MUEW standalone instrument: the shared editor view
// bound directly to an in-process synth, with the computer keyboard as a
// MIDI keyboard.
#import <AppKit/AppKit.h>
#import <AVFoundation/AVFoundation.h>
#import "MUEWEditorView.h"
#include "synth.h"
#include <mutex>
#include <atomic>
#include <chrono>
#include <algorithm>

using namespace muew;

static std::atomic<float> gCpu{0}; // 0.30.0 header meter: smoothed real-time load
static std::atomic<int> gVoices{0};
static std::atomic<float> gMorphA{-1.0f}, gMorphB{-1.0f}; // 0.35.0 live morph meter
static std::atomic<float> gVoiceMorph[2][8]{}; static std::atomic<int> gVoiceMorphN[2]{{0}, {0}}; // 0.36.0

static NSColor* C(uint32_t rgb, CGFloat a = 1) {
    return [NSColor colorWithRed:((rgb >> 16) & 255) / 255.0 green:((rgb >> 8) & 255) / 255.0 blue:(rgb & 255) / 255.0 alpha:a];
}

struct StandaloneHost : MUEWEditorHost {
    Synth* synth; std::mutex* lock;
    StandaloneHost(Synth* s, std::mutex* l) : synth(s), lock(l) {}
    void applyPreset(const Preset& p, int, bool) override {
        std::lock_guard<std::mutex> g(*lock);
        synth->setTables(p.tables[0], p.tables[1]);
        synth->setParams(p.voice, p.routes);
        synth->setFX(p.fx);
    }
    bool playsNotes() const override { return true; }
    void noteOn(int n, float v) override { std::lock_guard<std::mutex> g(*lock); synth->noteOn(n, v); }
    void noteOff(int n) override { std::lock_guard<std::mutex> g(*lock); synth->noteOff(n); }
};

@interface AppDelegate : NSObject <NSApplicationDelegate> {
    NSWindow* w; MUEWEditorView* v; StandaloneHost* binding; AVAudioEngine* engine; AVAudioSourceNode* source; Synth synth; std::mutex lock; NSTimer* meter;
}
@end

@implementation AppDelegate
- (void)applicationDidFinishLaunching:(NSNotification*)n {
    NSRect f = NSMakeRect(0, 0, 1000, 680);
    w = [[NSWindow alloc] initWithContentRect:f
                                    styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
                                      backing:NSBackingStoreBuffered defer:NO];
    w.title = @"MUEW";
    w.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    w.backgroundColor = C(0x0b0e13);
    synth.init(44100);
    binding = new StandaloneHost(&synth, &lock);
    v = [[MUEWEditorView alloc] initWithFrame:f];
    v->host = binding;
    w.contentView = v;
    int start = ui::indexOfSlug("formant-talker");
    [v loadPresetIndex:start >= 0 ? start : 0];
    [w center]; [w makeKeyAndOrderFront:nil]; [w makeFirstResponder:v];
    engine = [AVAudioEngine new];
    AVAudioFormat* fmt = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100 channels:2];
    Synth* s = &synth; std::mutex* l = &lock;
    source = [[AVAudioSourceNode alloc] initWithRenderBlock:^OSStatus(BOOL* silence, const AudioTimeStamp* t, AVAudioFrameCount count, AudioBufferList* out) {
        float* left = (float*)out->mBuffers[0].mData;
        float* right = (float*)out->mBuffers[1].mData;
        std::lock_guard<std::mutex> g(*l);
        const auto t0 = std::chrono::steady_clock::now(); // 0.30.0 header meter
        s->renderPlanar(left, right, (int)count);
        const double used = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count(), budget = count / 44100.0;
        if (budget > 0) { const float c = gCpu.load(); gCpu = c + 0.1f * ((float)std::min(used / budget, 4.0) - c); }
        gVoices = s->activeVoiceCount();
        gMorphA = s->specMorphMeter(0); gMorphB = s->specMorphMeter(1); // 0.35.0
        for (int o = 0; o < 2; ++o) { float vm[8]; const int n = s->specMorphVoices(o, vm, 8); for (int i = 0; i < 8; ++i) gVoiceMorph[o][i] = i < n ? vm[i] : -1.0f; gVoiceMorphN[o] = n; }
        return noErr;
    }];
    [engine attachNode:source];
    [engine connect:source to:engine.mainMixerNode format:fmt];
    NSError* err = nil;
    [engine startAndReturnError:&err];
    MUEWEditorView* view = v; // 0.30.0: feed the header voice / CPU meter
    meter = [NSTimer scheduledTimerWithTimeInterval:1.0 / 15 repeats:YES block:^(NSTimer*) {
        const auto& vp = view->current.voice;
        [view showEngineVoices:gVoices.load() limit:vp.voiceMode != 0 ? 1 : vp.polyVoices cpu:gCpu.load() render:false];
        [view showLiveMorphA:gMorphA.load() b:gMorphB.load()]; // 0.35.0
        float va[8], vb[8]; for (int i = 0; i < 8; ++i) { va[i] = gVoiceMorph[0][i].load(); vb[i] = gVoiceMorph[1][i].load(); }
        [view showVoiceMorph:va count:gVoiceMorphN[0].load() b:vb count:gVoiceMorphN[1].load()]; // 0.36.0
    }];
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)s { return YES; }
@end

int main(int argc, const char** argv) {
    @autoreleasepool {
        NSApplication* app = [NSApplication sharedApplication];
        app.activationPolicy = NSApplicationActivationPolicyRegular;
        app.presentationOptions = NSApplicationPresentationAutoHideDock;
        AppDelegate* d = [AppDelegate new];
        app.delegate = d;
        [app activateIgnoringOtherApps:YES];
        [app run];
    }
    return 0;
}
