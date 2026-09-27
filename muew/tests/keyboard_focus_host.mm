// Standalone-style editor keyboard/focus contract, run on the macOS CI desktop.
#import <AppKit/AppKit.h>
#import "MUEWEditorView.h"
#include <cstdio>
#include <vector>
#include <utility>
#include <string>
#include <cstdlib>
#import <dispatch/dispatch.h>
#import <objc/runtime.h>

static int failures = 0;
static void Check(bool ok, const char* why) {
    std::printf("%s keyboard focus: %s\n", ok ? "ok:" : "FAIL:", why);
    failures += !ok;
}
struct KeyboardHost final : MUEWEditorHost {
    std::vector<int> on, off;
    int patches = 0;
    void applyPreset(const muew::Preset&, int, bool) override { ++patches; }
    bool playsNotes() const override { return true; }
    void noteOn(int n, float) override { on.push_back(n); }
    void noteOff(int n) override { off.push_back(n); }
};
static NSEvent* Key(NSWindow* w, NSEventType type, NSString* text, unsigned short code = 0) {
    return [NSEvent keyEventWithType:type location:NSZeroPoint modifierFlags:0
                          timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:w.windowNumber
                           context:nil characters:text charactersIgnoringModifiers:text isARepeat:NO keyCode:code];
}
static void Down(MUEWEditorView* v, NSWindow* w, NSString* s) { [v keyDown:Key(w,NSEventTypeKeyDown,s)]; }
static void Up(MUEWEditorView* v, NSWindow* w, NSString* s) { [v keyUp:Key(w,NSEventTypeKeyUp,s)]; }
static void Snapshot(MUEWEditorView* v, const char* name) {
    const char* dir = std::getenv("MUEW_FOCUS_PROOF_DIR");
    if (!dir || !*dir) return;
    NSString* path = [[NSString stringWithUTF8String:dir] stringByAppendingPathComponent:[NSString stringWithFormat:@"MUEW-0.78.0-focus-%s.png",name]];
    NSBitmapImageRep* rep = [v bitmapImageRepForCachingDisplayInRect:v.bounds];
    [v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];
    NSData* data = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    Check(data.length > 10000 && [data writeToFile:path atomically:YES], name);
}
static void RunChecks(MUEWEditorView* v, NSWindow* w, KeyboardHost* host) {
    Check(w.isKeyWindow && w.firstResponder == v, "editor is the standalone key responder");
    const int original = v->currentIndex;
    Down(v,w,@"a"); Down(v,w,@"a");
    Check(host->on.size()==1 && !host->on.empty() && host->on.back()==48, "repeat/double keyDown cannot trigger duplicate note-on");
    v->octave=2; Up(v,w,@"a");
    Check(host->off.size()==1 && !host->off.empty() && host->off.back()==48, "keyUp releases original note after octave changes");
    v->octave=0;
    Down(v,w,@"s"); [w makeFirstResponder:v->search];
    Check(!host->on.empty() && !host->off.empty() && host->on.back()==50 && host->off.back()==50 && w.firstResponder != v, "changing to search releases held note");
    const size_t onBefore=host->on.size(), offBefore=host->off.size();
    const int patchBefore=v->currentIndex;
    v->search.stringValue=@"awsedftgyhujk zx";
    [v controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:v->search]];
    // Even misdirected events must not escape a native text editor into piano controls.
    Down(v,w,@"z"); Down(v,w,@"x"); Down(v,w,@"a");
    unichar rightArrow = NSRightArrowFunctionKey, escape = 27;
    NSString* arrow = [NSString stringWithCharacters:&rightArrow length:1];
    NSString* esc = [NSString stringWithCharacters:&escape length:1];
    Down(v,w,arrow);
    Check(host->on.size()==onBefore && host->off.size()==offBefore && v->octave==0 && v->currentIndex==patchBefore,
          "text focus blocks notes, octave and preset shortcuts");
    Snapshot(v,"text");
    [w makeFirstResponder:v];
    Down(v,w,@"a");
    [[NSNotificationCenter defaultCenter] postNotificationName:NSWindowDidResignKeyNotification object:w];
    Check(host->on.size()==onBefore+1 && host->off.size()==offBefore+1 && !host->off.empty() && host->off.back()==48,
          "window losing key focus releases held note");
    Up(v,w,@"a");
    Check(host->off.size()==offBefore+1, "late keyUp does not release twice");

    v->outputDetailOpen=true; [v setNeedsDisplay:YES]; Snapshot(v,"output-detail");
    Down(v,w,@"\r"); Check(!v->outputDetailOpen && v->currentIndex==original, "Return closes read-only output detail only");
    v->outputDetailOpen=true; v->browserOpen=true;
    Down(v,w,esc);
    Check(!v->outputDetailOpen && v->browserOpen, "Escape closes output before browser");
    v->browserOpen=false;
    v->search.stringValue=@"";
    [v controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:v->search]];
    [v setBrowserOpen:true];
    Check(!v->visible.empty(), "browser focus proof shows real preset rows");
    Snapshot(v,"browser");
    Down(v,w,@"\r"); Check(v->browserOpen, "Return does not activate browser rows");
    Down(v,w,esc);
    Check(!v->browserOpen, "Escape closes browser");
    v->wtEdit=0; v->fxDetail=0;
    Down(v,w,esc);
    Check(v->wtEdit<0 && v->fxDetail==0, "Escape closes wavetable before small panel");
    Down(v,w,esc);
    Check(v->fxDetail<0 && v->currentIndex==original, "Escape closes small panel without a sound edit");
    Down(v,w,esc);
    Check(v->currentIndex==original, "Escape on base editor has no effect");
    std::printf("%s keyboard focus host test\n",failures?"FAIL:":"PASS:");
    fflush(stdout);
    // Bypass runner AppKit teardown after capturing assertions and pixels. The
    // original harness crashed in objc_release after printing its final result.
    _Exit(failures ? 1 : 0);
}
int main() {
 @autoreleasepool {
    setvbuf(stdout, nullptr, _IONBF, 0); // retain the last passing assertion on a runner crash
    std::fprintf(stderr, "focus: boot\n");
    NSApplication* app = [NSApplication sharedApplication];
    app.activationPolicy = NSApplicationActivationPolicyRegular;
    NSWindow* w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1000,680)
                 styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    w.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    MUEWEditorView* v = [[MUEWEditorView alloc] initWithFrame:NSMakeRect(0,0,1000,680)];
    KeyboardHost* host = new KeyboardHost; v->host = host; w.contentView = v;
    [v loadPresetIndex:0]; [w center]; [w makeKeyAndOrderFront:nil];
    [app activateIgnoringOtherApps:YES];
    [w makeFirstResponder:v];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        std::fprintf(stderr, "focus: window ready, key=%d responder=%s\n", w.isKeyWindow, object_getClassName(w.firstResponder));
        RunChecks(v,w,host);
    });
    [app run];
    return 2; // normally unreachable
 }
}
