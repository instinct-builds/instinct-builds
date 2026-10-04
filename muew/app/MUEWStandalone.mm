#include "../tests/proof_watchdog.h"
// MUEWStandalone.mm - MUEW standalone instrument: the shared editor view
// bound directly to an in-process synth, with the computer keyboard as a
// MIDI keyboard.
#import <AppKit/AppKit.h>
#import <AVFoundation/AVFoundation.h>
#import "MUEWEditorView.h"
#import "MUEWMainMenu.h"
#import "MUEWMidiInput.h"
#include "synth.h"
#include "output_gain.h"
#include "perf_state.h"
#include "session_state.h"
#include <mutex>
#include <atomic>
#include <chrono>
#include <algorithm>

using namespace muew;

static bool gSessionNoSave = false; // 0.101.0 relaunch proof only
static muew::PerfTracker gPerf; // 0.107.0: what the editor shows as wheel / pressure / bend / last note / sustain
static muew::OutputGain gOutGain; // 0.104.0 / 0.105.0: MIDI CC7 output gain, standalone only
static std::atomic<float> gCpu{0}; // 0.30.0 header meter: smoothed real-time load
static std::atomic<int> gVoices{0};
static std::atomic<float> gMorphA{-1.0f}, gMorphB{-1.0f}; // 0.35.0 live morph meter
static std::atomic<float> gOutputPeak[2]{}; static std::atomic<float> gMasterDrive{0}; // 0.58.0
static std::atomic<float> gRouteMin[kMaxRoutes]{}, gRouteMax[kMaxRoutes]{};
static std::atomic<float> gRouteMeter[kMaxRoutes]{}; // 0.54.0
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
    bool supportsMidiLearn() const override { return true; } // 0.118.0: one global per-user CC map, outside presets and sessions
    std::string midiMapText() const override {
        NSString* t = [[NSUserDefaults standardUserDefaults] stringForKey:@"MUEWMidiMap"];
        return t ? std::string([t UTF8String]) : std::string();
    }
    void setMidiMapText(const std::string& s) override { [[NSUserDefaults standardUserDefaults] setObject:[NSString stringWithUTF8String:s.c_str()] forKey:@"MUEWMidiMap"]; }
    bool hasOutputVolume() const override { return true; } // 0.117.0
    float outputVolume() const override { return gOutGain.position(); }
    void setOutputVolume(float p) override { gOutGain.setPosition(p); }
    bool playsNotes() const override { return true; }
    void noteOn(int n, float v) override { gPerf.noteFromKeyboard(n); std::lock_guard<std::mutex> g(*lock); synth->noteOn(n, v); }
    void noteOff(int n) override { std::lock_guard<std::mutex> g(*lock); synth->noteOff(n); }
    void allNotesOff() override { gPerf.apply(muew::MidiEvent{muew::MidiEvent::AllNotesOff, 0, 0.0f}); std::lock_guard<std::mutex> g(*lock); synth->allNotesOff(); } // 0.109.0
};

@interface AppDelegate : NSObject <NSApplicationDelegate> {
    NSWindow* w; MUEWEditorView* v; StandaloneHost* binding; AVAudioEngine* engine; AVAudioSourceNode* source; Synth synth; std::mutex lock; MUEWMidiInput* midi; NSTimer* meter; NSMutableArray* pendingOpen;
}
@end

