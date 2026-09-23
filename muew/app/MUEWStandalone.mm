// MUEWStandalone.mm - MUEW standalone instrument: the shared editor view
// bound directly to an in-process synth, with the computer keyboard as a
// MIDI keyboard.
#import <AppKit/AppKit.h>
#import <AVFoundation/AVFoundation.h>
#import "MUEWEditorView.h"
#include "synth.h"
#include <mutex>

using namespace muew;

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
    NSWindow* w; MUEWEditorView* v; StandaloneHost* binding; AVAudioEngine* engine; AVAudioSourceNode* source; Synth synth; std::mutex lock;
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
    int start = ui::indexOfSlug("vowel-morph");
    [v loadPresetIndex:start >= 0 ? start : 0];
    [w center]; [w makeKeyAndOrderFront:nil]; [w makeFirstResponder:v];
    engine = [AVAudioEngine new];
    AVAudioFormat* fmt = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100 channels:2];
    Synth* s = &synth; std::mutex* l = &lock;
    source = [[AVAudioSourceNode alloc] initWithRenderBlock:^OSStatus(BOOL* silence, const AudioTimeStamp* t, AVAudioFrameCount count, AudioBufferList* out) {
        float* left = (float*)out->mBuffers[0].mData;
        float* right = (float*)out->mBuffers[1].mData;
        std::lock_guard<std::mutex> g(*l);
        s->renderPlanar(left, right, (int)count);
        return noErr;
    }];
    [engine attachNode:source];
    [engine connect:source to:engine.mainMixerNode format:fmt];
    NSError* err = nil;
    [engine startAndReturnError:&err];
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
