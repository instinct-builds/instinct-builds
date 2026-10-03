// Standalone-style editor keyboard/focus contract, run on the macOS CI desktop.
#import <AppKit/AppKit.h>
#import "MUEWEditorView.h"
#import "MUEWMainMenu.h"
#import "MUEWMidiInput.h"
#include "output_gain.h"
#include <cstdio>
#include <algorithm>
#include <cmath>
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
    NSString* path = [[NSString stringWithUTF8String:dir] stringByAppendingPathComponent:[NSString stringWithFormat:@"MUEW-0.106.0-focus-%s.png",name]];
    NSBitmapImageRep* rep = [v bitmapImageRepForCachingDisplayInRect:v.bounds];
    [v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];
    NSData* data = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    Check(data.length > 10000 && [data writeToFile:path atomically:YES], name);
}
// 0.96.0: with the browser closed the tree is the native Search plus the UNDO / REDO buttons; no browser
// control or results list may remain. Checked by content so later header controls do not break it.
static BOOL ClosedAXTree(MUEWEditorView* v) {
    NSArray* ax=[v accessibilityChildren];
    if (ax.count<1 || ax[0]!=v->search) return NO;
    for (NSUInteger i=1;i<ax.count;++i) {
        if ([[ax[i] accessibilityRole] isEqualToString:NSAccessibilityListRole]) return NO;
        NSString* l=[ax[i] accessibilityLabel];
        for (NSString* bad in @[@"Bank:",@"Type:",@"Sort:",@"Close preset browser",@"Back to",@"Surprise",@"Clear all",@"Minimum rating"])
            if ([l hasPrefix:bad]) return NO;
    }
    return YES;
}
static void RunChecks(MUEWEditorView* v, NSWindow* w, KeyboardHost* host) {
    {   // 0.93.0 LFO RATE destination through the real matrix destination menu path
        const auto savedRoutes=v->current.routes; const int savedPage=v->matrixPage; const bool savedEdited=v->edited;
        const auto& dests=muew::ui::matrixDests();
        const int di=(int)(std::find(dests.begin(),dests.end(),muew::ModRoute::Dest::Lfo2Rate)-dests.begin());
        v->current.routes.clear();
        muew::ui::addRoute(v->current.routes,muew::ModRoute::Source::Macro1,muew::ModRoute::Dest::FilterCutoff);
        const double before=muew::ui::routeDisplayAmount(v->current.routes[0]);
        NSMenuItem* pick=[[NSMenuItem alloc] initWithTitle:@"LFO2 RATE" action:nil keyEquivalent:@""];
        pick.tag=(2*100+0)*100+di;
        [v performSelector:NSSelectorFromString(@"menuPicked:") withObject:pick];
        const auto& r0=v->current.routes[0];
        const std::string ro=muew::ui::routeAmountReadout(r0);
        Check(di==34 && r0.dest==muew::ModRoute::Dest::Lfo2Rate && std::fabs(muew::ui::routeDisplayAmount(r0)-before)<1e-9 &&
              ro.size()>4 && ro.compare(ro.size()-4,4," oct")==0 && muew::ui::routeActive(r0),
              "matrix destination menu assigns LFO RATE and the route reads in octaves");
        v->matrixPage=0; [v setNeedsDisplay:YES];
        Snapshot(v,"lfo-rate-route");
        v->current.routes=savedRoutes; v->matrixPage=savedPage; v->edited=savedEdited; [v performSelector:NSSelectorFromString(@"applySound")];
    }
    {   // 0.94.0 envelope TIME destination through the real matrix destination menu path
        const auto savedRoutes=v->current.routes; const int savedPage=v->matrixPage; const bool savedEdited=v->edited;
        const auto& dests=muew::ui::matrixDests();
        const int di=(int)(std::find(dests.begin(),dests.end(),muew::ModRoute::Dest::ModEnvTime)-dests.begin());
        v->current.routes.clear();
        muew::ui::addRoute(v->current.routes,muew::ModRoute::Source::Macro1,muew::ModRoute::Dest::FilterCutoff);
        const double before=muew::ui::routeDisplayAmount(v->current.routes[0]);
        NSMenuItem* pick=[[NSMenuItem alloc] initWithTitle:@"MOD ENV TIME" action:nil keyEquivalent:@""];
        pick.tag=(2*100+0)*100+di;
        [v performSelector:NSSelectorFromString(@"menuPicked:") withObject:pick];
        const auto& r0=v->current.routes[0];
        const std::string ro=muew::ui::routeAmountReadout(r0);
        Check(di==38 && r0.dest==muew::ModRoute::Dest::ModEnvTime && std::fabs(muew::ui::routeDisplayAmount(r0)-before)<1e-9 &&
              ro.size()>4 && ro.compare(ro.size()-4,4," oct")==0 && muew::ui::routeActive(r0),
              "matrix destination menu assigns MOD ENV TIME and the route reads in octaves");
        v->matrixPage=0; [v setNeedsDisplay:YES];
        Snapshot(v,"env-time-route");
        v->current.routes=savedRoutes; v->matrixPage=savedPage; v->edited=savedEdited; [v performSelector:NSSelectorFromString(@"applySound")];
    }
    {   // 0.95.0 LEVEL A destination through the real matrix destination menu path
        const auto savedRoutes=v->current.routes; const int savedPage=v->matrixPage; const bool savedEdited=v->edited;
        const auto& dests=muew::ui::matrixDests();
        const int di=(int)(std::find(dests.begin(),dests.end(),muew::ModRoute::Dest::Osc1Level)-dests.begin());
        v->current.routes.clear();
        muew::ui::addRoute(v->current.routes,muew::ModRoute::Source::Macro1,muew::ModRoute::Dest::FilterCutoff);
        const double before=muew::ui::routeDisplayAmount(v->current.routes[0]);
        NSMenuItem* pick=[[NSMenuItem alloc] initWithTitle:@"LEVEL A" action:nil keyEquivalent:@""];
        pick.tag=(2*100+0)*100+di;
        [v performSelector:NSSelectorFromString(@"menuPicked:") withObject:pick];
        const auto& r0=v->current.routes[0];
        const std::string ro=muew::ui::routeAmountReadout(r0);
        Check(di==40 && r0.dest==muew::ModRoute::Dest::Osc1Level && std::fabs(muew::ui::routeDisplayAmount(r0)-before)<1e-9 &&
              ro.size()>1 && ro.back()=='%' && muew::ui::routeActive(r0),
              "matrix destination menu assigns LEVEL A and the route reads as a percent");
        v->matrixPage=0; [v setNeedsDisplay:YES];
        Snapshot(v,"level-a-route");
        v->current.routes=savedRoutes; v->matrixPage=savedPage; v->edited=savedEdited; [v performSelector:NSSelectorFromString(@"applySound")];
    }
    {   // 0.96.0 UNDO / REDO: real knob drag, Cmd-Z, Shift-Cmd-Z, AX press, header buttons, preset boundary
        const muew::Preset savedCurrent=v->current; const int savedIndex=v->currentIndex; const bool savedEdited=v->edited;
        [v historyReset];
        const muew::Preset before=v->current; 
        auto ME=[&](NSEventType t,NSPoint pt){ return [NSEvent mouseEventWithType:t location:pt modifierFlags:0
            timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:w.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1]; };
        const NSPoint kc=[v knobCenter:0];
        Check([v hitKnob:kc]==0, "knob 0 is hit at its centre for the undo proof");
        [v mouseDown:ME(NSEventTypeLeftMouseDown,kc)];
        NSPoint end=kc; const double kv=muew::ui::knobValue(v->current.voice,0); const int dir=kv>0.5 ? -1 : 1;
        for (int i=1;i<=6;++i) { end=NSMakePoint(kc.x,kc.y+dir*i*8); [v mouseDragged:ME(NSEventTypeLeftMouseDragged,end)]; }
        Check(!v->editHistory.canUndo() && !(v->current==before), "a drag in progress changes the sound but is not yet a step");
        [v mouseUp:ME(NSEventTypeLeftMouseUp,end)];
        const muew::Preset after=v->current;
        Check(v->editHistory.undoSteps()==1 && !(after==before), "one drag is exactly one undo step");
        Snapshot(v,"undo-redo");
        const int patches0=host->patches;
        Check([v performKeyEquivalent:Key(w,NSEventTypeKeyDown,@"z",6,NSEventModifierFlagCommand)] && v->current==before &&
              v->edited==!(before==muew::ui::library().at(v->currentIndex)) && host->patches>patches0 && !v->editHistory.canUndo() && v->editHistory.canRedo(),
              "Cmd-Z restores the sound and the edit marker, and the host receives it");
        Check([v performKeyEquivalent:Key(w,NSEventTypeKeyDown,@"z",6,NSEventModifierFlagCommand|NSEventModifierFlagShift)] &&
              v->current==after && v->edited && v->editHistory.canUndo() && !v->editHistory.canRedo(),
              "Shift-Cmd-Z redoes the drag");
        NSArray* hax=[v accessibilityChildren];
        Check(hax.count==4 && hax[0]==v->search && [[hax[1] accessibilityLabel] isEqualToString:@"Undo last edit, available"] &&
              [[hax[2] accessibilityLabel] isEqualToString:@"Redo edit, nothing to redo"],
              "accessibility tree names Undo and Redo with their state");
        Check([hax[1] accessibilityPerformPress] && v->current==before &&
              [[[v accessibilityChildren][1] accessibilityLabel] isEqualToString:@"Undo last edit, nothing to undo"] &&
              [[[v accessibilityChildren][2] accessibilityLabel] isEqualToString:@"Redo edit, available"],
              "AX press on Undo restores the sound and updates both labels");
        Check([hax[2] accessibilityPerformPress] && v->current==after, "AX press on Redo redoes it");
        NSRect ur=[v undoRect], rr=[v redoRect];
        [v mouseDown:ME(NSEventTypeLeftMouseDown,NSMakePoint(NSMidX(ur),NSMidY(ur)))]; [v mouseUp:ME(NSEventTypeLeftMouseUp,NSMakePoint(NSMidX(ur),NSMidY(ur)))];
        Check(v->current==before, "clicking the UNDO button restores the sound");
        [v mouseDown:ME(NSEventTypeLeftMouseDown,NSMakePoint(NSMidX(rr),NSMidY(rr)))]; [v mouseUp:ME(NSEventTypeLeftMouseUp,NSMakePoint(NSMidX(rr),NSMidY(rr)))];
        Check(v->current==after, "clicking the REDO button redoes it");
        {   // 0.98.0 menu bar: exact structure the standalone installs, validation and actions through the view
            NSMenu* bar=MUEWMakeMainMenu();
            auto item=[&](NSInteger menu,NSString* title)->NSMenuItem* {
                for (NSMenuItem* it in [bar itemAtIndex:menu].submenu.itemArray) if ([it.title isEqualToString:title]) return it;
                return nil; };
            NSMenuItem *quit=item(0,@"Quit MUEW"), *hide=item(0,@"Hide MUEW"), *undoI=item(1,@"Undo"), *redoI=item(1,@"Redo"),
                       *revertI=item(1,@"Revert to Loaded Sound"), *mini=item(2,@"Minimize"), *closeI=item(2,@"Close");
            Check(bar.itemArray.count==3 && [[bar itemAtIndex:0].submenu.title isEqualToString:@"MUEW"] && [[bar itemAtIndex:1].submenu.title isEqualToString:@"Edit"] &&
                  [[bar itemAtIndex:2].submenu.title isEqualToString:@"Window"], "menu bar has the MUEW, Edit and Window menus");
            Check(quit && quit.action==@selector(terminate:) && [quit.keyEquivalent isEqualToString:@"q"] && quit.keyEquivalentModifierMask==NSEventModifierFlagCommand &&
                  hide && [hide.keyEquivalent isEqualToString:@"h"] && mini && [mini.keyEquivalent isEqualToString:@"m"] && closeI && [closeI.keyEquivalent isEqualToString:@"w"],
                  "Quit, Hide, Minimize and Close carry the standard Command keys");
            Check(undoI && redoI && [undoI.keyEquivalent isEqualToString:@"z"] && undoI.keyEquivalentModifierMask==NSEventModifierFlagCommand &&
                  [redoI.keyEquivalent isEqualToString:@"z"] && redoI.keyEquivalentModifierMask==(NSEventModifierFlagCommand|NSEventModifierFlagShift) &&
                  undoI.action==@selector(undo:) && redoI.action==@selector(redo:) && revertI.action==@selector(revertSound:),
                  "Edit has Undo (Cmd-Z), Redo (Shift-Cmd-Z) and Revert wired to the editor actions");
            Check([v validateMenuItem:undoI]==v->editHistory.canUndo() && [v validateMenuItem:redoI]==v->editHistory.canRedo() &&
                  [v validateMenuItem:revertI]==[v canRevert], "menu items enable exactly when the editor can act");
            const muew::Preset menuBefore=v->current;
            [v undo:undoI];
            Check(!(v->current==menuBefore), "Edit > Undo goes through the same history");
            [v redo:redoI];
            Check(v->current==menuBefore, "Edit > Redo restores the edit");
        }
        {   // 0.99.0 hardware MIDI input: a real CoreMIDI virtual source into MUEWMidiInput, bounded by 3 s waits
            NSMutableArray* got=[NSMutableArray array];
            MUEWMidiInput* in=[[MUEWMidiInput alloc] initWithHandler:^(const muew::MidiEvent& e){
                @synchronized(got) { [got addObject:@[@((int)e.kind),@(e.note),@(e.value)]]; } }];
            auto pump=[](double s){ [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:s]]; };
            MIDIClientRef pc=0; MIDIEndpointRef src=0; OSStatus ce=noErr, se=noErr;
            if (in.available) { ce=MIDIClientCreate(CFSTR("MUEW proof client"),NULL,NULL,&pc); se=ce==noErr ? MIDISourceCreate(pc,CFSTR("MUEW proof source"),&src) : ce; }
            if (!in.available) printf("SKIP: CoreMIDI client unavailable on this runner\n");
            else if (se!=noErr) printf("SKIP: cannot create a virtual MIDI source (%d)\n",(int)se);
            else {
                const int base=in.connectedSources;
                NSDate* until=[NSDate dateWithTimeIntervalSinceNow:3.0];
                while (in.connectedSources<=base && until.timeIntervalSinceNow>0) { [in refresh]; pump(0.05); }
                Check(in.connectedSources>base, "the input connects a newly appearing MIDI source");
                Byte buf[256]; MIDIPacketList* pl=(MIDIPacketList*)buf; MIDIPacket* pk=MIDIPacketListInit(pl);
                const Byte msg[]={0x90,60,100, 0xB0,1,127, 0xE0,127,127, 0xC0,5, 0xB0,7,64};
                pk=MIDIPacketListAdd(pl,sizeof buf,pk,0,sizeof msg,msg); (void)pk;
                MIDIReceived(src,pl);
                until=[NSDate dateWithTimeIntervalSinceNow:3.0];
                while (until.timeIntervalSinceNow>0) { @synchronized(got) { if (got.count>=5) break; } pump(0.05); }
                NSArray* ev; @synchronized(got) { ev=[got copy]; }
                auto F=[&](NSUInteger i,NSUInteger j)->double { return [[(NSArray*)[ev objectAtIndex:i] objectAtIndex:j] doubleValue]; };
                Check(ev.count==5 && (int)F(4,0)==muew::MidiEvent::Volume && fabs(F(4,2)-64/127.0)<1e-6 && (int)F(3,0)==muew::MidiEvent::Program && (int)F(3,1)==5 && (int)F(0,0)==muew::MidiEvent::NoteOn && (int)F(0,1)==60 && fabs(F(0,2)-100/127.0)<1e-6 &&
                      (int)F(1,0)==muew::MidiEvent::Wheel && F(1,2)==1.0 &&
                      (int)F(2,0)==muew::MidiEvent::Bend && fabs(F(2,2)-1.0)<1e-6,
                      "a note, a mod wheel, a pitch bend, a program change and a volume sent to a virtual source arrive parsed, in order");
                { // 0.105.0 volume chain: the event that arrived drives the same OutputGain the standalone renders through
                    muew::OutputGain g; float l[64], r[64]; for (int i=0;i<64;i++) l[i]=r[i]=1.0f;
                    if (ev.count==5) g.setFromMidi((float)F(4,2));
                    const float want=muew::midiVolumeGain(64/127.0f);
                    Check(fabs(g.target()-want)<1e-6 && want>0.2f && want<0.3f, "the arrived CC7 sets the gain target to its tapered value");
                    g.apply(l,r,64);
                    Check(fabs(l[63]-want)<1e-6 && fabs(r[63]-want)<1e-6 && l[0]>want && l[0]<1.0f, "the first block ramps from unity to the target without a jump");
                    for (int i=0;i<64;i++) l[i]=r[i]=1.0f; g.apply(l,r,64);
                    Check(fabs(l[0]-want)<1e-6 && fabs(l[63]-want)<1e-6, "the next block holds the target");
                }
                MIDIEndpointDispose(src); MIDIClientDispose(pc);
            }
        }
        // 0.97.0 REVERT: back to the loaded sound as one undoable step
        v->current.voice.osc2Level+=v->current.voice.osc2Level>0.5 ? -0.3 : 0.3; v->edited=true; [v voiceParamEdited:-1];
        Check([v canRevert] && [[[v accessibilityChildren][3] accessibilityLabel] isEqualToString:@"Revert to loaded sound, available"],
              "an edited sound can be reverted and the control says so");
        Snapshot(v,"revert-available");
        const muew::Preset editedState=v->current; const size_t stepsBefore=v->editHistory.undoSteps();
        NSRect vr=[v revertRect];
        [v mouseDown:ME(NSEventTypeLeftMouseDown,NSMakePoint(NSMidX(vr),NSMidY(vr)))]; [v mouseUp:ME(NSEventTypeLeftMouseUp,NSMakePoint(NSMidX(vr),NSMidY(vr)))];
        Check(v->current==muew::ui::library().at(v->currentIndex) && !v->edited && ![v canRevert] && v->editHistory.undoSteps()==stepsBefore+1 &&
              [[[v accessibilityChildren][3] accessibilityLabel] isEqualToString:@"Revert to loaded sound, nothing to revert"],
              "clicking REVERT restores the loaded sound as one step and clears the edit marker");
        Check([v performKeyEquivalent:Key(w,NSEventTypeKeyDown,@"z",6,NSEventModifierFlagCommand)] && v->current==editedState && v->edited && [v canRevert],
              "Cmd-Z brings the edits back after a revert");
        Check([[v accessibilityChildren][3] accessibilityPerformPress] && v->current==muew::ui::library().at(v->currentIndex) && !v->edited,
              "AX press on Revert does the same");
        const int other=(savedIndex+1)%muew::ui::library().count();
        [v adoptPreset:muew::ui::library().at(other) index:other edited:false];
        Check(!v->editHistory.canUndo() && !v->editHistory.canRedo(), "another sound is the undo boundary");
        [v adoptPreset:savedCurrent index:savedIndex edited:savedEdited]; [v historyReset];
    }
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
    Check(ax.count==37 && ax[0]==v->search && [[ax[26] accessibilityRole] isEqualToString:NSAccessibilityListRole] &&
          [[ax[26] accessibilityLabel] isEqualToString:@"Preset results"],
          "accessibility tree exposes native Search, navigation and named results list");
    id list=ax.count>26 ? ax[26] : nil;
    id bankFactory=ax.count>2 ? ax[2] : nil;
    id typeLead=ax.count>7 ? ax[7] : nil;
    id sortName=ax.count>15 ? ax[15] : nil;
    Check([[bankFactory accessibilityLabel] containsString:@"Bank: Factory"] &&
          [[typeLead accessibilityLabel] containsString:@"Type: Lead"] &&
          [[sortName accessibilityLabel] containsString:@"Sort: Name"],
          "accessible navigation controls have exact names and stable order");
    id favorite=ax[32], rating=ax[29];
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
        auto clickStar=[&](int star) {
            NSRect r=[v minRatingStar:star];
            NSEvent* e=[NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:NSMakePoint(NSMidX(r),NSMidY(r)) modifierFlags:0
                timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:w.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
            [v mouseDown:e];
        };
        const int onCount=(int)host->on.size();
        clickStar(2);
        const bool setThree=v->filter.minRating==3;
        bool allThree=true;
        for (int idx : v->visible) allThree=allThree && muew::ui::ratingOf(v->ratings,muew::ui::library().slug(idx))>=3;
        clickStar(2);
        const bool cleared=v->filter.minRating==0 && v->visible.size()==before;
        clickStar(4);
        Check(setThree && allThree && cleared && v->filter.minRating==5 && host->patches==floorPatches && (int)host->on.size()==onCount,
              "native mouseDown on minimum-rating stars sets, clears and re-sets the floor without load or note");
        clickStar(4);
        Check(v->filter.minRating==0,"native mouseDown on the lit star clears the floor");
        {   // 0.89.0 SURPRISE ME: loads a visible, different sound exactly once, by AX and by native click
            id surprise=[v accessibilityChildren][24];
            const int surpriseOrigin=v->currentIndex;
            v->filter=muew::PresetFilter(); v->filter.category="Lead"; [v refilter];
            std::set<int> allowed(v->visible.begin(),v->visible.end());
            Check(v->visible.size()>2 && [[surprise accessibilityLabel] hasPrefix:@"Surprise me, load a random sound from "],
                  "surprise control names the shown count");
            bool inside=true,moved=true; int loads=0;
            for (int n=0;n<8;++n) {
                const int was=v->currentIndex, p0=host->patches, on0=(int)host->on.size();
                bool pressed=[surprise accessibilityPerformPress];
                inside=inside && pressed && allowed.count(v->currentIndex);
                moved=moved && v->currentIndex!=was && host->patches==p0+1 && (int)host->on.size()==on0;
                loads+=host->patches-p0;
            }
            Check(inside && moved && loads==8,"surprise AX press loads one visible different sound each time without playing a note");
            NSRect sr=[v browserSurpriseRect];
            NSEvent* se=[NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:NSMakePoint(NSMidX(sr),NSMidY(sr)) modifierFlags:0
                timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:w.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
            const int wasN=v->currentIndex, pN=host->patches;
            [v mouseDown:se];
            Check(v->currentIndex!=wasN && allowed.count(v->currentIndex) && host->patches==pN+1,"native mouseDown on SURPRISE ME loads one visible sound");
            {   // 0.90.0 BACK: steps through previous sounds newest first, never pushes itself, loads exactly once per press
                id back=[v accessibilityChildren][25];
                v->loadBack.clear(); [v refilter];
                Check([[back accessibilityLabel] isEqualToString:@"Back to previous sound, nothing earlier"] && ![back accessibilityPerformPress],
                      "back is inert with no history");
                const int a0=v->currentIndex;
                [surprise accessibilityPerformPress]; const int b0=v->currentIndex;
                [surprise accessibilityPerformPress];
                Snapshot(v,"back-active");
                const int pB=host->patches, onB=(int)host->on.size();
                const bool first=[back accessibilityPerformPress] && v->currentIndex==b0 && host->patches==pB+1;
                const bool second=[back accessibilityPerformPress] && v->currentIndex==a0 && host->patches==pB+2;
                const bool third=![back accessibilityPerformPress] && v->currentIndex==a0 && host->patches==pB+2;
                Check(first && second && third && v->loadBack.empty() && (int)host->on.size()==onB &&
                      [[back accessibilityLabel] isEqualToString:@"Back to previous sound, nothing earlier"],
                      "back AX press restores previous sounds newest first, loads once each, adds no history, plays no note");
                [surprise accessibilityPerformPress]; const int c0=v->currentIndex;
                NSRect brr=[v browserBackRect];
                NSEvent* be=[NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:NSMakePoint(NSMidX(brr),NSMidY(brr)) modifierFlags:0
                    timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:w.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
                const int pC=host->patches;
                [v mouseDown:be];
                Check(c0!=a0 && v->currentIndex==a0 && host->patches==pC+1,"native mouseDown on BACK restores the previous sound");
                (void)c0;
            }
            {   // 0.91.0 row heart: toggles that row's favorite without loading, selecting or playing
                v->filter=muew::PresetFilter(); v->filter.category="Lead"; v->sortMode=muew::ui::SortName; v->bscroll=0; [v refilter];
                const int rowIdx=v->visible[0]; const std::string rowSlug=muew::ui::library().slug(rowIdx);
                const bool wasFav=v->favorites.count(rowSlug)>0;
                const int loadedBefore=v->currentIndex, pH=host->patches, onH=(int)host->on.size();
                NSRect hr=[v rowHeart:0];
                auto clickHeart=[&]{
                    NSEvent* he=[NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:NSMakePoint(NSMidX(hr),NSMidY(hr)) modifierFlags:0
                        timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:w.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
                    [v mouseDown:he];
                };
                clickHeart();
                const bool flipped=(v->favorites.count(rowSlug)>0)!=wasFav;
                Snapshot(v,"row-heart");
                const int rowAfter=v->visible.empty() ? -1 : v->visible[0];
                (void)rowAfter;
                clickHeart();
                Check(flipped && (v->favorites.count(rowSlug)>0)==wasFav && v->currentIndex==loadedBefore &&
                      host->patches==pH && (int)host->on.size()==onH,
                      "native mouseDown on a row heart toggles that sound's favorite twice without loading or playing");
                v->favorites=savedFavorites; [v saveFavorites];
                v->filter=muew::PresetFilter(); v->filter.category="Lead"; v->sortMode=muew::ui::SortBank; [v refilter];
            }
            v->search.stringValue=@"zzzz-no-match"; v->filter.query="zzzz-no-match"; [v refilter];
            const int emptyIdx=v->currentIndex, emptyP=host->patches;
            Check(v->visible.empty() && ![surprise accessibilityPerformPress] && v->currentIndex==emptyIdx && host->patches==emptyP,
                  "surprise with no results is inert");
            Snapshot(v,"surprise-empty");
            v->filter=muew::PresetFilter(); v->search.stringValue=@""; [v refilter];
            Snapshot(v,"surprise-all");
            [v loadPresetIndex:surpriseOrigin]; [v refilter];
        }
        {   // 0.88.0 CLEAR FILTERS: nothing to clear is inert; real filters clear together, via AX and native click
            id clear=[v accessibilityChildren][23];
            const int clearPatches=host->patches; const int clearOn=(int)host->on.size();
            Check([[clear accessibilityLabel] isEqualToString:@"Clear all filters, nothing to clear"] && ![clear accessibilityPerformPress],
                  "clear filters is inert with no filter active");
            const auto keepRatings=v->ratings; const int keepSort=v->sortMode;
            v->filter.category="Lead"; v->filter.favoritesOnly=true; v->filter.tags={"bright"}; v->filter.bank=muew::ui::BankFactory;
            muew::ui::setMinRating(v->filter,2); v->search.stringValue=@"Br"; v->filter.query="Br"; [v refilter];
            Snapshot(v,"clear-filters-active");
            Check([[clear accessibilityLabel] isEqualToString:@"Clear all filters, available"] && [clear accessibilityPerformPress] &&
                  v->filter.category.empty() && !v->filter.favoritesOnly && v->filter.tags.empty() && v->filter.bank==-1 &&
                  v->filter.minRating==0 && v->filter.query.empty() && [v->search.stringValue length]==0 &&
                  (int)v->visible.size()==muew::ui::library().count() && v->sortMode==keepSort && v->ratings==keepRatings &&
                  host->patches==clearPatches && (int)host->on.size()==clearOn,
                  "clear filters AX press resets every filter and the query, keeps sort and ratings, loads nothing");
            v->filter.tags={"dark"}; v->filter.query="x"; v->search.stringValue=@"x"; [v refilter];
            NSRect cr=[v browserClearRect];
            NSEvent* ce=[NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:NSMakePoint(NSMidX(cr),NSMidY(cr)) modifierFlags:0
                timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:w.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
            [v mouseDown:ce];
            Check(v->filter.tags.empty() && v->filter.query.empty() && [v->search.stringValue length]==0 &&
                  host->patches==clearPatches && (int)host->on.size()==clearOn,
                  "native mouseDown on CLEAR FILTERS resets filters without load or note");
        }
        v->ratings=savedRatings; v->sortMode=muew::ui::SortBank; [v refilter];
    }
    ax=[v accessibilityChildren]; favorite=ax[32]; rating=ax[29]; // loads in the blocks above retire older loaded-sound controls
    const int sound=v->currentIndex, patches=host->patches;
    const std::string loadedSlug=muew::ui::library().slug(sound);
    [v moveBrowserCursor:1];
    Check([favorite accessibilityPerformPress] && v->favorites.count(loadedSlug)!=savedFavorites.count(loadedSlug) &&
          host->patches==patches && v->currentIndex==sound,
          "favorite targets loaded sound, not proposed row, without loading");
    Check([rating accessibilityPerformPress] && muew::ui::ratingOf(v->ratings,loadedSlug)==(muew::ui::ratingOf(savedRatings,loadedSlug)==3 ? 0 : 3) &&
          favorite==[v accessibilityChildren][32],"rating shares loaded-sound path and survives refilter");
    Snapshot(v,"accessible-detail");
    [v loadPresetIndex:(sound+1)%muew::ui::library().count()];
    Check(![favorite accessibilityPerformPress] && ![rating accessibilityPerformPress],
          "retained loaded-sound controls refuse to target newly loaded preset");
    [v loadPresetIndex:sound];
    v->favorites=savedFavorites; v->ratings=savedRatings; [v saveFavorites]; [v saveRatings]; [v refilter];
    for (int index=33;index<=35;++index) {
        const char* phase=index==33 ? "Save dialog launch" : index==34 ? "Import dialog launch" : "Export dialog launch";
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
    {   // 0.92.0 sort direction: the active header reverses; a new column starts at its natural direction
        const std::vector<int> asc=v->visible; std::vector<int> expectDesc(asc.rbegin(),asc.rend());
        const int pS=host->patches, onS=(int)host->on.size();
        Check(asc.size()>2 && !v->sortReverse && [[sortName accessibilityLabel] isEqualToString:@"Sort: Name, selected, ascending"],
              "active Name sort starts ascending");
        [sortName accessibilityPerformPress];
        Check(v->sortReverse && v->visible==expectDesc && [[sortName accessibilityLabel] isEqualToString:@"Sort: Name, selected, descending"] &&
              v->currentIndex==original && host->patches==pS,"second Name press reverses the list without loading");
        Snapshot(v,"sort-reverse");
        auto clickHeader=[&](int c){
            NSRect r=[v tableHeader:c];
            NSEvent* e=[NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:NSMakePoint(NSMidX(r),NSMidY(r)) modifierFlags:0
                timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:w.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
            [v mouseDown:e];
        };
        clickHeader(1);
        Check(!v->sortReverse && v->visible==asc,"native click on the active header restores ascending order");
        clickHeader(1); clickHeader(2);
        Check(v->sortMode==muew::ui::SortCategory && !v->sortReverse,"choosing another column starts at its natural direction");
        id sortRating=[v accessibilityChildren][17];
        clickHeader(4);
        Check(v->sortMode==muew::ui::SortRating && !v->sortReverse && [[sortRating accessibilityLabel] isEqualToString:@"Sort: Rating, selected, descending"],
              "Rating starts descending");
        [sortRating accessibilityPerformPress];
        Check(v->sortReverse && [[sortRating accessibilityLabel] isEqualToString:@"Sort: Rating, selected, ascending"] &&
              (int)host->on.size()==onS && host->patches==pS && v->currentIndex==original,"Rating reverses to ascending without load or note");
        v->sortMode=muew::ui::SortName; v->sortReverse=false; [v refilter];
    }
    [v setBrowserOpen:false];
    Check(ClosedAXTree(v) && ![retainedBank accessibilityPerformPress],
          "closed navigation disappears and retained control refuses press");
    [v setBrowserOpen:true];
    v->filter.bank=-1; v->filter.category=""; v->sortMode=muew::ui::SortBank; [v refilter];
    ax=[v accessibilityChildren]; list=ax[26];
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
    Check(ClosedAXTree(v) && ![target accessibilityPerformPress],
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