@implementation AppDelegate
- (void)applicationDidFinishLaunching:(NSNotification*)n {
    NSMenu* bar = MUEWMakeMainMenu(); // 0.98.0: Quit, Hide, Minimize, Close, Edit > Undo / Redo / Revert
    [NSApp setMainMenu:bar];
    [NSApp setWindowsMenu:[bar itemAtIndex:4].submenu];
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
    [v reloadMidiMap]; // 0.118.0
    w.contentView = v;
    int start = ui::indexOfSlug("formant-talker");
    // 0.100.0: reopen on the sound that was on screen at quit. The proof launches keep their fixed start.
    if (getenv("MUEW_AX_PROOF") || getenv("MUEW_AX_CONTROL") || getenv("MUEW_NO_SESSION") || ![self restoreSession])
        [v loadPresetIndex:start >= 0 ? start : 0];
    // 0.112.0: a .muew opened from Finder / the Dock (or the CI proof's MUEW_OPEN_FILE) imports and loads after the usual start.
    if (const char* of = getenv("MUEW_OPEN_FILE")) { if (!pendingOpen) pendingOpen = [NSMutableArray array]; [pendingOpen addObject:[NSString stringWithUTF8String:of]]; }
    for (NSString* f in pendingOpen) [v importPresetFile:f];
    pendingOpen = nil;
    // Only the AX IPC proof launch opts into an open browser. Normal launches
    // and AU embedding retain their existing initial state.
    if (getenv("MUEW_AX_PROOF")) { muew_proof::Watchdog("AX standalone target",150); [v setBrowserOpen:true]; }
    const char* axControl=getenv("MUEW_AX_CONTROL");
    if (axControl && *axControl) {
        NSString* request=[NSString stringWithUTF8String:axControl];
        NSString* response=[request stringByAppendingString:@".ack"];
        __block NSString* last=@"";
        [NSTimer scheduledTimerWithTimeInterval:0.05 repeats:YES block:^(NSTimer*) {
            NSString* line=[NSString stringWithContentsOfFile:request encoding:NSUTF8StringEncoding error:nil];
            if (!line || [line isEqualToString:last]) return;
            last=line;
            if ([line hasSuffix:@" filter-none"]) {
                v->filter.query="no-such-sound-987"; [v refilter];
            } else if ([line hasSuffix:@" filter-clear"]) {
                v->filter.query=""; [v refilter];
            } else if ([line hasSuffix:@" cursor-down"]) {
                [v moveBrowserCursor:1];
            }
            [line writeToFile:response atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }];
    }
    [w center];
    // 0.103.0: reopen where the window was left (position only; the editor has a fixed size). Proof launches stay centered.
    if (!getenv("MUEW_AX_PROOF") && !getenv("MUEW_AX_CONTROL") && !getenv("MUEW_NO_SESSION") && !getenv("MUEW_SESSION_REPORT")) [w setFrameAutosaveName:@"MUEWMainWindow"];
    [w makeKeyAndOrderFront:nil]; [w makeFirstResponder:v];
    // 0.101.0 relaunch proof: MUEW_SESSION_REPORT=<file> writes what the editor shows after launch, optionally
    // after MUEW_SESSION_STEP=edit (change the cutoff, as an editor edit would) or =corrupt (store garbage and
    // do not overwrite it at quit), then quits through the normal terminate path. Hard 60 s exit.
    if (const char* rep = getenv("MUEW_SESSION_REPORT")) {
        muew_proof::Watchdog("session relaunch proof", 60);
        NSString* path = [NSString stringWithUTF8String:rep];
        const char* stepc = getenv("MUEW_SESSION_STEP");
        std::string step = stepc ? stepc : "";
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (step == "edit") { v->current.voice.filterCutoff = 777; binding->applyPreset(v->current, v->currentIndex, true); }
            // 0.118.0 MIDI learn relaunch proof: learn CC74 on CUTOFF; next launch a CC74 must move it; then clear.
            const double cutoff0 = v->current.voice.filterCutoff;
            if (step == "learn") { [v beginMidiLearn:ui::Cutoff]; [v midiController:74 value:0.5f]; }
            if (step == "cc") [v midiController:74 value:1.0f];
            if (step == "clear") [v clearMidiMappings:nil];
            if (step == "corrupt") {
                gSessionNoSave = true;
                [[NSUserDefaults standardUserDefaults] setObject:@"not a session" forKey:@"MUEWSession"];
                [[NSUserDefaults standardUserDefaults] synchronize];
            }
            const bool edited = v->currentIndex >= 0 ? !(v->current == ui::library().at(v->currentIndex)) : true;
            NSString* line = [NSString stringWithFormat:@"name=%s index=%d cutoff=%d edited=%d cutoff0=%d midimap=%s\n",
                              v->current.info.name.c_str(), v->currentIndex, (int)v->current.voice.filterCutoff, edited ? 1 : 0, (int)cutoff0, v->midiMap.encode().c_str()];
            [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
            [NSApp terminate:nil];
        });
    }
    engine = [AVAudioEngine new];
    AVAudioFormat* fmt = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100 channels:2];
    Synth* s = &synth; std::mutex* l = &lock;
    source = [[AVAudioSourceNode alloc] initWithRenderBlock:^OSStatus(BOOL* silence, const AudioTimeStamp* t, AVAudioFrameCount count, AudioBufferList* out) {
        float* left = (float*)out->mBuffers[0].mData;
        float* right = (float*)out->mBuffers[1].mData;
        std::lock_guard<std::mutex> g(*l);
        const auto t0 = std::chrono::steady_clock::now(); // 0.30.0 header meter
        s->renderPlanar(left, right, (int)count);
        gOutGain.apply(left, right, (int)count); // 0.104.0: CC7 gain after the synth
        gOutputPeak[0] = s->outputMeter().left; gOutputPeak[1] = s->outputMeter().right;
        gMasterDrive = s->outputMeter().drive;
        const double used = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count(), budget = count / 44100.0;
        if (budget > 0) { const float c = gCpu.load(); gCpu = c + 0.1f * ((float)std::min(used / budget, 4.0) - c); }
        gVoices = s->activeVoiceCount();
        for (int i = 0; i < kMaxRoutes; ++i) { gRouteMeter[i] = s->routeMeter(i); gRouteMin[i] = s->routeMin(i); gRouteMax[i] = s->routeMax(i); }
        gMorphA = s->specMorphMeter(0); gMorphB = s->specMorphMeter(1); // 0.35.0
        for (int o = 0; o < 2; ++o) { float vm[8]; const int n = s->specMorphVoices(o, vm, 8); for (int i = 0; i < 8; ++i) gVoiceMorph[o][i] = i < n ? vm[i] : -1.0f; gVoiceMorphN[o] = n; }
        return noErr;
    }];
    [engine attachNode:source];
    [engine connect:source to:engine.mainMixerNode format:fmt];
    NSError* err = nil;
    [engine startAndReturnError:&err];
    // 0.106.0: a device change (headphones, AirPods, a display's speakers) stops the engine; bring it back on the new route.
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioConfigChanged:) name:AVAudioEngineConfigurationChangeNotification object:engine];
    if (const char* erep = getenv("MUEW_ENGINE_REPORT")) { // CI proof: stop the engine, post the change, report whether it came back
        muew_proof::Watchdog("engine restart proof", 30);
        NSString* path = [NSString stringWithUTF8String:erep]; AVAudioEngine* eng = engine;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (!eng.isRunning) { [@"before=0 SKIP no running audio engine on this runner\n" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]; [NSApp terminate:nil]; return; }
            [eng stop];
            const bool stopped = !eng.isRunning;
            [[NSNotificationCenter defaultCenter] postNotificationName:AVAudioEngineConfigurationChangeNotification object:eng];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                NSString* line = [NSString stringWithFormat:@"before=1 stopped=%d after=%d\n", stopped ? 1 : 0, eng.isRunning ? 1 : 0];
                [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
                [NSApp terminate:nil];
            });
        });
    }
    // 0.99.0: hardware MIDI keyboards and controllers play the standalone (all channels).
    MUEWEditorView* view0 = v;
    midi = [[MUEWMidiInput alloc] initWithHandler:^(const MidiEvent& e) {
        gPerf.apply(e); // 0.107.0
        std::lock_guard<std::mutex> g(*l);
        switch (e.kind) {
        case MidiEvent::NoteOn: s->noteOn(e.note, e.value); break;
        case MidiEvent::NoteOff: s->noteOff(e.note); break;
        case MidiEvent::Wheel: s->setModWheel(e.value); break;
        case MidiEvent::Aftertouch: s->setAftertouch(e.value); break;
        case MidiEvent::PolyAftertouch: s->setPolyAftertouch(e.note, e.value); break;
        case MidiEvent::Bend: s->setPitchBend(e.value); break;
        case MidiEvent::Sustain: s->setSustain(e.value > 0.5f); break;
        case MidiEvent::AllNotesOff: s->allNotesOff(); break;
        case MidiEvent::Volume: gOutGain.setFromMidi(e.value); break; // 0.104.0
        case MidiEvent::Controller: { // 0.118.0: MIDI learn; the editor owns the map, on the main thread
            const int cc = e.note; const float val = e.value; MUEWEditorView* vw = view0;
            dispatch_async(dispatch_get_main_queue(), ^{ [vw midiController:cc value:val]; });
            break; }
        case MidiEvent::Program: { // 0.102.0: program N is factory sound N; off the main thread, after the lock is released
            const int prog = e.note; MUEWEditorView* vw = view0;
            if (prog < kFactoryPresetCount) dispatch_async(dispatch_get_main_queue(), ^{ [vw loadPresetIndex:prog]; });
            break; }
        }
    }];
    // 0.119.0 CI proof of the real MIDI path: MUEW_MIDI_PROOF=<file> creates an in-process virtual MIDI source, learns CC74 on
    // CUTOFF from a CoreMIDI packet (CoreMIDI thread -> main thread dispatch -> editor), then a second packet must move CUTOFF.
    if (const char* mrep = getenv("MUEW_MIDI_PROOF")) {
        muew_proof::Watchdog("CoreMIDI learn proof", 40);
        NSString* path = [NSString stringWithUTF8String:mrep]; MUEWMidiInput* in = midi; MUEWEditorView* vw = v;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            void (^finish)(NSString*) = ^(NSString* line) { [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]; [NSApp terminate:nil]; };
            if (!in.available) { finish(@"SKIP no CoreMIDI client on this runner\n"); return; }
            MIDIClientRef pc = 0; MIDIEndpointRef src = 0;
            const OSStatus ce = MIDIClientCreate(CFSTR("MUEW proof client"), NULL, NULL, &pc);
            const OSStatus se = ce == noErr ? MIDISourceCreate(pc, CFSTR("MUEW proof source"), &src) : ce;
            if (se != noErr) { finish([NSString stringWithFormat:@"SKIP cannot create a virtual MIDI source (%d)\n", (int)se]); return; }
            void (^sendCC)(Byte, Byte) = ^(Byte cc, Byte val) {
                Byte buf[64]; MIDIPacketList* pl = (MIDIPacketList*)buf; MIDIPacket* pk = MIDIPacketListInit(pl);
                const Byte msg[] = {0xB0, cc, val}; pk = MIDIPacketListAdd(pl, sizeof buf, pk, 0, sizeof msg, msg); (void)pk;
                MIDIReceived(src, pl);
            };
            const int base = in.connectedSources;
            __block int phase = 0; __block NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:3.0];
            __block int learned = 0, moved = 0, connected = 0;
            [NSTimer scheduledTimerWithTimeInterval:0.05 repeats:YES block:^(NSTimer* t) {
                const bool late = deadline.timeIntervalSinceNow < 0;
                if (phase == 0) { // wait for the input to connect the new source
                    [in refresh];
                    if (in.connectedSources > base) { connected = 1; [vw beginMidiLearn:ui::Cutoff]; sendCC(74, 64); phase = 1; deadline = [NSDate dateWithTimeIntervalSinceNow:3.0]; }
                    else if (late) phase = 3;
                } else if (phase == 1) { // the packet must bind CC74 to CUTOFF
                    if (vw->midiMap.paramFor(74) == ui::knobParam(ui::Cutoff) && vw->learnKnob < 0) {
                        learned = 1; vw->current.voice.filterCutoff = 1000; sendCC(74, 127); phase = 2; deadline = [NSDate dateWithTimeIntervalSinceNow:3.0];
                    } else if (late) phase = 3;
                } else if (phase == 2) { // and the next one must move it
                    if (vw->current.voice.filterCutoff > 17999) { moved = 1; phase = 3; } else if (late) phase = 3;
                }
                if (phase == 3) {
                    [t invalidate];
                    finish([NSString stringWithFormat:@"connected=%d learned=%d moved=%d cutoff=%d map=%s\n", connected, learned, moved, (int)vw->current.voice.filterCutoff, vw->midiMap.encode().c_str()]);
                }
            }];
        });
    }
    MUEWEditorView* view = v; // 0.30.0: feed the header voice / CPU meter
    meter = [NSTimer scheduledTimerWithTimeInterval:1.0 / 15 repeats:YES block:^(NSTimer*) {
        const auto& vp = view->current.voice;
        [view showPerformance:gPerf.snapshot() note:gPerf.lastNote() sustain:gPerf.sustain()]; // 0.107.0: hardware wheel / bend / pressure / sustain are visible
        [view showEngineVoices:gVoices.load() limit:vp.voiceMode != 0 ? 1 : vp.polyVoices cpu:gCpu.load() render:false];
        [view showOutputLeft:gOutputPeak[0].load() right:gOutputPeak[1].load() drive:gMasterDrive.load()];
        float route[kMaxRoutes]; for (int i = 0; i < kMaxRoutes; ++i) route[i] = gRouteMeter[i].load();
        [view showRouteMeters:route count:kMaxRoutes]; // 0.54.0
        float lo[kMaxRoutes], hi[kMaxRoutes]; for (int i = 0; i < kMaxRoutes; ++i) { lo[i] = gRouteMin[i].load(); hi[i] = gRouteMax[i].load(); }
        [view showRouteMin:lo max:hi count:kMaxRoutes];
        [view showLiveMorphA:gMorphA.load() b:gMorphB.load()]; // 0.35.0
        float va[8], vb[8]; for (int i = 0; i < 8; ++i) { va[i] = gVoiceMorph[0][i].load(); vb[i] = gVoiceMorph[1][i].load(); }
        [view showVoiceMorph:va count:gVoiceMorphN[0].load() b:vb count:gVoiceMorphN[1].load()]; // 0.36.0
    }];
}
- (void)audioConfigChanged:(NSNotification*)n {
    if (engine && !engine.isRunning) { NSError* e = nil; [engine startAndReturnError:&e]; }
}
- (BOOL)application:(NSApplication*)app openFile:(NSString*)filename {
    if (!v) { if (!pendingOpen) pendingOpen = [NSMutableArray array]; [pendingOpen addObject:filename]; return YES; } // launched by the file: the window is not built yet
    return [v importPresetFile:filename];
}
- (BOOL)restoreSession {
    NSString* t = [[NSUserDefaults standardUserDefaults] stringForKey:@"MUEWSession"];
    if (!t) return NO;
    std::string slug; Preset p;
    if (!session::decode(std::string(t.UTF8String), slug, p)) return NO;
    int idx = slug.empty() ? -1 : ui::indexOfSlug(slug);
    if (idx >= 0 && p == ui::library().at(idx)) { [v loadPresetIndex:idx]; return YES; } // untouched library sound
    binding->applyPreset(p, idx, true);
    [v adoptPreset:p index:idx edited:true];
    return YES;
}
- (void)saveSession {
    if (gSessionNoSave || getenv("MUEW_AX_PROOF") || getenv("MUEW_AX_CONTROL") || getenv("MUEW_NO_SESSION")) return;
    std::string slug = v->currentIndex >= 0 ? ui::library().slug(v->currentIndex) : std::string();
    [[NSUserDefaults standardUserDefaults] setObject:[NSString stringWithUTF8String:session::encode(slug, v->current).c_str()] forKey:@"MUEWSession"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
- (void)applicationWillTerminate:(NSNotification*)n { [self saveSession]; }
- (void)applicationDidResignActive:(NSNotification*)n { [self saveSession]; }
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
