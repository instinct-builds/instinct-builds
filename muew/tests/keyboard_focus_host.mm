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
static NSEvent* Key(NSWindow* w, NSEventType type, NSString* text, unsigned short code = 0, NSEventModifierFlags modifiers = 0) {
    return [NSEvent keyEventWithType:type location:NSZeroPoint modifierFlags:modifiers
                          timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:w.windowNumber
                           context:nil characters:text charactersIgnoringModifiers:text isARepeat:NO keyCode:code];
}
static void Down(MUEWEditorView* v, NSWindow* w, NSString* s) { [v keyDown:Key(w,NSEventTypeKeyDown,s)]; }
static void Up(MUEWEditorView* v, NSWindow* w, NSString* s) { [v keyUp:Key(w,NSEventTypeKeyUp,s)]; }
static void Snapshot(MUEWEditorView* v, const char* name) {
    const char* dir = std::getenv("MUEW_FOCUS_PROOF_DIR");
    if (!dir || !*dir) return;
    NSString* path = [[NSString stringWithUTF8String:dir] stringByAppendingPathComponent:[NSString stringWithFormat:@"MUEW-0.80.0-focus-%s.png",name]];
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
    [v setBrowserOpen:true];
    Check(v->browserCursorSlug.empty(), "browser opens without an implicit keyboard choice");
    const int loaded=v->currentIndex, loads=host->patches;
    Down(v,w,@"\r"); Check(v->currentIndex==loaded && host->patches==loads,"Return without cursor does not load");
    Down(v,w,arrow);
    Check(v->browserCursorSlug.empty() && host->patches==loads,"right arrow is not a browser selection shortcut");
    unichar downCode=NSDownArrowFunctionKey, upCode=NSUpArrowFunctionKey;
    NSString* down=[NSString stringWithCharacters:&downCode length:1], *up=[NSString stringWithCharacters:&upCode length:1];
    Down(v,w,down); Down(v,w,down);
    Check(v->browserCursorSlug==muew::ui::library().slug(v->visible[1]) && host->patches==loads,
          "Down selects second row visibly without loading a preset");
    Check(v->currentIndex==loaded && v->visible[1]!=loaded,"cursor proposal remains distinct from loaded preset");
    Snapshot(v,"browser-cursor");
    const std::string chosen=v->browserCursorSlug;
    v->sortMode=muew::ui::SortName;
    [v refilter];
    Check(v->browserCursorSlug==chosen && [v browserCursorPosition]>=0,"cursor retains slug after sort, not old row number");
    v->browserCursorSlug="nonexistent-slug";
    Down(v,w,@"\r");
    Check(host->patches==loads && v->browserCursorSlug.empty(),"stale slug Return refuses to load by row index");
    v->browserCursorSlug=chosen;
    v->filter.query="no-such-sound-987"; [v refilter];
    Check(v->visible.empty() && v->browserCursorSlug.empty(),"filter removing cursor clears it instead of retargeting");
    Down(v,w,@"\r");
    Check(host->patches==loads && v->currentIndex==loaded,"Return with empty results is inert");
    v->filter.query=""; [v refilter];
    Check(v->browserCursorSlug.empty(),"broadening search never silently picks another preset");
    Down(v,w,up);
    Check(v->browserCursorSlug==muew::ui::library().slug(v->visible.back()),"Up from no cursor chooses last visible result");
    for(int i=0;i<110;++i) Down(v,w,up);
    Check(v->browserCursorSlug==muew::ui::library().slug(v->visible.front()) && v->bscroll==0,
          "Up clamps at first and scrolls it into view");
    for(int i=0;i<110;++i) Down(v,w,down);
    Check(v->browserCursorSlug==muew::ui::library().slug(v->visible.back()) && v->bscroll>0,
          "Down clamps at last and scrolls it into view");
    // Move to a different sound so Return must change the loaded preset.
    Down(v,w,up); const int chosenIndex=v->visible[[v browserCursorPosition]];
    Down(v,w,@"\r");
    Check(v->currentIndex==chosenIndex && v->browserCursorSlug.empty() && v->browserOpen && host->patches==loads+1,
          "Return commits exact cursor once, stays in browser and clears pending choice");
    [v setBrowserOpen:false]; [v setBrowserOpen:true];
    Down(v,w,down); const int committedBefore=v->currentIndex;
    Down(v,w,esc);
    Check(!v->browserOpen && v->browserCursorSlug.empty() && v->currentIndex==committedBefore,
          "Escape cancels pending cursor without loading");
    // Native field editor receives Tab; the delegate transfers to the result
    // list. A direct call to the view would not test AppKit's text-command path.
    [v setBrowserOpen:true];
    v->search.stringValue=@"";
    [v controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:v->search]];
    Down(v,w,down); Down(v,w,down);
    const std::string priorSlug=v->browserCursorSlug;
    [w makeFirstResponder:v->search];
    std::printf("handoff pre: first=%s list=%d current=%d expected=%d cursor=%s\n",
                object_getClassName(w.firstResponder),v->browserListFocus,v->currentIndex,committedBefore,v->browserCursorSlug.c_str());
    Check(!v->browserListFocus && w.firstResponder!=v,"search owns focus before Tab handoff");
    Snapshot(v,"handoff-search");
    id editor=w.firstResponder;
    [editor keyDown:Key(w,NSEventTypeKeyDown,@"\t",48)];
    Check(w.firstResponder==v && v->browserListFocus && v->browserCursorSlug==priorSlug,
          "real text-editor Tab transfers focus without replacing cursor");
    Snapshot(v,"handoff-list");
    const int oldPos=[v browserCursorPosition];
    Down(v,w,down);
    Check([v browserCursorPosition]==std::min(oldPos+1,(int)v->visible.size()-1),
          "first arrow after Tab advances from prior cursor");
    NSString* query=@"Bright";
    [w makeFirstResponder:v->search];
    v->search.stringValue=query;
    [v controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:v->search]];
    std::printf("handoff filter: first=%s list=%d current=%d expected=%d query=%s\n",
                object_getClassName(w.firstResponder),v->browserListFocus,v->currentIndex,committedBefore,v->search.stringValue.UTF8String);
    Check(!v->browserListFocus && v->currentIndex==committedBefore,
          "typed filter has no accidental preset load");
    editor=w.firstResponder;
    [editor keyDown:Key(w,NSEventTypeKeyDown,@"\t",48)];
    Check(w.firstResponder==v && v->browserListFocus && !v->visible.empty(),
          "Tab from filtered search reaches result list");
    [v keyDown:Key(w,NSEventTypeKeyDown,@"\t",48,NSEventModifierFlagShift)];
    std::printf("handoff back: first=%s list=%d query=%s expected=%s\n",
                object_getClassName(w.firstResponder),v->browserListFocus,v->search.stringValue.UTF8String,query.UTF8String);
    Check(w.firstResponder!=v && !v->browserListFocus && [v->search.stringValue isEqualToString:query],
          "Shift-Tab returns to Search without changing its query");
    Check(host->on.size()==onBefore+1 && host->off.size()==offBefore+1,
          "Tab/Shift-Tab and browser arrows never trigger piano notes");
    Snapshot(v,"handoff-search-return");
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
