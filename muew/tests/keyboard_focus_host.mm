// Standalone-style editor keyboard/focus contract, run on the macOS CI desktop.
#import <AppKit/AppKit.h>
#import "MUEWEditorView.h"
#include <cstdio>
#include "proof_watchdog.h"
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
    NSString* path = [[NSString stringWithUTF8String:dir] stringByAppendingPathComponent:[NSString stringWithFormat:@"MUEW-0.87.0-focus-%s.png",name]];
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

    muew_proof::Phase("matrix reset all-page proof");
    const muew::Preset preResetSound=v->current;
    v->current.routes.resize(muew::kMaxRoutes,{muew::ModRoute::Source::Macro1,muew::ModRoute::Dest::FilterCutoff,1.0});
    const muew::Preset resetSound=v->current;
    const bool resetEdited=v->edited;
    const int resetPatches=host->patches;
    const auto preResetOn=host->on.size(),preResetOff=host->off.size();
    Down(v,w,@"a");
    const auto resetOn=host->on.size(),resetOff=host->off.size();
    Check(resetOn==preResetOn+1 && resetOff==preResetOff,"matrix reset fixture has a held standalone piano note");
    float resetLive[muew::kMaxRoutes]{};
    for (int i=0;i<muew::kMaxRoutes;++i) {
        resetLive[i]=(i%2 ? -.4f : .6f);
        v->routeMeters[i]=resetLive[i];
        v->routeHold.value[i]=resetLive[i]; v->routeHold.age[i]=.1;
        v->routeTrace.low[i]=-.5f; v->routeTrace.high[i]=.7f;
    }
    const int savedPage=v->matrixPage;
    v->matrixPage=3; Snapshot(v,"matrix-reset-hidden-before");
    v->matrixPage=0; Snapshot(v,"matrix-reset-before");
    NSPoint resetPoint=[v matrixTraceReset].origin;
    resetPoint.x+=20; resetPoint.y+=7;
    NSEvent* resetEvent=[NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:resetPoint modifierFlags:0
        timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:w.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
    [v mouseDown:resetEvent];
    BOOL allClear=YES,liveUnchanged=YES;
    for (int i=0;i<muew::kMaxRoutes;++i) {
        allClear &= v->routeHold.value[i]==0 && v->routeHold.age[i]==0 && v->routeTrace.low[i]==0 && v->routeTrace.high[i]==0;
        liveUnchanged &= v->routeMeters[i]==resetLive[i];
    }
    Check(allClear && liveUnchanged && v->current==resetSound && v->edited==resetEdited && host->patches==resetPatches &&
          host->on.size()==resetOn && host->off.size()==resetOff && v->matrixPage==0,
          "RESET TRACE clears all 16 hidden/visible histories, not live values, sound, edits or notes");
    Snapshot(v,"matrix-reset-after");
    v->matrixPage=3; Snapshot(v,"matrix-reset-hidden-after");
    float resetLo[muew::kMaxRoutes]{}, resetHi[muew::kMaxRoutes]{};
    resetLo[0]=-.3f;resetHi[0]=.5f;
    [v showRouteMeters:resetLive count:muew::kMaxRoutes];
    [v showRouteMin:resetLo max:resetHi count:muew::kMaxRoutes];
    Check(v->routeHold.value[0]==resetLive[0] && v->routeTrace.low[0]==-.3f && v->routeTrace.high[0]==.5f &&
          v->current==resetSound && host->patches==resetPatches,"fresh in-process poll recaptures history without sound edits");
    Up(v,w,@"a");
    Check(host->off.size()==preResetOff+1,"held piano note releases normally after trace reset");
    host->on.resize(preResetOn);host->off.resize(preResetOff); // isolate from later key-count assertions
    v->current=preResetSound;
    v->matrixPage=savedPage; [v resetMatrixTrace];
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
    // Query AppKit's exposed tree as a client: the native Search survives,
    // while rows represent immutable slugs. Reading/traversal is inert.
    NSArray* ax=[v accessibilityChildren];
    Check(ax.count==34 && ax[0]==v->search && [[ax[23] accessibilityRole] isEqualToString:NSAccessibilityListRole] &&
          [[ax[23] accessibilityLabel] isEqualToString:@"Preset results"],
          "accessibility tree exposes native Search, navigation and named results list");
    id list=ax.count>23 ? ax[23] : nil;
    id bankFactory=ax.count>2 ? ax[2] : nil;
    id typeLead=ax.count>7 ? ax[7] : nil;
    id sortName=ax.count>15 ? ax[15] : nil;
    Check([[bankFactory accessibilityLabel] containsString:@"Bank: Factory"] &&
          [[typeLead accessibilityLabel] containsString:@"Type: Lead"] &&
          [[sortName accessibilityLabel] containsString:@"Sort: Name"],
          "accessible navigation controls have exact names and stable order");
    id favorite=ax[29], rating=ax[26];
    {
        id floor5=ax[22];
        const int floorPatches=host->patches;
        Check([[ax[18] accessibilityLabel] isEqualToString:@"Minimum rating: 1 star, not selected"] &&
              [[floor5 accessibilityLabel] isEqualToString:@"Minimum rating: 5 stars, not selected"] &&
              [floor5 accessibilityPerformPress] && v->filter.minRating==5 &&
              [[floor5 accessibilityLabel] isEqualToString:@"Minimum rating: 5 stars, selected"],
              "minimum-rating AX star sets the floor");
        bool allFive=true;
        for (int idx : v->visible) allFive=allFive && muew::ui::ratingOf(v->ratings,muew::ui::library().slug(idx))>=5;
        Check(allFive && [floor5 accessibilityPerformPress] && v->filter.minRating==0 && host->patches==floorPatches,
              "minimum-rating floor filters, clears on same star, and loads nothing");
    }
    const auto savedFavorites=v->favorites;
    const auto savedRatings=v->ratings;
    {   // lit-state pixels: a seeded 4-star floor over a narrowed list
        const int floorPatches=host->patches;
        v->ratings.clear();
        for (int i=0;i<12;++i) muew::ui::setRating(v->ratings,muew::ui::library().slug(i*3),(i%5)+1);
        v->filter.bank=-1; v->filter.category=""; v->sortMode=muew::ui::SortRating; [v refilter];
        const size_t before=v->visible.size();
        Check([ax[21] accessibilityPerformPress] && v->filter.minRating==4 && v->visible.size()<before && !v->visible.empty() &&
              [[ax[21] accessibilityLabel] isEqualToString:@"Minimum rating: 4 stars, selected"] && host->patches==floorPatches,
              "seeded 4-star floor narrows the list through the AX press without loading");
        Snapshot(v,"min-rating-floor");
        [ax[21] accessibilityPerformPress];
        Check(v->filter.minRating==0,"snapshot floor clears");
        v->ratings=savedRatings; v->sortMode=muew::ui::SortBank; [v refilter];
    }
    const int sound=v->currentIndex, patches=host->patches;
    const std::string loadedSlug=muew::ui::library().slug(sound);
    [v moveBrowserCursor:1];
    Check([favorite accessibilityPerformPress] && v->favorites.count(loadedSlug)!=savedFavorites.count(loadedSlug) &&
          host->patches==patches && v->currentIndex==sound,
          "favorite targets loaded sound, not proposed row, without loading");
    Check([rating accessibilityPerformPress] && muew::ui::ratingOf(v->ratings,loadedSlug)==(muew::ui::ratingOf(savedRatings,loadedSlug)==3 ? 0 : 3) &&
          favorite==[v accessibilityChildren][29],"rating shares loaded-sound path and survives refilter");
    Snapshot(v,"accessible-detail");
    [v loadPresetIndex:(sound+1)%muew::ui::library().count()];
    Check(![favorite accessibilityPerformPress] && ![rating accessibilityPerformPress],
          "retained loaded-sound controls refuse to target newly loaded preset");
    [v loadPresetIndex:sound];
    v->favorites=savedFavorites; v->ratings=savedRatings; [v saveFavorites]; [v saveRatings]; [v refilter];
    for (int index=30;index<=32;++index) {
        const char* phase=index==30 ? "Save dialog launch" : index==31 ? "Import dialog launch" : "Export dialog launch";
        muew_proof::Phase(phase);
        const int before=host->patches;
        __block BOOL modalSeen=NO;
        __block BOOL guarded=NO;
        NSTimer* timer=[NSTimer timerWithTimeInterval:0.05 repeats:YES block:^(NSTimer* t) {
            NSWindow* modal=v->browserNativeDialog ?: NSApp.modalWindow;
            if (!modal || !modal.isVisible) return;
            std::fprintf(stderr,"focus dialog index=%d native=%s modal=%d cancel-start\n",index,object_getClassName(modal),NSApp.modalWindow==modal);
            modalSeen=YES;
            guarded=![v performBrowserLoadedRating:1] && ![v performBrowserInfoAction:0];
            [t invalidate];
            if ([modal isKindOfClass:[NSSavePanel class]]) [(NSSavePanel*)modal cancel:nil];
            else { [NSApp stopModalWithCode:NSAlertSecondButtonReturn]; [modal orderOut:nil]; }
            std::fprintf(stderr,"focus dialog index=%d cancel-returned\n",index);
        }];
        [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSModalPanelRunLoopMode];
        [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSDefaultRunLoopMode];
        Check([[v accessibilityChildren][index] accessibilityPerformPress],"accessible file action accepts launch");
        NSDate* deadline=[NSDate dateWithTimeIntervalSinceNow:5];
        while (!modalSeen && deadline.timeIntervalSinceNow>0)
            [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        [timer invalidate];
        std::fprintf(stderr,"focus dialog index=%d launch-returned seen=%d active=%d\n",index,modalSeen,v->browserDialogActive);
        Check(modalSeen && guarded && !v->browserDialogActive && w.firstResponder==v && host->patches==before &&
              v->currentIndex==sound,"native file dialog cancels without edit and restores editor focus");
    }
    id retainedBank=bankFactory;
    [bankFactory accessibilityPerformPress];
    Check(v->filter.bank==muew::ui::BankFactory && retainedBank==[v accessibilityChildren][2] &&
          v->currentIndex==original,
          "accessible bank press uses shared filter path and retains control identity");
    [typeLead accessibilityPerformPress];
    Check(v->filter.category=="Lead" && retainedBank==[v accessibilityChildren][2] &&
          v->currentIndex==original,"accessible type press refilters without loading");
    [sortName accessibilityPerformPress];
    Check(v->sortMode==muew::ui::SortName && v->currentIndex==original,
          "accessible sort press reorders without loading");
    [v setBrowserOpen:false];
    Check([v accessibilityChildren].count==1 && ![retainedBank accessibilityPerformPress],
          "closed navigation disappears and retained control refuses press");
    [v setBrowserOpen:true];
    v->filter.bank=-1; v->filter.category=""; v->sortMode=muew::ui::SortBank; [v refilter];
    ax=[v accessibilityChildren]; list=ax[23];
    NSArray* rows=[list accessibilityChildren];
    Check(rows.count>1 && [[rows[0] accessibilityRole] isEqualToString:NSAccessibilityButtonRole] &&
          [[rows[0] accessibilityLabel] containsString:@"1 of 108"] &&
          [[rows[0] accessibilityLabel] containsString:@"proposed: no, loaded: yes"],
          "accessible row states and exact position are separate from focus");
    int axLoaded=v->currentIndex, axPatches=host->patches;
    [v accessibilityChildren]; [list accessibilityChildren]; [rows[0] accessibilityLabel];
    Check(v->currentIndex==axLoaded && host->patches==axPatches && v->browserCursorSlug.empty(),
          "accessibility traversal never loads or proposes a sound");
    MUEWBrowserAXRow* stale=rows[0]; NSString* staleSlug=stale.slug;
    v->filter.query="no-such-sound-987"; [v refilter];
    Check([[list accessibilityChildren] count]==0 && ![stale accessibilityPerformPress] &&
          v->currentIndex==axLoaded && host->patches==axPatches,
          "retained row from removed filter cannot retarget or activate");
    v->filter.query=""; [v refilter];
    v->sortMode=muew::ui::SortName; [v refilter];
    rows=[list accessibilityChildren];
    Check(rows.count>1 && [[rows[0] accessibilityLabel] containsString:@"1 of 108"] &&
          ![((MUEWBrowserAXRow*)rows[0]).slug isEqualToString:staleSlug],
          "accessible rows follow sort while retaining individual slug identity");
    v->sortMode=muew::ui::SortBank; [v refilter];
    rows=[list accessibilityChildren];
    Check(![stale accessibilityPerformPress] && v->currentIndex==axLoaded,
          "old row stays inert even when its slug reappears after refilter");
    const size_t axNotes=host->on.size();
    unichar axDown=NSDownArrowFunctionKey;
    Down(v,w,[NSString stringWithCharacters:&axDown length:1]);
    Down(v,w,[NSString stringWithCharacters:&axDown length:1]);
    rows=[list accessibilityChildren];
    MUEWBrowserAXRow* target=rows[1]; NSString* targetSlug=target.slug;
    Check([[target accessibilityLabel] containsString:@"proposed: yes"] &&
          v->currentIndex==axLoaded && host->patches==axPatches && host->on.size()==axNotes,
          "accessible proposed state tracks keyboard cursor without loading or notes");
    Check([target accessibilityPerformPress] && v->currentIndex==muew::ui::indexOfSlug(targetSlug.UTF8String) &&
          host->patches==axPatches+1 && v->browserCursorSlug.empty() && host->on.size()==axNotes,
          "deliberate accessible press loads exact visible slug once");
    rows=[list accessibilityChildren];
    Check([[rows[1] accessibilityLabel] containsString:@"proposed: no, loaded: yes"],
          "accessible loaded state updates after activation");
    [v setBrowserOpen:false];
    Check([v accessibilityChildren].count==1 && ![target accessibilityPerformPress],
          "closed browser hides the list and retained row cannot act");
    [v setBrowserOpen:true];
    [v loadPresetIndex:original];
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
    const NSRange caret=NSMakeRange(2,0); // deliberately not the default end-of-query position
    Check([editor isKindOfClass:[NSTextView class]],"filtered Search owns a native text editor");
    if ([editor isKindOfClass:[NSTextView class]]) [(NSTextView*)editor setSelectedRange:caret];
    Check([editor isKindOfClass:[NSTextView class]] && NSEqualRanges([(NSTextView*)editor selectedRange],caret),
          "nonterminal Search caret is established before Tab");
    Snapshot(v,"handoff-search-caret");
    [editor keyDown:Key(w,NSEventTypeKeyDown,@"\t",48)];
    Check(w.firstResponder==v && v->browserListFocus && !v->visible.empty(),
          "Tab from filtered search reaches result list");
    [v keyDown:Key(w,NSEventTypeKeyDown,@"\t",48,NSEventModifierFlagShift)];
    id returned=w.firstResponder;
    NSRange after=[returned isKindOfClass:[NSTextView class]] ? [(NSTextView*)returned selectedRange] : NSMakeRange(NSNotFound,0);
    std::printf("handoff caret: before=(%lu,%lu) after=(%lu,%lu) responder=%s\n",
                (unsigned long)caret.location,(unsigned long)caret.length,
                (unsigned long)after.location,(unsigned long)after.length,object_getClassName(returned));
    Check([returned isKindOfClass:[NSTextView class]] && NSEqualRanges(after,caret),
          "Shift-Tab restores the exact nonterminal Search caret");
    std::printf("handoff back: first=%s list=%d query=%s expected=%s\n",
                object_getClassName(w.firstResponder),v->browserListFocus,v->search.stringValue.UTF8String,query.UTF8String);
    Check(w.firstResponder!=v && !v->browserListFocus && [v->search.stringValue isEqualToString:query],
          "Shift-Tab returns to Search without changing its query");
    Snapshot(v,"handoff-search-return-caret");
    Check(host->on.size()==onBefore+1 && host->off.size()==offBefore+1,
          "Tab/Shift-Tab and browser arrows never trigger piano notes");
    Snapshot(v,"handoff-search-return");
    muew_proof::Phase("native type-to-refine proof");
    const int refineLoads=host->patches,refineIndex=v->currentIndex;
    const auto refineOn=host->on.size(),refineOff=host->off.size();
    [w makeFirstResponder:v->search];
    v->search.stringValue=@"Bright";
    [v controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:v->search]];
    [(NSTextView*)w.firstResponder setSelectedRange:NSMakeRange(1,3)];
    [w.firstResponder keyDown:Key(w,NSEventTypeKeyDown,@"\t",48)];
    Down(v,w,down);
    const std::string refineCursor=v->browserCursorSlug;
    Check(!refineCursor.empty(),"type-to-refine starts with a proposed list result");
    NSEvent* shiftedQuestion=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
        modifierFlags:NSEventModifierFlagShift timestamp:NSProcessInfo.processInfo.systemUptime
        windowNumber:w.windowNumber context:nil characters:@"?" charactersIgnoringModifiers:@"/" isARepeat:NO keyCode:44];
    [v keyDown:shiftedQuestion];
    id refineEditor=w.firstResponder;
    Check([refineEditor isKindOfClass:[NSTextView class]] && !v->browserListFocus &&
          [v->search.stringValue isEqualToString:@"Bright?"] && v->filter.query=="Bright?" &&
          NSEqualRanges([(NSTextView*)refineEditor selectedRange],NSMakeRange(7,0)),
          "native AppKit receives shifted ? event, not its unshifted / key, and appends to exact existing query");
    Check(v->visible.empty() && v->browserCursorSlug.empty() && v->currentIndex==refineIndex && host->patches==refineLoads &&
          host->on.size()==refineOn && host->off.size()==refineOff,
          "type-to-refine clears removed proposal without loading or piano notes");
    [refineEditor keyDown:Key(w,NSEventTypeKeyDown,@"\t",48)];
    Check(w.firstResponder==v && v->browserListFocus && v->visible.empty(),"empty-results list remains a valid refinement origin");
    [v keyDown:shiftedQuestion];
    refineEditor=w.firstResponder;
    Check([v->search.stringValue isEqualToString:@"Bright??"] && v->filter.query=="Bright??" &&
          NSEqualRanges([(NSTextView*)refineEditor selectedRange],NSMakeRange(8,0)) &&
          host->patches==refineLoads && host->on.size()==refineOn && host->off.size()==refineOff,
          "empty-results printable key appends byte-exact query at end without load or note");
    [refineEditor keyDown:Key(w,NSEventTypeKeyDown,@"\177",51)];
    Snapshot(v,"type-refine-search");
    [refineEditor keyDown:Key(w,NSEventTypeKeyDown,@"\177",51)];
    Check([v->search.stringValue isEqualToString:@"Bright"] && v->filter.query=="Bright",
          "native Search deletion remains native after type-to-refine");
    [w.firstResponder keyDown:Key(w,NSEventTypeKeyDown,@"\t",48)];
    Check(w.firstResponder==v && v->browserListFocus && v->browserCursorSlug.empty(),
          "Tab after refinement returns to list without implicit proposal");
    Snapshot(v,"type-refine-list");
    v->search.stringValue=@"";
    [v controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:v->search]];
    [w makeFirstResponder:v];v->browserListFocus=true;
    [v keyDown:Key(w,NSEventTypeKeyDown,@"b",11,NSEventModifierFlagCommand)];
    Check(w.firstResponder==v && v->search.stringValue.length==0,"modified list shortcut is not turned into Search text");
    Down(v,w,arrow);
    Check(w.firstResponder==v && v->search.stringValue.length==0,"function/navigation key is not turned into Search text");
    [v keyDown:Key(w,NSEventTypeKeyDown,@"B",11,NSEventModifierFlagShift)];
    Check([v->search.stringValue isEqualToString:@"B"] && v->filter.query=="B" && host->patches==refineLoads &&
          host->on.size()==refineOn && host->off.size()==refineOff,"empty-query type-to-refine preserves shifted character and stays inert");
    std::printf("%s keyboard focus host test\n",failures?"FAIL:":"PASS:");
    fflush(stdout);
    // Bypass runner AppKit teardown after capturing assertions and pixels. The
    // original harness crashed in objc_release after printing its final result.
    _Exit(failures ? 1 : 0);
}
int main() {
 @autoreleasepool {
    muew_proof::Watchdog("keyboard focus",90);
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
