// MUEWEditorView.mm - shared MUEW editor implementation (see MUEWEditorView.h).
#import "MUEWEditorView.h"
#include "user_presets.h"
#include "au_params.h"
#include "table_import.h"
#include <cmath>
#include <complex>

using namespace muew;

static NSColor* C(uint32_t rgb, CGFloat a = 1) {
    return [NSColor colorWithRed:((rgb >> 16) & 255) / 255.0 green:((rgb >> 8) & 255) / 255.0 blue:(rgb & 255) / 255.0 alpha:a];
}
static NSString* S(const std::string& s) { return [NSString stringWithUTF8String:s.c_str()]; }
static void TextA(NSString* s, NSRect r, CGFloat size, NSColor* color, NSFontWeight weight, NSTextAlignment align) {
    NSMutableParagraphStyle* ps = [NSMutableParagraphStyle new];
    ps.alignment = align;
    ps.lineBreakMode = NSLineBreakByTruncatingTail;
    [s drawInRect:r withAttributes:@{NSFontAttributeName: [NSFont systemFontOfSize:size weight:weight],
                                     NSForegroundColorAttributeName: color,
                                     NSParagraphStyleAttributeName: ps}];
}
// Single line that shrinks (down to minSize) instead of truncating.
static void TextFit(NSString* s, NSRect r, CGFloat size, CGFloat minSize, NSColor* color, NSFontWeight weight, NSTextAlignment align) {
    CGFloat sz = size;
    while (sz > minSize && [s sizeWithAttributes:@{NSFontAttributeName: [NSFont systemFontOfSize:sz weight:weight]}].width > r.size.width) sz -= 0.25;
    TextA(s, r, sz, color, weight, align);
}
static void Text(NSString* s, NSRect r, CGFloat size, NSColor* color, NSFontWeight weight = NSFontWeightRegular) {
    TextA(s, r, size, color, weight, NSTextAlignmentLeft);
}
static void FillRound(NSRect r, CGFloat rad, NSColor* c) {
    [c setFill];
    [[NSBezierPath bezierPathWithRoundedRect:r xRadius:rad yRadius:rad] fill];
}

static const CGFloat kRowH = 18;
static NSArray<NSString*>* ChipLabels() {
    return @[@"All", @"Bass", @"Lead", @"Pad", @"Keys", @"Pluck", @"Texture", @"FX", @"\u2605 Favs", @"User"];
}
static const int kUserChip = 9;

// User presets: plain .muew files in ~/Music/MUEW/Presets, shared by the app
// and the AU. MUEW_USER_PRESETS overrides the folder (tests).
static std::string UserPresetDir() {
    const char* env = getenv("MUEW_USER_PRESETS");
    if (env && *env) return env;
    NSArray* music = NSSearchPathForDirectoriesInDomains(NSMusicDirectory, NSUserDomainMask, YES);
    NSString* base = music.firstObject ?: [NSHomeDirectory() stringByAppendingPathComponent:@"Music"];
    return std::string([[base stringByAppendingPathComponent:@"MUEW/Presets"] fileSystemRepresentation]);
}

// Favorites live in MUEW's own defaults suite so the standalone app and the
// AU inside a DAW share them (a plugin must not write the host's defaults).
static NSUserDefaults* MUEWDefaults() {
    static NSUserDefaults* d = [[NSUserDefaults alloc] initWithSuiteName:@"co.instinct.muew"];
    return d;
}

// 0.22.0: complex response of a filter at hz (single-bin DFT over whole cycles), relative to the input tone.
template <class F> static std::complex<double> MeasureH(F& f, double hz, double amp, bool longSettle) {
    const double sr = 44100.0;
    f.reset();
    const int cycles = std::max(1, (int)std::ceil(500 * hz / sr));
    const int win = (int)std::lround(cycles * sr / hz), n = (longSettle ? 2100 : 900) + win;
    double re = 0, im = 0;
    for (int s = 0; s < n; ++s) {
        const double ph = 2 * M_PI * hz * s / sr;
        const double y = f.process((float)(amp * std::sin(ph)));
        if (s >= n - win) { re += y * std::cos(ph); im += y * std::sin(ph); }
    }
    return std::complex<double>(im, re) * (2.0 / win / amp); // y = |H| sin(ph + phase)
}

@implementation MUEWEditorView

- (instancetype)initWithFrame:(NSRect)f {
    if ((self = [super initWithFrame:f])) {
        self.wantsLayer = YES;
        currentIndex = -1; edited = false; chip = 0; scroll = 0; dragKnob = -1; octave = 0;
        matrixPage = 0; modSel = 2; dragSource = -1; dropKnob = -1; dropFx = -1; dropAux = -1; curveDrag = -1; routeDrag = -1; modFieldDrag = -1; fxMove = -1; fxDrop = -1; fxDetail = -1; fxRowDrag = -1; msegEdit = -1; msegGrid = 2; msegPt = -1; msegSeg = -1; msegLoopEdge = -1; lfoXDrag = -1; warpAmtDrag = -1; filterXDrag = -1; voiceDrag = -1; perfNote = -1; perfSustain = false;
        arpDrag = -1; arpLiveOn = false; arpLiveIndex = -1; arpLiveNote = -1; arpLiveStep = 0; arpLivePoolN = 0;
        patDrag = -1; arpLivePatCell = -1; arpLiveLocked = false;
        wtEdit = -1; wtFrame = 0; wtMode = 0; wtLastIdx = 0; wtLastVal = 0; wtDrawing = false; wtPosDrag = -1; wtSpec = SpectralProcess{}; wtSpecDrag = -1;
        filterPage = std::clamp((int)[MUEWDefaults() integerForKey:@"MUEWFilterPage"], 0, 2);
        NSArray* favs = [MUEWDefaults() arrayForKey:@"MUEWFavorites"];
        for (NSString* s in favs) favorites.insert(std::string(s.UTF8String));
        browserOpen = false; bscroll = 0;
        sortMode = std::clamp((int)[MUEWDefaults() integerForKey:@"MUEWSort"], 0, ui::SortModeCount - 1);
        NSDictionary* rd = [MUEWDefaults() dictionaryForKey:@"MUEWRatings"];
        for (NSString* k in rd) if ([rd[k] isKindOfClass:[NSNumber class]]) ui::setRating(ratings, std::string(k.UTF8String), [rd[k] intValue]);
        user::load(UserPresetDir(), ui::library());
        CGFloat top = f.size.height - 100;
        search = [[NSSearchField alloc] initWithFrame:NSMakeRect(812, top - 64, 150, 24)];
        search.placeholderString = @"Search presets";
        search.font = [NSFont systemFontOfSize:11];
        search.delegate = self;
        search.focusRingType = NSFocusRingTypeNone;
        [self addSubview:search];
        [self refilter];
    }
    return self;
}

- (BOOL)acceptsFirstResponder { return host && host->playsNotes(); }
- (BOOL)isFlipped { return NO; }

- (void)saveFavorites {
    NSMutableArray* a = [NSMutableArray array];
    for (const auto& s : favorites) [a addObject:S(s)];
    [MUEWDefaults() setObject:a forKey:@"MUEWFavorites"];
}

- (void)refilter {
    visible = ui::visiblePresets(filter, favorites, ui::library(), ratings, sortMode);
    [MUEWDefaults() setInteger:sortMode forKey:@"MUEWSort"];
    int rows = [self listRows];
    int maxScroll = std::max(0, (int)visible.size() - rows);
    scroll = std::clamp(scroll, 0, maxScroll);
    [self setNeedsDisplay:YES];
}

- (void)controlTextDidChange:(NSNotification*)n {
    filter.query = std::string(search.stringValue.UTF8String ?: "");
    scroll = 0; bscroll = 0;
    [self refilter];
}

- (void)applySound {
    if (host) host->applyPreset(current, ui::library().factoryNumber(currentIndex), edited);
}

- (void)knobEdited:(int)k {
    if (!host || !host->editParameter(ui::knobParam(k), current)) [self applySound];
}

- (void)adoptPreset:(const Preset&)p index:(int)index edited:(bool)wasEdited {
    if (index != currentIndex || p.info.name != current.info.name) { matrixPage = 0; wtHistory[0].clear(); wtHistory[1].clear(); } // a different sound starts on page 1, with no table history
    current = p;
    currentIndex = index;
    edited = wasEdited;
    [self revealCurrent];
    [self setNeedsDisplay:YES];
}

- (void)revealCurrent {
    for (int r = 0; r < (int)visible.size(); ++r)
        if (visible[r] == currentIndex) {
            int rows = [self listRows];
            if (r < scroll) scroll = r;
            if (r >= scroll + rows) scroll = r - rows + 1;
        }
}

- (void)loadPresetIndex:(int)i {
    const ui::Library& lib = ui::library();
    if (i < 0 || i >= lib.count()) return;
    currentIndex = i;
    current = lib.at(i);
    matrixPage = 0;
    wtHistory[0].clear(); wtHistory[1].clear(); // 0.32.0: undo never crosses into another preset
    edited = false;
    [self applySound];
    [self revealCurrent];
    [self setNeedsDisplay:YES];
}

- (void)stepPreset:(int)dir {
    const std::vector<int>& order = visible.empty() ? ui::visiblePresets({}, favorites, ui::library()) : visible;
    int pos = -1;
    for (int r = 0; r < (int)order.size(); ++r) if (order[r] == currentIndex) pos = r;
    int n = (int)order.size();
    if (n == 0) return;
    pos = pos < 0 ? 0 : (pos + dir + n) % n;
    [self loadPresetIndex:order[pos]];
}

// ---- geometry ----
- (CGFloat)top { return self.bounds.size.height - 100; }
- (CGFloat)listTop { return [self top] - 172; }
- (int)listRows { return (int)std::floor(([self listTop] - 76) / kRowH); }
- (NSPoint)knobCenter:(int)k {
    CGFloat t = [self top];
    NSPoint p[] = {{70, t - 192}, {190, t - 192}, {310, t - 192}, {430, t - 192},
                   {536, t - 94}, {637, t - 94}, {536, t - 200}, {637, t - 200}, {732, t - 200}};
    if (ui::isMacro(k)) { // macro strip in the header
        CGFloat h = self.bounds.size.height;
        return NSMakePoint(772 + (k - ui::Macro1) * 56, h - 38);
    }
    // Oscillator row: WARP A, UNISON A, MIX | WIDTH | WARP B, UNISON B, DETUNE
    if (k == ui::UniDetuneA) return NSMakePoint(130, t - 192);
    if (k == ui::Width) return NSMakePoint(250, t - 192);
    if (k == ui::UniDetuneB) return NSMakePoint(370, t - 192);
    // FILTER 2 + SUB/NOISE page reuses the FILTER 1 + AMP knob spots.
    if (k == ui::F2Cutoff) return p[ui::Cutoff];
    if (k == ui::F2Reso) return p[ui::Resonance];
    if (k == ui::Sub) return p[ui::Attack];
    if (k == ui::Noise) return p[ui::Release];
    if (k == ui::NoiseTone) return p[ui::MsegTime];
    return p[k];
}
- (BOOL)oscRowKnob:(int)k {
    return k == ui::WarpA || k == ui::Mix || k == ui::WarpB || k == ui::Detune || ui::isUnison(k);
}
- (CGFloat)knobRadius:(int)k {
    if (ui::isMacro(k)) return 13;
    if ([self oscRowKnob:k]) return 19;
    return (k == ui::Cutoff || k == ui::Resonance || k == ui::F2Cutoff || k == ui::F2Reso) ? 30 : 25;
}
// Unison strip under each oscillator display: 8 voice pips + readout.
- (NSRect)unisonStrip:(int)osc { return NSMakeRect(osc ? 252 : 46, [self top] - 137, 190, 18); } // 0.19.0: up 14 pt for the warp strip
- (NSRect)unisonPip:(int)osc voice:(int)i {
    NSRect r = [self unisonStrip:osc];
    return NSMakeRect(r.origin.x + 6 + i * 13, r.origin.y, 13, r.size.height);
}
// 0.23.0 voice strip in the OSCILLATORS title row: POLY/MONO/LEGATO, voice
// count stepper, GLIDE time bar, glide ALWAYS/LEGATO chip, unison PHASE chip,
// unison BLEND bar.
- (NSRect)voiceMode:(int)i {
    static const CGFloat x[3] = {133, 160, 189}, wd[3] = {26, 28, 38};
    return NSMakeRect(x[i], [self top] - 28, wd[i], 15);
}
- (NSRect)voiceCount { return NSMakeRect(231, [self top] - 28, 36, 15); }
- (NSRect)glideBar { return NSMakeRect(271, [self top] - 28, 78, 15); }
- (NSRect)glideModeChip { return NSMakeRect(352, [self top] - 28, 26, 15); }
- (NSRect)phaseChip { return NSMakeRect(381, [self top] - 28, 30, 15); }
- (NSRect)blendBar { return NSMakeRect(414, [self top] - 28, 42, 15); }
static double GlidePos(double t) { return std::sqrt(std::clamp(t, 0.0, 2.0) / 2.0); }   // bar 0..1 <-> 0..2 s, fine near 0
static double GlideFromPos(double x) { x = std::clamp(x, 0.0, 1.0); double t = 2.0 * x * x; return t < 0.002 ? 0.0 : t; }
static NSString* GlideValue(double t) {
    if (!(t > 0)) return @"OFF";
    return t < 1.0 ? [NSString stringWithFormat:@"%.0f ms", t * 1000] : [NSString stringWithFormat:@"%.2f s", t];
}
// A value pill: muted label left, value right, and a thin level track along the bottom edge.
static void ValuePill(NSRect r, NSString* label, NSString* value, double level, NSColor* accent, bool active) {
    FillRound(r, 4, C(0x0f141b));
    const NSRect track = NSMakeRect(r.origin.x + 4, r.origin.y + 2, r.size.width - 8, 1.5);
    FillRound(track, 0.75, C(0x232b36));
    if (level > 0) FillRound(NSMakeRect(track.origin.x, track.origin.y, std::max(2.0, track.size.width * std::clamp(level, 0.0, 1.0)), track.size.height), 0.75, accent);
    TextA(label, NSMakeRect(r.origin.x + 4, r.origin.y + 4.5, r.size.width - 8, 10), 6.5, C(0x6f7b8b), NSFontWeightBold, NSTextAlignmentLeft);
    TextA(value, NSMakeRect(r.origin.x + 4, r.origin.y + 4.5, r.size.width - 8, 10), 7, active ? accent : C(0x8793a3), NSFontWeightBold, NSTextAlignmentRight);
}
// ---- 0.25.0 ARP page ----
static NSString* NoteName(int n) {
    static const char* k[12] = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"};
    n = std::clamp(n, 0, 127);
    return [NSString stringWithFormat:@"%s%d", k[n % 12], n / 12 - 2]; // C3 = 60
}
static void Stepper(NSRect r, NSString* label, NSString* value, NSColor* accent, bool active) {
    FillRound(r, 4, C(0x0f141b));
    TextA(@"\u2039", NSMakeRect(r.origin.x + 1, r.origin.y + 2.5, 10, 12), 10, C(0x6f7b8b), NSFontWeightBold, NSTextAlignmentCenter);
    TextA(@"\u203A", NSMakeRect(NSMaxX(r) - 11, r.origin.y + 2.5, 10, 12), 10, C(0x6f7b8b), NSFontWeightBold, NSTextAlignmentCenter);
    TextA(label, NSMakeRect(r.origin.x + 12, r.origin.y + 5, r.size.width - 24, 10), 6.5, C(0x6f7b8b), NSFontWeightBold, NSTextAlignmentLeft);
    TextA(value, NSMakeRect(r.origin.x + 12, r.origin.y + 4.5, r.size.width - 24, 10), 7.5, active ? accent : C(0x8793a3), NSFontWeightBold, NSTextAlignmentRight);
}
static NSString* ArpSwingValue(double s) { return s <= 0 ? @"OFF" : [NSString stringWithFormat:@"%.0f%%", 50 + std::clamp(s, 0.0, 0.5) * 50]; }
- (void)drawArpPage {
    const VoiceParams& v = current.voice;
    NSColor* pink = C(0xf06fb0);
    const bool on = v.arpOn;
    TextA([NSString stringWithFormat:@"%s \u00B7 %s", arp::modeName(v.arpMode), arp::rateName(v.arpRate)], NSMakeRect(696, [self top] - 27, 72, 14), 8,
          on ? pink : C(0x5f6b7b), NSFontWeightSemibold, NSTextAlignmentRight);
    NSRect o = [self arpOnRect];
    FillRound(o, 4, on ? pink : C(0x0f141b));
    TextA(on ? @"ARP ON" : @"ARP OFF", NSMakeRect(o.origin.x, o.origin.y + 5, o.size.width, 10), 6.5, on ? C(0x0b0e13) : C(0x8793a3), NSFontWeightBold, NSTextAlignmentCenter);
    FillRound(NSMakeRect(540, [self top] - 58, 230, 18), 5, C(0x0f141b));
    NSString* names[arp::kModes] = {@"UP", @"DOWN", @"UP/DN", @"ORDER", @"RAND", @"CHORD"};
    for (int m = 0; m < arp::kModes; ++m) {
        NSRect r = [self arpModeRect:m];
        const bool sel = std::clamp(v.arpMode, 0, arp::kModes - 1) == m;
        if (sel) FillRound(NSInsetRect(r, 0.5, 0.5), 4, on ? pink : C(0x3a4452));
        TextA(names[m], NSMakeRect(r.origin.x, r.origin.y + 5, r.size.width, 10), 6.5, sel ? C(0x0b0e13) : C(0x8793a3), NSFontWeightBold, NSTextAlignmentCenter);
    }
    Stepper([self arpOctRect], @"OCT", [NSString stringWithFormat:@"%d", std::clamp(v.arpOctaves, 1, 4)], pink, on);
    Stepper([self arpRateRect], @"RATE", [NSString stringWithUTF8String:arp::rateName(v.arpRate)], pink, on);
    NSRect la = [self arpLatchRect];
    FillRound(la, 4, v.arpLatch ? [pink colorWithAlphaComponent:.22] : C(0x0f141b));
    TextA(@"LATCH", NSMakeRect(la.origin.x, la.origin.y + 5, la.size.width, 10), 6.5, v.arpLatch ? pink : C(0x8793a3), NSFontWeightBold, NSTextAlignmentCenter);
    const int held = arpLiveOn ? arpLivePoolN : 0;
    TextA(held ? [NSString stringWithFormat:@"%d KEY%s", held, held == 1 ? "" : "S"] : @"NO KEYS", NSMakeRect(724, [self top] - 79, 44, 10), 6.5,
          held ? pink : C(0x5f6b7b), NSFontWeightBold, NSTextAlignmentRight);
    ValuePill([self arpGateRect], @"GATE", v.arpGate >= 1 ? @"TIE" : [NSString stringWithFormat:@"%.0f%%", v.arpGate * 100], (v.arpGate - 0.05) / 0.95, pink, on);
    ValuePill([self arpSwingRect], @"SWING", ArpSwingValue(v.arpSwing), v.arpSwing / 0.5, pink, on && v.arpSwing > 0);
    [self drawArpGrid];
    [self drawArpPattern];
}
// 0.26.0 step pattern: ON cells are velocity bars, REST cells are empty, TIE
// cells bridge from the step before; a strip under each cell names its kind.
- (void)drawArpPattern {
    const VoiceParams& v = current.voice;
    NSColor* pink = C(0xf06fb0); NSColor* sky = C(0x5ec8f2);
    const bool on = v.arpOn && v.arpPatOn;
    NSRect po = [self arpPatOnRect];
    FillRound(po, 4, v.arpPatOn ? [pink colorWithAlphaComponent:.22] : C(0x0f141b));
    TextA(@"PATTERN", NSMakeRect(po.origin.x, po.origin.y + 5, po.size.width, 10), 6.5, v.arpPatOn ? pink : C(0x8793a3), NSFontWeightBold, NSTextAlignmentCenter);
    Stepper([self arpPatLenRect], @"LEN", [NSString stringWithFormat:@"%d", std::clamp(v.arpPatLen, 1, arp::kPatSteps)], pink, v.arpPatOn);
    NSRect sy = [self arpSyncRect];
    FillRound(sy, 4, v.clockSync ? [sky colorWithAlphaComponent:.22] : C(0x0f141b));
    TextA(@"HOST SYNC", NSMakeRect(sy.origin.x, sy.origin.y + 5, sy.size.width, 10), 6.5, v.clockSync ? sky : C(0x8793a3), NSFontWeightBold, NSTextAlignmentCenter);
    NSString* clk = !v.clockSync ? @"FREE CLOCK" : arpLiveLocked ? @"ON HOST BAR" : @"WAITING FOR PLAY";
    TextA(clk, NSMakeRect(700, sy.origin.y + 5.5, 68, 10), 6, v.clockSync && arpLiveLocked ? sky : C(0x5f6b7b), NSFontWeightBold, NSTextAlignmentRight);
    NSRect lane = [self arpPatLane];
    FillRound(lane, 5, C(0x0f141b));
    const int len = std::clamp(v.arpPatLen, 1, arp::kPatSteps);
    const int live = (arpLiveOn && v.arpPatOn) ? arpLivePatCell : -1;
    for (int i = 0; i < arp::kPatSteps; ++i) {
        const NSRect c = [self arpPatCell:i];
        const bool used = i < len;
        const int kind = std::clamp(v.arpPatKind[i], 0, arp::kStepKinds - 1);
        const NSRect bar = NSMakeRect(c.origin.x + 2, c.origin.y + 11, c.size.width - 4, c.size.height - 14);
        if (i == live) FillRound(NSInsetRect(c, 0.5, 0.5), 3, [pink colorWithAlphaComponent:.16]);
        if (i % 4 == 0) FillRound(NSMakeRect(c.origin.x + 2, c.origin.y + 8, c.size.width - 4, 1), 0, C(0x3a4452));
        NSColor* full = !used ? C(0x1c232d) : !on ? C(0x3a4452) : i == live ? pink : [pink colorWithAlphaComponent:.6];
        if (kind == arp::StepOn || kind == arp::StepTie) {
            int k = i, vel = v.arpPatVel[i];
            if (kind == arp::StepTie) { while (k > 0 && v.arpPatKind[k] == arp::StepTie) --k; vel = v.arpPatVel[k]; }
            const CGFloat h = std::max(2.0, bar.size.height * std::clamp(vel, 1, 127) / 127.0);
            NSRect b = NSMakeRect(bar.origin.x, bar.origin.y, bar.size.width, h);
            if (kind == arp::StepTie) { b.origin.x -= 4; b.size.width += 4; } // bridge from the cell before
            FillRound(b, 1.5, kind == arp::StepTie && used ? [full colorWithAlphaComponent:on ? .45 : .7] : full);
        } else if (used) {
            FillRound(NSMakeRect(NSMidX(bar) - 3, bar.origin.y + 1, 6, 1.5), 0.75, C(0x3a4452));
        }
        NSString* tag = kind == arp::StepOn ? @"" : kind == arp::StepRest ? @"R" : @"T";
        FillRound(NSMakeRect(c.origin.x + 2, c.origin.y + 1.5, c.size.width - 4, 6), 1.5, used && kind != arp::StepOn ? C(0x232b36) : C(0x151b23));
        if (tag.length) TextA(tag, NSMakeRect(c.origin.x, c.origin.y + 1, c.size.width, 7), 5, used ? C(0x8793a3) : C(0x3a4452), NSFontWeightBold, NSTextAlignmentCenter);
    }
}
- (void)drawArpGrid {
    const VoiceParams& v = current.voice;
    NSColor* pink = C(0xf06fb0);
    NSRect g = [self arpGrid];
    FillRound(g, 5, C(0x0f141b));
    // The keys: the AU's pool when it is holding some, otherwise a C major triad as a preview.
    int pool[8] = {60, 64, 67}; int pn = 3;
    const bool live = arpLiveOn && arpLivePoolN > 0 && v.arpOn;
    if (live) { pn = std::min(arpLivePoolN, 8); for (int i = 0; i < pn; ++i) pool[i] = arpLivePool[i]; }
    const int oct = std::clamp(v.arpOctaves, 1, 4);
    const int mode = std::clamp(v.arpMode, 0, arp::kModes - 1);
    std::array<int, arp::kSeq> seq{};
    int n = mode == arp::Chord ? oct : arp::sequence(mode == arp::Random ? arp::Up : mode, pool, pn, oct, seq);
    const int cols = std::clamp(n, 1, 16);
    int lo = 127, hi = 0;
    for (int i = 0; i < pn; ++i) { lo = std::min(lo, pool[i]); hi = std::max(hi, pool[i] + 12 * (oct - 1)); }
    if (hi - lo < 12) hi = lo + 12;
    const NSRect ga = NSMakeRect(g.origin.x + 26, g.origin.y + 18, g.size.width - 34, g.size.height - 26);
    const CGFloat cw = ga.size.width / cols, rowH = ga.size.height / (hi - lo + 1);
    // Octave lines and note names.
    for (int k = lo; k <= hi; ++k) if (k % 12 == 0 || k == lo || k == hi) {
        const CGFloat y = ga.origin.y + (k - lo) * rowH + rowH / 2;
        if (k % 12 == 0) FillRound(NSMakeRect(ga.origin.x, y - 0.25, ga.size.width, 0.5), 0, C(0x232b36));
        if (k == lo || k == hi) TextA(NoteName(k), NSMakeRect(g.origin.x + 2, y - 4.5, 22, 9), 6, C(0x5f6b7b), NSFontWeightBold, NSTextAlignmentRight);
    }
    // Beat marks under the steps.
    const double stepsPerBeat = 1.0 / arp::rateBeats(v.arpRate);
    for (int c = 0; c < cols; ++c) {
        const bool beat = std::fmod(c, stepsPerBeat) < 1e-6;
        FillRound(NSMakeRect(ga.origin.x + c * cw + 1, g.origin.y + 7, cw - 2, beat ? 3 : 1.5), 0.75, beat ? C(0x3a4452) : C(0x232b36));
    }
    const int cur = live ? arpLiveIndex : -1;
    const bool sounding = live && arpLiveNote >= 0;
    const double gate = std::clamp(v.arpGate, 0.05, 1.0), swing = std::clamp(v.arpSwing, 0.0, 0.5);
    for (int c = 0; c < cols; ++c) {
        const CGFloat x0 = ga.origin.x + c * cw + ((c & 1) ? swing * cw : 0);
        const CGFloat w = std::max(3.0, (cw - 2) * gate * ((c & 1) ? 1 - swing : 1));
        const bool isCur = mode != arp::Random && c == cur;
        if (isCur) FillRound(NSMakeRect(ga.origin.x + c * cw, ga.origin.y - 2, cw, ga.size.height + 4), 3, [pink colorWithAlphaComponent:sounding ? .16 : .08]);
        auto cell = [&](int note) {
            const CGFloat y = ga.origin.y + (note - lo) * rowH;
            NSColor* col = !v.arpOn ? C(0x3a4452) : mode == arp::Random ? [pink colorWithAlphaComponent:.35]
                         : isCur ? pink : [pink colorWithAlphaComponent:live ? .55 : .4];
            FillRound(NSMakeRect(x0 + 1, y + 0.5, w, std::max(2.5, rowH - 1)), 1.5, col);
        };
        if (mode == arp::Chord) { for (int i = 0; i < pn; ++i) cell(std::min(127, pool[i] + 12 * c)); }
        else cell(seq[c]);
    }
    if (n > cols) TextA([NSString stringWithFormat:@"+%d", n - cols], NSMakeRect(NSMaxX(g) - 30, NSMaxY(g) - 12, 26, 9), 6.5, C(0x6f7b8b), NSFontWeightBold, NSTextAlignmentRight);
    NSString* note = !v.arpOn ? @"ARP OFF: KEYS PLAY DIRECTLY" : !live ? @"HOLD KEYS TO PLAY \u00B7 PREVIEW: C E G"
                   : mode == arp::Random ? [NSString stringWithFormat:@"RANDOM FROM %d NOTES", n] : sounding ? [NSString stringWithFormat:@"STEP %d / %d \u00B7 %@", cur + 1, n, NoteName(arpLiveNote)]
                   : [NSString stringWithFormat:@"STEP %d / %d", cur + 1, n];
    TextA(note, NSMakeRect(g.origin.x + 26, NSMaxY(g) - 12, 200, 9), 6.5, v.arpOn ? C(0x8793a3) : C(0x5f6b7b), NSFontWeightBold, NSTextAlignmentLeft);
}
- (BOOL)arpMouseDown:(NSPoint)p {
    VoiceParams& v = current.voice;
    if (NSPointInRect(p, [self arpOnRect])) { v.arpOn = !v.arpOn; [self voiceParamEdited:-1]; return YES; }
    for (int m = 0; m < arp::kModes; ++m)
        if (NSPointInRect(p, [self arpModeRect:m])) { v.arpMode = m; [self voiceParamEdited:-1]; return YES; }
    NSRect oc = [self arpOctRect], rt = [self arpRateRect];
    if (NSPointInRect(p, oc)) { v.arpOctaves = std::clamp(v.arpOctaves + (p.x < NSMidX(oc) ? -1 : 1), 1, 4); [self voiceParamEdited:-1]; return YES; }
    if (NSPointInRect(p, rt)) { v.arpRate = std::clamp(v.arpRate + (p.x < NSMidX(rt) ? -1 : 1), 0, arp::kRates - 1); [self voiceParamEdited:-1]; return YES; }
    if (NSPointInRect(p, [self arpLatchRect])) { v.arpLatch = !v.arpLatch; [self voiceParamEdited:-1]; return YES; }
    for (int k = 0; k < 2; ++k) {
        NSRect r = k ? [self arpSwingRect] : [self arpGateRect];
        if (!NSPointInRect(p, NSInsetRect(r, 0, -3))) continue;
        const double x = std::clamp((p.x - r.origin.x) / r.size.width, 0.0, 1.0);
        if (host) host->parameterGesture(k ? params::ArpSwing : params::ArpGate, true);
        if (k) v.arpSwing = std::round(x * 50) / 100.0; else v.arpGate = 0.05 + std::round(x * 95) / 100.0;
        arpDrag = k; dragValue = x;
        [self voiceParamEdited:k ? params::ArpSwing : params::ArpGate];
        return YES;
    }
    if (NSPointInRect(p, [self arpPatOnRect])) { v.arpPatOn = !v.arpPatOn; [self voiceParamEdited:-1]; return YES; }
    NSRect pl = [self arpPatLenRect];
    if (NSPointInRect(p, pl)) { v.arpPatLen = std::clamp(v.arpPatLen + (p.x < NSMidX(pl) ? -1 : 1), 1, arp::kPatSteps); [self voiceParamEdited:-1]; return YES; }
    if (NSPointInRect(p, [self arpSyncRect])) { v.clockSync = !v.clockSync; [self voiceParamEdited:-1]; return YES; }
    if (NSPointInRect(p, [self arpPatLane])) {
        const int i = std::clamp((int)((p.x - [self arpPatLane].origin.x) / [self arpPatCell:0].size.width), 0, arp::kPatSteps - 1);
        const NSRect c = [self arpPatCell:i];
        v.arpPatOn = true;
        if (i >= v.arpPatLen) v.arpPatLen = i + 1; // clicking past the end grows the pattern
        if (p.y < c.origin.y + 9) v.arpPatKind[i] = (v.arpPatKind[i] + 1) % arp::kStepKinds; // kind strip: ON -> REST -> TIE
        else { v.arpPatKind[i] = arp::StepOn; [self setPatVelocity:i at:p]; patDrag = i; }
        [self voiceParamEdited:-1];
        return YES;
    }
    return NSPointInRect(p, [self arpGrid]);
}
- (void)setPatVelocity:(int)i at:(NSPoint)p {
    const NSRect c = [self arpPatCell:i];
    const double y = std::clamp((p.y - (c.origin.y + 11)) / (c.size.height - 14), 0.0, 1.0);
    current.voice.arpPatVel[i] = std::clamp((int)std::lround(y * 127), 1, 127);
}
- (void)showArpOn:(bool)on pool:(const int*)pool count:(int)n index:(int)index note:(int)note step:(int)step {
    n = std::clamp(n, 0, 8);
    bool same = on == arpLiveOn && n == arpLivePoolN && index == arpLiveIndex && note == arpLiveNote && step == arpLiveStep;
    for (int i = 0; same && i < n; ++i) same = pool[i] == arpLivePool[i];
    if (same) return;
    arpLiveOn = on; arpLivePoolN = n; arpLiveIndex = index; arpLiveNote = note; arpLiveStep = step;
    for (int i = 0; i < n; ++i) arpLivePool[i] = pool[i];
    if (filterPage == 2) [self setNeedsDisplayInRect:NSMakeRect(480, [self top] - 260, 300, 250)];
}
// 0.30.0 Engine HQ: header block with the QUALITY pill, voice count and CPU load.
- (NSRect)engineBox { return NSMakeRect(268, self.bounds.size.height - 66, 104, 40); }
- (NSRect)engineHQPill { NSRect b = [self engineBox]; return NSMakeRect(b.origin.x + 7, b.origin.y + 21, 28, 13); }
- (void)showEngineVoices:(int)active limit:(int)limit cpu:(float)cpu render:(bool)render {
    const int pc = (int)std::lround(std::clamp(cpu, 0.0f, 9.99f) * 100), was = (int)std::lround(std::clamp(engCpu, 0.0f, 9.99f) * 100);
    const bool same = active == engVoices && limit == engLimit && render == engRender && pc == was;
    engVoices = active; engLimit = limit; engCpu = cpu; engRender = render;
    if (!same) [self setNeedsDisplayInRect:NSInsetRect([self engineBox], -2, -2)];
}
- (NSString*)muewEngineText {
    return [NSString stringWithFormat:@"hq=%d voices=%d/%d cpu=%.4f render=%d", current.voice.oscQuality, engVoices, engLimit, engCpu, engRender ? 1 : 0];
}
- (void)drawEngine {
    const NSRect b = [self engineBox];
    FillRound(b, 7, C(0x0a0d12));
    [C(0x232a35) setStroke];
    [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(b, 0.5, 0.5) xRadius:7 yRadius:7] stroke];
    const bool hq = current.voice.oscQuality == 1 || engRender;
    const NSRect pill = [self engineHQPill];
    NSColor* teal = C(0x5adac8);
    if (hq) FillRound(pill, 6.5, [teal colorWithAlphaComponent:0.9]);
    else {
        FillRound(pill, 6.5, C(0x141a22));
        [C(0x3a4452) setStroke];
        [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(pill, 0.5, 0.5) xRadius:6 yRadius:6] stroke];
    }
    TextA(@"HQ", NSMakeRect(pill.origin.x, pill.origin.y + 1.5, pill.size.width, 10), 8, hq ? C(0x06201c) : C(0x8391a3), NSFontWeightBold, NSTextAlignmentCenter);
    NSString* vs = [NSString stringWithFormat:@"%d/%d", engVoices, engLimit > 0 ? engLimit : current.voice.polyVoices];
    TextA(engRender ? @"RENDER" : @"VOICES", NSMakeRect(b.origin.x + 40, b.origin.y + 23, 36, 10), 7, C(0x5f6b7b), NSFontWeightSemibold, NSTextAlignmentLeft);
    TextA(vs, NSMakeRect(b.origin.x + 72, b.origin.y + 22, 26, 11), 8.5, engVoices > 0 ? C(0xe6ebf1) : C(0x758192), NSFontWeightSemibold, NSTextAlignmentRight);
    // CPU: share of the real-time budget, amber past 50 %, red past 80 %.
    TextA(@"CPU", NSMakeRect(b.origin.x + 8, b.origin.y + 6, 22, 10), 7, C(0x5f6b7b), NSFontWeightSemibold, NSTextAlignmentLeft);
    const float cpu = std::clamp(engCpu, 0.0f, 1.0f);
    const NSRect track = NSMakeRect(b.origin.x + 30, b.origin.y + 9, 40, 4);
    FillRound(track, 2, C(0x1a212b));
    NSColor* cc = cpu > 0.8f ? C(0xf06a5f) : cpu > 0.5f ? C(0xf2ab55) : teal;
    if (cpu > 0.002f) FillRound(NSMakeRect(track.origin.x, track.origin.y, std::max<CGFloat>(3, track.size.width * cpu), 4), 2, cc);
    TextA([NSString stringWithFormat:@"%d%%", (int)std::lround(std::clamp(engCpu, 0.0f, 9.99f) * 100)], NSMakeRect(b.origin.x + 72, b.origin.y + 5, 26, 11), 8.5, C(0xb7c1cd), NSFontWeightSemibold, NSTextAlignmentRight);
}
- (void)showArpPatCell:(int)cell locked:(bool)locked { // 0.26.0
    if (cell == arpLivePatCell && locked == arpLiveLocked) return;
    arpLivePatCell = cell; arpLiveLocked = locked;
    if (filterPage == 2) [self setNeedsDisplayInRect:NSMakeRect(480, [self top] - 260, 300, 250)];
}
- (NSString*)muewArpText {
    const VoiceParams& v = current.voice;
    NSMutableString* s = [NSMutableString stringWithFormat:@"page=%d on=%d mode=%s oct=%d rate=%s gate=%.2f swing=%.2f latch=%d live=%d pool=", filterPage, v.arpOn ? 1 : 0,
        arp::modeName(v.arpMode), v.arpOctaves, arp::rateName(v.arpRate), v.arpGate, v.arpSwing, v.arpLatch ? 1 : 0, arpLiveOn ? 1 : 0];
    for (int i = 0; i < arpLivePoolN; ++i) [s appendFormat:@"%s%d", i ? "," : "", arpLivePool[i]];
    [s appendFormat:@" index=%d note=%d", arpLiveIndex, arpLiveNote];
    [s appendFormat:@" sync=%d locked=%d pat=%d len=%d cell=%d steps=", v.clockSync ? 1 : 0, arpLiveLocked ? 1 : 0, v.arpPatOn ? 1 : 0, v.arpPatLen, arpLivePatCell]; // 0.26.0
    for (int i = 0; i < v.arpPatLen; ++i) [s appendFormat:@"%s%c%d", i ? "," : "", "ORT"[std::clamp(v.arpPatKind[i], 0, 2)], v.arpPatVel[i]];
    return s;
}
- (void)drawVoiceStrip {
    const VoiceParams& v = current.voice;
    NSColor* teal = C(0x5adac8);
    NSColor* amber = C(0xf2ab55);
    NSString* modes[3] = {@"POLY", @"MONO", @"LEGATO"};
    FillRound(NSMakeRect(131, [self top] - 29, 98, 17), 5, C(0x0f141b));
    for (int i = 0; i < 3; ++i) {
        NSRect r = [self voiceMode:i];
        const bool on = std::clamp(v.voiceMode, 0, 2) == i;
        if (on) FillRound(NSInsetRect(r, 0.5, 0.5), 4, teal);
        TextA(modes[i], NSMakeRect(r.origin.x, r.origin.y + 4, r.size.width, 10), 6.5, on ? C(0x0b0e13) : C(0x8793a3), NSFontWeightBold, NSTextAlignmentCenter);
    }
    NSRect vc = [self voiceCount];
    FillRound(vc, 4, C(0x0f141b));
    const bool poly = v.voiceMode == 0;
    TextA(@"\u2039", NSMakeRect(vc.origin.x + 1, vc.origin.y + 1.5, 9, 12), 10, C(0x6f7b8b), NSFontWeightBold, NSTextAlignmentCenter);
    TextA(@"\u203A", NSMakeRect(NSMaxX(vc) - 10, vc.origin.y + 1.5, 9, 12), 10, C(0x6f7b8b), NSFontWeightBold, NSTextAlignmentCenter);
    TextA([NSString stringWithFormat:@"%d V", poly ? std::clamp(v.polyVoices, 1, 16) : 1], NSMakeRect(vc.origin.x + 8, vc.origin.y + 4, vc.size.width - 16, 10), 7,
          poly ? C(0xd5dce5) : C(0x5f6b7b), NSFontWeightBold, NSTextAlignmentCenter);
    ValuePill([self glideBar], @"GLIDE", GlideValue(v.glideTime), GlidePos(v.glideTime), amber, v.glideTime > 0);
    NSRect gm = [self glideModeChip];
    FillRound(gm, 4, v.glideLegato ? [amber colorWithAlphaComponent:.22] : C(0x0f141b));
    TextA(v.glideLegato ? @"LEG" : @"ALL", NSMakeRect(gm.origin.x, gm.origin.y + 4, gm.size.width, 10), 6.5, v.glideTime > 0 ? amber : C(0x5f6b7b),
          NSFontWeightBold, NSTextAlignmentCenter);
    NSRect ph = [self phaseChip];
    FillRound(ph, 4, v.uniPhase ? [teal colorWithAlphaComponent:.22] : C(0x0f141b));
    TextA(v.uniPhase ? @"RAND" : @"SPRD", NSMakeRect(ph.origin.x, ph.origin.y + 4, ph.size.width, 10), 6.5, v.uniPhase ? teal : C(0x8793a3), NSFontWeightBold, NSTextAlignmentCenter);
    const double bl = std::clamp(v.uniBlend, 0.0, 1.0);
    ValuePill([self blendBar], @"BLND", [NSString stringWithFormat:@"%.0f", bl * 100], bl, C(0xc3cbd6), true);
}
- (void)voiceParamEdited:(int)id {
    edited = true;
    if (id < 0 || !host || !host->editParameter(id, current)) [self applySound];
    [self setNeedsDisplay:YES];
}
- (BOOL)voiceStripMouseDown:(NSPoint)p event:(NSEvent*)e {
    VoiceParams& v = current.voice;
    for (int i = 0; i < 3; ++i)
        if (NSPointInRect(p, [self voiceMode:i])) { v.voiceMode = i; [self voiceParamEdited:-1]; return YES; }
    if (NSPointInRect(p, [self voiceCount])) {
        if (v.voiceMode != 0) v.voiceMode = 0; // the count is a POLY setting: stepping it returns to POLY
        else v.polyVoices = std::clamp(v.polyVoices + (p.x < NSMidX([self voiceCount]) ? -1 : 1), 1, 16);
        [self voiceParamEdited:-1];
        return YES;
    }
    if (NSPointInRect(p, NSInsetRect([self glideBar], 0, -3))) {
        if (host) host->parameterGesture(params::GlideTime, true);
        if (e.clickCount == 2) v.glideTime = 0;
        else { v.glideTime = GlideFromPos((p.x - [self glideBar].origin.x) / [self glideBar].size.width); voiceDrag = 0; dragValue = GlidePos(v.glideTime); }
        [self voiceParamEdited:params::GlideTime];
        if (voiceDrag < 0 && host) host->parameterGesture(params::GlideTime, false);
        return YES;
    }
    if (NSPointInRect(p, [self glideModeChip])) { v.glideLegato = !v.glideLegato; [self voiceParamEdited:-1]; return YES; }
    if (NSPointInRect(p, [self phaseChip])) { v.uniPhase = v.uniPhase ? 0 : 1; [self voiceParamEdited:-1]; return YES; }
    if (NSPointInRect(p, NSInsetRect([self blendBar], 0, -3))) {
        if (host) host->parameterGesture(params::UnisonBlend, true);
        if (e.clickCount == 2) v.uniBlend = VoiceParams{}.uniBlend;
        else { v.uniBlend = std::clamp((p.x - [self blendBar].origin.x) / [self blendBar].size.width, 0.0, 1.0); voiceDrag = 1; dragValue = v.uniBlend; }
        [self voiceParamEdited:params::UnisonBlend];
        if (voiceDrag < 0 && host) host->parameterGesture(params::UnisonBlend, false);
        return YES;
    }
    return NO;
}
// FX rack: 5 x 2 cards (0.27.0; 4 x 2 before) laid out in chain order (FXParams::order), left to
// right, top to bottom. Card geometry is by slot; the unit in a slot is
// current.fx.order.slot[s]. Unit ids follow muew::FxUnit.
- (CGFloat)fxCardH { return ([self top] - 286 - 44 - 58 - 6) / 2; }
- (NSRect)fxCard:(int)slot {
    CGFloat h = [self fxCardH];
    return NSMakeRect(468 + (slot % 5) * 62, slot < 5 ? 58 + h + 6 : 58, 56, h);
}
- (NSPoint)fxRingCenter:(int)slot { NSRect r = [self fxCard:slot]; return NSMakePoint(NSMidX(r), r.origin.y + 36); }
- (NSRect)fxLed:(int)slot { NSRect r = [self fxCard:slot]; return NSMakeRect(NSMaxX(r) - 17, NSMaxY(r) - 19, 16, 16); }
- (int)fxSlotAt:(NSPoint)p {
    for (int s = 0; s < kFxUnits; ++s) if (NSPointInRect(p, NSInsetRect([self fxCard:s], -4, -3))) return s;
    return -1;
}
// 0.14.0 FX detail panel: covers the matrix while a unit is open.
static const int kFxAccent[kFxUnits] = {0xf27a55, 0xf2ab55, 0xf2ab55, 0x6cb6ff, 0xf2ab55, 0x5adac8, 0xb68cff, 0xb68cff, 0x75ead8, 0xff7fb0};
// 0.27.0: HYPER and FILTER FX pages put a live picture beside compact rows.
// 0.28.0: COMP and REVERB join them (static curve per band, decay envelope).
static bool FxVisualPage(int u) { return u == FxHyper || u == FxFilter || u == FxComp || u == FxReverb; }
- (NSRect)fxDetailPanel { return NSMakeRect(36, 48, 424, 200); }
- (NSRect)fxDetailClose { NSRect r = [self fxDetailPanel]; return NSMakeRect(NSMaxX(r) - 30, NSMaxY(r) - 26, 20, 18); }
- (NSRect)fxDetailToggle { NSRect r = [self fxDetailPanel]; return NSMakeRect(NSMaxX(r) - 84, NSMaxY(r) - 25, 46, 16); }
- (NSRect)fxDetailRow:(int)i {
    NSRect r = [self fxDetailPanel];
    if (FxVisualPage(fxDetail)) return NSMakeRect(r.origin.x + 12, NSMaxY(r) - 52 - i * 17, 252, 16); // 8 rows clear the footer
    return NSMakeRect(r.origin.x + 12, NSMaxY(r) - 58 - i * 24, r.size.width - 24, 20);
}
- (NSRect)fxDetailBar:(int)i {
    NSRect r = [self fxDetailRow:i];
    if (FxVisualPage(fxDetail)) return NSMakeRect(r.origin.x + 62, r.origin.y + 2, 100, 13);
    return NSMakeRect(r.origin.x + 92, r.origin.y + 3, 196, 14);
}
- (NSRect)fxDetailVisual { NSRect r = [self fxDetailPanel]; return NSMakeRect(r.origin.x + 274, r.origin.y + 26, r.size.width - 286, r.size.height - 64); }
// AU parameter behind a detail row (-1: panel-only control, saved with the sound).
static int FxRowParam(int u, int i) {
    switch (u) {
    case FxDist: return i == 1 ? params::DistDrive : -1;
    case FxChorus: return i == 3 ? params::ChorusMix : -1;
    case FxDelay: return i == 5 ? params::DelayMix : -1;
    case FxComp: return i == 1 ? params::CompAmount : i == 2 ? params::CompUpward : -1;  // 0.28.0 rows
    case FxReverb: return i == 7 ? params::ReverbMix : i == 4 ? params::ReverbSize : -1; // 0.28.0 rows
    case FxPhaser: return i == 3 ? params::PhaserMix : -1;
    case FxFlanger: return i == 3 ? params::FlangerMix : -1;
    case FxHyper: return i == 3 ? params::HyperMix : -1;       // 0.27.0
    case FxFilter: return i == 1 ? params::FilterFxCutoff : -1; // 0.27.0
    default: return -1;
    }
}
// AU parameter behind each unit's ring (-1: the EQ has no ring).
static int FxParam(int u) {
    static const int id[kFxUnits] = {params::DistDrive, params::ChorusMix, params::DelayMix, params::CompAmount, params::ReverbMix, -1,
                                     params::PhaserMix, params::FlangerMix, params::HyperMix, params::FilterFxCutoff};
    return (u >= 0 && u < kFxUnits) ? id[u] : -1;
}
// Ring position 0..1 of an FX ring parameter (Hertz rings sweep geometrically).
static double RingNorm(const Preset& p, int id) {
    const auto& d = params::def(id);
    const double v = params::get(p, id);
    if (d.log) return std::log(v / d.lo) / std::log(d.hi / d.lo);
    return (v - d.lo) / (d.hi - d.lo);
}
static double RingValue(int id, double n) {
    const auto& d = params::def(id);
    n = std::clamp(n, 0.0, 1.0);
    return d.log ? d.lo * std::pow(d.hi / d.lo, n) : d.lo + n * (d.hi - d.lo);
}
static bool& FxEnabled(Preset& p, int i) {
    switch (i) {
    case 0: return p.fx.dist.enabled;
    case 1: return p.fx.chorus.enabled;
    case 2: return p.fx.delay.enabled;
    case 3: return p.fx.comp.enabled;
    case 4: return p.fx.reverb.enabled;
    case 6: return p.fx.phaser.enabled;
    case 7: return p.fx.flanger.enabled;
    case 8: return p.fx.hyper.enabled;
    case 9: return p.fx.filter.enabled;
    default: return p.fx.eq.enabled;
    }
}
static const NSInteger kFxDrag = 100; // dragKnob values >= kFxDrag are FX rings
- (int)paramForDrag:(NSInteger)d { return d >= kFxDrag ? FxParam((int)(d - kFxDrag)) : ui::knobParam((int)d); }
- (NSRect)chipRect:(int)i {
    CGFloat t = [self top];
    return NSMakeRect(812 + (i % 3) * 51, t - 90 - (i / 3) * 22, 46, 18);
}
- (NSRect)favToggleRect { return NSMakeRect(812, 46, 110, 20); }
// Row 4 of the chip grid: [User] [Save] [Export].
- (NSRect)saveRect { return [self chipRect:10]; }
- (NSRect)exportRect { return [self chipRect:11]; }
- (NSRect)prevRect { return NSMakeRect(386, self.bounds.size.height - 62, 26, 30); }
- (NSRect)nextRect { return NSMakeRect(668, self.bounds.size.height - 62, 26, 30); }
// ---- mod matrix geometry (MODULATION area, x 44-452, y 58-250) ----
// Left: 4 visible route rows of the 16-slot matrix plus page tabs.
- (NSRect)routeRow:(int)i { return NSMakeRect(44, 190 - i * 44, 248, 38); }
- (NSRect)routeSourcePill:(int)i { NSRect r = [self routeRow:i]; return NSMakeRect(r.origin.x + 28, r.origin.y + 20, 62, 14); }
- (NSRect)routeDestPill:(int)i { NSRect r = [self routeRow:i]; return NSMakeRect(r.origin.x + 108, r.origin.y + 20, 110, 14); }
- (NSRect)routeClear:(int)i { NSRect r = [self routeRow:i]; return NSMakeRect(r.origin.x + 226, r.origin.y + 20, 16, 14); }
- (NSRect)routeBar:(int)i { NSRect r = [self routeRow:i]; return NSMakeRect(r.origin.x + 28, r.origin.y + 4, 118, 14); }
// 0.16.0: response-curve glyph and AUX chip between the amount bar and its readout.
- (NSRect)routeCurve:(int)i { NSRect r = [self routeRow:i]; return NSMakeRect(r.origin.x + 151, r.origin.y + 4, 20, 14); }
- (NSRect)routeAux:(int)i { NSRect r = [self routeRow:i]; return NSMakeRect(r.origin.x + 174, r.origin.y + 4, 26, 14); }
- (NSRect)pageTab:(int)i { return NSMakeRect(172 + i * 30, 234, 28, 14); }
// Right: 15 source badges (2 x 8), preview, and the selected modulator's controls.
- (NSRect)sourceBadge:(int)i { // 2 pt gaps (0.18.0); 0.24.0 performance badges (15-18) on a third row
    if (i >= 15) return NSMakeRect(304 + (i - 15) * 19, 180, 17, 15);
    return NSMakeRect(304 + (i % 8) * 19, i < 8 ? 216 : 198, 17, 15);
}
- (NSRect)bendChip { return NSMakeRect(384, 180, 68, 15); } // 0.24.0 pitch bend RANGE stepper
- (NSRect)bendArrow:(int)d { NSRect c = [self bendChip]; return d < 0 ? NSMakeRect(c.origin.x, c.origin.y, 14, 15) : NSMakeRect(NSMaxX(c) - 14, c.origin.y, 14, 15); }
// 0.17.0 MSEG editor: opens over the matrix like the FX detail panel.
- (NSRect)msegPanel { return NSMakeRect(36, 48, 424, 200); }
- (NSRect)msegClose { NSRect r = [self msegPanel]; return NSMakeRect(NSMaxX(r) - 30, NSMaxY(r) - 26, 20, 18); }
- (NSRect)msegTab:(int)k { NSRect r = [self msegPanel]; return NSMakeRect(r.origin.x + 150 + k * 56, NSMaxY(r) - 25, 52, 16); }
- (NSRect)msegCanvas { NSRect r = [self msegPanel]; return NSMakeRect(r.origin.x + 14, r.origin.y + 46, r.size.width - 28, r.size.height - 46 - 38); } // hint line sits below it (0.18.0)
- (NSRect)msegModePill:(int)i { NSRect r = [self msegPanel]; return NSMakeRect(r.origin.x + 12 + i * 58, r.origin.y + 10, 54, 17); }
- (NSRect)msegGridPill:(int)i {
    NSRect r = [self msegPanel];
    if (msegEdit >= 2 && msegEdit < 6) return NSMakeRect(r.origin.x + 252 + i * 20, r.origin.y + 10, 18, 17);
    return NSMakeRect(r.origin.x + 216 + i * 27, r.origin.y + 10, 25, 17);
}
// 0.18.0 LFO editor: LFO 1-4 tabs, CUSTOM toggle, RETRIG/FREE and PHASE/DELAY/RISE pills.
- (NSRect)lfoTab:(int)i { NSRect r = [self msegPanel]; return NSMakeRect(r.origin.x + 150 + i * 44, NSMaxY(r) - 25, 40, 16); }
- (NSRect)lfoCustomChip { NSRect r = [self msegPanel]; return NSMakeRect(r.origin.x + 334, NSMaxY(r) - 25, 52, 16); }
- (NSRect)lfoTrigPill:(int)i { NSRect r = [self msegPanel]; return NSMakeRect(r.origin.x + 12 + i * 44, r.origin.y + 10, 42, 17); }
- (NSRect)lfoXPill:(int)j { NSRect r = [self msegPanel]; return NSMakeRect(r.origin.x + 104 + j * 48, r.origin.y + 10, 46, 17); }
- (NSRect)msegLenPill { NSRect r = [self msegPanel]; return msegEdit >= 2 ? NSMakeRect(r.origin.x + 334, r.origin.y + 10, 44, 17) : NSMakeRect(r.origin.x + 328, r.origin.y + 10, 50, 17); }
- (NSRect)msegSyncPill { NSRect r = [self msegPanel]; return NSMakeRect(r.origin.x + 381, r.origin.y + 10, 31, 17); }
- (NSRect)modPreview { return NSMakeRect(304, 122, 148, 44); } // 0.24.0: 14 pt shorter for the performance row
// 0.9.0 oscillator displays and the wavetable editor that opens over the
// OSCILLATORS panel.
- (NSRect)oscDisplay:(int)o { return NSMakeRect(o ? 252 : 46, [self top] - 111, 190, 62); }
// 0.19.0 warp strip under each oscillator: two slot chips [n][<][MODE][>][amount].
- (NSRect)warpChip:(int)o slot:(int)s { return NSMakeRect((o ? 252 : 46) + s * 96, [self top] - 157, s ? 94 : 92, 16); }
- (NSRect)warpArrow:(int)o slot:(int)s dir:(int)d { NSRect c = [self warpChip:o slot:s]; return NSMakeRect(c.origin.x + 10 + (d > 0 ? 46 : 0), c.origin.y, 10, c.size.height); }
- (NSRect)warpName:(int)o slot:(int)s { NSRect c = [self warpChip:o slot:s]; return NSMakeRect(c.origin.x + 20, c.origin.y, 36, c.size.height); }
- (NSRect)warpAmt:(int)o slot:(int)s { NSRect c = [self warpChip:o slot:s]; return NSMakeRect(c.origin.x + 67, c.origin.y + 3, c.size.width - 70, c.size.height - 6); }
- (NSRect)remapChip:(int)o { NSRect r = [self oscDisplay:o]; return NSMakeRect(NSMaxX(r) - 84, NSMaxY(r) - 17, 40, 13); }
- (NSRect)oscTitle:(int)o { return NSMakeRect(o ? 256 : 50, [self top] - 47, 186, 16); }
- (NSRect)wtPosBar:(int)o { NSRect r = [self oscDisplay:o]; return NSMakeRect(r.origin.x + 10, r.origin.y + 5, r.size.width - 20, 7); }
// 0.25.0: FILTER 1 / FILTER 2 + SUB / ARP tabs, narrowed so the FILTER 1 model selector keeps its own space to the right.
- (NSRect)filterTab:(int)i { static const CGFloat x[3] = {492, 550, 638}, wd[3] = {54, 84, 34}; i = std::clamp(i, 0, 2); return NSMakeRect(x[i], [self top] - 29, wd[i], 17); }
// 0.25.0 ARP page (FILTER panel tab 3).
- (NSRect)arpOnRect { return NSMakeRect(492, [self top] - 58, 44, 18); }
- (NSRect)arpModeRect:(int)m { return NSMakeRect(542 + m * 38, [self top] - 58, 36, 18); }
- (NSRect)arpOctRect { return NSMakeRect(492, [self top] - 84, 74, 18); }
- (NSRect)arpRateRect { return NSMakeRect(572, [self top] - 84, 88, 18); }
- (NSRect)arpLatchRect { return NSMakeRect(666, [self top] - 84, 54, 18); }
- (NSRect)arpGateRect { return NSMakeRect(492, [self top] - 108, 135, 16); }
- (NSRect)arpSwingRect { return NSMakeRect(633, [self top] - 108, 135, 16); }
- (NSRect)arpGrid { return NSMakeRect(492, [self top] - 184, 276, 66); } // 0.26.0: shorter, the pattern lane sits below
- (NSRect)arpPatOnRect { return NSMakeRect(492, [self top] - 205, 62, 18); }
- (NSRect)arpPatLenRect { return NSMakeRect(560, [self top] - 205, 70, 18); }
- (NSRect)arpSyncRect { return NSMakeRect(636, [self top] - 205, 62, 18); }
- (NSRect)arpPatLane { return NSMakeRect(492, [self top] - 246, 276, 37); }
- (NSRect)arpPatCell:(int)i { NSRect l = [self arpPatLane]; const CGFloat w = l.size.width / arp::kPatSteps; return NSMakeRect(l.origin.x + i * w, l.origin.y, w, l.size.height); }
- (NSRect)f2Display { return NSMakeRect(686, [self top] - 138, 86, 94); }
- (NSRect)f2TypeRect { NSRect r = [self f2Display]; return NSMakeRect(r.origin.x, NSMaxY(r) - 18, r.size.width, 18); }
- (NSRect)f2RouteRect:(int)i { NSRect r = [self f2Display]; return NSMakeRect(r.origin.x + 5 + i * 39, r.origin.y + 4, 37, 13); }
// 0.21.0 FILTER 1 page: model selector (arrows step the model), response display, DRIVE / KEYTRACK / MORPH bars.
- (NSRect)f1ModelRect { return NSMakeRect(676, [self top] - 29, 94, 17); } // 0.25.0: 676 (was 656 / 116) clears the ARP tab
- (NSRect)f1MsegChip { NSRect r = [self f2Display]; return NSMakeRect(NSMaxX(r) - 37, r.origin.y + 4, 33, 13); }
- (NSRect)f1Bar:(int)i { return NSMakeRect(494 + i * 94, [self top] - 167, 88, 13); }
// 0.22.0 FILTER 2 + SUB page bars: F1 MIX, F2 MIX, BALANCE, F2 MORPH (drag ids 3-6).
- (NSRect)f2Bar:(int)i { return NSMakeRect(494 + i * 71, [self top] - 167, 67, 13); }
- (NSRect)filterXBar:(int)id { return id < 3 ? [self f1Bar:id] : [self f2Bar:id - 3]; }
- (double*)filterXField:(int)id {
    VoiceParams& v = current.voice;
    double* f[7] = {&v.filterDrive, &v.filterKeytrack, &v.filterMorph, &v.filter1Mix, &v.filter2Mix, &v.filterBalance, &v.filter2Morph};
    return f[std::clamp(id, 0, 6)];
}
- (NSRect)subPill:(int)i { return NSMakeRect(563, [self top] - 190 - i * 19, 48, 15); } // 0.22.0: 4 pt lower, clear of the MIX bars
- (NSRect)wtPanel { return NSMakeRect(24, [self top] - 260, 440, 260); }
- (NSRect)wtCanvas { return NSMakeRect(40, [self top] - 184, 408, 138); }
- (NSRect)wtThumb:(int)i { return NSMakeRect(40 + i * 25.5, [self top] - 220, 23, 28); }
- (NSRect)wtButton:(int)i { return NSMakeRect(40 + i * 51, [self top] - 250, 48, 20); }
- (NSRect)wtModeTab:(int)i { return NSMakeRect(262 + i * 34, [self top] - 32, 31, 17); } // DRAW, HARM, 3D (0.20.0), SPEC (0.31.0)
- (NSRect)wtUndoRect:(int)i { return NSMakeRect(224 + i * 18, [self top] - 32, 15, 17); } // 0.32.0 UNDO, REDO
// 0.31.0 SPECTRAL page geometry (inside the canvas): preview on the left, four bipolar bars and APPLY / RESET on the right.
- (NSRect)wtSpecPreview { NSRect cv = [self wtCanvas]; return NSMakeRect(cv.origin.x + 8, cv.origin.y + 8, 196, cv.size.height - 16); }
- (NSRect)wtSpecBar:(int)i { NSRect cv = [self wtCanvas]; return NSMakeRect(cv.origin.x + 272, NSMaxY(cv) - 22 - i * 22, 88, 6); }
- (NSRect)wtSpecButton:(int)i { NSRect cv = [self wtCanvas]; return NSMakeRect(cv.origin.x + 272 + i * 66, cv.origin.y + 8, 60, 18); }
- (NSRect)wtDoneRect { return NSMakeRect(400, [self top] - 32, 48, 17); }
- (NSRect)modField:(int)j {
    int n = [self modFieldCount];
    CGFloat w = (148 - (n - 1) * 4) / (CGFloat)std::max(n, 1);
    return NSMakeRect(304 + j * (w + 4), 62, w, 50);
}
static bool IsLfo(ModRoute::Source s) {
    return s == ModRoute::Source::LFO1 || s == ModRoute::Source::LFO2 || s == ModRoute::Source::LFO3 || s == ModRoute::Source::LFO4;
}
static int LfoIndex(ModRoute::Source s) {
    return s == ModRoute::Source::LFO1 ? 0 : s == ModRoute::Source::LFO2 ? 1 : s == ModRoute::Source::LFO3 ? 2 : 3;
}
static bool IsMseg(ModRoute::Source s) { return s == ModRoute::Source::MSEG1 || s == ModRoute::Source::MSEG2; }
static int MsegIndex(ModRoute::Source s) { return s == ModRoute::Source::MSEG2 ? 1 : 0; }
static bool IsRack(ModRoute::Source s) { return s == ModRoute::Source::FxLfo1 || s == ModRoute::Source::FxLfo2; }
// 0.18.0: editor index for a source (MSEG 1/2 = 0/1, LFO 1-4 = 2-5) and back.
static int EditIndex(ModRoute::Source s) { return IsLfo(s) ? 2 + LfoIndex(s) : MsegIndex(s); }
static ModRoute::Source EditSource(int k) {
    static const ModRoute::Source src[6] = {ModRoute::Source::MSEG1, ModRoute::Source::MSEG2, ModRoute::Source::LFO1,
                                            ModRoute::Source::LFO2, ModRoute::Source::LFO3, ModRoute::Source::LFO4};
    return src[std::clamp(k, 0, 5)];
}
static int RackIndex(ModRoute::Source s) { return s == ModRoute::Source::FxLfo2 ? 1 : 0; }
static NSColor* SourceColor(ModRoute::Source s) {
    if (IsRack(s)) return C(0xb68cff);
    if (s == ModRoute::Source::MSEG2) return C(0x8fdc7a);
    if (IsLfo(s)) return C(0x6cb6ff);
    if (s == ModRoute::Source::ModEnv || s == ModRoute::Source::Env3) return C(0xf2ab55);
    if (s == ModRoute::Source::MSEG1) return C(0x66e2d0);
    if (s == ModRoute::Source::Velocity) return C(0xc792ea);
    if ((int)s >= (int)ModRoute::Source::ModWheel) return C(0xffd166); // 0.24.0 performance sources
    return C(0xf27a55); // macros
}
// Envelope stage fields for ENV 2 (0) / ENV 3 (1): A, D, S, R.
static int& OscShape(VoiceParams& v, int o) { return o ? v.osc2Shape : v.osc1Shape; }
static double& OscWtPos(VoiceParams& v, int o) { return o ? v.osc2WtPos : v.osc1WtPos; }
static NSColor* OscColor(int o) { return o ? C(0x9d7df2) : C(0x5adac8); }
// 0.31.0 SPECTRAL bars: FORMANT (st), STRETCH, TILT (dB/oct), ODD/EVEN, each mapped to -1..1 around the centre.
static double& SpecField(SpectralProcess& sp, int i) { return i == 0 ? sp.formantSt : i == 1 ? sp.stretch : i == 2 ? sp.tiltDb : sp.oddEven; }
static double SpecRange(int i) { return i == 0 ? 24.0 : i == 1 ? 0.5 : i == 2 ? 12.0 : 1.0; }
static NSString* SpecValueText(const SpectralProcess& sp, int i) {
    if (i == 0) return sp.formantSt == 0 ? @"0 st" : [NSString stringWithFormat:@"%+.0f st", sp.formantSt];
    if (i == 1) return sp.stretch == 0 ? @"0" : [NSString stringWithFormat:@"%+.2f", sp.stretch];
    if (i == 2) return sp.tiltDb == 0 ? @"0 dB" : [NSString stringWithFormat:@"%+.1f dB", sp.tiltDb];
    if (sp.oddEven == 0) return @"BOTH";
    return [NSString stringWithFormat:@"%@ %.0f%%", sp.oddEven < 0 ? @"ODD" : @"EVEN", std::fabs(sp.oddEven) * 100];
}
static NSArray<NSString*>* WtButtonLabels() { return @[@"+ ADD", @"DUP", @"DELETE", @"MORPH", @"SMOOTH", @"NORMAL", @"IMPORT", @"EXPORT"]; }
// 0.20.0: the frame strip has 16 thumbs; tables of up to 64 frames spread them evenly.
static int ThumbFrame(int i, int n) { return n <= 16 ? i : (int)std::lround(i * (n - 1) / 15.0); }
static int ThumbFor(int frame, int n) { return n <= 16 ? frame : (int)std::lround(frame * 15.0 / std::max(1, n - 1)); }
// 3D stack geometry inside the canvas: frame j of n sits at depth d (0 = front, bottom-left).
static NSRect StackRow(NSRect cv, int j, int n) {
    const double d = n > 1 ? (double)j / (n - 1) : 0.0;
    const CGFloat w = cv.size.width * .6, h = cv.size.height * .34;
    return NSMakeRect(cv.origin.x + 14 + d * (cv.size.width - w - 28), cv.origin.y + 18 + d * (cv.size.height - h - 30), w, h);
}
static void StrokeFrame(const Frame& f, NSRect r, CGFloat amp, NSColor* col, CGFloat width) {
    if (f.empty()) return;
    NSBezierPath* p = [NSBezierPath bezierPath];
    const int n = (int)f.size();
    for (int i = 0; i <= n; ++i) {
        CGFloat x = r.origin.x + r.size.width * i / (CGFloat)n;
        CGFloat y = NSMidY(r) + std::clamp((double)f[i % n], -1.1, 1.1) * r.size.height * amp;
        i ? [p lineToPoint:NSMakePoint(x, y)] : [p moveToPoint:NSMakePoint(x, y)];
    }
    [col setStroke]; p.lineWidth = width; p.lineJoinStyle = NSLineJoinStyleRound; [p stroke];
}

static double& EnvField(VoiceParams& v, bool env3, int j) {
    if (env3) return j == 0 ? v.env3A : j == 1 ? v.env3D : j == 2 ? v.env3S : v.env3R;
    return j == 0 ? v.modA : j == 1 ? v.modD : j == 2 ? v.modS : v.modR;
}
// Log-scaled 0..1 positions for drag: times 1 ms..10 s, rates 0.02..20 Hz.
static double TimeTo01(double t) { return std::log(std::clamp(t, 0.001, 10.0) / 0.001) / std::log(10000.0); }
static double TimeFrom01(double n) { return 0.001 * std::pow(10000.0, std::clamp(n, 0.0, 1.0)); }
static double RateTo01(double hz) { return std::log(std::clamp(hz, 0.02, 20.0) / 0.02) / std::log(1000.0); }
static double RateFrom01(double n) { return 0.02 * std::pow(1000.0, std::clamp(n, 0.0, 1.0)); }
- (int)modFieldCount {
    ModRoute::Source s = ui::matrixSources()[modSel];
    if (IsLfo(s) || IsRack(s)) return 3;                                      // SHAPE, RATE, SYNC
    if (IsMseg(s)) return 3;                                                  // MODE, LENGTH, SYNC
    if (s == ModRoute::Source::ModEnv || s == ModRoute::Source::Env3) return 4; // A, D, S, R
    return 0;
}

// ---- drawing ----
- (void)panel:(NSRect)r title:(NSString*)title {
    NSBezierPath* p = [NSBezierPath bezierPathWithRoundedRect:r xRadius:12 yRadius:12];
    [C(0x151a22) setFill]; [p fill];
    [C(0x29313d) setStroke]; p.lineWidth = 1; [p stroke];
    Text(title, NSMakeRect(r.origin.x + 16, NSMaxY(r) - 30, r.size.width - 32, 20), 11, C(0x8793a3), NSFontWeightSemibold);
}

- (void)knob:(int)k accent:(NSColor*)accent {
    NSPoint c = [self knobCenter:k];
    CGFloat rad = [self knobRadius:k];
    double v = ui::knobValue(current.voice, k);
    [[NSColor colorWithWhite:.04 alpha:1] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(c.x - rad - 3, c.y - rad - 3, rad * 2 + 6, rad * 2 + 6)] fill];
    CGFloat lw = ui::isMacro(k) ? 3 : 4;
    NSBezierPath* ring = [NSBezierPath bezierPath];
    [ring appendBezierPathWithArcWithCenter:c radius:rad startAngle:225 endAngle:-45 clockwise:YES];
    [C(0x303947) setStroke]; ring.lineWidth = lw; [ring stroke];
    NSBezierPath* arc = [NSBezierPath bezierPath];
    if (k == ui::Detune) // bipolar: draw from center
        [arc appendBezierPathWithArcWithCenter:c radius:rad startAngle:90 endAngle:225 - 270 * v clockwise:v > .5];
    else
        [arc appendBezierPathWithArcWithCenter:c radius:rad startAngle:225 endAngle:225 - 270 * v clockwise:YES];
    [accent setStroke]; arc.lineWidth = lw; [arc stroke];
    double a = (225 - 270 * v) * M_PI / 180;
    NSBezierPath* line = [NSBezierPath bezierPath];
    [line moveToPoint:c];
    CGFloat inset = ui::isMacro(k) ? 4 : 7;
    [line lineToPoint:NSMakePoint(c.x + cos(a) * (rad - inset), c.y + sin(a) * (rad - inset))];
    [C(0xeaf1f8) setStroke]; line.lineWidth = 2; [line stroke];
    double depth = ui::knobModDepth(current.routes, k);
    if (depth != 0) { // mod ring: where routed modulation can push this knob
        double a0 = 225 - 270 * v, a1 = 225 - 270 * std::clamp(v + depth, 0.0, 1.0);
        NSBezierPath* mr = [NSBezierPath bezierPath];
        [mr appendBezierPathWithArcWithCenter:c radius:rad + 5 startAngle:a0 endAngle:a1 clockwise:depth > 0];
        [C(0x5adac8, .9) setStroke]; mr.lineWidth = 2; mr.lineCapStyle = NSLineCapStyleRound; [mr stroke];
    }
    if (dragSource >= 0 && ui::knobDest(k) >= 0) { // drop targets while a source badge is dragged
        NSBezierPath* t = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(c.x - rad - 8, c.y - rad - 8, rad * 2 + 16, rad * 2 + 16)];
        CGFloat dash[2] = {3, 3};
        if (dropKnob != k) [t setLineDash:dash count:2 phase:0];
        [(dropKnob == k ? SourceColor(ui::matrixSources()[dragSource]) : C(0x5f6b7b)) setStroke];
        t.lineWidth = dropKnob == k ? 2 : 1; [t stroke];
    }
    NSString* label = dragKnob == k ? S(ui::knobReadout(current.voice, k)) : S(ui::knobLabel(k));
    bool macro = ui::isMacro(k);
    CGFloat lw2 = std::max<CGFloat>(60, rad * 2 + 32);
    TextA(label, NSMakeRect(c.x - lw2 / 2, c.y - rad - (macro ? 18 : 25), lw2, 13), macro ? 8 : 10,
          dragKnob == k ? accent : C(0xa8b2c1), macro ? NSFontWeightSemibold : NSFontWeightMedium, NSTextAlignmentCenter);
}

- (void)waveIn:(NSRect)r osc:(int)o shape:(int)shape warpMode:(int)wm warp:(double)w color:(NSColor*)col {
    FillRound(r, 7, C(0x0a0d12));
    [C(0x1c232d) setStroke];
    NSBezierPath* mid = [NSBezierPath bezierPath];
    [mid moveToPoint:NSMakePoint(r.origin.x + 6, NSMidY(r))]; [mid lineToPoint:NSMakePoint(NSMaxX(r) - 6, NSMidY(r))];
    mid.lineWidth = 1; [mid stroke];
    const bool user = shape == kCustomShape;
    const auto wx = ui::warpExtras(current.voice, o); // 0.19.0: second slot + REMAP curve
    std::vector<float> wv = user ? ui::waveformUser(current.tables[o], OscWtPos(current.voice, o), wm, w, 240, &wx)
                                 : ui::waveform(table, shape, wm, w, 240, &wx);
    NSBezierPath* p = [NSBezierPath bezierPath];
    for (int i = 0; i < 240; ++i) {
        CGFloat x = r.origin.x + 8 + (r.size.width - 16) * i / 239.0;
        CGFloat y = NSMidY(r) + std::clamp((double)wv[i], -1.1, 1.1) * r.size.height * .36;
        i ? [p lineToPoint:NSMakePoint(x, y)] : [p moveToPoint:NSMakePoint(x, y)];
    }
    // 0.19.0: round joins (sharp warps made miter spikes) and a clip so a wave never leaves its display
    [NSGraphicsContext saveGraphicsState];
    [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(r, 1, 1) xRadius:6 yRadius:6] addClip];
    p.lineJoinStyle = NSLineJoinStyleRound;
    [[col colorWithAlphaComponent:.25] setStroke]; p.lineWidth = 5; [p stroke];
    [col setStroke]; p.lineWidth = 1.8; [p stroke];
    [NSGraphicsContext restoreGraphicsState];
    // Click-to-edit pill, and for a user table its frame position bar.
    NSRect pill = NSMakeRect(NSMaxX(r) - 40, NSMaxY(r) - 17, 34, 13);
    FillRound(pill, 4, user ? [col colorWithAlphaComponent:.22] : C(0x161c25));
    TextA(@"EDIT", NSMakeRect(pill.origin.x, pill.origin.y + 1.5, pill.size.width, 10), 7.5, user ? col : C(0x6f7b8b),
          NSFontWeightBold, NSTextAlignmentCenter);
    if (ui::usesRemap(current.voice, o)) { // opens this oscillator's REMAP curve
        NSRect rc = [self remapChip:o];
        bool open = msegEdit == 6 + o;
        FillRound(rc, 4, open ? [col colorWithAlphaComponent:.85] : [col colorWithAlphaComponent:.22]);
        TextA(@"CURVE", NSMakeRect(rc.origin.x, rc.origin.y + 1.5, rc.size.width, 10), 7.5, open ? C(0x0b0e13) : col, NSFontWeightBold, NSTextAlignmentCenter);
    }
    if (user) {
        const TableFrames& t = current.tables[o];
        const double pos = OscWtPos(current.voice, o);
        NSRect bar = [self wtPosBar:o];
        FillRound(bar, 3.5, C(0x1a212b));
        FillRound(NSMakeRect(bar.origin.x, bar.origin.y, std::max<CGFloat>(7, bar.size.width * pos), bar.size.height), 3.5,
                  [col colorWithAlphaComponent:wtPosDrag == o ? .9 : .6]);
        int nf = std::max(1, (int)t.size());
        for (int i = 1; i < nf - 1; ++i)
            FillRound(NSMakeRect(bar.origin.x + bar.size.width * i / (nf - 1) - .5, bar.origin.y + 1.5, 1, 4), .5, C(0x0a0d12, .8));
        FillRound(NSMakeRect(r.origin.x + 5, NSMaxY(r) - 17, 50, 13), 4, C(0x0a0d12, .85)); // 0.19.0: keeps the label readable over the wave
        TextA([NSString stringWithFormat:@"POS %.0f%%", pos * 100], NSMakeRect(r.origin.x + 8, NSMaxY(r) - 16, 70, 11), 7.5,
              col, NSFontWeightSemibold, NSTextAlignmentLeft);
    }
}

- (void)drawTableEditor {
    if (wtEdit < 0 || wtEdit > 1) return;
    TableFrames& t = current.tables[wtEdit];
    if (t.empty()) { wtEdit = -1; return; }
    wtFrame = std::clamp(wtFrame, 0, (int)t.size() - 1);
    NSColor* col = OscColor(wtEdit);
    NSRect P = [self wtPanel];
    NSBezierPath* bg = [NSBezierPath bezierPathWithRoundedRect:P xRadius:12 yRadius:12];
    [C(0x131820) setFill]; [bg fill];
    [[col colorWithAlphaComponent:.55] setStroke]; bg.lineWidth = 1; [bg stroke];
    Text([NSString stringWithFormat:@"WAVETABLE  \u2022  OSC %@", wtEdit ? @"B" : @"A"],
         NSMakeRect(40, NSMaxY(P) - 30, 150, 20), 11, col, NSFontWeightSemibold);
    Text([NSString stringWithFormat:@"FRAME %d / %d", wtFrame + 1, (int)t.size()],
         NSMakeRect(146, NSMaxY(P) - 29, 78, 20), 10, C(0x8793a3), NSFontWeightMedium);
    for (int i = 0; i < 2; ++i) { // 0.32.0 UNDO / REDO: curved arrows, lit when there is a step to take
        const NSRect r = [self wtUndoRect:i];
        const bool live = i == 0 ? wtHistory[wtEdit].canUndo() : wtHistory[wtEdit].canRedo();
        FillRound(r, 4, C(0x1b222c));
        NSColor* ac = live ? C(0xc9d2dd) : C(0x3f4856);
        const CGFloat cx = NSMidX(r), cy = NSMidY(r) - 1, rad = 4.2, dir = i == 0 ? 1 : -1;
        NSBezierPath* arc = [NSBezierPath bezierPath];
        [arc appendBezierPathWithArcWithCenter:NSMakePoint(cx, cy) radius:rad startAngle:(i == 0 ? 160 : 20) endAngle:(i == 0 ? -60 : 240) clockwise:(i == 0)];
        arc.lineWidth = 1.4; arc.lineCapStyle = NSLineCapStyleRound; [ac setStroke]; [arc stroke];
        const CGFloat ax = cx - dir * rad * 0.94, ay = cy + rad * 0.34; // arrow head at the arc's start
        NSBezierPath* head = [NSBezierPath bezierPath];
        [head moveToPoint:NSMakePoint(ax - dir * 2.6, ay + 0.6)]; [head lineToPoint:NSMakePoint(ax, ay - 2.8)]; [head lineToPoint:NSMakePoint(ax + dir * 2.4, ay + 1.4)];
        head.lineWidth = 1.4; head.lineCapStyle = NSLineCapStyleRound; head.lineJoinStyle = NSLineJoinStyleRound; [head stroke];
    }
    NSArray* tabs = @[@"DRAW", @"HARM", @"3D", @"SPEC"];
    for (int i = 0; i < 4; ++i) {
        NSRect r = [self wtModeTab:i];
        FillRound(r, 4, wtMode == i ? [col colorWithAlphaComponent:.28] : C(0x1b222c));
        TextA(tabs[i], NSMakeRect(r.origin.x, r.origin.y + 3, r.size.width, 11), 8, wtMode == i ? col : C(0x8793a3),
              NSFontWeightBold, NSTextAlignmentCenter);
    }
    NSRect dn = [self wtDoneRect];
    FillRound(dn, 4, col);
    TextA(@"DONE", NSMakeRect(dn.origin.x, dn.origin.y + 3, dn.size.width, 11), 8, C(0x0b0e13), NSFontWeightBold, NSTextAlignmentCenter);

    // Canvas: grid, neighbour frames as ghosts, then the frame or its harmonics.
    NSRect cv = [self wtCanvas];
    FillRound(cv, 8, C(0x0a0d12));
    for (int i = 1; i < 8; ++i) FillRound(NSMakeRect(cv.origin.x + cv.size.width * i / 8, cv.origin.y + 6, 1, cv.size.height - 12), 0, C(0x161c25));
    for (int i = -1; i <= 1; ++i)
        FillRound(NSMakeRect(cv.origin.x + 6, NSMidY(cv) + i * cv.size.height * .42 - .5, cv.size.width - 12, 1), 0, i ? C(0x161c25) : C(0x222a36));
    const Frame& f = t[wtFrame];
    if (wtMode == 3) { // 0.31.0 SPECTRAL: preview of the processed frame over the original, bars, APPLY / RESET
        FillRound(cv, 8, C(0x0a0d12)); // no DRAW grid behind the controls
        const NSRect pv = [self wtSpecPreview];
        FillRound(pv, 6, C(0x0d1117));
        // 0.31.0 fix2: the wave gets the top of the preview, the partial spectrum its own band below it.
        const CGFloat specH = 38;
        const NSRect wv = NSMakeRect(pv.origin.x, pv.origin.y + specH + 4, pv.size.width, pv.size.height - specH - 4);
        const NSRect sp = NSMakeRect(pv.origin.x + 4, pv.origin.y + 4, pv.size.width - 8, specH - 4);
        for (int i = 1; i < 4; ++i) FillRound(NSMakeRect(wv.origin.x + wv.size.width * i / 4, wv.origin.y + 4, 1, wv.size.height - 8), 0, C(0x161c25));
        FillRound(NSMakeRect(wv.origin.x + 4, NSMidY(wv) - .5, wv.size.width - 8, 1), 0, C(0x222a36));
        FillRound(NSMakeRect(pv.origin.x + 4, pv.origin.y + specH + 1.5, pv.size.width - 8, 1), 0, C(0x1b222c));
        const Frame pf = processFrame(f, wtSpec);
        const bool changed = !wtSpec.isIdentity();
        StrokeFrame(f, NSInsetRect(wv, 4, 6), .42, [col colorWithAlphaComponent:changed ? .22 : .9], changed ? 1.2 : 1.8);
        if (changed) { StrokeFrame(pf, NSInsetRect(wv, 4, 6), .42, [col colorWithAlphaComponent:.22], 5); StrokeFrame(pf, NSInsetRect(wv, 4, 6), .42, col, 1.8); }
        // Partials 1-32 on a 48 dB scale: processed bars, original as a grey cap line on each bar.
        const int nP = 32;
        std::vector<double> hp = frameHarmonics(pf, nP), ho = frameHarmonics(f, nP);
        auto dbh = [](double a) { return a <= 0 ? 0.0 : std::clamp(1.0 + 20.0 * std::log10(a) / 48.0, 0.0, 1.0); };
        const CGFloat bw = sp.size.width / nP, barTop = sp.size.height - 10;
        for (int k = 0; k < nP; ++k) {
            const double v = dbh(hp[k]), o = dbh(ho[k]);
            const CGFloat x = sp.origin.x + k * bw;
            FillRound(NSMakeRect(x + .5, sp.origin.y, bw - 1, 1), 0, C(0x1b222c));
            if (v > 0) FillRound(NSMakeRect(x + .5, sp.origin.y, bw - 1, std::max<CGFloat>(1.5, barTop * v)), 1, [col colorWithAlphaComponent:.35 + .55 * v]);
            if (changed && o > 0) FillRound(NSMakeRect(x + .5, sp.origin.y + barTop * o - .5, bw - 1, 1.2), 0, C(0x8793a3));
        }
        TextA(@"PARTIALS 1-32", NSMakeRect(sp.origin.x + 2, NSMaxY(sp) - 8, 90, 9), 6.5, C(0x5f6b7b), NSFontWeightBold, NSTextAlignmentLeft);
        TextA(changed ? @"GREY = BEFORE" : @"48 dB", NSMakeRect(NSMaxX(sp) - 92, NSMaxY(sp) - 8, 90, 9), 6.5, C(0x4a5462), NSFontWeightBold, NSTextAlignmentRight);
        TextA(changed ? @"PREVIEW" : @"FRAME", NSMakeRect(pv.origin.x + 6, NSMaxY(pv) - 14, 80, 10), 7, changed ? col : C(0x5f6b7b), NSFontWeightBold, NSTextAlignmentLeft);
        NSArray* names = @[@"FORMANT", @"STRETCH", @"TILT", @"ODD/EVEN"];
        for (int i = 0; i < 4; ++i) {
            const NSRect bar = [self wtSpecBar:i];
            TextA(names[i], NSMakeRect(cv.origin.x + 214, bar.origin.y - 2, 56, 10), 7.5, C(0x8793a3), NSFontWeightSemibold, NSTextAlignmentLeft);
            FillRound(bar, 3, C(0x1a212b));
            const double v = std::clamp(SpecField(wtSpec, i) / SpecRange(i), -1.0, 1.0);
            const CGFloat mid = NSMidX(bar), x = mid + v * bar.size.width / 2;
            FillRound(NSMakeRect(std::min(mid, x), bar.origin.y, std::max<CGFloat>(1, std::fabs(x - mid)), bar.size.height), 3, [col colorWithAlphaComponent:wtSpecDrag == i ? .95 : .7]);
            FillRound(NSMakeRect(mid - .5, bar.origin.y - 2, 1, bar.size.height + 4), 0, C(0x3a4452));
            FillRound(NSMakeRect(x - 4, NSMidY(bar) - 4, 8, 8), 4, v == 0 ? C(0x5f6b7b) : C(0xeaf1f8));
            TextA(SpecValueText(wtSpec, i), NSMakeRect(NSMaxX(bar) + 4, bar.origin.y - 2.5, 50, 11), 8, v == 0 ? C(0x5f6b7b) : C(0xe6ebf1), NSFontWeightSemibold, NSTextAlignmentRight);
        }
        TextA([NSString stringWithFormat:@"APPLIES TO ALL %d FRAMES", (int)t.size()], NSMakeRect(cv.origin.x + 214, cv.origin.y + 31, 190, 10), 7,
              C(0x4a5462), NSFontWeightSemibold, NSTextAlignmentLeft);
        for (int i = 0; i < 2; ++i) {
            const NSRect b = [self wtSpecButton:i];
            const bool live = changed;
            if (i == 0) FillRound(b, 4, live ? col : C(0x1b222c));
            else { FillRound(b, 4, C(0x1b222c)); }
            TextA(i == 0 ? @"APPLY" : @"RESET", NSMakeRect(b.origin.x, b.origin.y + 4, b.size.width, 11), 8,
                  i == 0 ? (live ? C(0x0b0e13) : C(0x5f6b7b)) : (live ? C(0xc9d2dd) : C(0x5f6b7b)), NSFontWeightBold, NSTextAlignmentCenter);
        }
    } else if (wtMode == 2) { // 0.20.0 3D stack, back to front; each frame occludes the ones behind it
        const int n = (int)t.size();
        [NSGraphicsContext saveGraphicsState];
        [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(cv, 1, 1) xRadius:7 yRadius:7] addClip];
        for (int j = n - 1; j >= 0; --j) {
            NSRect row = StackRow(cv, j, n);
            const Frame& fr = t[j];
            NSBezierPath* line = [NSBezierPath bezierPath];
            NSBezierPath* body = [NSBezierPath bezierPath];
            [body moveToPoint:NSMakePoint(row.origin.x, row.origin.y)];
            const int N = (int)fr.size();
            for (int i = 0; i <= N; i += 2) {
                NSPoint q = NSMakePoint(row.origin.x + row.size.width * i / (CGFloat)N,
                                        NSMidY(row) + std::clamp((double)fr[i % N], -1.1, 1.1) * row.size.height * .5);
                i ? [line lineToPoint:q] : [line moveToPoint:q];
                [body lineToPoint:q];
            }
            [body lineToPoint:NSMakePoint(NSMaxX(row), row.origin.y)]; [body closePath];
            const double depth = n > 1 ? (double)j / (n - 1) : 0.0;
            [C(0x0a0d12, j == wtFrame ? .55 : .8) setFill]; [body fill];
            if (j == wtFrame) {
                [[col colorWithAlphaComponent:.22] setFill]; [body fill];
                [[col colorWithAlphaComponent:.3] setStroke]; line.lineWidth = 5; line.lineJoinStyle = NSLineJoinStyleRound; [line stroke];
                [col setStroke]; line.lineWidth = 1.8; [line stroke];
            } else {
                [[col colorWithAlphaComponent:.75 - .5 * depth] setStroke]; line.lineWidth = n > 24 ? .8 : 1.1; line.lineJoinStyle = NSLineJoinStyleRound; [line stroke];
            }
        }
        [NSGraphicsContext restoreGraphicsState];
        NSRect sel = StackRow(cv, wtFrame, n);
        TextA([NSString stringWithFormat:@"%d", wtFrame + 1], NSMakeRect(NSMaxX(sel) + 4, NSMidY(sel) - 5, 26, 10), 8, col, NSFontWeightBold, NSTextAlignmentLeft);
        TextA(@"CLICK A FRAME TO SELECT IT", NSMakeRect(NSMaxX(cv) - 170, cv.origin.y + 6, 162, 11), 7.5, C(0x4a5462),
              NSFontWeightSemibold, NSTextAlignmentRight);
    } else if (wtMode == 0) {
        if (wtFrame > 0) StrokeFrame(t[wtFrame - 1], cv, .42, [col colorWithAlphaComponent:.14], 1);
        if (wtFrame + 1 < (int)t.size()) StrokeFrame(t[wtFrame + 1], cv, .42, [col colorWithAlphaComponent:.14], 1);
        StrokeFrame(f, cv, .42, [col colorWithAlphaComponent:.22], 6);
        StrokeFrame(f, cv, .42, col, 2);
        TextA(@"DRAW WITH THE MOUSE", NSMakeRect(NSMaxX(cv) - 150, cv.origin.y + 6, 142, 11), 7.5, C(0x4a5462),
              NSFontWeightSemibold, NSTextAlignmentRight);
    } else {
        StrokeFrame(f, cv, .42, [col colorWithAlphaComponent:.12], 1.5);
        std::vector<double> hs = frameHarmonics(f, 32);
        CGFloat bw = cv.size.width / 32.0;
        for (int k = 0; k < 32; ++k) {
            NSRect br = NSMakeRect(cv.origin.x + k * bw + 2, cv.origin.y + 16, bw - 4, 0);
            br.size.height = std::max<CGFloat>(2, (cv.size.height - 26) * std::clamp(hs[k], 0.0, 1.0));
            FillRound(NSMakeRect(br.origin.x, cv.origin.y + 16, br.size.width, cv.size.height - 26), 2, C(0x121821));
            FillRound(br, 2, [col colorWithAlphaComponent:.45 + .5 * std::clamp(hs[k], 0.0, 1.0)]);
            if (k == 0 || (k + 1) % 4 == 0)
                TextA([NSString stringWithFormat:@"%d", k + 1], NSMakeRect(br.origin.x - 4, cv.origin.y + 4, bw + 0, 10), 7,
                      C(0x5f6b7b), NSFontWeightMedium, NSTextAlignmentCenter);
        }
    }

    // Frame strip.
    const int nT = (int)t.size(), selT = ThumbFor(wtFrame, nT);
    for (int i = 0; i < 16; ++i) {
        NSRect r = [self wtThumb:i];
        if (i < std::min(nT, 16)) {
            const bool on = i == selT;
            const int fi = on ? wtFrame : ThumbFrame(i, nT); // 0.31.0 fix2: the selected thumb shows the frame being edited
            FillRound(r, 4, on ? [col colorWithAlphaComponent:.22] : C(0x0f141b));
            if (nT > 16) { // 0.21.0: the frame number gets its own band under the wave instead of sitting on it
                StrokeFrame(t[fi], NSMakeRect(r.origin.x + 2, r.origin.y + 11, r.size.width - 4, r.size.height - 13), .4,
                            on ? col : [col colorWithAlphaComponent:.55], 1);
                FillRound(NSMakeRect(r.origin.x + 2, r.origin.y + 2, r.size.width - 4, 9), 2, on ? [col colorWithAlphaComponent:.28] : C(0x161c25));
                TextA([NSString stringWithFormat:@"%d", fi + 1], NSMakeRect(r.origin.x, r.origin.y + 2.5, r.size.width, 9), 7,
                      on ? C(0xeaf1f8) : C(0xa8b2c1), NSFontWeightSemibold, NSTextAlignmentCenter);
            } else
                StrokeFrame(t[fi], NSInsetRect(r, 2, 4), .4, on ? col : [col colorWithAlphaComponent:.55], 1);
            if (on) {
                NSBezierPath* sel = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(r, .5, .5) xRadius:4 yRadius:4];
                [col setStroke]; sel.lineWidth = 1; [sel stroke];
            }
        } else {
            FillRound(r, 4, C(0x0e1218));
        }
    }
    NSArray* labels = WtButtonLabels();
    for (int i = 0; i < (int)labels.count; ++i) {
        NSRect r = [self wtButton:i];
        FillRound(r, 4, C(0x1d2430));
        TextA(labels[i], NSMakeRect(r.origin.x, r.origin.y + 4.5, r.size.width, 11), 7.5, C(0xc3cbd6), NSFontWeightBold, NSTextAlignmentCenter);
    }
}

- (void)curve:(const std::vector<MSEG::Point>&)pts in:(NSRect)r color:(NSColor*)col dots:(BOOL)dots {
    NSBezierPath* p = [NSBezierPath bezierPath];
    for (size_t i = 0; i < pts.size(); ++i) {
        NSPoint q = NSMakePoint(r.origin.x + r.size.width * pts[i].time,
                                NSMidY(r) + std::clamp(pts[i].value, -1.0, 1.0) * r.size.height * .5);
        i ? [p lineToPoint:q] : [p moveToPoint:q];
    }
    [col setStroke]; p.lineWidth = 1.6; [p stroke];
    if (!dots) return;
    for (const auto& pt : pts) {
        NSPoint q = NSMakePoint(r.origin.x + r.size.width * pt.time, NSMidY(r) + std::clamp(pt.value, -1.0, 1.0) * r.size.height * .5);
        [C(0xeaf1f8) setFill];
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(q.x - 2, q.y - 2, 4, 4)] fill];
    }
}

// Filter 2 response plus the whole filter section: filter 1 (dim), filter 2 (thin)
// and the combined serial/parallel result with both MIX amounts and BALANCE (bold).
- (void)filter2In:(NSRect)r {
    const VoiceParams& v = current.voice;
    FillRound(r, 7, C(0x0a0d12));
    const bool on = v.filter2Type != 0;
    Text([NSString stringWithFormat:@"F2 \u2022 %s", ui::filter2TypeName(v.filter2Type)], NSMakeRect(r.origin.x + 6, NSMaxY(r) - 15, r.size.width - 8, 12), 8,
         on ? C(0xf2ab55) : C(0x6f7b8b), NSFontWeightSemibold);
    NSRect plot = NSMakeRect(r.origin.x + 5, r.origin.y + 21, r.size.width - 10, r.size.height - 40);
    for (int g = 0; g < 3; ++g) // 0 dB, -18 dB, -36 dB guides
        FillRound(NSMakeRect(plot.origin.x, plot.origin.y + plot.size.height * (48.0 - 12.0 - g * 18.0) / 48.0, plot.size.width, 1), 0, C(g ? 0x141a22 : 0x1c232d));
    const double sr = 44100.0, lo = 30.0, hi = 18000.0;
    Filter1 f1; f1.setSampleRate(sr); f1.setMode(v.filterMode); f1.setDrive(v.filterDrive); f1.setMorph(v.filterMorph);
    f1.setOversample(v.filterDrive > 0); f1.set(v.filterCutoff, v.filterReso);
    Filter2 f2; f2.setSampleRate(sr); f2.setType(v.filter2Type); f2.setMorph(v.filter2Morph); f2.set(v.filter2Cutoff, v.filter2Reso);
    const bool comb1 = v.filterMode == 6 || v.filterMode == 7, comb2 = v.filter2Type == 4 || v.filter2Type == 7;
    const int pts = (comb1 || comb2) ? 72 : 48;
    const double m1 = std::clamp(v.filter1Mix, 0.0, 1.0), m2 = std::clamp(v.filter2Mix, 0.0, 1.0), bal = std::clamp(v.filterBalance, 0.0, 1.0);
    NSBezierPath *p1 = [NSBezierPath bezierPath], *p2 = [NSBezierPath bezierPath], *pt = [NSBezierPath bezierPath];
    auto yOf = [&](std::complex<double> h) { return plot.origin.y + plot.size.height * (std::clamp(20 * std::log10(std::abs(h) + 1e-6), -36.0, 12.0) + 36.0) / 48.0; };
    for (int i = 0; i < pts; ++i) {
        const double hz = lo * std::pow(hi / lo, i / (double)(pts - 1));
        // Dry paths are delayed to match an oversampled filter (as the voice does), so they carry that phase too.
        const double w = 2 * M_PI * hz / sr;
        const int d1 = f1.latency(), d2 = f2.latency();
        const std::complex<double> dry1 = std::polar(1.0, -w * d1), dry2 = std::polar(1.0, -w * d2);
        const std::complex<double> h1 = MeasureH(f1, hz, 0.25, comb1);
        const std::complex<double> a1 = dry1 + m1 * (h1 - dry1);
        std::complex<double> a2 = 1.0, total = a1;
        if (on) {
            const std::complex<double> h2 = MeasureH(f2, hz, 0.25, comb2);
            a2 = dry2 + m2 * (h2 - dry2);
            const int dd = d1 - d2; // parallel: the earlier path waits for the later one
            total = v.filterRouting == 1 ? (1.0 - bal) * a1 * std::polar(1.0, -w * std::max(0, -dd)) + bal * a2 * std::polar(1.0, -w * std::max(0, dd)) : a1 * a2;
        }
        const CGFloat x = plot.origin.x + plot.size.width * i / (pts - 1);
        NSPoint q1 = NSMakePoint(x, yOf(a1)), q2 = NSMakePoint(x, yOf(a2)), qt = NSMakePoint(x, yOf(total));
        if (i) { [p1 lineToPoint:q1]; [p2 lineToPoint:q2]; [pt lineToPoint:qt]; }
        else { [p1 moveToPoint:q1]; [p2 moveToPoint:q2]; [pt moveToPoint:qt]; }
    }
    [C(0xf2ab55, .30) setStroke]; p1.lineWidth = 1; [p1 stroke];              // filter 1 alone
    if (on) { [C(0x6cb6ff, .75) setStroke]; p2.lineWidth = 1; [p2 stroke]; } // filter 2 alone
    NSBezierPath* fill = [pt copy];
    [fill lineToPoint:NSMakePoint(NSMaxX(plot), plot.origin.y)]; [fill lineToPoint:NSMakePoint(plot.origin.x, plot.origin.y)]; [fill closePath];
    [C(0xeaf1f8, .07) setFill]; [fill fill];
    [C(0xeaf1f8, .20) setStroke]; pt.lineWidth = 3.5; [pt stroke];            // what you hear
    [C(0xeaf1f8) setStroke]; pt.lineWidth = 1.4; [pt stroke];
    if (!on)
        TextA(@"click to enable", NSMakeRect(plot.origin.x, NSMaxY(plot) - 12, plot.size.width, 11), 7.5, C(0x4a5462),
              NSFontWeightSemibold, NSTextAlignmentCenter);
    NSArray* routes = @[@"SER", @"PAR"];
    for (int i = 0; i < 2; ++i) {
        NSRect b = [self f2RouteRect:i];
        bool sel = v.filterRouting == i;
        FillRound(b, 3, sel ? C(0xf2ab55, .25) : C(0x161c25));
        TextA(routes[i], NSMakeRect(b.origin.x, b.origin.y + 2, b.size.width, 10), 7, sel ? C(0xf2ab55) : C(0x6f7b8b),
              NSFontWeightBold, NSTextAlignmentCenter);
    }
}

// Filter 1 response, measured by running the real filter 1 model on test tones.
- (void)filter1In:(NSRect)r {
    const VoiceParams& v = current.voice;
    FillRound(r, 7, C(0x0a0d12));
    Text(@"RESPONSE", NSMakeRect(r.origin.x + 6, NSMaxY(r) - 15, r.size.width - 8, 12), 8, C(0xf2ab55), NSFontWeightSemibold);
    NSRect plot = NSMakeRect(r.origin.x + 5, r.origin.y + 21, r.size.width - 10, r.size.height - 40);
    for (int g = 0; g < 3; ++g) // 0 dB, -18 dB, -36 dB guides
        FillRound(NSMakeRect(plot.origin.x, plot.origin.y + plot.size.height * (48.0 - 12.0 - g * 18.0) / 48.0, plot.size.width, 1), 0, C(g ? 0x141a22 : 0x1c232d));
    const double sr = 44100.0, lo = 30.0, hi = 18000.0;
    const double fc = std::clamp((double)v.filterCutoff, lo, hi);
    CGFloat cx = plot.origin.x + plot.size.width * std::log(fc / lo) / std::log(hi / lo);
    FillRound(NSMakeRect(cx - .5, plot.origin.y, 1, plot.size.height), 0, C(0xf2ab55, .22));
    Filter1 f; f.setSampleRate(sr); f.setMode(v.filterMode); f.setDrive(v.filterDrive); f.setMorph(v.filterMorph); f.set(v.filterCutoff, v.filterReso);
    const bool comb = v.filterMode == 6 || v.filterMode == 7;
    const int pts = comb ? 80 : 48;
    const double amp = 0.25;
    NSBezierPath* path = [NSBezierPath bezierPath];
    for (int i = 0; i < pts; ++i) {
        const double hz = lo * std::pow(hi / lo, i / (double)(pts - 1));
        f.reset();
        double re = 0, im = 0; // fundamental only (single-bin DFT), so DRIVE's harmonics don't read as gain
        const int cycles = std::max(1, (int)std::ceil(500 * hz / sr));      // whole cycles, so low tones don't leak
        const int win = (int)std::lround(cycles * sr / hz), n = (comb ? 2100 : 900) + win;
        for (int s2 = 0; s2 < n; ++s2) {
            const double ph = 2 * M_PI * hz * s2 / sr;
            float y = f.process((float)(amp * std::sin(ph)));
            if (s2 >= n - win) { re += y * std::cos(ph); im += y * std::sin(ph); }
        }
        const double pk = 2 * std::sqrt(re * re + im * im) / win;
        const double db = std::clamp(20 * std::log10(pk / amp + 1e-6), -36.0, 12.0);
        CGFloat x = plot.origin.x + plot.size.width * i / (pts - 1);
        CGFloat y = plot.origin.y + plot.size.height * (db + 36.0) / 48.0;
        i ? [path lineToPoint:NSMakePoint(x, y)] : [path moveToPoint:NSMakePoint(x, y)];
    }
    NSBezierPath* fill = [path copy];
    [fill lineToPoint:NSMakePoint(NSMaxX(plot), plot.origin.y)]; [fill lineToPoint:NSMakePoint(plot.origin.x, plot.origin.y)]; [fill closePath];
    [C(0xf2ab55, .10) setFill]; [fill fill];
    [C(0xf2ab55, .25) setStroke]; path.lineWidth = 4; [path stroke];
    [C(0xf2ab55) setStroke]; path.lineWidth = 1.5; [path stroke];
    char b[16];
    if (fc >= 1000) snprintf(b, sizeof b, "%.1fk", fc / 1000); else snprintf(b, sizeof b, "%.0f", fc);
    TextA(S(b), NSMakeRect(r.origin.x + 5, r.origin.y + 5, 36, 10), 7, C(0x8793a3), NSFontWeightSemibold, NSTextAlignmentLeft);
    NSRect m = [self f1MsegChip]; // MSEG 1 lives one click away (its editor)
    FillRound(m, 3, C(0x161c25));
    TextA(@"MSEG", NSMakeRect(m.origin.x, m.origin.y + 2, m.size.width, 10), 7, C(0x66e2d0), NSFontWeightBold, NSTextAlignmentCenter);
}

// A labelled 0..100% drag bar (FILTER pages).
- (void)valueBar:(NSRect)r label:(NSString*)label value:(double)val live:(bool)live {
    FillRound(r, 3, C(0x1c232d));
    if (val > 0) FillRound(NSMakeRect(r.origin.x, r.origin.y, std::max<CGFloat>(4, r.size.width * val), r.size.height), 3, live ? C(0xf2ab55, .55) : C(0x4a5462, .6));
    TextA(label, NSMakeRect(r.origin.x + 5, r.origin.y + 2, r.size.width - 10, 10), 7, live ? C(0xe8edf3) : C(0x8793a3), NSFontWeightBold, NSTextAlignmentLeft);
    char b[8]; snprintf(b, sizeof b, "%.0f%%", val * 100);
    TextA(S(b), NSMakeRect(r.origin.x + 5, r.origin.y + 2, r.size.width - 10, 10), 7, live ? C(0xe8edf3) : C(0x8793a3), NSFontWeightSemibold, NSTextAlignmentRight);
}

- (void)filter2Controls { // 0.22.0
    const VoiceParams& v = current.voice;
    const bool on = v.filter2Type != 0;
    NSString* names[4] = {@"F1 MIX", @"F2 MIX", @"BALANCE", @"MORPH"};
    const bool live[4] = {true, on, on && v.filterRouting == 1, on && v.filter2Type == 8};
    for (int i = 0; i < 4; ++i) [self valueBar:[self f2Bar:i] label:names[i] value:*[self filterXField:3 + i] live:live[i]];
}

- (void)filter1Controls {
    const VoiceParams& v = current.voice;
    NSRect mr = [self f1ModelRect];
    FillRound(mr, 4, C(0x1b222c));
    for (int side = 0; side < 2; ++side) { // model arrows: filled triangles, easy to see and hit
        const CGFloat ax = side ? NSMaxX(mr) - 10 : mr.origin.x + 10, ay = NSMidY(mr), d = side ? 1 : -1;
        NSBezierPath* tri = [NSBezierPath bezierPath];
        [tri moveToPoint:NSMakePoint(ax + 3 * d, ay)];
        [tri lineToPoint:NSMakePoint(ax - 2.5 * d, ay + 4)];
        [tri lineToPoint:NSMakePoint(ax - 2.5 * d, ay - 4)];
        [tri closePath];
        [C(0xc3cbd6) setFill]; [tri fill];
    }
    TextFit(S(ui::filterModeName(v.filterMode)), NSMakeRect(mr.origin.x + 14, mr.origin.y + 3, mr.size.width - 28, 11), 8.5, 7, C(0xf2ab55),
          NSFontWeightBold, NSTextAlignmentCenter);
    const char* names[3] = {"DRIVE", "KEYTRACK", "MORPH"};
    const double vals[3] = {v.filterDrive, v.filterKeytrack, v.filterMorph};
    for (int i = 0; i < 3; ++i) {
        NSRect r = [self f1Bar:i];
        const bool live = i != 2 || v.filterMode == 8; // MORPH shapes only the MORPH model
        NSColor* col = live ? C(0xf2ab55) : C(0x4a5462);
        FillRound(r, 3, C(0x1c232d));
        if (vals[i] > 0) FillRound(NSMakeRect(r.origin.x, r.origin.y, std::max<CGFloat>(4, r.size.width * vals[i]), r.size.height), 3, live ? C(0xf2ab55, .55) : C(0x4a5462, .6));
        TextA(S(names[i]), NSMakeRect(r.origin.x + 5, r.origin.y + 2, r.size.width - 10, 10), 7, live ? C(0xe8edf3) : C(0x8793a3), NSFontWeightBold, NSTextAlignmentLeft);
        char b[8]; snprintf(b, sizeof b, "%.0f%%", vals[i] * 100);
        TextA(S(b), NSMakeRect(r.origin.x + 5, r.origin.y + 2, r.size.width - 10, 10), 7, live ? C(0xe8edf3) : C(0x8793a3), NSFontWeightSemibold, NSTextAlignmentRight);
        (void)col;
    }
}

- (void)msegIn:(NSRect)r {
    FillRound(r, 7, C(0x0a0d12));
    Text(current.voice.mseg1Loop ? @"MSEG 1 \u2022 LOOP" : @"MSEG 1", NSMakeRect(r.origin.x + 6, NSMaxY(r) - 15, r.size.width - 8, 12), 8, C(0x66e2d0), NSFontWeightSemibold);
    NSRect plot = NSMakeRect(r.origin.x + 7, r.origin.y + 8, r.size.width - 14, r.size.height - 30);
    const auto& pts = current.voice.mseg1Points;
    if (current.voice.mseg1Loop && pts.size() > 2) {
        CGFloat x0 = plot.origin.x + plot.size.width * pts[1].time;
        CGFloat x1 = plot.origin.x + plot.size.width * pts.back().time;
        FillRound(NSMakeRect(x0, plot.origin.y - 3, x1 - x0, plot.size.height + 6), 3, C(0x5adac8, .10));
    }
    [self curve:pts in:plot color:C(0x5adac8) dots:YES];
}

// Shape of a modulation source, drawn in its matrix slot.
// 0.24.0 performance preview: a meter for WHL / AT / PB and the keyboard ramp for KEY, with the live value.
- (void)perfPreview:(ModRoute::Source)src in:(NSRect)r color:(NSColor*)col {
    using S = ModRoute::Source;
    NSString* ro = @"";
    if (src == S::Keytrack) {
        const int keys = 21; // three octaves of white keys, C1..B3 style strip under the ramp
        const CGFloat kw = r.size.width / keys;
        for (int k = 0; k < keys; ++k) FillRound(NSMakeRect(r.origin.x + k * kw + .5, r.origin.y, kw - 1, 9), 1, C(0x2a323e));
        NSBezierPath* ramp = [NSBezierPath bezierPath];
        [ramp moveToPoint:NSMakePoint(r.origin.x, r.origin.y + 12)];
        [ramp lineToPoint:NSMakePoint(NSMaxX(r), NSMaxY(r) - 2)];
        [col setStroke]; ramp.lineWidth = 1.5; [ramp stroke];
        const CGFloat cx = NSMidX(r); // C3 = 0
        [[col colorWithAlphaComponent:.35] setStroke];
        NSBezierPath* c3 = [NSBezierPath bezierPath]; [c3 moveToPoint:NSMakePoint(cx, r.origin.y)]; [c3 lineToPoint:NSMakePoint(cx, NSMaxY(r))]; c3.lineWidth = 1; [c3 stroke];
        if (perfNote >= 0) {
            const double k = std::clamp((perfNote - 60) / 60.0, -1.0, 1.0);
            const CGFloat x = r.origin.x + (k + 1) * 0.5 * r.size.width, y = r.origin.y + 12 + (k + 1) * 0.5 * (r.size.height - 14);
            [col setFill]; [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(x - 3, y - 3, 6, 6)] fill];
            ro = [NSString stringWithFormat:@"NOTE %d  %+.0f%%", perfNote, k * 100];
        } else ro = @"0 AT C3";
    } else {
        const bool bip = src == S::PitchBend;
        const double v = src == S::ModWheel ? perfShown.wheel : src == S::Aftertouch ? perfShown.aftertouch : perfShown.bend;
        const NSRect bar = NSMakeRect(r.origin.x + 4, NSMidY(r) - 5, r.size.width - 8, 10);
        FillRound(bar, 3, C(0x1c232d));
        const CGFloat zero = bip ? NSMidX(bar) : bar.origin.x;
        const CGFloat to = bip ? NSMidX(bar) + v * bar.size.width / 2 : bar.origin.x + v * bar.size.width;
        if (std::fabs(to - zero) > 0.5) FillRound(NSMakeRect(std::min(zero, to), bar.origin.y, std::fabs(to - zero), bar.size.height), 3, col);
        if (bip) FillRound(NSMakeRect(NSMidX(bar) - .5, bar.origin.y - 3, 1, bar.size.height + 6), .5, C(0x8793a3));
        if (src == S::PitchBend) ro = [NSString stringWithFormat:@"%+.2f  (%+.1f ST)", v, v * current.voice.bendRange];
        else ro = [NSString stringWithFormat:@"%.0f%%", v * 100];
    }
    TextA(ro, NSMakeRect(r.origin.x, NSMaxY(r) - 9, r.size.width, 10), 7, C(0xd5dce5), NSFontWeightBold, NSTextAlignmentRight);
}
- (void)showPerformance:(const muew::Performance&)p note:(int)note sustain:(bool)sus {
    if (p.wheel == perfShown.wheel && p.aftertouch == perfShown.aftertouch && p.bend == perfShown.bend && note == perfNote && sus == perfSustain) return;
    perfShown = p; perfNote = note; perfSustain = sus;
    [self setNeedsDisplay:YES];
}
// Read by the CI harness through KVC: the performance the editor is showing.
- (NSString*)muewPerformanceText {
    return [NSString stringWithFormat:@"sel=%s wheel=%.3f at=%.3f bend=%.3f note=%d sustain=%d range=%d overlay=%d/%d", ui::sourceBadge(ui::matrixSources()[modSel]),
            perfShown.wheel, perfShown.aftertouch, perfShown.bend, perfNote, perfSustain ? 1 : 0, current.voice.bendRange, msegEdit, fxDetail];
}
- (void)sourcePreview:(ModRoute::Source)src in:(NSRect)r color:(NSColor*)col {
    FillRound(NSInsetRect(r, -4, -4), 5, C(0x0f141b));
    const VoiceParams& v = current.voice;
    std::vector<MSEG::Point> pts;
    if (IsMseg(src)) { // sampled through the engine so segment curves show
        MSEG m; m.setPoints(src == ModRoute::Source::MSEG2 ? v.mseg2Points : v.mseg1Points);
        for (int i = 0; i <= 64; ++i) pts.push_back({i / 64.0, m.valueAt(i / 64.0)});
    } else if (src == ModRoute::Source::ModEnv || src == ModRoute::Source::Env3) {
        bool e3 = src == ModRoute::Source::Env3;
        double a = std::max(e3 ? v.env3A : v.modA, 0.001), d = std::max(e3 ? v.env3D : v.modD, 0.001), rel = std::max(e3 ? v.env3R : v.modR, 0.001);
        double total = a + d + rel + (a + d + rel) * 0.4;
        double t1 = a / total, t2 = (a + d) / total, t3 = 1.0 - rel / total;
        double sus = std::clamp(e3 ? v.env3S : v.modS, 0.0, 1.0) * 2 - 1;
        pts = {{0, -1}, {t1, 1}, {t2, sus}, {t3, sus}, {1, -1}};
    } else if ((int)src >= (int)ModRoute::Source::ModWheel) { // 0.24.0: live value (WHL / AT 0..1, PB -1..1), KEY a ramp over the keys
        [self perfPreview:src in:r color:col];
        return;
    } else if (src == ModRoute::Source::Velocity) {
        pts = {{0, -1}, {1, 1}};
    } else if ((int)src >= (int)ModRoute::Source::Macro1 && (int)src <= (int)ModRoute::Source::Macro4) {
        double m = v.macros[(int)src - (int)ModRoute::Source::Macro1] * 2 - 1; // current macro position
        pts = {{0, m}, {1, m}};
    } else if (IsRack(src)) {
        int shape = current.fx.lfo[RackIndex(src)].shape;
        for (int i = 0; i <= 64; ++i) {
            double t = i / 64.0, ph = std::fmod(t * 2.0, 1.0);
            if ((shape == 2 || shape == 3) && i % 32 == 0 && i > 0) pts.push_back({t - 1e-6, rackLfoValue(shape, 0.999999)});
            if (shape == 3 && (i % 32 == 16)) pts.push_back({t - 1e-6, rackLfoValue(shape, 0.49)});
            pts.push_back({t, rackLfoValue(shape, ph)});
        }
    } else if (v.lfoCustom[LfoIndex(src)]) { // 0.18.0: the drawn cycle, twice
        MSEG m; m.setPoints(v.lfoPoints[LfoIndex(src)]);
        for (int i = 0; i <= 96; ++i) { double t = i / 96.0; pts.push_back({t, m.valueAt(std::fmod(t * 2.0, 1.0) + (i == 96 ? 1.0 : 0.0))}); }
    } else {
        int shape = ui::lfoShape(const_cast<VoiceParams&>(v), LfoIndex(src));
        for (int i = 0; i <= 64; ++i) {
            double t = i / 64.0, ph = std::fmod(t * 2.0, 1.0), y = 0;
            switch (shape) {
            case 0: y = std::sin(2 * M_PI * t * 2); break;
            case 1: y = ph < .5 ? 4 * ph - 1 : 3 - 4 * ph; break;
            case 2: y = 2 * ph - 1; if (i % 32 == 0 && i > 0) pts.push_back({t - 1e-6, 1}); break;
            default: y = ph < .5 ? 1 : -1; break;
            }
            pts.push_back({t, y});
        }
    }
    [self curve:pts in:r color:col dots:NO];
}

- (void)drawRect:(NSRect)dirty {
    NSRect b = self.bounds;
    [C(0x0b0e13) setFill]; NSRectFill(b);
    NSGradient* g = [[NSGradient alloc] initWithStartingColor:C(0x121822) endingColor:C(0x080a0e)];
    [g drawInRect:NSMakeRect(0, b.size.height - 82, b.size.width, 82) angle:270];
    Text(@"MUEW", NSMakeRect(28, b.size.height - 59, 180, 38), 28, C(0xf5f7fa), NSFontWeightBold);
    Text(@"WAVETABLE INSTRUMENT", NSMakeRect(126, b.size.height - 50, 200, 16), 10, C(0x5adac8), NSFontWeightSemibold);
    [self drawEngine]; // 0.30.0

    // Preset display
    NSRect disp = NSMakeRect(380, b.size.height - 66, 320, 40);
    FillRound(disp, 8, C(0x0a0d12));
    [C(0x29313d) setStroke];
    [[NSBezierPath bezierPathWithRoundedRect:disp xRadius:8 yRadius:8] stroke];
    TextA(@"\u25C0", [self prevRect], 13, C(0x75ead8), NSFontWeightRegular, NSTextAlignmentCenter);
    TextA(@"\u25B6", [self nextRect], 13, C(0x75ead8), NSFontWeightRegular, NSTextAlignmentCenter);
    std::string pname = currentIndex >= 0 ? current.info.name : "Init";
    if (edited) pname += " *";
    TextA(S(pname), NSMakeRect(414, b.size.height - 47, 252, 18), 14, C(0xf5f7fa), NSFontWeightSemibold, NSTextAlignmentCenter);
    std::string sub = current.info.category;
    for (size_t i = 0; i < current.info.tags.size() && i < 2; ++i) sub += "  \u2022  " + current.info.tags[i];
    TextA(S(sub), NSMakeRect(414, b.size.height - 62, 252, 13), 9, C(0x758192), NSFontWeightMedium, NSTextAlignmentCenter);
    // Macro strip
    TextA(@"MACROS", NSMakeRect(716, b.size.height - 43, 38, 12), 8, C(0x5f6b7b), NSFontWeightSemibold, NSTextAlignmentRight);
    [self knob:ui::Macro1 accent:C(0xf2ab55)];
    [self knob:ui::Macro2 accent:C(0x9d7df2)];
    [self knob:ui::Macro3 accent:C(0xf2ab55)];
    [self knob:ui::Macro4 accent:C(0x5adac8)];

    CGFloat top = [self top];
    [self panel:NSMakeRect(24, top - 260, 440, 260) title:@"OSCILLATORS"];
    [self panel:NSMakeRect(478, top - 260, 306, 260) title:@""];
    [self panel:NSMakeRect(798, 38, b.size.width - 822, top - 38) title:@"PRESET BROWSER"];

    // Oscillators
    const VoiceParams& v = current.voice;
    NSRect wa = [self oscDisplay:0], wb = [self oscDisplay:1];
    [self waveIn:wa osc:0 shape:v.osc1Shape warpMode:v.osc1WarpMode warp:v.osc1Warp color:C(0x5adac8)];
    [self waveIn:wb osc:1 shape:v.osc2Shape warpMode:v.osc2WarpMode warp:v.osc2Warp color:C(0x9d7df2)];
    Text([NSString stringWithFormat:@"OSC A  \u2022  %s%@  \u2022  %s", ui::shapeName(v.osc1Shape),
          v.osc1Shape == kCustomShape ? [NSString stringWithFormat:@" %dF", std::max(1, (int)current.tables[0].size())] : @"", ui::warpName(v.osc1WarpMode)],
         NSMakeRect(50, top - 47, 190, 16), 10, C(0x5adac8), NSFontWeightSemibold);
    Text([NSString stringWithFormat:@"OSC B  \u2022  %s%@  \u2022  %s", ui::shapeName(v.osc2Shape),
          v.osc2Shape == kCustomShape ? [NSString stringWithFormat:@" %dF", std::max(1, (int)current.tables[1].size())] : @"", ui::warpName(v.osc2WarpMode)],
         NSMakeRect(256, top - 47, 190, 16), 10, C(0x9d7df2), NSFontWeightSemibold);
    [self drawVoiceStrip]; // 0.23.0
    for (int o = 0; o < 2; ++o) { // unison strips
        NSColor* col = o ? C(0x9d7df2) : C(0x5adac8);
        NSRect st = [self unisonStrip:o];
        FillRound(st, 5, C(0x0f141b));
        int n = ui::unisonVoices(v, o);
        for (int i = 0; i < kMaxUnison; ++i) {
            NSRect pr = [self unisonPip:o voice:i];
            NSRect dot = NSMakeRect(NSMidX(pr) - 3.5, NSMidY(pr) - 3.5, 7, 7);
            [(i < n ? col : C(0x2a323e)) setFill];
            [[NSBezierPath bezierPathWithOvalInRect:dot] fill];
        }
        NSString* ro = S(ui::unisonReadout(v, o));
        if (n > 1) ro = [ro stringByAppendingFormat:@"  \u00b1%.0f ct", (o ? v.osc2UniDetune : v.osc1UniDetune) * 100];
        TextA(ro, NSMakeRect(st.origin.x + 110, st.origin.y + 3, 74, 12), 8, n > 1 ? col : C(0x5f6b7b),
              NSFontWeightSemibold, NSTextAlignmentRight);
    }
    for (int o = 0; o < 2; ++o) // 0.19.0 warp slots
        for (int sl = 0; sl < 2; ++sl) {
            NSColor* col = o ? C(0x9d7df2) : C(0x5adac8);
            VoiceParams& vv = current.voice;
            const int mode = ui::warpMode(vv, o, sl);
            const double amt = ui::warpAmount(vv, o, sl);
            NSRect c = [self warpChip:o slot:sl];
            FillRound(c, 4, C(0x0f141b));
            FillRound(NSMakeRect(c.origin.x + 2, c.origin.y + 3, 8, 10), 2, mode ? [col colorWithAlphaComponent:.8] : C(0x2a323e));
            TextA(sl ? @"2" : @"1", NSMakeRect(c.origin.x + 2, c.origin.y + 4, 8, 9), 7, mode ? C(0x0b0e13) : C(0x8793a3), NSFontWeightBold, NSTextAlignmentCenter);
            for (int d = -1; d <= 1; d += 2)
                TextA(d < 0 ? @"\u2039" : @"\u203A", NSMakeRect([self warpArrow:o slot:sl dir:d].origin.x, c.origin.y + 1.5, 10, 13), 10, C(0x6f7b8b),
                      NSFontWeightBold, NSTextAlignmentCenter);
            NSRect nm = [self warpName:o slot:sl];
            TextFit(S(ui::warpName(mode)), NSMakeRect(nm.origin.x, c.origin.y + 3.5, nm.size.width, 10), 7.5, 5.5, mode ? col : C(0x6f7b8b),
                    NSFontWeightBold, NSTextAlignmentCenter);
            NSRect ab = [self warpAmt:o slot:sl];
            if (sl == 0) { // slot 1's amount is the WARP knob; show its value
                char b[8]; snprintf(b, sizeof b, "%.0f%%", amt * 100);
                TextA(S(b), NSMakeRect(ab.origin.x - 2, c.origin.y + 3.5, ab.size.width + 2, 10), 7.5, mode ? C(0xd5dce5) : C(0x5f6b7b),
                      NSFontWeightSemibold, NSTextAlignmentRight);
            } else { // slot 2 has its own amount bar (drag)
                FillRound(ab, 2, C(0x1c232d));
                if (amt > 0) FillRound(NSMakeRect(ab.origin.x, ab.origin.y, ab.size.width * amt, ab.size.height), 2, mode ? col : C(0x4a5462));
                char b[8]; snprintf(b, sizeof b, "%.0f", amt * 100);
                TextA(S(b), NSMakeRect(ab.origin.x, ab.origin.y + 0.5, ab.size.width - 2, 9), 6.5, amt > .55 ? C(0x0b0e13) : C(0xd5dce5), NSFontWeightBold,
                      NSTextAlignmentRight);
            }
        }
    [self knob:ui::WarpA accent:C(0x5adac8)];
    [self knob:ui::UniDetuneA accent:C(0x5adac8)];
    [self knob:ui::Mix accent:C(0x5adac8)];
    [self knob:ui::Width accent:C(0xc3cbd6)];
    [self knob:ui::WarpB accent:C(0x9d7df2)];
    [self knob:ui::UniDetuneB accent:C(0x9d7df2)];
    [self knob:ui::Detune accent:C(0x9d7df2)];

    // Filter + amp: two pages behind header tabs (0.10.0).
    {
        NSArray* tabs = @[@"FILTER 1", @"FILTER 2 + SUB", @"ARP"];
        for (int i = 0; i < 3; ++i) {
            NSRect r = [self filterTab:i];
            bool on = filterPage == i;
            NSColor* ac = i == 2 ? C(0xf06fb0) : C(0xf2ab55);
            bool live = i == 1 ? (v.filter2Type != 0 || v.subLevel > 0 || v.noiseLevel > 0) : i == 2 ? v.arpOn : false;
            FillRound(r, 4, on ? [ac colorWithAlphaComponent:.22] : C(0x1b222c));
            TextA(tabs[i], NSMakeRect(r.origin.x, r.origin.y + 3, r.size.width, 11), 8, on ? ac : C(0x8793a3),
                  NSFontWeightBold, NSTextAlignmentCenter);
            if (live && !on) FillRound(NSMakeRect(NSMaxX(r) - 7, NSMaxY(r) - 7, 4, 4), 2, ac);
        }
    }
    if (filterPage == 2) {
        [self drawArpPage];
    } else if (filterPage == 0) {
        [self filter1Controls];
        [self knob:ui::Cutoff accent:C(0xf2ab55)];
        [self knob:ui::Resonance accent:C(0xf2ab55)];
        [self filter1In:[self f2Display]]; // 0.21.0: the response curve takes the MSEG 1 spot; its MSEG chip opens the editor
        [self knob:ui::Attack accent:C(0x6cb6ff)];
        [self knob:ui::Release accent:C(0x6cb6ff)];
        [self knob:ui::MsegTime accent:C(0x5adac8)];
    } else {
        TextA(v.filterRouting ? @"PARALLEL" : @"SERIAL", NSMakeRect(650, top - 27, 118, 14), 9, C(0xf2ab55), NSFontWeightSemibold, NSTextAlignmentRight);
        [self knob:ui::F2Cutoff accent:C(0xf2ab55)];
        [self knob:ui::F2Reso accent:C(0xf2ab55)];
        [self filter2In:[self f2Display]];
        [self filter2Controls];
        [self knob:ui::Sub accent:C(0x6cb6ff)];
        [self knob:ui::Noise accent:C(0xc3cbd6)];
        [self knob:ui::NoiseTone accent:C(0xc3cbd6)];
        NSString* pills[2] = {v.subOctave >= 2 ? @"-2 OCT" : @"-1 OCT", S(ui::subShapeName(v.subShape))};
        for (int i = 0; i < 2; ++i) {
            NSRect r = [self subPill:i];
            FillRound(r, 4, C(0x1b222c));
            TextA(pills[i], NSMakeRect(r.origin.x, r.origin.y + 2.5, r.size.width, 10), 7.5, v.subLevel > 0 ? C(0x6cb6ff) : C(0x8793a3),
                  NSFontWeightBold, NSTextAlignmentCenter);
        }
    }

    // Browser: chips
    NSArray* chips = ChipLabels();
    for (int i = 0; i < (int)chips.count; ++i) {
        NSRect r = [self chipRect:i];
        bool on = i == chip;
        FillRound(r, 9, on ? C(0x21423e) : C(0x1d232d));
        TextA(chips[i], NSMakeRect(r.origin.x, r.origin.y + 3, r.size.width, 13), 9,
              on ? C(0x75ead8) : C(0x9ca6b4), on ? NSFontWeightSemibold : NSFontWeightMedium, NSTextAlignmentCenter);
    }
    for (int a = 0; a < 2; ++a) { // actions: outlined, not filters
        NSRect r = a == 0 ? [self saveRect] : [self exportRect];
        [C(0x3a6b64) setStroke];
        NSBezierPath* o = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(r, 0.5, 0.5) xRadius:9 yRadius:9];
        o.lineWidth = 1; [o stroke];
        TextA(a == 0 ? @"+ Save" : @"Export", NSMakeRect(r.origin.x, r.origin.y + 3, r.size.width, 13), 9,
              C(0x75ead8), NSFontWeightSemibold, NSTextAlignmentCenter);
    }
    // Browser: list
    CGFloat lt = [self listTop];
    int rows = [self listRows];
    const ui::Library& lib = ui::library();
    for (int r = 0; r < rows && scroll + r < (int)visible.size(); ++r) {
        int idx = visible[scroll + r];
        CGFloat y = lt - (r + 1) * kRowH;
        bool sel = idx == currentIndex;
        if (sel) FillRound(NSMakeRect(806, y, b.size.width - 836, kRowH - 1), 4, C(0x293c3b));
        Text(S(lib.at(idx).info.name), NSMakeRect(814, y + 2, 88, 14), 10, sel ? C(0x75ead8) : C(0xc3cbd6),
             sel ? NSFontWeightSemibold : NSFontWeightRegular);
        TextA(lib.isUser(idx) ? @"User" : S(lib.at(idx).info.category), NSMakeRect(904, y + 3, 40, 12), 8,
              lib.isUser(idx) ? C(0x3a8f84) : C(0x5f6b7b), NSFontWeightMedium, NSTextAlignmentRight);
        bool fav = favorites.count(lib.slug(idx)) > 0;
        TextA(fav ? @"\u2605" : @"\u2606", NSMakeRect(946, y + 2, 16, 14), 10, fav ? C(0xf2ab55) : C(0x3b4552),
              NSFontWeightRegular, NSTextAlignmentCenter);
    }
    if (visible.empty() && chip == kUserChip)
        TextA(@"No saved presets yet - use + Save", NSMakeRect(806, lt - 40, b.size.width - 836, 16), 10, C(0x5f6b7b), NSFontWeightMedium, NSTextAlignmentCenter);
    else if (visible.empty())
        TextA(@"No presets match", NSMakeRect(806, lt - 40, b.size.width - 836, 16), 10, C(0x5f6b7b), NSFontWeightMedium, NSTextAlignmentCenter);
    if ((int)visible.size() > rows) { // scroll indicator
        CGFloat trackH = lt - 76, thumbH = std::max(24.0, trackH * rows / visible.size());
        CGFloat thumbY = lt - thumbH - (trackH - thumbH) * scroll / std::max(1, (int)visible.size() - rows);
        FillRound(NSMakeRect(b.size.width - 30, thumbY, 3, thumbH), 1.5, C(0x3b4552));
    }
    // Browser footer
    [C(0x29313d) setFill]; NSRectFill(NSMakeRect(812, 72, b.size.width - 850, 1));
    bool curFav = currentIndex >= 0 && favorites.count(lib.slug(currentIndex));
    Text(curFav ? @"\u2605  FAVORITE" : @"\u2606  ADD TO FAVORITES", NSMakeRect(812, 50, 110, 14), 9,
         curFav ? C(0xf2ab55) : C(0x8793a3), NSFontWeightSemibold);
    TextA([NSString stringWithFormat:@"%d / %d", (int)visible.size(), lib.count()], NSMakeRect(912, 50, 50, 14), 9,
          C(0x5f6b7b), NSFontWeightMedium, NSTextAlignmentRight);

    { // expand to the full browser
        NSRect r = [self expandRect];
        [C(0x3a6b64) setStroke];
        NSBezierPath* o = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(r, 0.5, 0.5) xRadius:8 yRadius:8];
        o.lineWidth = 1; [o stroke];
        // Drawn expand icon (two corner arrows) instead of a font glyph, which
        // rendered too small at this size (0.12.0).
        NSBezierPath* ic = [NSBezierPath bezierPath];
        CGFloat gx = r.origin.x + 8, gy = r.origin.y + 4, gs = 8;
        [ic moveToPoint:NSMakePoint(gx, gy + gs)]; [ic lineToPoint:NSMakePoint(gx + gs, gy)];
        [ic moveToPoint:NSMakePoint(gx, gy + gs - 3.5)]; [ic lineToPoint:NSMakePoint(gx, gy + gs)]; [ic lineToPoint:NSMakePoint(gx + 3.5, gy + gs)];
        [ic moveToPoint:NSMakePoint(gx + gs - 3.5, gy)]; [ic lineToPoint:NSMakePoint(gx + gs, gy)]; [ic lineToPoint:NSMakePoint(gx + gs, gy + 3.5)];
        ic.lineWidth = 1.4; ic.lineCapStyle = NSLineCapStyleRound; ic.lineJoinStyle = NSLineJoinStyleRound;
        [C(0x75ead8) setStroke]; [ic stroke];
        TextA(@"FULL", NSMakeRect(r.origin.x + 18, r.origin.y + 2.5, r.size.width - 22, 11), 8, C(0x75ead8), NSFontWeightBold, NSTextAlignmentCenter);
    }

    // Modulation + effects
    CGFloat low = top - 286;
    [self panel:NSMakeRect(24, 38, 760, low - 48) title:@"MODULATION + EFFECTS"];
    [self drawMatrix];
    // FX rack, chain order left to right, top to bottom. Cards drag to reorder.
    const FXParams& f = current.fx;
    char det[kFxUnits][40];
    snprintf(det[0], 40, "%s%s", ui::distModeName(f.dist.mode), f.dist.quality && f.dist.mode != 2 ? " HQ" : "");
    snprintf(det[1], 40, "RATE %.2f Hz", f.chorus.rateHz);
    snprintf(det[2], 40, "%s", ui::delayCardReadout(f.delay).c_str());
    if (f.comp.mode == 1) snprintf(det[3], 40, "3-BAND %.0f%%", 100.0 * std::clamp(f.comp.amount, 0.0, 1.0));
    else snprintf(det[3], 40, "RATIO %.1f:1", 1.5 + 6.5 * std::clamp(f.comp.amount, 0.0, 1.0));
    if (f.reverb.mode == 0) snprintf(det[4], 40, "DECAY %.2f", f.reverb.decay);
    else snprintf(det[4], 40, "%s %.1fs", f.reverb.mode == 2 ? "PLATE" : "HALL", SpaceReverb::rt60(f.reverb.mode, f.reverb.decay));
    snprintf(det[5], 40, "%+.0f %+.0f %+.0f dB", f.eq.lowDb, f.eq.midDb, f.eq.highDb);
    snprintf(det[6], 40, "%.2f Hz  FB %.0f", f.phaser.rateHz, f.phaser.feedback * 100);
    snprintf(det[7], 40, "%.2f Hz  FB %.0f", f.flanger.rateHz, f.flanger.feedback * 100);
    { double pk = 0; for (int v = 0; v < Hyper::kVoices; ++v) pk = std::max(pk, Hyper::peakCents(v, f.hyper.rateHz, f.hyper.detune));
      snprintf(det[8], 40, "\u00B1%.0f ct  DIM %.0f", pk, f.hyper.dimension * 100); } // same peak as the HYPER page
    snprintf(det[9], 40, "%s", ui::filterFxModeName(f.filter.mode));
    static const char* names[kFxUnits] = {"DIST", "CHORUS", "DELAY", "COMP", "REVERB", "EQ", "PHASER", "FLANGER", "HYPER", "FILTER"};
    static const char* ringLabel[kFxUnits] = {"DRIVE", "MIX", "MIX", "AMOUNT", "MIX", "", "MIX", "MIX", "MIX", "CUTOFF"};
    const int* accHex = kFxAccent;
    {
        NSRect c0 = [self fxCard:0];
        TextA(fxMove >= 0 ? @"DROP TO MOVE IN THE CHAIN" : @"FX CHAIN  \u2022  CLICK TO EDIT, DRAG TO REORDER",
              NSMakeRect(c0.origin.x, NSMaxY(c0) + 12, 304, 12), 8, fxMove >= 0 ? C(0x75ead8) : C(0x4f5a69),
              NSFontWeightSemibold, NSTextAlignmentRight);
    }
    for (int s = 0; s < kFxUnits; ++s) { // flow chevrons between neighbours
        if (s % 5 == 4) continue;
        NSRect r = [self fxCard:s];
        NSBezierPath* ch = [NSBezierPath bezierPath];
        CGFloat cx = NSMaxX(r) + 3, cy = NSMidY(r);
        [ch moveToPoint:NSMakePoint(cx - 1.5, cy + 3)]; [ch lineToPoint:NSMakePoint(cx + 1.5, cy)]; [ch lineToPoint:NSMakePoint(cx - 1.5, cy - 3)];
        [C(0x3b4552) setStroke]; ch.lineWidth = 1.2; [ch stroke];
    }
    for (int s = 0; s < kFxUnits; ++s) {
        const int i = f.order.slot[s];
        NSRect r = [self fxCard:s];
        bool on = FxEnabled(const_cast<Preset&>(current), i);
        bool moving = fxMove == s;
        NSColor* acc = C(accHex[i]);
        FillRound(r, 8, moving ? C(0x121820) : on ? C(0x1d2530) : C(0x181d25));
        if (fxMove >= 0 && fxDrop == s && fxDrop != fxMove) { // landing slot
            NSBezierPath* o = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(r, 0.5, 0.5) xRadius:8 yRadius:8];
            [C(0x75ead8) setStroke]; o.lineWidth = 1.5; [o stroke];
            CGFloat bx = fxDrop < fxMove ? r.origin.x - 4 : NSMaxX(r) + 4; // insertion bar on the side it slides in from
            FillRound(NSMakeRect(bx - 1, r.origin.y + 6, 2, r.size.height - 12), 1, C(0x75ead8));
        }
        if (moving) {
            NSBezierPath* o = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(r, 0.5, 0.5) xRadius:8 yRadius:8];
            CGFloat dash[2] = {3, 3}; [o setLineDash:dash count:2 phase:0];
            [C(0x3b4552) setStroke]; o.lineWidth = 1; [o stroke];
        }
        if (fxDetail == i && !moving) { // the unit open in the detail panel
            NSBezierPath* o = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(r, 0.5, 0.5) xRadius:8 yRadius:8];
            [C(accHex[i], 0.85) setStroke]; o.lineWidth = 1.2; [o stroke];
        }
        if (dragSource >= 0 && ui::fxUnitDest(i) >= 0) { // drop target: a source badge routes to this unit's main amount
            NSBezierPath* o = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(r, -2.5, -2.5) xRadius:10 yRadius:10];
            CGFloat dash[2] = {2, 3};
            if (dropFx != s) [o setLineDash:dash count:2 phase:0];
            [(dropFx == s ? SourceColor(ui::matrixSources()[dragSource]) : C(0x5f6b7b)) setStroke];
            o.lineWidth = dropFx == s ? 2 : 1; [o stroke];
        }
        CGFloat alpha = moving ? 0.35 : 1.0;
        Text(S(names[i]), NSMakeRect(r.origin.x + 6, NSMaxY(r) - 17, r.size.width - 14, 12), strlen(names[i]) > 6 ? 7.0 : 7.5,
             [(on ? acc : C(0x5f6b7b)) colorWithAlphaComponent:alpha], NSFontWeightBold);
        NSRect led = [self fxLed:s];
        FillRound(NSMakeRect(NSMidX(led) - 3, NSMidY(led) - 3, 6, 6), 3, [(on ? acc : C(0x303947)) colorWithAlphaComponent:alpha]);
        Text(S(det[i]), NSMakeRect(r.origin.x + 6, NSMaxY(r) - 29, r.size.width - 8, 10), 6.3,
             [(on ? C(0x8793a3) : C(0x4a5462)) colorWithAlphaComponent:alpha], NSFontWeightMedium);
        TextA([NSString stringWithFormat:@"%d", s + 1], NSMakeRect(NSMaxX(r) - 14, r.origin.y + 3, 10, 9), 6.5,
              C(0x3b4552), NSFontWeightBold, NSTextAlignmentRight); // chain position
        if (i == FxEQ) { // EQ: response curve instead of a ring
            NSRect plot = NSMakeRect(r.origin.x + 5, r.origin.y + 14, r.size.width - 10, 36);
            FillRound(plot, 4, C(0x0f141b));
            [C(0x232b36) setStroke];
            NSBezierPath* zero = [NSBezierPath bezierPath];
            [zero moveToPoint:NSMakePoint(plot.origin.x + 4, NSMidY(plot))]; [zero lineToPoint:NSMakePoint(NSMaxX(plot) - 4, NSMidY(plot))];
            [zero stroke];
            NSBezierPath* curve = [NSBezierPath bezierPath];
            for (int k = 0; k <= 48; ++k) {
                double hz = 20.0 * std::pow(1000.0, k / 48.0), lo = hz / 180.0, hi = hz / 6000.0, oct = std::log2(hz / 1200.0);
                double db = f.eq.lowDb / (1 + lo * lo) + f.eq.highDb * hi * hi / (1 + hi * hi) + f.eq.midDb * std::exp(-oct * oct * 1.5);
                NSPoint q = NSMakePoint(plot.origin.x + 4 + (plot.size.width - 8) * k / 48.0,
                                        NSMidY(plot) + std::clamp(db, -12.0, 12.0) / 12.0 * (plot.size.height / 2 - 4));
                k ? [curve lineToPoint:q] : [curve moveToPoint:q];
            }
            [[(on ? acc : C(0x3b4552)) colorWithAlphaComponent:alpha] setStroke]; curve.lineWidth = 1.4; [curve stroke];
            continue;
        }
        const int rid = FxParam(i);
        double val = RingNorm(current, rid);
        bool dragging = dragKnob == kFxDrag + i;
        NSPoint c = [self fxRingCenter:s];
        NSBezierPath* ring = [NSBezierPath bezierPath];
        [ring appendBezierPathWithArcWithCenter:c radius:13 startAngle:225 endAngle:-45 clockwise:YES];
        [[C(0x303947) colorWithAlphaComponent:alpha] setStroke]; ring.lineWidth = 2.4; [ring stroke];
        NSBezierPath* arc = [NSBezierPath bezierPath];
        [arc appendBezierPathWithArcWithCenter:c radius:13 startAngle:225 endAngle:225 - 270 * val clockwise:YES];
        [[(on ? acc : C(0x4a5462)) colorWithAlphaComponent:alpha] setStroke]; arc.lineWidth = 2.4; [arc stroke];
        NSString* vt;
        if (params::def(rid).unit == params::Hertz) {
            double hz = params::get(current, rid);
            vt = hz >= 1000 ? [NSString stringWithFormat:@"%.1fk", hz / 1000] : [NSString stringWithFormat:@"%.0f", hz];
        } else vt = [NSString stringWithFormat:@"%.0f", val * 100];
        TextA(vt, NSMakeRect(c.x - 13, c.y - 5, 26, 11), 8.5,
              [(dragging ? acc : (on ? C(0xd5dce5) : C(0x5f6b7b))) colorWithAlphaComponent:alpha], NSFontWeightSemibold, NSTextAlignmentCenter);
        TextA(S(ringLabel[i]), NSMakeRect(r.origin.x + 2, r.origin.y + 12, r.size.width - 4, 9), 6,
              [C(0x6f7b8b) colorWithAlphaComponent:alpha], NSFontWeightSemibold, NSTextAlignmentCenter);
    }
    if (fxMove >= 0 && fxMove < kFxUnits) { // the card under the pointer
        const int u = f.order.slot[fxMove];
        NSRect g = NSMakeRect(dragPoint.x - 30, dragPoint.y - 12, 60, 24);
        FillRound(g, 7, C(0x26303c));
        NSBezierPath* o = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(g, 0.5, 0.5) xRadius:7 yRadius:7];
        [C(accHex[u]) setStroke]; o.lineWidth = 1; [o stroke];
        TextA(S(names[u]), NSMakeRect(g.origin.x, g.origin.y + 6, g.size.width, 12), 9, C(accHex[u]), NSFontWeightBold, NSTextAlignmentCenter);
    }
    if (msegEdit >= 0) [self drawMsegEditor];
    else if (fxDetail >= 0) [self drawFxDetail];
    [self drawTableEditor];
    [self drawDragBadge];
    if (browserOpen) [self drawBrowser];
}

- (void)drawMatrix {
    const auto& srcs = ui::matrixSources();
    int n = (int)current.routes.size();
    Text(@"MATRIX", NSMakeRect(44, 235, 60, 12), 9, C(0xa8b2c1), NSFontWeightSemibold);
    Text([NSString stringWithFormat:@"%d / %d", n, kMaxRoutes], NSMakeRect(96, 235, 60, 12), 9, C(0x5f6b7b), NSFontWeightMedium);
    static NSString* pages[4] = {@"1-4", @"5-8", @"9-12", @"13-16"};
    for (int i = 0; i < 4; ++i) {
        NSRect t = [self pageTab:i];
        bool sel = i == matrixPage, used = n > i * 4;
        FillRound(t, 3, sel ? C(0x2c3a4a) : C(0x161b22));
        TextA(pages[i], NSMakeRect(t.origin.x, t.origin.y + 1, t.size.width, 11), 8, sel ? C(0xeaf1f8) : used ? C(0x8793a3) : C(0x3b4552),
              NSFontWeightSemibold, NSTextAlignmentCenter);
    }
    for (int i = 0; i < 4; ++i) {
        int slot = matrixPage * 4 + i;
        NSRect r = [self routeRow:i];
        bool has = slot < n;
        FillRound(r, 6, has ? C(0x202630) : C(0x181d25));
        Text([NSString stringWithFormat:@"%02d", slot + 1], NSMakeRect(r.origin.x + 8, r.origin.y + 21, 20, 12), 9, C(0x5f6b7b), NSFontWeightSemibold);
        if (!has) {
            if (slot == n)
                Text(@"+  ADD ROUTE  or drag a source onto a knob", NSMakeRect(r.origin.x + 28, r.origin.y + 21, 214, 12), 9, C(0x4f5a69), NSFontWeightMedium);
            continue;
        }
        const ModRoute& rt = current.routes[slot];
        NSColor* col = SourceColor(rt.source);
        NSRect sp = [self routeSourcePill:i], dp = [self routeDestPill:i];
        FillRound(sp, 4, [col colorWithAlphaComponent:.18]);
        TextA(S(std::string(ui::sourceName(rt.source)) + " \u25BE"), NSMakeRect(sp.origin.x, sp.origin.y + 1, sp.size.width, 12), 9, col,
              NSFontWeightSemibold, NSTextAlignmentCenter);
        TextA(@"\u2192", NSMakeRect(sp.origin.x + sp.size.width, sp.origin.y, 18, 13), 10, C(0x5f6b7b), NSFontWeightRegular, NSTextAlignmentCenter);
        FillRound(dp, 4, C(0x2a323e));
        TextA(S(std::string(ui::destName(rt.dest)) + " \u25BE"), NSMakeRect(dp.origin.x, dp.origin.y + 1, dp.size.width, 12), 9, C(0xeaf1f8),
              NSFontWeightMedium, NSTextAlignmentCenter);
        TextA(@"\u00D7", [self routeClear:i], 12, C(0x6f7b8b), NSFontWeightRegular, NSTextAlignmentCenter);
        NSRect bar = [self routeBar:i];
        NSRect track = NSMakeRect(bar.origin.x, bar.origin.y + 4, bar.size.width, 5);
        FillRound(track, 2.5, C(0x111820));
        FillRound(NSMakeRect(NSMidX(track) - 0.5, track.origin.y - 2, 1, 9), 0.5, C(0x3b4552));
        double amt = ui::routeDisplayAmount(rt);
        CGFloat mid = NSMidX(track), w = amt * track.size.width / 2;
        FillRound(NSMakeRect(w >= 0 ? mid : mid + w, track.origin.y, std::fabs(w), 5), 2.5, col);
        FillRound(NSMakeRect(mid + w - 3, track.origin.y - 2, 6, 9), 2, C(0xeaf1f8));
        // Curve glyph: the route's response, 0..1 in and out.
        NSRect cg = [self routeCurve:i];
        bool bent = rt.curve != 0.0;
        FillRound(cg, 3, curveDrag == slot ? C(0x26303c) : C(0x111820));
        {
            NSRect in = NSInsetRect(cg, 3.5, 2.5);
            NSBezierPath* cp = [NSBezierPath bezierPath];
            auto pts = ui::curvePoints(rt.curve, 12);
            for (size_t k = 0; k < pts.size(); ++k) {
                NSPoint q = NSMakePoint(in.origin.x + in.size.width * pts[k].first, in.origin.y + in.size.height * pts[k].second);
                k ? [cp lineToPoint:q] : [cp moveToPoint:q];
            }
            [(bent || curveDrag == slot ? col : C(0x5f6b7b)) setStroke]; cp.lineWidth = 1.2; cp.lineJoinStyle = NSLineJoinStyleRound; [cp stroke];
        }
        // AUX chip: empty outline, or the aux source's badge (dim when it can't reach this destination).
        NSRect ax = [self routeAux:i];
        bool auxDrop = dropAux == slot && dragSource >= 0;
        if (rt.aux >= 0) {
            auto as = (ModRoute::Source)rt.aux;
            bool live = ui::auxActive(rt);
            NSColor* acol = live ? SourceColor(as) : C(0x5f6b7b);
            FillRound(ax, 3, [acol colorWithAlphaComponent:live ? .2 : .12]);
            TextFit(S(std::string("\u00D7") + ui::sourceBadge(as)), NSMakeRect(ax.origin.x, ax.origin.y + 2, ax.size.width, 10), 7, 5.5, acol,
                    NSFontWeightBold, NSTextAlignmentCenter);
            if (!live) FillRound(NSMakeRect(ax.origin.x + 3, NSMidY(ax) - 0.5, ax.size.width - 6, 1), .5, C(0x8793a3));
        } else {
            NSBezierPath* o = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(ax, .5, .5) xRadius:3 yRadius:3];
            CGFloat dash[2] = {2, 2}; if (!auxDrop) [o setLineDash:dash count:2 phase:0];
            [(auxDrop ? SourceColor(ui::matrixSources()[dragSource]) : C(0x3b4552)) setStroke]; o.lineWidth = auxDrop ? 1.5 : 1; [o stroke];
            TextA(@"AUX", NSMakeRect(ax.origin.x, ax.origin.y + 2.5, ax.size.width, 10), 6.5, C(0x4f5a69), NSFontWeightBold, NSTextAlignmentCenter);
        }
        if (auxDrop && rt.aux >= 0) {
            NSBezierPath* o = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(ax, -1, -1) xRadius:4 yRadius:4];
            [SourceColor(ui::matrixSources()[dragSource]) setStroke]; o.lineWidth = 1.5; [o stroke];
        }
        std::string ro = curveDrag == slot ? ui::curveReadout(rt.curve) : ui::routeAmountReadout(rt);
        TextFit(S(ro), NSMakeRect(NSMaxX(ax) + 4, r.origin.y + 4, NSMaxX(r) - NSMaxX(ax) - 7, 12), 9, 6.5,
                routeDrag == slot || curveDrag == slot ? col : C(0x8793a3), NSFontWeightMedium, NSTextAlignmentRight);
    }
    // Modulators: badges double as drag handles.
    Text(@"SOURCES \u00B7 DRAG ONTO A KNOB", NSMakeRect(304, 235, 150, 12), 8, C(0x5f6b7b), NSFontWeightSemibold);
    for (int i = 0; i < (int)srcs.size(); ++i) {
        NSRect bdg = [self sourceBadge:i];
        NSColor* col = SourceColor(srcs[i]);
        bool used = false;
        for (const auto& rt : current.routes) used |= rt.source == srcs[i];
        FillRound(bdg, 3, i == modSel ? [col colorWithAlphaComponent:.85] : C(0x202630));
        if (used && i != modSel) FillRound(NSMakeRect(NSMidX(bdg) - 5, bdg.origin.y + 1, 10, 1.5), .75, col);
        // 15 badges share 152 pt: labels shrink to fit inside the chip with 1 pt padding, so four-letter
        // names (LFO1, ENV2, FXL2) never truncate or touch the next chip (0.18.0).
        TextFit(S(ui::sourceBadge(srcs[i])), NSMakeRect(bdg.origin.x + 1, bdg.origin.y + 2.5, bdg.size.width - 2, 10), 6.5, 4.75,
                i == modSel ? C(0x0b0e13) : col, NSFontWeightBold, NSTextAlignmentCenter);
    }
    { // 0.24.0 pitch bend RANGE stepper and the sustain pedal light
        NSRect bc = [self bendChip];
        NSColor* pc = SourceColor(ModRoute::Source::PitchBend);
        FillRound(bc, 3, C(0x202630));
        TextA(@"\u2039", NSMakeRect(bc.origin.x + 1, bc.origin.y + 1, 12, 13), 10, C(0x8793a3), NSFontWeightBold, NSTextAlignmentCenter);
        TextA(@"\u203A", NSMakeRect(NSMaxX(bc) - 13, bc.origin.y + 1, 12, 13), 10, C(0x8793a3), NSFontWeightBold, NSTextAlignmentCenter);
        TextA([NSString stringWithFormat:@"BEND \u00B1%d", std::clamp(current.voice.bendRange, 0, 24)], NSMakeRect(bc.origin.x + 12, bc.origin.y + 3.5, bc.size.width - 24, 10), 7,
              pc, NSFontWeightBold, NSTextAlignmentCenter);
    }
    ModRoute::Source sel = srcs[modSel];
    NSColor* scol = SourceColor(sel);
    NSRect pv = [self modPreview];
    [self sourcePreview:sel in:NSInsetRect(pv, 4, 4) color:scol];
    Text(S(ui::sourceName(sel)), NSMakeRect(pv.origin.x + 2, NSMaxY(pv) + 2, 90, 11), 8, C(0x8793a3), NSFontWeightSemibold);
    if ((int)sel >= (int)ModRoute::Source::ModWheel && perfSustain) { // 0.24.0: sustain pedal down
        NSRect pd = NSMakeRect(NSMaxX(pv) - 34, NSMaxY(pv) + 1, 34, 12);
        FillRound(pd, 3, [scol colorWithAlphaComponent:.85]);
        TextA(@"PEDAL", NSMakeRect(pd.origin.x, pd.origin.y + 2, pd.size.width, 9), 6.5, C(0x0b0e13), NSFontWeightBold, NSTextAlignmentCenter);
    }
    if (IsMseg(sel) || IsLfo(sel)) { // the preview opens the MSEG / LFO editor
        bool open = msegEdit == EditIndex(sel);
        NSRect ed = NSMakeRect(NSMaxX(pv) - 34, NSMaxY(pv) + 1, 34, 12);
        FillRound(ed, 3, open ? [scol colorWithAlphaComponent:.85] : [scol colorWithAlphaComponent:.18]);
        TextA(open ? @"EDITING" : @"EDIT", NSMakeRect(ed.origin.x, ed.origin.y + 2, ed.size.width, 9), 6.5, open ? C(0x0b0e13) : scol,
              NSFontWeightBold, NSTextAlignmentCenter);
    }
    VoiceParams& v = current.voice;
    int nf = [self modFieldCount];
    for (int j = 0; j < nf; ++j) {
        NSRect f = [self modField:j];
        FillRound(f, 5, modFieldDrag == j ? C(0x26303c) : C(0x1b212a));
        NSString* lab = @""; std::string val;
        char b[24];
        if (IsMseg(sel)) {
            auto mv = ui::msegView(v, MsegIndex(sel));
            if (j == 0) { lab = @"MODE"; val = ui::msegModeName(mv.mode()); }
            else if (j == 1) { lab = @"LENGTH"; val = ui::msegLengthReadout(mv); }
            else { lab = @"SYNC"; val = *mv.sync ? "ON" : "FREE"; }
        } else if (IsRack(sel)) {
            const RackLfoParams& rl = current.fx.lfo[RackIndex(sel)];
            if (j == 0) { lab = @"SHAPE"; val = ui::lfoShapeName(rl.shape); }
            else if (j == 1) { lab = @"RATE"; val = ui::rackLfoRateReadout(rl); }
            else { lab = @"SYNC"; val = rl.sync ? "ON" : "FREE"; }
        } else if (IsLfo(sel)) {
            int li = LfoIndex(sel);
            if (j == 0) { lab = @"SHAPE"; val = ui::lfoShapeIndexName(ui::lfoShapeIndex(v, li)); }
            else if (j == 1) { lab = @"RATE"; val = ui::lfoRateReadout(v, li); }
            else { lab = @"SYNC"; val = v.lfoSync[li] ? "ON" : "FREE"; }
        } else {
            bool e3 = sel == ModRoute::Source::Env3;
            static NSString* L[4] = {@"A", @"D", @"S", @"R"};
            lab = L[j];
            double x = EnvField(v, e3, j);
            if (j == 2) snprintf(b, sizeof b, "%.0f%%", x * 100);
            else if (x < 1) snprintf(b, sizeof b, "%.0fms", x * 1000);
            else snprintf(b, sizeof b, "%.2fs", x);
            val = b;
        }
        TextA(lab, NSMakeRect(f.origin.x, NSMaxY(f) - 16, f.size.width, 11), 8, C(0x6f7b8b), NSFontWeightSemibold, NSTextAlignmentCenter);
        TextFit(S(val), NSMakeRect(f.origin.x + 2, f.origin.y + 14, f.size.width - 4, 14), nf == 4 ? 9 : 10, 7, // 0.16.0: shrink, never "TRIANG..."
                modFieldDrag == j ? scol : C(0xd5dce5), NSFontWeightMedium, NSTextAlignmentCenter);
    }
    if (nf == 0) {
        using S = ModRoute::Source;
        NSString* note = sel == S::Velocity ? @"How hard each note is played."
                       : sel == S::ModWheel ? @"Mod wheel, MIDI CC 1."
                       : sel == S::Aftertouch ? @"Key pressure, note or channel."
                       : sel == S::PitchBend ? @"Pitch lever, range set by BEND."
                       : sel == S::Keytrack ? @"Note pitch, centred at C3."
                       : @"Follows its macro knob.";
        TextFit(note, NSMakeRect(304, 92, 148, 12), 9, 7, C(0x6f7b8b), NSFontWeightMedium, NSTextAlignmentCenter); // 0.24.0: shrink, never "..."
    }
}
- (void)drawDragBadge {
    const auto& srcs = ui::matrixSources();
    if (dragSource >= 0 && hypot(dragPoint.x - dragStart.x, dragPoint.y - dragStart.y) > 3) { // badge following the pointer
        NSRect fb = NSMakeRect(dragPoint.x - 16, dragPoint.y - 9, 32, 17);
        FillRound(fb, 4, SourceColor(srcs[dragSource]));
        TextA(S(ui::sourceBadge(srcs[dragSource])), NSMakeRect(fb.origin.x, fb.origin.y + 3, 32, 11), 8, C(0x0b0e13), NSFontWeightBold, NSTextAlignmentCenter);
    }
}

// ---- 0.17.0 MSEG editor ----
- (NSPoint)msegPointAt:(double)t value:(double)v {
    NSRect c = [self msegCanvas];
    return NSMakePoint(c.origin.x + c.size.width * t, NSMidY(c) + std::clamp(v, -1.0, 1.0) * (c.size.height / 2 - 4));
}
- (void)drawMsegEditor {
    const int k = msegEdit;
    const bool isRemap = k >= 6; // 0.19.0: oscillator REMAP curve (x = input phase, y = output phase)
    const bool isLfo = k >= 2 && !isRemap;
    auto mv = ui::editView(current.voice, k);
    const auto& pts = *mv.points;
    NSColor* acc = isRemap ? (k == 7 ? C(0x9d7df2) : C(0x5adac8)) : SourceColor(EditSource(k));
    const bool drawn = !isLfo || current.voice.lfoCustom[k - 2]; // an LFO plays its drawing only with CUSTOM on
    NSRect P = [self msegPanel];
    FillRound(P, 10, C(0x19202a));
    NSBezierPath* edge = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(P, 0.5, 0.5) xRadius:10 yRadius:10];
    [[acc colorWithAlphaComponent:.45] setStroke]; edge.lineWidth = 1; [edge stroke];
    FillRound(NSMakeRect(P.origin.x + 12, NSMaxY(P) - 22, 3, 12), 1.5, acc);
    Text(isRemap ? @"REMAP CURVE" : isLfo ? @"LFO EDITOR" : @"MSEG EDITOR", NSMakeRect(P.origin.x + 21, NSMaxY(P) - 24, 120, 15), 11, acc, NSFontWeightBold);
    if (isLfo) {
        for (int i = 0; i < 4; ++i) {
            NSRect t = [self lfoTab:i];
            NSColor* tc = SourceColor(EditSource(2 + i));
            FillRound(t, 4, 2 + i == k ? [tc colorWithAlphaComponent:.22] : C(0x131820));
            TextA([NSString stringWithFormat:@"LFO %d", i + 1], NSMakeRect(t.origin.x, t.origin.y + 3, t.size.width, 11), 8, 2 + i == k ? tc : C(0x6f7b8b),
                  NSFontWeightBold, NSTextAlignmentCenter);
        }
        NSRect cc = [self lfoCustomChip];
        FillRound(cc, 4, drawn ? [acc colorWithAlphaComponent:.85] : C(0x131820));
        if (!drawn) {
            NSBezierPath* o = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(cc, 0.5, 0.5) xRadius:4 yRadius:4];
            [[acc colorWithAlphaComponent:.5] setStroke]; o.lineWidth = 1; [o stroke];
        }
        TextA(@"CUSTOM", NSMakeRect(cc.origin.x, cc.origin.y + 3.5, cc.size.width, 10), 7.5, drawn ? C(0x0b0e13) : acc, NSFontWeightBold, NSTextAlignmentCenter);
    } else if (isRemap) {
        for (int i = 0; i < 2; ++i) {
            NSRect t = [self msegTab:i];
            NSColor* tc = i ? C(0x9d7df2) : C(0x5adac8);
            bool on = 6 + i == k, live = ui::usesRemap(current.voice, i);
            FillRound(t, 4, on ? [tc colorWithAlphaComponent:.22] : C(0x131820));
            TextA(i ? @"OSC B" : @"OSC A", NSMakeRect(t.origin.x, t.origin.y + 3, t.size.width, 11), 8, on ? tc : live ? C(0x8793a3) : C(0x3d4653),
                  NSFontWeightBold, NSTextAlignmentCenter);
        }
    } else
    for (int i = 0; i < 2; ++i) {
        NSRect t = [self msegTab:i];
        NSColor* tc = SourceColor(i ? ModRoute::Source::MSEG2 : ModRoute::Source::MSEG1);
        FillRound(t, 4, i == k ? [tc colorWithAlphaComponent:.22] : C(0x131820));
        TextA(i ? @"MSEG 2" : @"MSEG 1", NSMakeRect(t.origin.x, t.origin.y + 3, t.size.width, 11), 8, i == k ? tc : C(0x6f7b8b),
              NSFontWeightBold, NSTextAlignmentCenter);
    }
    TextA(@"\u00D7", [self msegClose], 13, C(0x8793a3), NSFontWeightRegular, NSTextAlignmentCenter);
    // Canvas: grid, loop span, filled shape, segment bend handles, points.
    NSRect c = [self msegCanvas];
    FillRound(c, 6, C(0x0a0d12));
    int divs = ui::msegGridDivs(msegGrid);
    for (int i = 1; i < std::max(divs, 4); ++i) {
        CGFloat x = c.origin.x + c.size.width * i / std::max(divs, 4);
        FillRound(NSMakeRect(x - 0.5, c.origin.y + 3, 1, c.size.height - 6), 0, divs && (i % (divs / 4 ? divs / 4 : 1)) == 0 ? C(0x222a35) : C(0x161c24));
    }
    FillRound(NSMakeRect(c.origin.x + 3, NSMidY(c) - 0.5, c.size.width - 6, 1), 0, C(0x222a35));
    if (isRemap) { // dashed identity line: a curve on it leaves the phase unchanged
        NSBezierPath* id = [NSBezierPath bezierPath];
        [id moveToPoint:[self msegPointAt:0 value:-1]]; [id lineToPoint:[self msegPointAt:1 value:1]];
        CGFloat dash[2] = {3, 3}; [id setLineDash:dash count:2 phase:0];
        [C(0x3a4452) setStroke]; id.lineWidth = 1; [id stroke];
    }
    const int mode = mv.mode(), ls = *mv.loopStart, le = mv.loopEndIndex();
    const bool loopOk = mode != 0 && ls >= 0 && le > ls && le < (int)pts.size();
    if (loopOk) {
        CGFloat x0 = [self msegPointAt:pts[ls].time value:0].x, x1 = [self msegPointAt:pts[le].time value:0].x;
        FillRound(NSMakeRect(x0, c.origin.y + 2, x1 - x0, c.size.height - 4), 3, [acc colorWithAlphaComponent:.09]);
        for (int e = 0; e < 2; ++e) {
            CGFloat x = e ? x1 : x0;
            FillRound(NSMakeRect(x - 0.5, c.origin.y + 2, 1, c.size.height - 4), 0, [acc colorWithAlphaComponent:.55]);
            NSRect flag = NSMakeRect(e ? x - 12 : x, NSMaxY(c) - 12, 12, 10);
            FillRound(flag, 2, msegLoopEdge == e ? C(0xeaf1f8) : acc);
            TextA(e ? @"E" : @"L", NSMakeRect(flag.origin.x, flag.origin.y + 1.5, 12, 8), 6.5, C(0x0b0e13), NSFontWeightBold, NSTextAlignmentCenter);
        }
    }
    MSEG m; m.setPoints(pts);
    NSBezierPath* line = [NSBezierPath bezierPath];
    NSBezierPath* fill = [NSBezierPath bezierPath];
    const int N = 240;
    for (int i = 0; i <= N; ++i) {
        double t = i / (double)N;
        NSPoint q = [self msegPointAt:t value:m.valueAt(t)];
        if (i) [line lineToPoint:q]; else [line moveToPoint:q];
        if (i) [fill lineToPoint:q]; else { [fill moveToPoint:NSMakePoint(q.x, NSMidY(c))]; [fill lineToPoint:q]; }
    }
    [fill lineToPoint:NSMakePoint(NSMaxX(c) - 0, NSMidY(c))]; [fill closePath];
    [[acc colorWithAlphaComponent:drawn ? .12 : .05] setFill]; [fill fill];
    [(drawn ? acc : [acc colorWithAlphaComponent:.4]) setStroke]; line.lineWidth = 1.8; line.lineJoinStyle = NSLineJoinStyleRound; [line stroke];
    for (int i = 0; i + 1 < (int)pts.size(); ++i) { // bend handles at segment centres
        double tm = 0.5 * (pts[i].time + pts[i + 1].time);
        NSPoint q = [self msegPointAt:tm value:m.valueAt(tm)];
        NSBezierPath* d = [NSBezierPath bezierPath];
        CGFloat r = msegSeg == i ? 4 : 3;
        [d moveToPoint:NSMakePoint(q.x, q.y + r)]; [d lineToPoint:NSMakePoint(q.x + r, q.y)];
        [d lineToPoint:NSMakePoint(q.x, q.y - r)]; [d lineToPoint:NSMakePoint(q.x - r, q.y)]; [d closePath];
        [(pts[i].curve != 0 || msegSeg == i ? acc : C(0x4a5462)) setFill]; [d fill];
    }
    for (int i = 0; i < (int)pts.size(); ++i) {
        NSPoint q = [self msegPointAt:pts[i].time value:pts[i].value];
        CGFloat r = msegPt == i ? 4.5 : 3.5;
        if (msegPt == i) { [[acc colorWithAlphaComponent:.35] setFill]; [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(q.x - 7, q.y - 7, 14, 14)] fill]; }
        [C(0xeaf1f8) setFill]; [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(q.x - r, q.y - r, r * 2, r * 2)] fill];
        [acc setFill]; [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(q.x - 1.5, q.y - 1.5, 3, 3)] fill];
    }
    // Hint on its own line under the canvas so the shape never runs through it (0.18.0).
    Text(isRemap ? @"X = INPUT PHASE  \u2022  Y = OUTPUT PHASE  \u2022  CLICK ADDS  \u2022  DOUBLE-CLICK DELETES  \u2022  DRAG \u25C6 TO BEND" :
         isLfo && !drawn ? @"EDITING TURNS CUSTOM ON  \u2022  CLICK ADDS A POINT  \u2022  DOUBLE-CLICK DELETES  \u2022  DRAG \u25C6 TO BEND"
                         : @"CLICK ADDS A POINT  \u2022  DOUBLE-CLICK DELETES  \u2022  DRAG \u25C6 TO BEND",
         NSMakeRect(c.origin.x + 2, P.origin.y + 32, 380, 10), 6.5, C(0x4a5462), NSFontWeightSemibold);
    if (msegPt >= 0 && msegPt < (int)pts.size()) {
        char b[48];
        if (isRemap) snprintf(b, sizeof b, "IN %.0f%%  \u2192  OUT %.0f%%", pts[msegPt].time * 100, (pts[msegPt].value + 1) * 50);
        else snprintf(b, sizeof b, "%.0f%%  \u2192  %+.2f", pts[msegPt].time * 100, pts[msegPt].value);
        TextA(S(b), NSMakeRect(NSMaxX(c) - 100, P.origin.y + 32, 100, 10), 7, acc, NSFontWeightBold, NSTextAlignmentRight);
    } else if (msegSeg >= 0 && msegSeg < (int)pts.size()) {
        TextA(S(ui::curveReadout(pts[msegSeg].curve)), NSMakeRect(NSMaxX(c) - 100, P.origin.y + 32, 100, 10), 7, acc, NSFontWeightBold, NSTextAlignmentRight);
    }
    // Footer: mode (LFO: RETRIG/FREE + PHASE/DELAY/RISE), grid, length.
    if (isLfo) {
        const VoiceParams& v = current.voice;
        const int li = k - 2;
        for (int i = 0; i < 2; ++i) {
            NSRect r = [self lfoTrigPill:i];
            bool on = (i == 1) == v.lfoFree[li];
            FillRound(r, 4, on ? [acc colorWithAlphaComponent:.22] : C(0x131820));
            TextA(i ? @"FREE" : @"RETRIG", NSMakeRect(r.origin.x, r.origin.y + 4, r.size.width, 10), 7.5, on ? acc : C(0x6f7b8b), NSFontWeightBold, NSTextAlignmentCenter);
        }
        static NSString* xl[3] = {@"PHASE", @"DELAY", @"RISE"};
        for (int j = 0; j < 3; ++j) {
            NSRect r = [self lfoXPill:j];
            double val = j == 0 ? v.lfoPhase[li] : j == 1 ? v.lfoDelay[li] : v.lfoRise[li];
            bool live = lfoXDrag == j;
            FillRound(r, 4, live ? C(0x26303c) : C(0x131820));
            // 0.19.0: label stacked over the value so both read at full size
            TextA(xl[j], NSMakeRect(r.origin.x, NSMaxY(r) - 1, r.size.width, 8), 6.5, C(0x6f7b8b), NSFontWeightBold, NSTextAlignmentCenter);
            std::string ro = j == 0 ? ui::lfoPhaseReadout(val) : ui::lfoFadeReadout(val);
            TextFit(S(ro), NSMakeRect(r.origin.x + 2, r.origin.y + 3.5, r.size.width - 4, 11), 8.5, 7, live ? acc : (val > 0 ? C(0xd5dce5) : C(0x6f7b8b)),
                    NSFontWeightSemibold, NSTextAlignmentCenter);
        }
    } else
    for (int i = 0; i < 3 && !isRemap; ++i) {
        NSRect r = [self msegModePill:i];
        FillRound(r, 4, mode == i ? [acc colorWithAlphaComponent:.22] : C(0x131820));
        TextA(S(ui::msegModeName(i)), NSMakeRect(r.origin.x, r.origin.y + 4, r.size.width, 10), 7.5, mode == i ? acc : C(0x6f7b8b),
              NSFontWeightBold, NSTextAlignmentCenter);
    }
    if (isRemap) { // curve reset + output range readout where the MSEG mode pills sit
        NSRect r = [self msegModePill:0];
        FillRound(r, 4, C(0x131820));
        TextA(@"RESET", NSMakeRect(r.origin.x, r.origin.y + 4, r.size.width, 10), 7.5, C(0x8793a3), NSFontWeightBold, NSTextAlignmentCenter);
        Text([NSString stringWithFormat:@"%d POINTS", (int)pts.size()], NSMakeRect(r.origin.x + 64, r.origin.y + 5, 80, 10), 7.5, C(0x5f6b7b), NSFontWeightSemibold);
    }
    if (!isLfo) TextA(@"GRID", NSMakeRect(P.origin.x + 182, P.origin.y + 14, 30, 10), 7, C(0x5f6b7b), NSFontWeightSemibold, NSTextAlignmentRight);
    static NSString* grids[4] = {@"OFF", @"4", @"8", @"16"};
    for (int i = 0; i < 4; ++i) {
        NSRect r = [self msegGridPill:i];
        FillRound(r, 4, msegGrid == i ? C(0x2c3a4a) : C(0x131820));
        TextA(grids[i], NSMakeRect(r.origin.x, r.origin.y + 4, r.size.width, 10), 7.5, msegGrid == i ? C(0xeaf1f8) : C(0x6f7b8b),
              NSFontWeightBold, NSTextAlignmentCenter);
    }
    if (isRemap) return; // a REMAP curve has no length or sync
    NSRect lp = [self msegLenPill], sp = [self msegSyncPill];
    FillRound(lp, 4, modFieldDrag == 1 ? C(0x26303c) : C(0x131820));
    TextFit(S(isLfo ? ui::lfoRateReadout(current.voice, k - 2) : ui::msegLengthReadout(mv)), NSMakeRect(lp.origin.x + 2, lp.origin.y + 3.5, lp.size.width - 4, 11), 8.5, 6.5,
            modFieldDrag == 1 ? acc : C(0xd5dce5), NSFontWeightSemibold, NSTextAlignmentCenter);
    FillRound(sp, 4, *mv.sync ? [acc colorWithAlphaComponent:.22] : C(0x131820));
    TextA(@"SYNC", NSMakeRect(sp.origin.x, sp.origin.y + 4, sp.size.width, 10), 7, *mv.sync ? acc : C(0x6f7b8b), NSFontWeightBold, NSTextAlignmentCenter);
}

- (BOOL)msegMouseDown:(NSPoint)p event:(NSEvent*)e {
    if (msegEdit < 0 || !NSPointInRect(p, [self msegPanel])) return NO;
    auto mv = ui::editView(current.voice, msegEdit);
    auto& pts = *mv.points;
    const bool isRemap = msegEdit >= 6;
    const int li = isRemap ? -1 : msegEdit - 2; // LFO index when >= 0
    if (NSPointInRect(p, NSInsetRect([self msegClose], -4, -4))) { msegEdit = -1; [self setNeedsDisplay:YES]; return YES; }
    if (isRemap) {
        for (int i = 0; i < 2; ++i)
            if (NSPointInRect(p, [self msegTab:i])) { msegEdit = 6 + i; msegPt = msegSeg = -1; [self setNeedsDisplay:YES]; return YES; }
        if (NSPointInRect(p, [self msegModePill:0])) {
            current.voice.remapPoints[msegEdit - 6] = VoiceParams::kDefaultRemap(); msegPt = msegSeg = -1;
            edited = true; [self applySound]; [self setNeedsDisplay:YES]; return YES;
        }
    } else if (li >= 0) {
        VoiceParams& v = current.voice;
        auto selectEditor = [&](int k) {
            msegEdit = k;
            const auto& srcs = ui::matrixSources();
            for (int j = 0; j < (int)srcs.size(); ++j) if (srcs[j] == EditSource(k)) modSel = j;
        };
        for (int i = 0; i < 4; ++i)
            if (NSPointInRect(p, [self lfoTab:i])) { selectEditor(2 + i); [self setNeedsDisplay:YES]; return YES; }
        if (NSPointInRect(p, [self lfoCustomChip])) { v.lfoCustom[li] = !v.lfoCustom[li]; edited = true; [self applySound]; [self setNeedsDisplay:YES]; return YES; }
        for (int i = 0; i < 2; ++i)
            if (NSPointInRect(p, [self lfoTrigPill:i])) { v.lfoFree[li] = i == 1; edited = true; [self applySound]; [self setNeedsDisplay:YES]; return YES; }
        for (int j = 0; j < 3; ++j)
            if (NSPointInRect(p, [self lfoXPill:j])) {
                if (e.clickCount == 2) { (j == 0 ? v.lfoPhase[li] : j == 1 ? v.lfoDelay[li] : v.lfoRise[li]) = 0; edited = true; [self applySound]; }
                else { lfoXDrag = j; dragValue = j == 0 ? v.lfoPhase[li] : ui::fadeTo01(j == 1 ? v.lfoDelay[li] : v.lfoRise[li]); }
                [self setNeedsDisplay:YES];
                return YES;
            }
    } else
    for (int i = 0; i < 2; ++i)
        if (NSPointInRect(p, [self msegTab:i])) {
            msegEdit = i;
            const auto& srcs = ui::matrixSources();
            for (int j = 0; j < (int)srcs.size(); ++j) if (srcs[j] == (i ? ModRoute::Source::MSEG2 : ModRoute::Source::MSEG1)) modSel = j;
            [self setNeedsDisplay:YES];
            return YES;
        }
    for (int i = 0; i < 3 && li < 0 && !isRemap; ++i)
        if (NSPointInRect(p, [self msegModePill:i])) { mv.setMode(i); edited = true; [self applySound]; [self setNeedsDisplay:YES]; return YES; }
    for (int i = 0; i < 4; ++i)
        if (NSPointInRect(p, [self msegGridPill:i])) { msegGrid = i; [self setNeedsDisplay:YES]; return YES; }
    if (!isRemap && NSPointInRect(p, [self msegSyncPill])) { *mv.sync = *mv.sync ? 0 : 3; edited = true; [self applySound]; [self setNeedsDisplay:YES]; return YES; }
    if (!isRemap && NSPointInRect(p, [self msegLenPill])) { // drag like the LENGTH field (modSel is this MSEG while the editor is open)
        modFieldDrag = 1;
        dragValue = *mv.sync ? (*mv.sync - 1) / (double)(kSyncCount - 2) : li >= 0 ? RateTo01(ui::lfoRate(current.voice, li)) : TimeTo01(*mv.seconds);
        [self setNeedsDisplay:YES];
        return YES;
    }
    NSRect c = [self msegCanvas];
    if (!NSPointInRect(p, NSInsetRect(c, -6, -6))) return YES;
    const int ls = *mv.loopStart, le = mv.loopEndIndex();
    if (mv.mode() != 0 && p.y > NSMaxY(c) - 14 && le > ls && le < (int)pts.size()) { // loop flags
        CGFloat x0 = [self msegPointAt:pts[ls].time value:0].x, x1 = [self msegPointAt:pts[le].time value:0].x;
        if (p.x >= x0 - 2 && p.x <= x0 + 14) { msegLoopEdge = 0; [self setNeedsDisplay:YES]; return YES; }
        if (p.x >= x1 - 14 && p.x <= x1 + 2) { msegLoopEdge = 1; [self setNeedsDisplay:YES]; return YES; }
    }
    int best = -1; double bd = 8;
    for (int i = 0; i < (int)pts.size(); ++i) {
        NSPoint q = [self msegPointAt:pts[i].time value:pts[i].value];
        double d = hypot(q.x - p.x, q.y - p.y);
        if (d < bd) { bd = d; best = i; }
    }
    if (best >= 0) {
        if (e.clickCount == 2) { if (ui::msegDelete(mv, best)) { if (li >= 0) current.voice.lfoCustom[li] = true; edited = true; [self applySound]; } }
        else msegPt = best;
        [self setNeedsDisplay:YES];
        return YES;
    }
    MSEG m; m.setPoints(pts);
    for (int i = 0; i + 1 < (int)pts.size(); ++i) {
        double tm = 0.5 * (pts[i].time + pts[i + 1].time);
        NSPoint q = [self msegPointAt:tm value:m.valueAt(tm)];
        if (hypot(q.x - p.x, q.y - p.y) < 7) {
            if (e.clickCount == 2) { pts[i].curve = 0; if (li >= 0) current.voice.lfoCustom[li] = true; edited = true; [self applySound]; }
            else { msegSeg = i; dragValue = pts[i].curve; }
            [self setNeedsDisplay:YES];
            return YES;
        }
    }
    double t = ui::msegSnap((p.x - c.origin.x) / c.size.width, msegGrid);
    double v = (p.y - NSMidY(c)) / (c.size.height / 2 - 4);
    int i = ui::msegInsert(mv, t, v);
    if (i < 0) NSBeep();
    else { msegPt = i; if (li >= 0) current.voice.lfoCustom[li] = true; edited = true; [self applySound]; }
    [self setNeedsDisplay:YES];
    return YES;
}

- (void)msegDragTo:(NSPoint)p shift:(bool)fine {
    auto mv = ui::editView(current.voice, msegEdit);
    if (msegEdit >= 2 && msegEdit < 6 && (msegPt >= 0 || msegSeg >= 0)) current.voice.lfoCustom[msegEdit - 2] = true; // drawing turns CUSTOM on
    auto& pts = *mv.points;
    NSRect c = [self msegCanvas];
    double t = std::clamp((p.x - c.origin.x) / c.size.width, 0.0, 1.0);
    if (msegPt >= 0 && msegPt < (int)pts.size()) {
        double v = (p.y - NSMidY(c)) / (c.size.height / 2 - 4);
        if (msegGrid && !fine) v = std::round(v * 8) / 8; // values snap to eighths with the grid on; shift = free
        ui::msegMove(mv, msegPt, fine ? t : ui::msegSnap(t, msegGrid), v);
    } else if (msegSeg >= 0 && msegSeg < (int)pts.size()) {
        bool rising = msegSeg + 1 < (int)pts.size() && pts[msegSeg + 1].value >= pts[msegSeg].value;
        double dy = (p.y - dragStart.y) / (fine ? 240.0 : 60.0);
        pts[msegSeg].curve = ui::clampCurve(dragValue + (rising ? -dy : dy)); // drag the handle toward where the line should bow
    } else if (msegLoopEdge >= 0) {
        int best = 0; double bd = 1e9;
        for (int i = 0; i < (int)pts.size(); ++i) { double d = std::fabs(pts[i].time - t); if (d < bd) { bd = d; best = i; } }
        ui::msegSetLoop(mv, msegLoopEdge, best);
    }
    edited = true; [self applySound]; [self setNeedsDisplay:YES];
}

// 0.27.0 HYPER page: the six voices across the stereo field. Each voice is a
// column at its pan position whose height is its pitch swing (cents); the
// shaded wings show how far the dimension taps widen the image.
- (void)drawHyperVisual:(bool)on {
    const HyperParams& h = current.fx.hyper;
    NSColor* acc = C(kFxAccent[FxHyper]);
    NSRect V = [self fxDetailVisual];
    FillRound(V, 6, C(0x10151c));
    NSRect plot = NSInsetRect(V, 10, 16);
    plot.origin.y += 4;
    const CGFloat midY = NSMidY(plot), half = plot.size.height / 2;
    const double dim = std::clamp(h.dimension, 0.0, 1.0), mix = std::clamp(h.mix, 0.0, 1.0);
    // Dimension wings: gradient from the centre outwards.
    if (dim > 0) {
        NSGradient* g = [[NSGradient alloc] initWithStartingColor:C(kFxAccent[FxHyper], 0.0)
                                                      endingColor:C(kFxAccent[FxHyper], (on ? 0.22 : 0.08) * dim)];
        CGFloat w = plot.size.width / 2;
        [g drawInRect:NSMakeRect(NSMidX(plot), plot.origin.y, w, plot.size.height) angle:0];
        [g drawInRect:NSMakeRect(plot.origin.x, plot.origin.y, w, plot.size.height) angle:180];
    }
    [C(0x232b36) setStroke];
    for (int g = -1; g <= 1; ++g) { // cent grid: 0 and +-20
        NSBezierPath* l = [NSBezierPath bezierPath];
        CGFloat y = midY + g * half * 0.8;
        [l moveToPoint:NSMakePoint(plot.origin.x, y)]; [l lineToPoint:NSMakePoint(NSMaxX(plot), y)];
        if (g) { CGFloat d[2] = {2, 3}; [l setLineDash:d count:2 phase:0]; }
        [l stroke];
    }
    NSBezierPath* cl = [NSBezierPath bezierPath];
    [cl moveToPoint:NSMakePoint(NSMidX(plot), plot.origin.y)]; [cl lineToPoint:NSMakePoint(NSMidX(plot), NSMaxY(plot))]; [cl stroke];
    double peak = 0;
    for (int v = 0; v < Hyper::kVoices; ++v) {
        const double ct = Hyper::peakCents(v, h.rateHz, h.detune);
        peak = std::max(peak, ct);
        const CGFloat x = NSMidX(plot) + Hyper::voicePan(v) * (plot.size.width / 2 - 6);
        const CGFloat hgt = std::max<CGFloat>(1.5, std::min(ct / 20.0, 1.2) * half * 0.8);
        NSColor* vc = on ? [acc colorWithAlphaComponent:0.35 + 0.65 * mix] : C(0x4a5462);
        FillRound(NSMakeRect(x - 3, midY - hgt, 6, 2 * hgt), 3, [vc colorWithAlphaComponent:on ? 0.3 : 0.4]);
        FillRound(NSMakeRect(x - 1, midY - hgt, 2, 2 * hgt), 1, vc);
        FillRound(NSMakeRect(x - 3.5, midY - 3.5, 7, 7), 3.5, on ? C(0xd5dce5) : C(0x5f6b7b));
        TextA([NSString stringWithFormat:@"%d", v + 1], NSMakeRect(x - 6, plot.origin.y - 13, 12, 9), 6.5, C(0x5f6b7b), NSFontWeightBold, NSTextAlignmentCenter);
    }
    Text(@"L", NSMakeRect(V.origin.x + 6, NSMaxY(V) - 13, 12, 10), 7, C(0x5f6b7b), NSFontWeightBold);
    TextA(@"R", NSMakeRect(NSMaxX(V) - 18, NSMaxY(V) - 13, 12, 10), 7, C(0x5f6b7b), NSFontWeightBold, NSTextAlignmentRight);
    TextA([NSString stringWithFormat:@"\u00B1%.1f CENTS", peak], NSMakeRect(V.origin.x, NSMaxY(V) - 13, V.size.width, 10), 7,
          on ? acc : C(0x8793a3), NSFontWeightBold, NSTextAlignmentCenter);
}

// 0.27.0 FILTER FX page: the response at the set cutoff, the sweep range the
// LFO covers (shaded, with its end curves dashed) and the cutoff marker.
static double FilterFxMag(int mode, double hz, double fc, double q) {
    const double w = hz / fc, re = 1.0 - w * w, im = w / q, den = std::sqrt(re * re + im * im);
    switch (mode) {
    case 1: return w / den;                 // band (peak gain Q)
    case 2: return (w * w) / den;           // high
    case 3: return std::fabs(re) / den;     // notch
    case 4: return (1.0 + w * w) / den;     // peak: low - high
    default: return 1.0 / den;              // low
    }
}
- (void)drawFilterFxVisual:(bool)on {
    const FilterFxParams& fp = current.fx.filter;
    NSColor* acc = C(kFxAccent[FxFilter]);
    NSRect V = [self fxDetailVisual];
    FillRound(V, 6, C(0x10151c));
    NSRect plot = NSInsetRect(V, 8, 14);
    plot.origin.y += 2;
    const double q = 0.5 * std::pow(28.0, std::clamp(fp.reso, 0.0, 1.0)), depth = std::clamp(fp.lfoDepth, 0.0, 1.0);
    const double fc = std::clamp(fp.cutoffHz, 40.0, 18000.0);
    auto xOf = [&](double hz) { return plot.origin.x + plot.size.width * std::log(hz / 20.0) / std::log(1000.0); };
    auto yOf = [&](double mag) { double db = 20.0 * std::log10(std::max(mag, 1e-4)); return plot.origin.y + plot.size.height * (std::clamp(db, -36.0, 24.0) + 36.0) / 60.0; };
    [C(0x232b36) setStroke];
    for (double g : {100.0, 1000.0, 10000.0}) { // decade lines
        NSBezierPath* l = [NSBezierPath bezierPath];
        [l moveToPoint:NSMakePoint(xOf(g), plot.origin.y)]; [l lineToPoint:NSMakePoint(xOf(g), NSMaxY(plot))]; [l stroke];
    }
    { NSBezierPath* l = [NSBezierPath bezierPath]; // 0 dB
      [l moveToPoint:NSMakePoint(plot.origin.x, yOf(1.0))]; [l lineToPoint:NSMakePoint(NSMaxX(plot), yOf(1.0))];
      CGFloat d[2] = {2, 3}; [l setLineDash:d count:2 phase:0]; [l stroke]; }
    const double lo = std::clamp(fc * std::pow(2.0, -4.0 * depth), 20.0, 20000.0), hi = std::clamp(fc * std::pow(2.0, 4.0 * depth), 20.0, 20000.0);
    if (depth > 0) { // sweep band
        FillRound(NSMakeRect(xOf(lo), plot.origin.y, xOf(hi) - xOf(lo), plot.size.height), 3, C(kFxAccent[FxFilter], on ? 0.10 : 0.05));
        for (double e : {lo, hi}) {
            NSBezierPath* c = [NSBezierPath bezierPath];
            for (int k = 0; k <= 72; ++k) {
                double hz = 20.0 * std::pow(1000.0, k / 72.0);
                NSPoint pt = NSMakePoint(xOf(hz), yOf(FilterFxMag(fp.mode, hz, e, q)));
                k ? [c lineToPoint:pt] : [c moveToPoint:pt];
            }
            CGFloat d[2] = {3, 3}; [c setLineDash:d count:2 phase:0];
            [C(kFxAccent[FxFilter], on ? 0.45 : 0.2) setStroke]; c.lineWidth = 1; [c stroke];
        }
    }
    NSBezierPath* curve = [NSBezierPath bezierPath];
    for (int k = 0; k <= 120; ++k) {
        double hz = 20.0 * std::pow(1000.0, k / 120.0);
        NSPoint pt = NSMakePoint(xOf(hz), yOf(FilterFxMag(fp.mode, hz, fc, q)));
        k ? [curve lineToPoint:pt] : [curve moveToPoint:pt];
    }
    NSBezierPath* fill = [curve copy];
    [fill lineToPoint:NSMakePoint(NSMaxX(plot), plot.origin.y)]; [fill lineToPoint:NSMakePoint(plot.origin.x, plot.origin.y)]; [fill closePath];
    [C(kFxAccent[FxFilter], on ? 0.14 : 0.05) setFill]; [fill fill];
    [(on ? acc : C(0x4a5462)) setStroke]; curve.lineWidth = 1.8; [curve stroke];
    const CGFloat mx = xOf(fc);
    FillRound(NSMakeRect(mx - 0.75, plot.origin.y, 1.5, plot.size.height), 0.75, on ? C(0xd5dce5, 0.6) : C(0x4a5462));
    const CGFloat my = yOf(FilterFxMag(fp.mode, fc, fc, q));
    FillRound(NSMakeRect(mx - 4, std::clamp(my, plot.origin.y, NSMaxY(plot)) - 4, 8, 8), 4, on ? C(0xffffff) : C(0x8793a3));
    Text(@"20 Hz", NSMakeRect(V.origin.x + 6, V.origin.y + 3, 40, 10), 6.5, C(0x4a5462), NSFontWeightSemibold);
    TextA(@"20 kHz", NSMakeRect(NSMaxX(V) - 46, V.origin.y + 3, 40, 10), 6.5, C(0x4a5462), NSFontWeightSemibold, NSTextAlignmentRight);
    TextA(S(ui::fxValueText(current.fx, FxFilter, 1)), NSMakeRect(V.origin.x, NSMaxY(V) - 12, V.size.width - 8, 10), 7,
          on ? acc : C(0x8793a3), NSFontWeightBold, NSTextAlignmentRight);
    Text(S(ui::filterFxModeName(fp.mode)), NSMakeRect(V.origin.x + 8, NSMaxY(V) - 12, 80, 10), 7, C(0x8793a3), NSFontWeightBold);
}

- (NSRect)compAutoGainPill { NSRect V = [self fxDetailVisual]; return NSMakeRect(NSMaxX(V) - 66, NSMaxY(V) - 14, 60, 13); }
// 0.28.0 COMP page: input/output curve per band (from the parameters) beside the three band trims.
- (void)drawCompVisual:(bool)on {
    const CompressorParams& cp = current.fx.comp;
    NSColor* acc = C(kFxAccent[FxComp]);
    NSRect V = [self fxDetailVisual];
    FillRound(V, 6, C(0x10151c));
    const bool multi = cp.mode == 1;
    NSRect plot = NSMakeRect(V.origin.x + 8, V.origin.y + 16, multi ? V.size.width - 62 : V.size.width - 16, V.size.height - 32);
    auto xOf = [&](double db) { return plot.origin.x + plot.size.width * (std::clamp(db, -72.0, 0.0) + 72.0) / 72.0; };
    auto yOf = [&](double db) { return plot.origin.y + plot.size.height * (std::clamp(db, -72.0, 6.0) + 72.0) / 78.0; };
    [C(0x232b36) setStroke];
    for (double g : {-60.0, -48.0, -36.0, -24.0, -12.0}) {
        NSBezierPath* l = [NSBezierPath bezierPath];
        [l moveToPoint:NSMakePoint(xOf(g), plot.origin.y)]; [l lineToPoint:NSMakePoint(xOf(g), NSMaxY(plot))];
        [l moveToPoint:NSMakePoint(plot.origin.x, yOf(g))]; [l lineToPoint:NSMakePoint(NSMaxX(plot), yOf(g))]; [l stroke];
    }
    { NSBezierPath* l = [NSBezierPath bezierPath]; // unity line
      [l moveToPoint:NSMakePoint(xOf(-72), yOf(-72))]; [l lineToPoint:NSMakePoint(xOf(0), yOf(0))];
      CGFloat d[2] = {2, 3}; [l setLineDash:d count:2 phase:0]; [C(0x3a4452) setStroke]; [l stroke]; }
    const double a = std::clamp(cp.amount, 0.0, 1.0);
    MultibandComp mb; mb.init(48000.0); mb.set(cp);
    auto outDb = [&](double in) {
        if (multi) return in + mb.staticGainDb(in);
        const double thr = -6.0 - 30.0 * a, ratio = 1.5 + 6.5 * a;
        return in > thr ? thr + (in - thr) / ratio : in;
    };
    NSBezierPath* curve = [NSBezierPath bezierPath];
    for (int k = 0; k <= 96; ++k) {
        double in = -72.0 + 72.0 * k / 96.0;
        NSPoint pt = NSMakePoint(xOf(in), yOf(outDb(in)));
        k ? [curve lineToPoint:pt] : [curve moveToPoint:pt];
    }
    NSBezierPath* fill = [curve copy];
    [fill lineToPoint:NSMakePoint(NSMaxX(plot), plot.origin.y)]; [fill lineToPoint:NSMakePoint(plot.origin.x, plot.origin.y)]; [fill closePath];
    [C(kFxAccent[FxComp], on ? 0.12 : 0.05) setFill]; [fill fill];
    [(on ? acc : C(0x4a5462)) setStroke]; curve.lineWidth = 1.8; [curve stroke];
    if (multi) { // knees: where upward lift and downward squeeze start
        for (double k : {-12.0 - 18.0 * a, -18.0 - 18.0 * a}) {
            if (k == -18.0 - 18.0 * a && cp.upward <= 0.0) continue;
            FillRound(NSMakeRect(xOf(k) - 3, yOf(outDb(k)) - 3, 6, 6), 3, on ? C(0xffffff) : C(0x8793a3));
        }
        // Band trims: three meters, centre is 0 dB, +/-12 dB range.
        static const char* nm[3] = {"LO", "MID", "HI"};
        const double trim[3] = {cp.lowDb, cp.midDb, cp.highDb};
        for (int b = 0; b < 3; ++b) {
            NSRect col = NSMakeRect(NSMaxX(plot) + 8 + b * 15, plot.origin.y, 11, plot.size.height);
            FillRound(col, 3, C(0x19202a));
            const CGFloat mid = NSMidY(col), h = col.size.height / 2 - 2;
            const CGFloat y1 = mid + h * std::clamp(trim[b], -12.0, 12.0) / 12.0;
            FillRound(NSMakeRect(col.origin.x + 2, std::min(mid, y1), 7, std::max<CGFloat>(std::fabs(y1 - mid), 1.5)), 2,
                      on ? C(kFxAccent[FxComp], 0.85) : C(0x4a5462));
            FillRound(NSMakeRect(col.origin.x, mid - 0.5, 11, 1), 0.5, C(0x5f6b7b));
            TextA(S(nm[b]), NSMakeRect(col.origin.x - 4, V.origin.y + 3, 19, 10), 6, C(0x5f6b7b), NSFontWeightBold, NSTextAlignmentCenter);
        }
    }
    Text(@"IN -72 dB", NSMakeRect(V.origin.x + 6, V.origin.y + 3, 50, 10), 6.5, C(0x4a5462), NSFontWeightSemibold);
    TextA(@"0 dB", NSMakeRect(NSMaxX(plot) - 30, V.origin.y + 3, 30, 10), 6.5, C(0x4a5462), NSFontWeightSemibold, NSTextAlignmentRight);
    Text(S(ui::compModeName(cp.mode)), NSMakeRect(V.origin.x + 8, NSMaxY(V) - 12, 80, 10), 7, C(0x8793a3), NSFontWeightBold);
    if (multi) { // 0.29.0 AUTO GAIN pill (click toggles)
        NSRect pill = [self compAutoGainPill];
        const bool mk = cp.makeup != 0;
        FillRound(pill, 5, mk ? C(kFxAccent[FxComp], on ? 0.28 : 0.12) : C(0x19202a));
        char t[32];
        if (mk) snprintf(t, sizeof t, "AUTO %+.1f dB", mb.makeupDb()); else snprintf(t, sizeof t, "AUTO GAIN");
        TextA(S(t), NSMakeRect(pill.origin.x, pill.origin.y + 2.5, pill.size.width, 10), 6.5, mk ? (on ? acc : C(0x8793a3)) : C(0x5f6b7b),
              NSFontWeightBold, NSTextAlignmentCenter);
    } else {
        char t[32]; snprintf(t, sizeof t, "%.1f:1", 1.5 + 6.5 * a);
        TextA(S(t), NSMakeRect(V.origin.x, NSMaxY(V) - 12, V.size.width - 8, 10), 7, on ? acc : C(0x8793a3), NSFontWeightBold, NSTextAlignmentRight);
    }
}

// 0.28.0 REVERB page: energy over time - pre-delay gap, diffusion build, decay slope; the dim line is the treble dying first.
- (void)drawReverbVisual:(bool)on {
    const ReverbParams& rp = current.fx.reverb;
    NSColor* acc = C(kFxAccent[FxReverb]);
    NSRect V = [self fxDetailVisual];
    FillRound(V, 6, C(0x10151c));
    NSRect plot = NSMakeRect(V.origin.x + 8, V.origin.y + 16, V.size.width - 16, V.size.height - 32);
    const bool classic = rp.mode == 0;
    const double rt = classic ? -3.0 * 0.028 / std::log10(std::clamp(rp.decay, 0.05, 0.97)) : SpaceReverb::rt60(rp.mode, rp.decay);
    const double pre = classic ? 0.0 : std::clamp(rp.preDelayMs, 0.0, 250.0) * 0.001;
    const double span = std::max(0.5, (pre + rt) * 1.1);
    auto xOf = [&](double sec) { return plot.origin.x + plot.size.width * std::clamp(sec / span, 0.0, 1.0); };
    auto yOf = [&](double db) { return plot.origin.y + plot.size.height * (std::clamp(db, -66.0, 0.0) + 66.0) / 66.0; };
    [C(0x232b36) setStroke];
    for (double g : {-60.0, -40.0, -20.0}) {
        NSBezierPath* l = [NSBezierPath bezierPath];
        [l moveToPoint:NSMakePoint(plot.origin.x, yOf(g))]; [l lineToPoint:NSMakePoint(NSMaxX(plot), yOf(g))]; [l stroke];
    }
    const double build = classic ? 0.01 : (rp.mode == 2 ? 0.006 : 0.02 + 0.04 * std::clamp(rp.size, 0.0, 1.0));
    const double damp = std::clamp(rp.damping, 0.0, 1.0) * (rp.mode == 2 ? 0.6 : 0.85);
    auto env = [&](double t, double speed) { // dB at time t; speed > 1 decays faster
        if (t < pre) return -80.0;
        double u = t - pre, rise = std::min(1.0, u / build);
        return 20.0 * std::log10(std::max(rise, 1e-4)) - 60.0 * speed * u / rt;
    };
    auto path = [&](double speed) {
        NSBezierPath* c = [NSBezierPath bezierPath];
        for (int k = 0; k <= 140; ++k) {
            double t = span * k / 140.0;
            NSPoint pt = NSMakePoint(xOf(t), yOf(env(t, speed)));
            k ? [c lineToPoint:pt] : [c moveToPoint:pt];
        }
        return c;
    };
    if (pre > 0) FillRound(NSMakeRect(plot.origin.x, plot.origin.y, xOf(pre) - plot.origin.x, plot.size.height), 2, C(0x19202a));
    NSBezierPath* body = path(1.0);
    NSBezierPath* fill = [body copy];
    [fill lineToPoint:NSMakePoint(NSMaxX(plot), plot.origin.y)]; [fill lineToPoint:NSMakePoint(plot.origin.x, plot.origin.y)]; [fill closePath];
    [C(kFxAccent[FxReverb], on ? 0.14 : 0.05) setFill]; [fill fill];
    NSBezierPath* treble = path(1.0 + 1.6 * damp);
    CGFloat d[2] = {3, 3}; [treble setLineDash:d count:2 phase:0];
    [C(kFxAccent[FxReverb], on ? 0.5 : 0.2) setStroke]; treble.lineWidth = 1; [treble stroke];
    [(on ? acc : C(0x4a5462)) setStroke]; body.lineWidth = 1.8; [body stroke];
    const CGFloat xr = xOf(pre + rt); // RT60 marker
    FillRound(NSMakeRect(xr - 0.75, plot.origin.y, 1.5, plot.size.height), 0.75, on ? C(0xd5dce5, 0.6) : C(0x4a5462));
    FillRound(NSMakeRect(xr - 3.5, yOf(-60) - 3.5, 7, 7), 3.5, on ? C(0xffffff) : C(0x8793a3));
    char t[40];
    snprintf(t, sizeof t, "%sRT60 %.1f s", classic ? "~" : "", rt);
    TextA(S(t), NSMakeRect(V.origin.x, NSMaxY(V) - 12, V.size.width - 8, 10), 7, on ? acc : C(0x8793a3), NSFontWeightBold, NSTextAlignmentRight);
    Text(S(ui::reverbModeName(rp.mode)), NSMakeRect(V.origin.x + 8, NSMaxY(V) - 12, 80, 10), 7, C(0x8793a3), NSFontWeightBold);
    Text(@"0 s", NSMakeRect(V.origin.x + 6, V.origin.y + 3, 30, 10), 6.5, C(0x4a5462), NSFontWeightSemibold);
    snprintf(t, sizeof t, "%.1f s", span);
    TextA(S(t), NSMakeRect(NSMaxX(V) - 46, V.origin.y + 3, 40, 10), 6.5, C(0x4a5462), NSFontWeightSemibold, NSTextAlignmentRight);
}

// ---- interaction ----
- (void)drawFxDetail {
    const int u = fxDetail;
    const FXParams& f = current.fx;
    NSColor* acc = C(kFxAccent[u]);
    bool on = FxEnabled(const_cast<Preset&>(current), u);
    NSRect P = [self fxDetailPanel];
    FillRound(P, 10, C(0x19202a));
    NSBezierPath* edge = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(P, 0.5, 0.5) xRadius:10 yRadius:10];
    [C(kFxAccent[u], 0.45) setStroke]; edge.lineWidth = 1; [edge stroke];
    FillRound(NSMakeRect(P.origin.x + 12, NSMaxY(P) - 22, 3, 12), 1.5, acc);
    NSString* title = S(ui::fxUnitTitle(u));
    const CGFloat titleW = [title sizeWithAttributes:@{NSFontAttributeName: [NSFont systemFontOfSize:11 weight:NSFontWeightBold]}].width;
    Text(title, NSMakeRect(P.origin.x + 21, NSMaxY(P) - 24, std::max<CGFloat>(120, titleW + 4), 15), 11, acc, NSFontWeightBold);
    // 0.27.0: the slot label follows the title so long titles never run into it.
    Text([NSString stringWithFormat:@"SLOT %d OF %d", f.order.slotOf(u) + 1, kFxUnits],
         NSMakeRect(P.origin.x + std::max<CGFloat>(128, 21 + titleW + 14), NSMaxY(P) - 22.5, 90, 12), 8,
         C(0x5f6b7b), NSFontWeightSemibold);
    NSRect tg = [self fxDetailToggle];
    FillRound(tg, 8, on ? C(kFxAccent[u], 0.22) : C(0x232b36));
    FillRound(NSMakeRect(tg.origin.x + 7, NSMidY(tg) - 3, 6, 6), 3, on ? acc : C(0x4a5462));
    TextA(on ? @"ON" : @"OFF", NSMakeRect(tg.origin.x + 14, tg.origin.y + 2.5, tg.size.width - 18, 11), 8, on ? acc : C(0x8793a3),
          NSFontWeightBold, NSTextAlignmentCenter);
    NSRect cl = [self fxDetailClose];
    NSBezierPath* x = [NSBezierPath bezierPath];
    [x moveToPoint:NSMakePoint(NSMidX(cl) - 4, NSMidY(cl) - 4)]; [x lineToPoint:NSMakePoint(NSMidX(cl) + 4, NSMidY(cl) + 4)];
    [x moveToPoint:NSMakePoint(NSMidX(cl) - 4, NSMidY(cl) + 4)]; [x lineToPoint:NSMakePoint(NSMidX(cl) + 4, NSMidY(cl) - 4)];
    [C(0x8793a3) setStroke]; x.lineWidth = 1.4; [x stroke];
    [C(0x29313d) setFill]; NSRectFill(NSMakeRect(P.origin.x + 12, NSMaxY(P) - 34, P.size.width - 24, 1));

    const auto& cs = ui::fxControls(u);
    const bool compact = FxVisualPage(u);
    const CGFloat valW = compact ? 52 : 64, tagW = compact ? 32 : 36;
    for (int i = 0; i < (int)cs.size(); ++i) {
        const ui::FxControl& c = cs[i];
        NSRect row = [self fxDetailRow:i], bar = [self fxDetailBar:i];
        bool inactive = ui::fxRowInactive(f, u, i);
        bool live = on && !inactive;
        Text(S(c.label), NSMakeRect(row.origin.x + 2, row.origin.y + (compact ? 3 : 4), compact ? 60 : 88, 12), compact ? 7.5 : 8.5,
             inactive ? C(0x4a5462) : C(0xa8b2c1), NSFontWeightSemibold);
        const double v = ui::fxGet(f, u, i);
        if (c.fmt == ui::FmtChoice && c.hi - c.lo < 3) { // segmented choice
            int n = (int)(c.hi - c.lo) + 1;
            CGFloat w = bar.size.width / n;
            for (int k = 0; k < n; ++k) {
                NSRect seg = NSMakeRect(bar.origin.x + k * w + 1, bar.origin.y - 1, w - 2, 16);
                bool sel = (int)v == k;
                FillRound(seg, 4, sel ? C(kFxAccent[u], live ? 0.28 : 0.12) : C(0x10151c));
                TextA(S(ui::fxChoiceName(u, i, k)), NSMakeRect(seg.origin.x, seg.origin.y + (compact ? 3.5 : 3), seg.size.width, 11), compact ? 6.5 : 7.5,
                      sel ? (live ? acc : C(0x8793a3)) : C(0x5f6b7b), NSFontWeightBold, NSTextAlignmentCenter);
            }
        } else if (c.fmt == ui::FmtChoice) { // stepper: left half steps down, right half up
            NSRect box = NSMakeRect(bar.origin.x + 1, bar.origin.y - 1, bar.size.width - 2, compact ? 15 : 16);
            FillRound(box, 4, C(0x10151c));
            TextA(@"\u25C0", NSMakeRect(box.origin.x + 4, box.origin.y + 3, 14, 11), 7, (int)v > c.lo ? C(0x8793a3) : C(0x303947), NSFontWeightBold, NSTextAlignmentCenter);
            TextA(@"\u25B6", NSMakeRect(NSMaxX(box) - 18, box.origin.y + 3, 14, 11), 7, (int)v < c.hi ? C(0x8793a3) : C(0x303947), NSFontWeightBold, NSTextAlignmentCenter);
            if (u == FxFilter && i == 0) // filter type: the name sits in the stepper
                TextA(S(ui::filterFxModeName((int)v)), NSMakeRect(box.origin.x + 18, box.origin.y + 3, box.size.width - 36, 10), 7,
                      on ? acc : C(0x8793a3), NSFontWeightBold, NSTextAlignmentCenter);
            else
                TextA((int)v == 0 ? (compact ? @"FREE" : @"FREE TIME") : (compact ? @"SYNC" : @"TEMPO SYNC"),
                      NSMakeRect(box.origin.x + 18, box.origin.y + 3.5, box.size.width - 36, 10), 7,
                      (int)v == 0 ? C(0x5f6b7b) : (live || on ? acc : C(0x8793a3)), NSFontWeightSemibold, NSTextAlignmentCenter);
        } else { // slider
            double n = ui::fxNorm(c, v);
            NSRect track = NSMakeRect(bar.origin.x, NSMidY(bar) - 2, bar.size.width, 4);
            FillRound(track, 2, C(0x10151c));
            bool bip = c.lo < 0 && c.hi > 0; // dB rows fill from the centre
            double z = bip ? ui::fxNorm(c, 0.0) : 0.0;
            CGFloat a0 = track.origin.x + track.size.width * std::min(z, n), a1 = track.origin.x + track.size.width * std::max(z, n);
            FillRound(NSMakeRect(a0, track.origin.y, std::max<CGFloat>(a1 - a0, 0), 4), 2, inactive ? C(0x303947) : live ? acc : C(0x4a5462));
            if (c.dest >= 0) { // modulation ranges into this row: macros push one way (above), FX LFOs swing both ways (below)
                double mac = 0, lfo = 0;
                for (const auto& rt : current.routes) {
                    if ((int)rt.dest != c.dest || !ui::routeActive(rt)) continue;
                    (IsRack(rt.source) ? lfo : mac) += rt.amount;
                }
                // FX CUTOFF routes are octaves (1 = +4 oct) on a log row; others are row units.
                double unit = c.dest == (int)ModRoute::Dest::FxFilterCutoff ? 4.0 / std::log2(c.hi / c.lo)
                                                                            : (c.fmt == ui::FmtMs ? 10.0 : 1.0) / (c.hi - c.lo);
                if (mac != 0) {
                    double span = mac * unit;
                    double m0 = std::clamp(n + std::min(0.0, span), 0.0, 1.0), m1 = std::clamp(n + std::max(0.0, span), 0.0, 1.0);
                    FillRound(NSMakeRect(track.origin.x + track.size.width * m0, track.origin.y - 3, track.size.width * (m1 - m0), 2), 1,
                              C(0xf27a55, 0.9));
                }
                if (lfo != 0) {
                    double span = std::fabs(lfo * unit);
                    double m0 = std::clamp(n - span, 0.0, 1.0), m1 = std::clamp(n + span, 0.0, 1.0);
                    FillRound(NSMakeRect(track.origin.x + track.size.width * m0, track.origin.y + 6.5, track.size.width * (m1 - m0), 2), 1,
                              C(0xb68cff, 0.9));
                }
            }
            NSPoint k = NSMakePoint(track.origin.x + track.size.width * n, NSMidY(track));
            FillRound(NSMakeRect(k.x - 5, k.y - 5, 10, 10), 5, inactive ? C(0x303947) : (fxRowDrag == i ? C(0xffffff) : C(0xd5dce5)));
            FillRound(NSMakeRect(k.x - 2, k.y - 2, 4, 4), 2, inactive ? C(0x19202a) : acc);
        }
        const bool segRow = c.fmt == ui::FmtChoice && c.hi - c.lo < 3;
        if (!(u == FxFilter && i == 0) && !(compact && segRow)) // 0.29.0: compact segmented rows already show their value
            TextA(S(ui::fxValueText(f, u, i)), NSMakeRect(NSMaxX(bar) + 4, row.origin.y + (compact ? 2.5 : 3.5), valW, 13), compact ? 8.5 : 9.5,
                  inactive ? C(0x5f6b7b) : fxRowDrag == i ? acc : C(0xd5dce5), NSFontWeightMedium, NSTextAlignmentRight);
        if (c.dest >= 0) { // modulation tag: route amount when a macro or FX LFO drives this row
            int nr = 0; double amt = ui::fxRouteSum(current.routes, c.dest, &nr);
            NSRect tag = NSMakeRect(NSMaxX(row) - tagW, row.origin.y + (compact ? 2 : 3), tagW, compact ? 13 : 14);
            bool rack = false;
            for (const auto& rt : current.routes) if ((int)rt.dest == c.dest && ui::routeActive(rt) && IsRack(rt.source)) rack = true;
            NSColor* tc = rack ? C(0xb68cff) : C(0xf27a55);
            FillRound(tag, 4, nr ? [tc colorWithAlphaComponent:0.18] : C(0x10151c));
            NSString* t = !nr ? @"MOD" : c.fmt == ui::FmtMs ? [NSString stringWithFormat:@"%+.0fms", amt * 10.0]
                        : c.dest == (int)ModRoute::Dest::FxFilterCutoff ? [NSString stringWithFormat:@"%+.1fo", amt * 4.0]
                                                   : [NSString stringWithFormat:@"%+.0f%%", amt * 100.0];
            TextA(t, NSMakeRect(tag.origin.x, tag.origin.y + 2.5, tag.size.width, 10), 7, nr ? tc : C(0x4a5462), NSFontWeightBold,
                  NSTextAlignmentCenter);
        }
    }
    // Footer: what the unit is doing right now.
    char foot[96] = "";
    switch (u) {
    case FxDelay: {
        auto side = [&](int sync, double sec) {
            char t[16];
            if (sync > 0) snprintf(t, sizeof t, "%s", ui::syncName(sync)); else snprintf(t, sizeof t, "%.0f ms", sec * 1000);
            return std::string(t);
        };
        snprintf(foot, sizeof foot, "L %s  \u2022  R %s  \u2022  SYNCED SIDES FOLLOW THE HOST TEMPO",
                 side(f.delay.syncL, f.delay.timeLSec).c_str(), side(f.delay.syncR, f.delay.timeRSec).c_str());
        break;
    }
    case FxComp: {
        const double a = std::clamp(f.comp.amount, 0.0, 1.0);
        if (f.comp.mode == 1)
            snprintf(foot, sizeof foot, "3 BANDS  \u2022  SPLITS 120 Hz / 2.5 kHz  \u2022  DOWN %.1f:1 ABOVE %.0f dB  \u2022  UP BELOW %.0f dB",
                     1.0 + 5.0 * a, -12.0 - 18.0 * a, -18.0 - 18.0 * a);
        else
            snprintf(foot, sizeof foot, "THRESHOLD %.0f dB  \u2022  RATIO %.1f:1  \u2022  ONE-KNOB MAKEUP", -6.0 - 30.0 * a, 1.5 + 6.5 * a);
        break;
    }
    case FxReverb:
        if (f.reverb.mode == 0) snprintf(foot, sizeof foot, "FOUR DAMPED COMBS INTO TWO ALLPASSES PER SIDE");
        else snprintf(foot, sizeof foot, "%s  \u2022  8-LINE FEEDBACK NETWORK  \u2022  RT60 %.1f s  \u2022  PRE %.0f ms",
                      f.reverb.mode == 2 ? "PLATE" : "HALL", SpaceReverb::rt60(f.reverb.mode, f.reverb.decay), f.reverb.preDelayMs);
        break;
    case FxPhaser: snprintf(foot, sizeof foot, "SIX ALLPASS STAGES  \u2022  SWEEP 180 Hz TO %.1f kHz", 0.18 * std::pow(25.0, std::clamp(f.phaser.depth, 0.0, 1.0))); break;
    case FxFlanger: snprintf(foot, sizeof foot, "SWEEP 0.3 TO %.1f ms  \u2022  QUADRATURE STEREO", 0.3 + 4.0 * std::clamp(f.flanger.depth, 0.0, 1.0)); break;
    case FxChorus: snprintf(foot, sizeof foot, "TWO MODULATED TAPS  \u2022  %.1f TO %.1f ms", f.chorus.baseMs, f.chorus.baseMs + f.chorus.depthMs); break;
    case FxDist: snprintf(foot, sizeof foot, "OUTPUT TRIMS AS DRIVE RISES"); break;
    case FxHyper:
        snprintf(foot, sizeof foot, "SIX DRIFTING VOICES  \u2022  %.0f TO %.0f ms  \u2022  CROSS-FED DIMENSION TAPS",
                 Hyper::voiceBaseMs(0), Hyper::voiceBaseMs(Hyper::kVoices - 1));
        break;
    case FxFilter: {
        const double lo = std::clamp(f.filter.cutoffHz * std::pow(2.0, -4.0 * f.filter.lfoDepth), 20.0, 20000.0);
        const double hi = std::clamp(f.filter.cutoffHz * std::pow(2.0, 4.0 * f.filter.lfoDepth), 20.0, 20000.0);
        auto hz = [](double v) { char t[16]; if (v >= 1000) snprintf(t, sizeof t, "%.1f kHz", v / 1000); else snprintf(t, sizeof t, "%.0f Hz", v); return std::string(t); };
        if (f.filter.lfoDepth <= 0.0) snprintf(foot, sizeof foot, "STEREO STATE-VARIABLE FILTER  \u2022  SWEEP OFF");
        else snprintf(foot, sizeof foot, "SWEEP %s TO %s  \u2022  %s  \u2022  RIGHT SIDE LEADS", hz(lo).c_str(), hz(hi).c_str(),
                      f.filter.lfoSync > 0 ? (std::string(ui::syncName(f.filter.lfoSync)) + " SYNCED").c_str() : "FREE RUNNING");
        break;
    }
    default: break;
    }
    if (u == FxHyper) [self drawHyperVisual:on];
    else if (u == FxFilter) [self drawFilterFxVisual:on];
    else if (u == FxComp) [self drawCompVisual:on];
    else if (u == FxReverb) [self drawReverbVisual:on];
    if (u == FxEQ) { // response curve under the three bands
        NSRect plot = NSMakeRect(P.origin.x + 104, P.origin.y + 14, 196, 66);
        FillRound(plot, 6, C(0x10151c));
        [C(0x232b36) setStroke];
        for (int g = -1; g <= 1; ++g) {
            NSBezierPath* l = [NSBezierPath bezierPath];
            CGFloat y = NSMidY(plot) + g * (plot.size.height / 2 - 8) * 0.5;
            [l moveToPoint:NSMakePoint(plot.origin.x + 6, y)]; [l lineToPoint:NSMakePoint(NSMaxX(plot) - 6, y)]; [l stroke];
        }
        NSBezierPath* curve = [NSBezierPath bezierPath];
        for (int k = 0; k <= 96; ++k) {
            double hz = 20.0 * std::pow(1000.0, k / 96.0), lo = hz / 180.0, hi = hz / 6000.0, oct = std::log2(hz / 1200.0);
            double db = f.eq.lowDb / (1 + lo * lo) + f.eq.highDb * hi * hi / (1 + hi * hi) + f.eq.midDb * std::exp(-oct * oct * 1.5);
            NSPoint q = NSMakePoint(plot.origin.x + 6 + (plot.size.width - 12) * k / 96.0,
                                    NSMidY(plot) + std::clamp(db, -12.0, 12.0) / 12.0 * (plot.size.height / 2 - 8));
            k ? [curve lineToPoint:q] : [curve moveToPoint:q];
        }
        [(on ? acc : C(0x4a5462)) setStroke]; curve.lineWidth = 1.8; [curve stroke];
        Text(@"20 Hz", NSMakeRect(plot.origin.x + 6, plot.origin.y + 3, 40, 10), 6.5, C(0x4a5462), NSFontWeightSemibold);
        TextA(@"20 kHz", NSMakeRect(NSMaxX(plot) - 46, plot.origin.y + 3, 40, 10), 6.5, C(0x4a5462), NSFontWeightSemibold, NSTextAlignmentRight);
    } else if (*foot) {
        Text(S(foot), NSMakeRect(P.origin.x + 14, P.origin.y + 10, P.size.width - 28, 11), 7.5, C(0x4f5a69), NSFontWeightSemibold);
    }
}

// Detail panel clicks. Returns YES when the panel took the click.
- (BOOL)fxDetailMouseDown:(NSPoint)p event:(NSEvent*)e {
    if (fxDetail < 0 || !NSPointInRect(p, [self fxDetailPanel])) return NO;
    const int u = fxDetail;
    if (NSPointInRect(p, NSInsetRect([self fxDetailClose], -4, -4))) { fxDetail = -1; [self setNeedsDisplay:YES]; return YES; }
    if (NSPointInRect(p, [self fxDetailToggle])) {
        bool& en = FxEnabled(current, u); en = !en;
        edited = true; [self applySound]; [self setNeedsDisplay:YES]; return YES;
    }
    if (u == FxComp && current.fx.comp.mode == 1 && NSPointInRect(p, NSInsetRect([self compAutoGainPill], -3, -3))) { // 0.29.0
        current.fx.comp.makeup = current.fx.comp.makeup ? 0 : 1;
        edited = true; [self applySound]; [self setNeedsDisplay:YES]; return YES;
    }
    const auto& cs = ui::fxControls(u);
    for (int i = 0; i < (int)cs.size(); ++i) {
        NSRect bar = NSInsetRect([self fxDetailBar:i], -6, -4);
        if (!NSPointInRect(p, bar)) continue;
        const ui::FxControl& c = cs[i];
        bar = [self fxDetailBar:i];
        if (c.fmt == ui::FmtChoice) {
            int v = (int)ui::fxGet(current.fx, u, i);
            if (c.hi - c.lo < 3) v = (int)std::clamp((p.x - bar.origin.x) / (bar.size.width / (c.hi - c.lo + 1)), c.lo, c.hi);
            else v += p.x < NSMidX(bar) ? -1 : 1;
            ui::fxSet(current.fx, u, i, v);
            edited = true; [self applySound]; [self setNeedsDisplay:YES];
            return YES;
        }
        fxRowDrag = i;
        int id = FxRowParam(u, i);
        if (id >= 0 && host) host->parameterGesture(id, true);
        double v = e.clickCount == 2 ? ui::fxDefault(u, i) : ui::fxFromNorm(c, (p.x - bar.origin.x) / bar.size.width);
        [self setFxRow:i value:v];
        return YES;
    }
    return YES; // the panel is modal over the matrix
}

- (void)setFxRow:(int)i value:(double)v {
    ui::fxSet(current.fx, fxDetail, i, v);
    edited = true;
    int id = FxRowParam(fxDetail, i);
    if (id < 0 || !host || !host->editParameter(id, current)) [self applySound];
    [self setNeedsDisplay:YES];
}

- (NSInteger)hitKnob:(NSPoint)p {
    for (int k = 0; k < ui::KnobCount; ++k) {
        if (ui::knobPage(k) >= 0 && ui::knobPage(k) != filterPage) continue; // other FILTER page
        NSPoint c = [self knobCenter:k];
        CGFloat reach = [self oscRowKnob:k] ? 6 : 8; // osc-row knobs sit 60 pt apart
        if (hypot(p.x - c.x, p.y - c.y) < [self knobRadius:k] + reach) return k;
    }
    for (int s = 0; s < kFxUnits; ++s) {
        const int u = current.fx.order.slot[s];
        if (FxParam(u) < 0) continue;
        NSPoint c = [self fxRingCenter:s];
        if (hypot(p.x - c.x, p.y - c.y) < 16) return kFxDrag + u;
    }
    return -1;
}

// ---- mod matrix interaction ----
- (BOOL)matrixMouseDown:(NSPoint)p event:(NSEvent*)e {
    const auto& srcs = ui::matrixSources();
    int n = (int)current.routes.size();
    for (int i = 0; i < 4; ++i)
        if (NSPointInRect(p, [self pageTab:i])) { matrixPage = i; [self setNeedsDisplay:YES]; return YES; }
    if ((IsMseg(srcs[modSel]) || IsLfo(srcs[modSel])) && NSPointInRect(p, NSMakeRect([self modPreview].origin.x, [self modPreview].origin.y, [self modPreview].size.width, [self modPreview].size.height + 14))) { // open / close the MSEG or LFO editor
        int k = EditIndex(srcs[modSel]);
        msegEdit = msegEdit == k ? -1 : k;
        if (msegEdit >= 0) fxDetail = -1;
        [self setNeedsDisplay:YES];
        return YES;
    }
    if (NSPointInRect(p, [self bendChip])) { // 0.24.0 BEND RANGE: left third steps down, the rest up
        const int d = p.x < [self bendChip].origin.x + 24 ? -1 : 1;
        current.voice.bendRange = std::clamp(current.voice.bendRange + d, 0, 24);
        for (int i = 0; i < (int)srcs.size(); ++i) if (srcs[i] == ModRoute::Source::PitchBend) modSel = i;
        edited = true; [self applySound]; [self setNeedsDisplay:YES];
        return YES;
    }
    for (int i = 0; i < (int)srcs.size(); ++i)
        if (NSPointInRect(p, [self sourceBadge:i])) { // select; dragging it onto a knob assigns
            modSel = i; dragSource = i; dragPoint = p; dropKnob = -1;
            [self setNeedsDisplay:YES];
            return YES;
        }
    for (int i = 0; i < 4; ++i) {
        int slot = matrixPage * 4 + i;
        if (!NSPointInRect(p, [self routeRow:i])) continue;
        if (slot == n && n < kMaxRoutes) { [self popMenu:0 slot:slot at:p]; return YES; } // + ADD ROUTE
        if (slot >= n) return YES;
        if (NSPointInRect(p, [self routeClear:i])) {
            ui::removeRoute(current.routes, slot);
            edited = true; [self applySound]; [self setNeedsDisplay:YES];
            return YES;
        }
        if (NSPointInRect(p, [self routeSourcePill:i])) { [self popMenu:1 slot:slot at:p]; return YES; }
        if (NSPointInRect(p, [self routeDestPill:i])) { [self popMenu:2 slot:slot at:p]; return YES; }
        if (NSPointInRect(p, NSInsetRect([self routeCurve:i], -1, -3))) { // bend: drag up for EXP, down for LOG
            if (e.clickCount == 2) { current.routes[slot].curve = 0.0; edited = true; [self applySound]; }
            curveDrag = slot; dragValue = current.routes[slot].curve;
            [self setNeedsDisplay:YES];
            return YES;
        }
        if (NSPointInRect(p, NSInsetRect([self routeAux:i], -1, -3))) { // set: pick a source; set already: clear
            if (current.routes[slot].aux >= 0) { current.routes[slot].aux = -1; edited = true; [self applySound]; [self setNeedsDisplay:YES]; }
            else [self popMenu:3 slot:slot at:p];
            return YES;
        }
        if (NSPointInRect(p, NSInsetRect([self routeBar:i], -4, 0))) {
            if (e.clickCount == 2) { // double-click: back to the default depth
                current.routes[slot].amount = ui::defaultRouteAmount(current.routes[slot].dest);
                edited = true; [self applySound];
            }
            routeDrag = slot; dragValue = ui::routeDisplayAmount(current.routes[slot]);
            [self setNeedsDisplay:YES];
            return YES;
        }
        return YES;
    }
    int nf = [self modFieldCount];
    for (int j = 0; j < nf; ++j) {
        if (!NSPointInRect(p, [self modField:j])) continue;
        ModRoute::Source sel = srcs[modSel];
        VoiceParams& v = current.voice;
        if (IsMseg(sel)) {
            auto mv = ui::msegView(v, MsegIndex(sel));
            if (j == 0) mv.setMode((mv.mode() + 1) % 3);
            else if (j == 2) *mv.sync = *mv.sync ? 0 : 3;
            else { modFieldDrag = 1; dragValue = *mv.sync ? (*mv.sync - 1) / (double)(kSyncCount - 2) : TimeTo01(*mv.seconds); }
            if (j != 1) { edited = true; [self applySound]; }
        } else if (IsRack(sel)) {
            RackLfoParams& rl = current.fx.lfo[RackIndex(sel)];
            if (j == 0) rl.shape = (rl.shape + 1) % 4;
            else if (j == 2) rl.sync = rl.sync ? 0 : 3;
            else { modFieldDrag = 1; dragValue = rl.sync ? (rl.sync - 1) / (double)(kSyncCount - 2) : RateTo01(rl.rateHz); }
            if (j != 1) { edited = true; [self applySound]; }
        } else if (IsLfo(sel)) {
            int li = LfoIndex(sel);
            if (j == 0) ui::setLfoShapeIndex(v, li, ui::lfoShapeIndex(v, li) + 1); // ... SQUARE, CUSTOM, SINE
            else if (j == 2) v.lfoSync[li] = v.lfoSync[li] ? 0 : 3; // FREE <-> 1/4, rate then steps divisions
            else { modFieldDrag = 1; dragValue = v.lfoSync[li] ? (v.lfoSync[li] - 1) / (double)(kSyncCount - 2) : RateTo01(ui::lfoRate(v, li)); }
            if (j != 1) { edited = true; [self applySound]; }
        } else {
            bool e3 = sel == ModRoute::Source::Env3;
            modFieldDrag = j;
            dragValue = j == 2 ? EnvField(v, e3, j) : TimeTo01(EnvField(v, e3, j));
        }
        [self setNeedsDisplay:YES];
        return YES;
    }
    return NO;
}

- (void)dragModField:(double)x {
    ModRoute::Source sel = ui::matrixSources()[modSel];
    VoiceParams& v = current.voice;
    x = std::clamp(x, 0.0, 1.0);
    if (IsMseg(sel)) {
        auto mv = ui::msegView(v, MsegIndex(sel));
        if (*mv.sync) *mv.sync = 1 + (int)std::lround(x * (kSyncCount - 2));
        else *mv.seconds = std::clamp(TimeFrom01(x), 0.05, 8.0);
    } else if (IsRack(sel)) {
        RackLfoParams& rl = current.fx.lfo[RackIndex(sel)];
        if (rl.sync) rl.sync = 1 + (int)std::lround(x * (kSyncCount - 2));
        else rl.rateHz = RateFrom01(x);
    } else if (IsLfo(sel)) {
        int li = LfoIndex(sel);
        if (v.lfoSync[li]) v.lfoSync[li] = 1 + (int)std::lround(x * (kSyncCount - 2));
        else ui::lfoRate(v, li) = RateFrom01(x);
    } else {
        bool e3 = sel == ModRoute::Source::Env3;
        EnvField(v, e3, modFieldDrag) = modFieldDrag == 2 ? x : TimeFrom01(x);
    }
    edited = true; [self applySound]; [self setNeedsDisplay:YES];
}

// kind 0: add a route (pick its source), 1: change source, 2: change destination.
- (void)popMenu:(int)kind slot:(int)slot at:(NSPoint)p {
    NSMenu* m = [[NSMenu alloc] initWithTitle:@""];
    m.autoenablesItems = NO;
    if (kind == 2) {
        const auto& d = ui::matrixDests();
        for (int i = 0; i < (int)d.size(); ++i) {
            NSMenuItem* it = [m addItemWithTitle:S(ui::destName(d[i])) action:@selector(menuPicked:) keyEquivalent:@""];
            it.target = self; it.tag = (kind * 100 + slot) * 100 + i;
            if (slot < (int)current.routes.size() && current.routes[slot].dest == d[i]) it.state = NSControlStateValueOn;
        }
    } else {
        const auto& s = ui::matrixSources();
        for (int i = 0; i < (int)s.size(); ++i) {
            NSMenuItem* it = [m addItemWithTitle:S(ui::sourceName(s[i])) action:@selector(menuPicked:) keyEquivalent:@""];
            it.target = self; it.tag = (kind * 100 + slot) * 100 + i;
            if (kind == 1 && slot < (int)current.routes.size() && current.routes[slot].source == s[i]) it.state = NSControlStateValueOn;
            if (kind == 3 && slot < (int)current.routes.size()) { // AUX: only sources that can reach this destination
                ModRoute t = current.routes[slot]; t.aux = (int)s[i];
                it.enabled = ui::auxActive(t);
            }
        }
        if (kind == 3) {
            [m insertItem:[NSMenuItem separatorItem] atIndex:0];
            NSMenuItem* h = [m insertItemWithTitle:@"AUX SCALES THIS ROUTE BY" action:nil keyEquivalent:@"" atIndex:0];
            h.enabled = NO;
        }
    }
    [m popUpMenuPositioningItem:nil atLocation:p inView:self];
}

- (void)menuPicked:(NSMenuItem*)it {
    int i = (int)(it.tag % 100), slot = (int)(it.tag / 100 % 100), kind = (int)(it.tag / 10000);
    if (kind == 0) {
        ModRoute::Source src = ui::matrixSources()[i];
        int got = ui::addRoute(current.routes, src, ModRoute::Dest::FilterCutoff);
        if (got < 0) { NSBeep(); return; }
        matrixPage = got / 4;
    } else if (slot < (int)current.routes.size()) {
        if (kind == 1) current.routes[slot].source = ui::matrixSources()[i];
        else if (kind == 3) current.routes[slot].aux = (int)ui::matrixSources()[i];
        else ui::setRouteDest(current.routes[slot], ui::matrixDests()[i]);
    }
    edited = true; [self applySound]; [self setNeedsDisplay:YES];
}

// ---- user presets ----
- (BOOL)saveUserPresetNamed:(NSString*)name {
    int idx = user::save(UserPresetDir(), current, std::string(name.UTF8String ?: ""), ui::library());
    if (idx < 0) { NSBeep(); return NO; }
    [self refilter];
    [self loadPresetIndex:idx]; // now a saved preset: no edit marker, host sees its name
    [self refilter];
    return YES;
}

- (void)promptSave {
    NSAlert* a = [NSAlert new];
    a.messageText = @"Save preset";
    a.informativeText = @"Saved to Music/MUEW/Presets. The app and the plugin both see it.";
    [a addButtonWithTitle:@"Save"]; [a addButtonWithTitle:@"Cancel"];
    NSTextField* f = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 240, 24)];
    f.stringValue = S(current.info.name.empty() ? std::string("User Preset") : current.info.name);
    a.accessoryView = f;
    a.window.initialFirstResponder = f;
    if ([a runModal] == NSAlertFirstButtonReturn) [self saveUserPresetNamed:f.stringValue];
}

- (void)promptExport {
    NSSavePanel* panel = [NSSavePanel savePanel];
    panel.nameFieldStringValue = [S(user::fileStem(current.info.name)) stringByAppendingPathExtension:@"muew"];
    panel.allowsOtherFileTypes = NO;
    if ([panel runModal] == NSModalResponseOK && panel.URL)
        if (!user::exportTo(std::string(panel.URL.fileSystemRepresentation), current)) NSBeep();
}

// ---- 0.9.0 wavetable editor ----
- (void)openTableEditor:(int)o {
    VoiceParams& v = current.voice;
    TableFrames& t = current.tables[o];
    if (t.empty()) t.push_back(shapeFrame(std::clamp(OscShape(v, o), 0, 4))); // start from the current shape
    OscShape(v, o) = kCustomShape;
    wtEdit = o;
    wtFrame = std::clamp((int)std::lround(OscWtPos(v, o) * ((int)t.size() - 1)), 0, (int)t.size() - 1);
    edited = true;
    [self applySound];
    [self setNeedsDisplay:YES];
}

// Selecting a frame moves WT POS onto it so the edit is what you hear.
- (void)selectTableFrame:(int)i {
    TableFrames& t = current.tables[wtEdit];
    wtFrame = std::clamp(i, 0, (int)t.size() - 1);
    OscWtPos(current.voice, wtEdit) = t.size() > 1 ? (double)wtFrame / ((int)t.size() - 1) : 0.0;
    edited = true;
    [self applySound];
    [self setNeedsDisplay:YES];
}

- (void)tableStrokeTo:(NSPoint)p first:(BOOL)first {
    NSRect cv = [self wtCanvas];
    Frame& f = current.tables[wtEdit][wtFrame];
    double x = std::clamp((p.x - cv.origin.x) / cv.size.width, 0.0, 1.0);
    if (wtMode == 0) {
        double y = std::clamp((p.y - NSMidY(cv)) / (cv.size.height * .42), -1.0, 1.0);
        int idx = std::min(kFrameSize - 1, (int)(x * kFrameSize));
        drawStroke(f, first ? idx : wtLastIdx, first ? y : wtLastVal, idx, y);
        wtLastIdx = idx; wtLastVal = y;
    } else {
        int hn = std::min(32, 1 + (int)(x * 32));
        double amp = std::clamp((p.y - cv.origin.y - 16) / (cv.size.height - 26), 0.0, 1.0);
        setFrameHarmonic(f, hn, amp);
    }
    edited = true;
    [self setNeedsDisplay:YES];
}

- (void)importTable {
    NSOpenPanel* op = [NSOpenPanel openPanel];
    op.allowedFileTypes = @[@"wav", @"wave", @"aif", @"aiff", @"aifc"];
    op.message = @"Choose a WAV or AIFF: a wavetable (2048-sample frames), a single cycle, any pitched sound to slice into up to 64 frames, or a longer unpitched texture to resynthesize as a moving table.";
    if ([op runModal] != NSModalResponseOK || !op.URL) return;
    if (![self importTableFile:op.URL.path]) NSBeep();
}
// 0.20.0: WAV/AIFF import into the open editor's oscillator (also driven by the host harness).
- (BOOL)importTableFile:(NSString*)path {
    if (wtEdit < 0 || wtEdit > 1) return NO;
    NSData* d = [NSData dataWithContentsOfFile:path];
    std::vector<unsigned char> bytes;
    if (d.length) bytes.assign((const unsigned char*)d.bytes, (const unsigned char*)d.bytes + d.length);
    TableFrames in = importAudio(bytes);
    if (in.empty()) return NO;
    [self wtRemember:"IMPORT"];
    current.tables[wtEdit] = in;
    OscShape(current.voice, wtEdit) = kCustomShape;
    [self selectTableFrame:0];
    return YES;
}

- (void)exportTable {
    NSSavePanel* sp = [NSSavePanel savePanel];
    sp.nameFieldStringValue = [NSString stringWithFormat:@"%@ OSC %@.wav", S(user::fileStem(current.info.name)), wtEdit ? @"B" : @"A"];
    sp.allowedFileTypes = @[@"wav"];
    if ([sp runModal] != NSModalResponseOK || !sp.URL) return;
    std::vector<unsigned char> bytes = exportWav(current.tables[wtEdit]);
    NSData* d = [NSData dataWithBytes:bytes.data() length:bytes.size()];
    if (![d writeToURL:sp.URL atomically:YES]) NSBeep();
}

// 0.32.0: snapshot the open table before an edit changes it.
- (void)wtRemember:(const char*)label {
    if (wtEdit < 0 || wtEdit > 1) return;
    wtHistory[wtEdit].push(current.tables[wtEdit], wtFrame, label);
}
- (void)wtStep:(BOOL)redo {
    if (wtEdit < 0 || wtEdit > 1) return;
    TableFrames& t = current.tables[wtEdit];
    int f = wtFrame;
    if (!(redo ? wtHistory[wtEdit].redo(t, f) : wtHistory[wtEdit].undo(t, f))) { NSBeep(); return; }
    [self selectTableFrame:f]; // moves WT POS onto the restored frame, applies the sound and redraws
}
- (void)muewTableUndo { [self wtStep:NO]; }
- (void)muewTableRedo { [self wtStep:YES]; }
- (NSString*)muewHistoryText {
    if (wtEdit < 0 || wtEdit > 1) return @"";
    const auto& h = wtHistory[wtEdit];
    return [NSString stringWithFormat:@"undo=%d redo=%d last=%s", h.undoDepth(), h.redoDepth(), h.undoLabel().c_str()];
}

- (void)tableButton:(int)i {
    TableFrames& t = current.tables[wtEdit];
    const int n = (int)t.size();
    switch (i) {
    case 0: // add a fresh frame at the end
        if (n >= kMaxFrames) { NSBeep(); return; }
        [self wtRemember:"ADD"];
        t.push_back(shapeFrame(2));
        [self selectTableFrame:n];
        return;
    case 1: // duplicate the selected frame after itself
        if (n >= kMaxFrames) { NSBeep(); return; }
        [self wtRemember:"DUP"];
        { Frame copy = t[wtFrame]; t.insert(t.begin() + wtFrame + 1, copy); }
        [self selectTableFrame:wtFrame + 1];
        return;
    case 2:
        if (n <= 1) { NSBeep(); return; }
        [self wtRemember:"DELETE"];
        t.erase(t.begin() + wtFrame);
        [self selectTableFrame:std::min(wtFrame, n - 2)];
        return;
    case 3: { // 0.20.0 spectral morph: rebuild as the next of 8/16/32/64 frames through every key frame
        if (n < 2) { NSBeep(); return; }
        [self wtRemember:"MORPH"];
        const int N = morphTarget(n);
        const double at = n > 1 ? (double)wtFrame / (n - 1) : 0.0;
        t = spectralMorph(t, N);
        [self selectTableFrame:(int)std::lround(at * (N - 1))];
        return;
    }
    case 4: [self wtRemember:"SMOOTH"]; smoothFrame(t[wtFrame], 2); break;
    case 5: [self wtRemember:"NORMAL"]; normalizeFrame(t[wtFrame]); break;
    case 6: [self importTable]; return;
    case 7: [self exportTable]; return;
    default: return;
    }
    edited = true;
    [self applySound];
    [self setNeedsDisplay:YES];
}

- (void)specDragTo:(NSPoint)p { // 0.31.0: bipolar bar, centre = 0; snaps to 0 near the centre
    const NSRect bar = [self wtSpecBar:wtSpecDrag];
    double v = std::clamp((p.x - NSMidX(bar)) / (bar.size.width / 2), -1.0, 1.0);
    if (std::fabs(v) < 0.04) v = 0;
    double val = v * SpecRange(wtSpecDrag);
    if (wtSpecDrag == 0) val = std::round(val); // whole semitones
    else if (wtSpecDrag == 2) val = std::round(val * 2) / 2;
    else val = std::round(val * 100) / 100;
    SpecField(wtSpec, wtSpecDrag) = val;
    [self setNeedsDisplay:YES];
}
- (NSString*)muewSpecText {
    const int n = (wtEdit >= 0 && wtEdit <= 1) ? (int)current.tables[wtEdit].size() : 0;
    const double c = n ? frameCentroid(current.tables[wtEdit][std::clamp(wtFrame, 0, n - 1)]) : 0;
    return [NSString stringWithFormat:@"mode=%d formant=%.1f stretch=%.2f tilt=%.1f oddeven=%.2f frames=%d centroid=%.3f", wtMode, wtSpec.formantSt, wtSpec.stretch, wtSpec.tiltDb, wtSpec.oddEven, n, c];
}
- (void)tableMouseDown:(NSPoint)p {
    TableFrames& t = current.tables[wtEdit];
    if (NSPointInRect(p, [self wtDoneRect])) { wtEdit = -1; [self setNeedsDisplay:YES]; return; }
    for (int i = 0; i < 4; ++i)
        if (NSPointInRect(p, [self wtModeTab:i])) { wtMode = i; [self setNeedsDisplay:YES]; return; }
    for (int i = 0; i < 2; ++i) // 0.32.0 UNDO / REDO
        if (NSPointInRect(p, NSInsetRect([self wtUndoRect:i], -1, -2))) { [self wtStep:i == 1]; return; }
    if (wtMode == 3 && NSPointInRect(p, NSInsetRect([self wtCanvas], -4, -4))) { // 0.31.0 SPECTRAL page
        for (int i = 0; i < 4; ++i)
            if (NSPointInRect(p, NSInsetRect([self wtSpecBar:i], -6, -7))) { wtSpecDrag = i; [self specDragTo:p]; return; }
        if (NSPointInRect(p, [self wtSpecButton:0]) && !wtSpec.isIdentity()) {
            [self wtRemember:"APPLY"];
            t = processTable(t, wtSpec); wtSpec = SpectralProcess{};
            edited = true; [self applySound]; [self setNeedsDisplay:YES]; return;
        }
        if (NSPointInRect(p, [self wtSpecButton:1])) { wtSpec = SpectralProcess{}; [self setNeedsDisplay:YES]; return; }
        return; // the SPECTRAL page never draws into the frame
    }
    for (int i = 0; i < std::min((int)t.size(), 16); ++i)
        if (NSPointInRect(p, [self wtThumb:i])) { [self selectTableFrame:ThumbFrame(i, (int)t.size())]; return; }
    if (wtMode == 2 && NSPointInRect(p, [self wtCanvas])) { // 3D: pick the frame whose wave row is under the pointer
        NSRect cv = [self wtCanvas];
        const int n = (int)t.size();
        int best = 0; double bd = 1e9;
        for (int j = 0; j < n; ++j) { NSRect row = StackRow(cv, j, n); double dd = std::fabs(NSMidY(row) - p.y) + (NSPointInRect(p, NSInsetRect(row, -4, -2)) ? 0 : 20); if (dd < bd) { bd = dd; best = j; } }
        [self selectTableFrame:best];
        return;
    }
    for (int i = 0; i < (int)WtButtonLabels().count; ++i)
        if (NSPointInRect(p, [self wtButton:i])) { [self tableButton:i]; return; }
    if (NSPointInRect(p, NSInsetRect([self wtCanvas], -4, -4))) { wtDrawing = true; [self wtRemember:wtMode == 1 ? "HARM" : "DRAW"]; [self tableStrokeTo:p first:YES]; }
}

// FILTER panel page tabs and the FILTER 2 + SUB page's click controls.
- (BOOL)filterPanelMouseDown:(NSPoint)p event:(NSEvent*)e {
    for (int i = 0; i < 3; ++i)
        if (NSPointInRect(p, [self filterTab:i])) {
            filterPage = i;
            [MUEWDefaults() setInteger:i forKey:@"MUEWFilterPage"];
            [self setNeedsDisplay:YES];
            return YES;
        }
    if (filterPage == 2) return [self arpMouseDown:p]; // 0.25.0
    if (filterPage == 0) { // 0.21.0: model arrows, DRIVE / KEYTRACK / MORPH bars, response display
        VoiceParams& v = current.voice;
        NSRect mr = [self f1ModelRect];
        if (NSPointInRect(p, mr)) {
            const int step = (p.x < NSMidX(mr) - 20) ? -1 : 1; // left arrow steps back, the rest steps forward
            v.filterMode = (v.filterMode + step + kFilterModes) % kFilterModes;
            edited = true; [self applySound]; [self setNeedsDisplay:YES];
            return YES;
        }
        for (int i = 0; i < 3; ++i)
            if (NSPointInRect(p, NSInsetRect([self f1Bar:i], -2, -3))) {
                double& val = i == 0 ? v.filterDrive : i == 1 ? v.filterKeytrack : v.filterMorph;
                if (e.clickCount == 2) { val = 0; edited = true; [self applySound]; }
                else {
                    NSRect r = [self f1Bar:i]; // click sets the value under the pointer, then drags
                    val = std::clamp((p.x - r.origin.x) / r.size.width, 0.0, 1.0);
                    filterXDrag = i; dragValue = val; edited = true; [self applySound];
                }
                [self setNeedsDisplay:YES];
                return YES;
            }
        if (NSPointInRect(p, [self f2Display]) && !NSPointInRect(p, NSInsetRect([self f1MsegChip], -3, -3))) {
            v.filterMode = (v.filterMode + 1) % kFilterModes; // the display cycles the model, like FILTER 2's
            edited = true; [self applySound]; [self setNeedsDisplay:YES];
            return YES;
        }
    }
    if (filterPage == 0 && NSPointInRect(p, NSInsetRect([self f1MsegChip], -3, -3))) { // MSEG chip: open MSEG 1's editor
        msegEdit = 0; fxDetail = -1;
        const auto& srcs = ui::matrixSources();
        for (int i = 0; i < (int)srcs.size(); ++i) if (srcs[i] == ModRoute::Source::MSEG1) modSel = i;
        [self setNeedsDisplay:YES];
        return YES;
    }
    if (filterPage != 1) return NO;
    VoiceParams& v = current.voice;
    for (int i = 0; i < 4; ++i) // 0.22.0 F1 MIX / F2 MIX / BALANCE / MORPH bars
        if (NSPointInRect(p, NSInsetRect([self f2Bar:i], -2, -3))) {
            double& val = *[self filterXField:3 + i];
            if (e.clickCount == 2) val = (i == 2) ? 0.5 : (i == 3 ? 0.0 : 1.0); // double-click: the default
            else {
                NSRect r = [self f2Bar:i];
                val = std::clamp((p.x - r.origin.x) / r.size.width, 0.0, 1.0);
                filterXDrag = 3 + i; dragValue = val;
            }
            edited = true; [self applySound]; [self setNeedsDisplay:YES];
            return YES;
        }
    bool hit = false;
    for (int i = 0; i < 2 && !hit; ++i)
        if (NSPointInRect(p, [self f2RouteRect:i])) { v.filterRouting = i; hit = true; }
    if (!hit && NSPointInRect(p, [self f2Display])) { v.filter2Type = (v.filter2Type + 1) % kFilter2Types; hit = true; }
    if (!hit && NSPointInRect(p, [self subPill:0])) { v.subOctave = v.subOctave >= 2 ? 1 : 2; hit = true; }
    if (!hit && NSPointInRect(p, [self subPill:1])) { v.subShape = (v.subShape + 1) % kSubShapes; hit = true; }
    if (!hit) return NO;
    edited = true;
    [self applySound];
    [self setNeedsDisplay:YES];
    return YES;
}

// Clicks on the oscillator header and displays: the name cycles the shape
// (SINE..PULSE, USER), the WT POS bar drags the frame position, and the rest
// of the display opens the wavetable editor. Returns YES if handled.
- (BOOL)oscMouseDown:(NSPoint)p event:(NSEvent*)e {
    for (int o = 0; o < 2; ++o) {
        VoiceParams& v = current.voice;
        if (NSPointInRect(p, [self oscTitle:o])) {
            int& sh = OscShape(v, o);
            sh = (std::clamp(sh, 0, kCustomShape) + 1) % (kCustomShape + 1);
            if (sh == kCustomShape && current.tables[o].empty()) current.tables[o].push_back(shapeFrame(2));
            edited = true; [self applySound]; [self setNeedsDisplay:YES];
            return YES;
        }
        if (OscShape(v, o) == kCustomShape && NSPointInRect(p, NSInsetRect([self wtPosBar:o], -2, -4))) {
            wtPosDrag = o;
            dragValue = OscWtPos(v, o);
            if (host) host->parameterGesture(o ? params::WtPosB : params::WtPosA, true);
            return YES;
        }
        for (int sl = 0; sl < 2; ++sl) { // 0.19.0 warp slots: arrows/name step the mode, slot 2's bar drags its amount
            if (!NSPointInRect(p, [self warpChip:o slot:sl])) continue;
            if (sl == 1 && NSPointInRect(p, NSInsetRect([self warpAmt:o slot:sl], -2, -3))) {
                if (e.clickCount == 2) { ui::warpAmount(v, o, 1) = 0; edited = true; [self applySound]; }
                else { warpAmtDrag = o; dragValue = ui::warpAmount(v, o, 1); }
                [self setNeedsDisplay:YES];
                return YES;
            }
            ui::stepWarpMode(v, o, sl, NSPointInRect(p, [self warpArrow:o slot:sl dir:-1]) ? -1 : 1);
            if (msegEdit >= 6 && !ui::usesRemap(v, msegEdit - 6)) msegEdit = -1; // its curve no longer plays
            edited = true; [self applySound]; [self setNeedsDisplay:YES];
            return YES;
        }
        if (ui::usesRemap(v, o) && NSPointInRect(p, NSInsetRect([self remapChip:o], -2, -2))) {
            msegEdit = msegEdit == 6 + o ? -1 : 6 + o;
            if (msegEdit >= 0) fxDetail = -1;
            msegPt = msegSeg = -1;
            [self setNeedsDisplay:YES];
            return YES;
        }
        if (NSPointInRect(p, [self oscDisplay:o])) { [self openTableEditor:o]; return YES; }
    }
    return NO;
}

// ---- 0.11.0 full preset browser (overlay over the panels) ----
// Sidebar: banks, categories, character tags. Table: sortable columns with
// star ratings. Info pane: description, tags, oscillator previews, actions.
static NSArray<NSString*>* BankRows() { return @[@"All banks", @"Factory", @"User", @"Imported"]; }
- (NSRect)browserRect { return NSMakeRect(24, 38, self.bounds.size.width - 48, [self top] - 38); }
- (NSRect)browserClose { NSRect b = [self browserRect]; return NSMakeRect(NSMaxX(b) - 34, NSMaxY(b) - 30, 22, 20); }
- (NSRect)expandRect { return NSMakeRect(self.bounds.size.width - 76, [self top] - 26, 46, 16); }
- (NSRect)presetDisplayRect { return NSMakeRect(414, self.bounds.size.height - 66, 252, 40); }
- (NSRect)bankRow:(int)i { return NSMakeRect(40, [self top] - 80 - i * 20, 170, 18); }
- (NSRect)catRow:(int)i { return NSMakeRect(40, [self top] - 186 - i * 20, 170, 18); } // 0 All, 1-7 categories, 8 favorites
- (NSRect)tagChip:(int)i { return NSMakeRect(40 + (i % 2) * 86, [self top] - 404 - (i / 2) * 22, 82, 18); }
- (CGFloat)tableTop { return [self top] - 62; }
- (int)tableRows { return (int)std::floor(([self tableTop] - 54) / 20); }
- (NSRect)tableHeader:(int)c { // 0 #, 1 NAME, 2 TYPE, 3 AUTHOR, 4 RATING
    static const CGFloat x[] = {228, 262, 452, 526, 624}, w[] = {30, 186, 70, 94, 76};
    return NSMakeRect(x[c], [self tableTop] + 2, w[c], 16);
}
- (NSRect)tableRow:(int)r { return NSMakeRect(226, [self tableTop] - (r + 1) * 20, 476, 19); }
- (NSRect)rowStar:(int)r star:(int)s { NSRect row = [self tableRow:r]; return NSMakeRect(624 + s * 13, row.origin.y + 2, 13, 15); }
- (NSRect)infoStar:(int)s { return NSMakeRect(728 + s * 20, [self top] - 104, 20, 20); }
- (NSRect)infoButton:(int)i { // 0 favorite, 1 + save, 2 import, 3 export
    return NSMakeRect(728 + (i % 2) * 118, 90 - (i / 2) * 28, 112, 22);
}
static int SortForColumn(int c) {
    switch (c) { case 1: return ui::SortName; case 2: return ui::SortCategory; case 4: return ui::SortRating; default: return ui::SortBank; }
}

- (void)saveRatings {
    NSMutableDictionary* d = [NSMutableDictionary dictionary];
    for (const auto& kv : ratings) d[S(kv.first)] = @(kv.second);
    [MUEWDefaults() setObject:d forKey:@"MUEWRatings"];
}

- (void)setBrowserOpen:(bool)open {
    browserOpen = open;
    wtEdit = -1;
    bscroll = 0;
    NSRect b = [self browserRect];
    search.frame = open ? NSMakeRect(NSMaxX(b) - 250, NSMaxY(b) - 32, 200, 24) : NSMakeRect(812, [self top] - 64, 150, 24);
    if (!open) { // the compact chips show what they can of the shared filter
        const auto& cats = factoryCategories();
        auto it = std::find(cats.begin(), cats.end(), filter.category);
        chip = filter.favoritesOnly ? 8 : filter.bank == ui::BankUserFolder ? kUserChip
             : it != cats.end() ? 1 + (int)(it - cats.begin()) : 0;
    }
    [self refilter];
    if (open) [self revealInTable];
}

- (void)revealInTable {
    int rows = [self tableRows];
    for (int r = 0; r < (int)visible.size(); ++r)
        if (visible[r] == currentIndex) {
            if (r < bscroll) bscroll = r;
            if (r >= bscroll + rows) bscroll = r - rows + 1;
        }
}

- (void)miniWave:(NSRect)r shape:(int)shape osc:(int)o warpMode:(int)wm warp:(double)w color:(NSColor*)col {
    FillRound(r, 6, C(0x0a0d12));
    std::vector<float> wv = shape == kCustomShape ? ui::waveformUser(current.tables[o], OscWtPos(current.voice, o), wm, w, 160)
                                                  : ui::waveform(table, shape, wm, w, 160);
    NSBezierPath* p = [NSBezierPath bezierPath];
    for (int i = 0; i < 160; ++i) {
        CGFloat x = r.origin.x + 6 + (r.size.width - 12) * i / 159.0;
        CGFloat y = NSMidY(r) + std::clamp((double)wv[i], -1.1, 1.1) * r.size.height * .34;
        i ? [p lineToPoint:NSMakePoint(x, y)] : [p moveToPoint:NSMakePoint(x, y)];
    }
    [[col colorWithAlphaComponent:.22] setStroke]; p.lineWidth = 4; [p stroke];
    [col setStroke]; p.lineWidth = 1.5; [p stroke];
}

- (void)stars:(int)n in:(NSRect)first step:(CGFloat)step size:(CGFloat)size {
    for (int s = 0; s < 5; ++s)
        TextA(s < n ? @"\u2605" : @"\u2606", NSMakeRect(first.origin.x + s * step, first.origin.y, step, first.size.height), size,
              s < n ? C(0xf2ab55) : C(0x3b4552), NSFontWeightRegular, NSTextAlignmentCenter);
}

- (void)drawBrowser {
    NSRect b = [self browserRect];
    [C(0x05070a, .72) setFill]; NSRectFillUsingOperation(NSMakeRect(0, 0, self.bounds.size.width, [self top] + 8), NSCompositingOperationSourceOver);
    FillRound(b, 12, C(0x121821));
    [C(0x2b3a45) setStroke];
    NSBezierPath* edge = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(b, .5, .5) xRadius:12 yRadius:12];
    edge.lineWidth = 1; [edge stroke];
    CGFloat t = NSMaxY(b);
    Text(@"PRESET BROWSER", NSMakeRect(40, t - 30, 200, 18), 12, C(0xe6ebf1), NSFontWeightBold);
    const ui::Library& lib = ui::library();
    TextA([NSString stringWithFormat:@"%d of %d sounds", (int)visible.size(), lib.count()], NSMakeRect(170, t - 28, 140, 14), 9,
          C(0x5f6b7b), NSFontWeightMedium, NSTextAlignmentLeft);
    TextA(@"\u2715", [self browserClose], 12, C(0x9ca6b4), NSFontWeightRegular, NSTextAlignmentCenter);
    [C(0x232c37) setFill]; NSRectFill(NSMakeRect(b.origin.x + 12, t - 42, b.size.width - 24, 1));

    // Sidebar
    auto sideRow = [&](NSRect r, NSString* label, int count, bool on) {
        if (on) FillRound(r, 5, C(0x21423e));
        Text(label, NSMakeRect(r.origin.x + 8, r.origin.y + 3, 120, 13), 10, on ? C(0x75ead8) : C(0xc3cbd6),
             on ? NSFontWeightSemibold : NSFontWeightRegular);
        TextA([NSString stringWithFormat:@"%d", count], NSMakeRect(NSMaxX(r) - 44, r.origin.y + 3, 38, 13), 9,
              on ? C(0x75ead8) : C(0x5f6b7b), NSFontWeightMedium, NSTextAlignmentRight);
    };
    Text(@"BANK", NSMakeRect(48, [self top] - 58, 100, 12), 8, C(0x5f6b7b), NSFontWeightBold);
    for (int i = 0; i < 4; ++i) {
        PresetFilter f = filter; f.bank = i - 1;
        sideRow([self bankRow:i], BankRows()[i], ui::countWith(f, favorites, lib), filter.bank == i - 1);
    }
    Text(@"TYPE", NSMakeRect(48, [self top] - 164, 100, 12), 8, C(0x5f6b7b), NSFontWeightBold);
    const auto& cats = factoryCategories();
    for (int i = 0; i < 9; ++i) {
        PresetFilter f = filter;
        f.favoritesOnly = i == 8 ? true : filter.favoritesOnly;
        if (i < 8) f.category = i == 0 ? std::string() : cats[i - 1];
        bool on = i == 8 ? filter.favoritesOnly : (i == 0 ? filter.category.empty() : filter.category == cats[i - 1]);
        NSString* label = i == 0 ? @"All types" : i == 8 ? @"\u2605 Favorites" : S(cats[i - 1]);
        sideRow([self catRow:i], label, ui::countWith(f, favorites, lib), on);
    }
    Text(@"CHARACTER", NSMakeRect(48, [self top] - 382, 100, 12), 8, C(0x5f6b7b), NSFontWeightBold);
    for (int i = 0; i < (int)characterTags().size(); ++i) {
        NSRect r = [self tagChip:i];
        bool on = filter.tags.count(characterTags()[i]) > 0;
        FillRound(r, 9, on ? C(0x9d7df2, .28) : C(0x1d232d));
        TextA(S(characterTags()[i]), NSMakeRect(r.origin.x, r.origin.y + 3, r.size.width, 13), 9,
              on ? C(0xc9b8ff) : C(0x9ca6b4), on ? NSFontWeightSemibold : NSFontWeightMedium, NSTextAlignmentCenter);
    }
    [C(0x232c37) setFill]; NSRectFill(NSMakeRect(218, 50, 1, t - 100));

    // Table
    NSArray* heads = @[@"#", @"NAME", @"TYPE", @"AUTHOR", @"RATING"];
    for (int c = 0; c < 5; ++c) {
        bool on = SortForColumn(c) == sortMode && (c != 0 || sortMode == ui::SortBank) && c != 3;
        NSString* h = on ? [heads[c] stringByAppendingString:c == 4 ? @" \u25BC" : @" \u25B2"] : heads[c];
        Text(h, [self tableHeader:c], 8, on ? C(0x75ead8) : C(0x6f7b8b), NSFontWeightBold);
    }
    [C(0x232c37) setFill]; NSRectFill(NSMakeRect(226, [self tableTop], 476, 1));
    int rows = [self tableRows];
    bscroll = std::clamp(bscroll, 0, std::max(0, (int)visible.size() - rows));
    for (int r = 0; r < rows && bscroll + r < (int)visible.size(); ++r) {
        int idx = visible[bscroll + r];
        const Preset& p = lib.at(idx);
        NSRect row = [self tableRow:r];
        bool sel = idx == currentIndex;
        if (sel) FillRound(row, 4, C(0x293c3b));
        else if (r % 2) FillRound(row, 4, C(0x161d27));
        CGFloat y = row.origin.y + 3;
        int bk = ui::bankOf(lib, idx);
        TextA(bk == ui::BankFactory ? [NSString stringWithFormat:@"%d", idx + 1] : bk == ui::BankUser ? @"U" : @"IMP",
              NSMakeRect(226, y, 28, 13), 8, C(0x5f6b7b), NSFontWeightMedium, NSTextAlignmentCenter);
        Text(S(p.info.name), NSMakeRect(262, y - 1, 186, 15), 11, sel ? C(0x75ead8) : C(0xdde3ea), sel ? NSFontWeightSemibold : NSFontWeightRegular);
        Text(S(p.info.category), NSMakeRect(452, y, 70, 13), 9, C(0x8793a3), NSFontWeightMedium);
        Text(S(p.info.author), NSMakeRect(526, y, 94, 13), 9, bk == ui::BankFactory ? C(0x5f6b7b) : C(0x3a8f84), NSFontWeightMedium);
        [self stars:ui::ratingOf(ratings, lib.slug(idx)) in:[self rowStar:r star:0] step:13 size:10];
        bool fav = favorites.count(lib.slug(idx)) > 0;
        if (fav) TextA(@"\u2665", NSMakeRect(NSMaxX(row) - 18, y - 1, 14, 14), 10, C(0xf2ab55), NSFontWeightRegular, NSTextAlignmentCenter);
    }
    if (visible.empty())
        TextA(@"No presets match these filters", NSMakeRect(226, [self tableTop] - 60, 476, 16), 11, C(0x5f6b7b), NSFontWeightMedium, NSTextAlignmentCenter);
    if ((int)visible.size() > rows) {
        CGFloat trackH = [self tableTop] - 54, thumbH = std::max(24.0, trackH * rows / visible.size());
        CGFloat thumbY = [self tableTop] - thumbH - (trackH - thumbH) * bscroll / std::max(1, (int)visible.size() - rows);
        FillRound(NSMakeRect(704, thumbY, 3, thumbH), 1.5, C(0x3b4552));
    }
    [C(0x232c37) setFill]; NSRectFill(NSMakeRect(714, 50, 1, t - 100));

    // Info pane: the loaded sound
    CGFloat ix = 728, iw = NSMaxX(b) - 12 - ix;
    bool has = currentIndex >= 0;
    Text(S(has ? current.info.name : "Init"), NSMakeRect(ix, [self top] - 68, iw, 20), 15, C(0xf5f7fa), NSFontWeightSemibold);
    std::string line = current.info.category + "  \u2022  " + (current.info.author.empty() ? "Unknown" : current.info.author);
    if (has) line += std::string("  \u2022  ") + ui::bankName(ui::bankOf(lib, currentIndex));
    Text(S(line), NSMakeRect(ix, [self top] - 84, iw, 13), 9, C(0x8793a3), NSFontWeightMedium);
    [self stars:has ? ui::ratingOf(ratings, lib.slug(currentIndex)) : 0 in:[self infoStar:0] step:20 size:15];
    NSString* desc = current.info.description.empty() ? @"No description." : S(current.info.description);
    NSMutableParagraphStyle* ps = [NSMutableParagraphStyle new];
    ps.lineBreakMode = NSLineBreakByWordWrapping; ps.lineSpacing = 2;
    [desc drawInRect:NSMakeRect(ix, [self top] - 178, iw, 66)
      withAttributes:@{NSFontAttributeName: [NSFont systemFontOfSize:10.5], NSForegroundColorAttributeName: C(0xb4bdc9), NSParagraphStyleAttributeName: ps}];
    CGFloat tx = ix, ty = [self top] - 202;
    for (const auto& tag : current.info.tags) { // tag pills, wrapping
        NSString* s = S(tag);
        CGFloat w = [s sizeWithAttributes:@{NSFontAttributeName: [NSFont systemFontOfSize:8.5 weight:NSFontWeightSemibold]}].width + 14;
        if (tx + w > ix + iw) { tx = ix; ty -= 20; }
        if (ty < [self top] - 244) break;
        bool ch = std::find(characterTags().begin(), characterTags().end(), tag) != characterTags().end();
        FillRound(NSMakeRect(tx, ty, w, 16), 8, ch ? C(0x9d7df2, .22) : C(0x1d232d));
        TextA(s, NSMakeRect(tx, ty + 2.5, w, 11), 8.5, ch ? C(0xc9b8ff) : C(0x9ca6b4), NSFontWeightSemibold, NSTextAlignmentCenter);
        tx += w + 5;
    }
    const VoiceParams& v = current.voice;
    Text(@"OSC A", NSMakeRect(ix, [self top] - 266, 60, 11), 8, C(0x5adac8), NSFontWeightBold);
    Text(@"OSC B", NSMakeRect(ix + iw / 2 + 3, [self top] - 266, 60, 11), 8, C(0x9d7df2), NSFontWeightBold);
    [self miniWave:NSMakeRect(ix, [self top] - 336, iw / 2 - 3, 66) shape:v.osc1Shape osc:0 warpMode:v.osc1WarpMode warp:v.osc1Warp color:C(0x5adac8)];
    [self miniWave:NSMakeRect(ix + iw / 2 + 3, [self top] - 336, iw / 2 - 3, 66) shape:v.osc2Shape osc:1 warpMode:v.osc2WarpMode warp:v.osc2Warp color:C(0x9d7df2)];
    std::string layers;
    if (v.subLevel > 0) layers += "SUB  ";
    if (v.noiseLevel > 0) layers += "NOISE  ";
    if (v.filter2Type > 0) layers += std::string("F2 ") + ui::filter2TypeName(v.filter2Type) + "  ";
    if (ui::unisonVoices(v, 0) > 1 || ui::unisonVoices(v, 1) > 1) layers += "UNISON  ";
    Text(S(layers.empty() ? "OSC A + OSC B" : layers), NSMakeRect(ix, [self top] - 356, iw, 12), 8, C(0x6f7b8b), NSFontWeightBold);
    bool fav = has && favorites.count(lib.slug(currentIndex));
    NSArray* labels = @[fav ? @"\u2665  Favorite" : @"\u2661  Favorite", @"+ Save", @"Import\u2026", @"Export\u2026"];
    for (int i = 0; i < 4; ++i) {
        NSRect r = [self infoButton:i];
        bool lit = i == 0 && fav;
        FillRound(r, 6, lit ? C(0xf2ab55, .2) : C(0x1d232d));
        TextA(labels[i], NSMakeRect(r.origin.x, r.origin.y + 4.5, r.size.width, 13), 9.5, lit ? C(0xf2ab55) : C(0x75ead8),
              NSFontWeightSemibold, NSTextAlignmentCenter);
    }
}

- (void)promptImport {
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    panel.allowsMultipleSelection = NO;
    panel.allowedFileTypes = @[@"muew"];
    if ([panel runModal] != NSModalResponseOK || !panel.URL) return;
    [self importPresetFile:panel.URL.path];
}

- (BOOL)importPresetFile:(NSString*)path {
    int idx = user::importFile(UserPresetDir(), std::string(path.fileSystemRepresentation), ui::library());
    if (idx < 0) { NSBeep(); return NO; }
    filter.bank = ui::BankImported;
    [self refilter];
    [self loadPresetIndex:idx];
    [self revealInTable];
    return YES;
}

- (void)toggleFavorite:(int)idx {
    if (idx < 0) return;
    std::string slug = ui::library().slug(idx);
    if (favorites.count(slug)) favorites.erase(slug); else favorites.insert(slug);
    [self saveFavorites]; [self refilter];
}

- (void)rate:(int)idx stars:(int)n {
    if (idx < 0) return;
    ui::setRating(ratings, ui::library().slug(idx), n);
    [self saveRatings]; [self refilter];
}

- (void)browserMouseDown:(NSPoint)p {
    if (NSPointInRect(p, [self browserClose]) || !NSPointInRect(p, [self browserRect])) { [self setBrowserOpen:false]; return; }
    for (int i = 0; i < 4; ++i)
        if (NSPointInRect(p, [self bankRow:i])) {
            filter.bank = i - 1;
            if (filter.bank >= ui::BankUser) user::load(UserPresetDir(), ui::library());
            bscroll = 0; [self refilter]; return;
        }
    for (int i = 0; i < 9; ++i)
        if (NSPointInRect(p, [self catRow:i])) {
            if (i == 8) filter.favoritesOnly = !filter.favoritesOnly;
            else filter.category = i == 0 ? std::string() : factoryCategories()[i - 1];
            bscroll = 0; [self refilter]; return;
        }
    for (int i = 0; i < (int)characterTags().size(); ++i)
        if (NSPointInRect(p, [self tagChip:i])) {
            const std::string& t = characterTags()[i];
            if (filter.tags.count(t)) filter.tags.erase(t); else filter.tags.insert(t);
            bscroll = 0; [self refilter]; return;
        }
    for (int c = 0; c < 5; ++c)
        if (c != 3 && NSPointInRect(p, NSInsetRect([self tableHeader:c], -2, -3))) { sortMode = SortForColumn(c); [self refilter]; [self revealInTable]; return; }
    for (int s = 0; s < 5; ++s)
        if (NSPointInRect(p, [self infoStar:s])) { [self rate:currentIndex stars:s + 1]; return; }
    for (int i = 0; i < 4; ++i)
        if (NSPointInRect(p, [self infoButton:i])) {
            if (i == 0) [self toggleFavorite:currentIndex];
            else if (i == 1) [self promptSave];
            else if (i == 2) [self promptImport];
            else [self promptExport];
            return;
        }
    int rows = [self tableRows];
    for (int r = 0; r < rows && bscroll + r < (int)visible.size(); ++r) {
        if (!NSPointInRect(p, [self tableRow:r])) continue;
        int idx = visible[bscroll + r];
        for (int s = 0; s < 5; ++s)
            if (NSPointInRect(p, [self rowStar:r star:s])) { [self rate:idx stars:s + 1]; return; }
        [self loadPresetIndex:idx];
        return;
    }
}

- (void)mouseDown:(NSEvent*)e {
    [self.window makeFirstResponder:self];
    NSPoint p = [self convertPoint:e.locationInWindow fromView:nil];
    dragStart = p;
    dragKnob = -1;
    if (browserOpen) { [self browserMouseDown:p]; return; }
    if (NSPointInRect(p, NSInsetRect([self engineHQPill], -4, -4))) { // 0.30.0 global QUALITY
        current.voice.oscQuality = current.voice.oscQuality ? 0 : 1;
        edited = true; [self applySound]; [self setNeedsDisplay:YES]; return;
    }
    if (NSPointInRect(p, [self expandRect]) || NSPointInRect(p, [self presetDisplayRect])) { [self setBrowserOpen:true]; return; }
    if (wtEdit >= 0 && NSPointInRect(p, [self wtPanel])) { [self tableMouseDown:p]; return; }
    if ([self voiceStripMouseDown:p event:e]) return; // 0.23.0
    if ([self oscMouseDown:p event:e]) return;
    if ([self filterPanelMouseDown:p event:e]) return;
    if ([self msegMouseDown:p event:e]) return;
    if ([self fxDetailMouseDown:p event:e]) return;
    dragKnob = [self hitKnob:p];
    if (dragKnob >= kFxDrag) { // FX ring: drive / mix / amount, published as AU parameters
        int id = [self paramForDrag:dragKnob];
        if (host) host->parameterGesture(id, true);
        dragValue = RingNorm(current, id);
        [self setNeedsDisplay:YES];
        return;
    }
    if (dragKnob >= 0) {
        if (host) host->parameterGesture(ui::knobParam((int)dragKnob), true);
        if (e.clickCount == 2 && currentIndex >= 0) { // double-click restores the preset value
            ui::knobField(current.voice, (int)dragKnob) = ui::knobField(const_cast<VoiceParams&>(ui::library().at(currentIndex).voice), (int)dragKnob);
            [self knobEdited:(int)dragKnob];
        }
        dragValue = ui::knobValue(current.voice, (int)dragKnob);
        [self setNeedsDisplay:YES];
        return;
    }
    if ([self matrixMouseDown:p event:e]) return;
    for (int s = 0; s < kFxUnits; ++s)
        if (NSPointInRect(p, [self fxLed:s])) { // toggle an FX stage
            bool& en = FxEnabled(current, current.fx.order.slot[s]);
            en = !en;
            edited = true;
            [self applySound];
            [self setNeedsDisplay:YES];
            return;
        }
    if (int s = [self fxSlotAt:p]; s >= 0) { // pick up a card to move it in the chain
        fxMove = s; fxDrop = s; dragPoint = p;
        [self setNeedsDisplay:YES];
        return;
    }
    for (int o = 0; o < 2; ++o)
        for (int i = 0; i < kMaxUnison; ++i)
            if (NSPointInRect(p, [self unisonPip:o voice:i])) { // pick the unison voice count
                ui::setUnisonVoices(current.voice, o, i + 1);
                edited = true;
                [self applySound];
                [self setNeedsDisplay:YES];
                return;
            }
    if (NSPointInRect(p, [self prevRect])) { [self stepPreset:-1]; return; }
    if (NSPointInRect(p, [self nextRect])) { [self stepPreset:1]; return; }
    NSArray* chips = ChipLabels();
    for (int i = 0; i < (int)chips.count; ++i) {
        if (NSPointInRect(p, [self chipRect:i])) {
            chip = i;
            filter.favoritesOnly = (i == 8);
            filter.bank = i == kUserChip ? (int)ui::BankUserFolder : -1;
            filter.tags.clear(); // the compact chips never hide a tag filter
            if (i == kUserChip) user::load(UserPresetDir(), ui::library()); // pick up presets saved elsewhere
            filter.category = (i >= 1 && i <= 7) ? factoryCategories()[i - 1] : std::string();
            scroll = 0;
            [self refilter];
            return;
        }
    }
    if (NSPointInRect(p, [self saveRect])) { [self promptSave]; return; }
    if (NSPointInRect(p, [self exportRect])) { [self promptExport]; return; }
    if (NSPointInRect(p, [self favToggleRect]) && currentIndex >= 0) {
        std::string slug = ui::library().slug(currentIndex);
        if (favorites.count(slug)) favorites.erase(slug); else favorites.insert(slug);
        [self saveFavorites]; [self refilter];
        return;
    }
    CGFloat lt = [self listTop];
    if (p.x > 806 && p.x < self.bounds.size.width - 30 && p.y < lt && p.y > 76) {
        int r = (int)((lt - p.y) / kRowH) + scroll;
        if (r >= 0 && r < (int)visible.size()) {
            int idx = visible[r];
            if (p.x >= 944) {
                std::string slug = ui::library().slug(idx);
                if (favorites.count(slug)) favorites.erase(slug); else favorites.insert(slug);
                [self saveFavorites]; [self refilter];
            } else {
                [self loadPresetIndex:idx];
            }
        }
    }
}

- (void)mouseDragged:(NSEvent*)e {
    NSPoint p = [self convertPoint:e.locationInWindow fromView:nil];
    double scale = (e.modifierFlags & NSEventModifierFlagShift) ? 600.0 : 150.0; // shift = fine
    if (wtDrawing && wtEdit >= 0) { [self tableStrokeTo:p first:NO]; return; }
    if (wtSpecDrag >= 0 && wtEdit >= 0) { [self specDragTo:p]; return; } // 0.31.0
    if (wtPosDrag >= 0) { // WT POS bar: the full bar width is 0..100%
        OscWtPos(current.voice, wtPosDrag) = std::clamp(dragValue + (p.x - dragStart.x) / ([self wtPosBar:wtPosDrag].size.width * scale / 150.0), 0.0, 1.0);
        edited = true;
        if (!host || !host->editParameter(wtPosDrag ? params::WtPosB : params::WtPosA, current)) [self applySound];
        [self setNeedsDisplay:YES];
        return;
    }
    if (msegEdit >= 0 && (msegPt >= 0 || msegSeg >= 0 || msegLoopEdge >= 0)) { [self msegDragTo:p shift:(e.modifierFlags & NSEventModifierFlagShift) != 0]; return; }
    if (patDrag >= 0) { // 0.26.0 pattern lane: drag paints velocity across cells
        const NSRect l = [self arpPatLane];
        const int i = std::clamp((int)((p.x - l.origin.x) / [self arpPatCell:0].size.width), 0, arp::kPatSteps - 1);
        if (i < current.voice.arpPatLen) { if (current.voice.arpPatKind[i] == arp::StepOn) [self setPatVelocity:i at:p]; patDrag = i; [self voiceParamEdited:-1]; }
        return;
    }
    if (arpDrag >= 0) { // 0.25.0 ARP GATE / SWING pills: the full width is the whole range
        NSRect r = arpDrag ? [self arpSwingRect] : [self arpGateRect];
        const double x = std::clamp(dragValue + (p.x - dragStart.x) / (r.size.width * scale / 150.0), 0.0, 1.0);
        if (arpDrag) current.voice.arpSwing = std::round(x * 50) / 100.0; else current.voice.arpGate = 0.05 + std::round(x * 95) / 100.0;
        [self voiceParamEdited:arpDrag ? params::ArpSwing : params::ArpGate];
        return;
    }
    if (voiceDrag >= 0) { // 0.23.0 GLIDE / BLEND bars: the full bar width is the whole range
        NSRect r = voiceDrag ? [self blendBar] : [self glideBar];
        const double x = std::clamp(dragValue + (p.x - dragStart.x) / (r.size.width * scale / 150.0), 0.0, 1.0);
        if (voiceDrag) current.voice.uniBlend = x; else current.voice.glideTime = GlideFromPos(x);
        [self voiceParamEdited:voiceDrag ? params::UnisonBlend : params::GlideTime];
        return;
    }
    if (filterXDrag >= 0) { // 0.21.0 FILTER 1 bars: the full bar width is 0..100%
        double& val = *[self filterXField:filterXDrag];
        val = std::clamp(dragValue + (p.x - dragStart.x) / ([self filterXBar:filterXDrag].size.width * scale / 150.0), 0.0, 1.0);
        edited = true; [self applySound]; [self setNeedsDisplay:YES];
        return;
    }
    if (warpAmtDrag >= 0) { // WARP 2 amount: the full bar width is 0..100%
        ui::warpAmount(current.voice, warpAmtDrag, 1) =
            std::clamp(dragValue + (p.x - dragStart.x) / ([self warpAmt:warpAmtDrag slot:1].size.width * scale / 150.0), 0.0, 1.0);
        edited = true; [self applySound]; [self setNeedsDisplay:YES];
        return;
    }
    if (msegEdit >= 2 && msegEdit < 6 && lfoXDrag >= 0) { // PHASE 0..360 degrees, DELAY/RISE off .. 8 s
        VoiceParams& v = current.voice;
        const int li = msegEdit - 2;
        double x = std::clamp(dragValue + (p.y - dragStart.y) / scale, 0.0, 1.0);
        if (lfoXDrag == 0) v.lfoPhase[li] = std::round(x * 72) / 72; // 5 degree steps
        else (lfoXDrag == 1 ? v.lfoDelay[li] : v.lfoRise[li]) = ui::fadeFrom01(x);
        edited = true; [self applySound]; [self setNeedsDisplay:YES];
        return;
    }
    if (fxRowDrag >= 0 && fxDetail >= 0) {
        NSRect bar = [self fxDetailBar:fxRowDrag];
        [self setFxRow:fxRowDrag value:ui::fxFromNorm(ui::fxControls(fxDetail)[fxRowDrag], (p.x - bar.origin.x) / bar.size.width)];
        return;
    }
    if (fxMove >= 0) {
        dragPoint = p;
        int s = [self fxSlotAt:p];
        if (s >= 0) fxDrop = s;
        [self setNeedsDisplay:YES];
        return;
    }
    if (dragSource >= 0) {
        dragPoint = p;
        NSInteger k = [self hitKnob:p];
        dropKnob = (k >= 0 && k < kFxDrag && ui::knobDest((int)k) >= 0) ? (int)k : -1;
        dropAux = -1;
        if (dropKnob < 0)
            for (int i = 0; i < 4; ++i) {
                int slot = matrixPage * 4 + i;
                if (slot < (int)current.routes.size() && NSPointInRect(p, NSInsetRect([self routeAux:i], -3, -4))) dropAux = slot;
            }
        int fs = dropKnob < 0 && dropAux < 0 ? [self fxSlotAt:p] : -1;
        dropFx = (fs >= 0 && ui::fxUnitDest(current.fx.order.slot[fs]) >= 0) ? fs : -1;
        [self setNeedsDisplay:YES];
        return;
    }
    if (routeDrag >= 0 && routeDrag < (int)current.routes.size()) { // 75 pt of drag per full scale (the bar itself is 118 pt since 0.16.0)
        double d = ((p.x - dragStart.x) + (p.y - dragStart.y)) / (scale / 2);
        ui::setRouteDisplayAmount(current.routes[routeDrag], dragValue + d);
        edited = true; [self applySound]; [self setNeedsDisplay:YES];
        return;
    }
    if (curveDrag >= 0 && curveDrag < (int)current.routes.size()) { // 60 pt from linear to full bend
        current.routes[curveDrag].curve = ui::clampCurve(dragValue + (p.y - dragStart.y) / 60.0);
        edited = true; [self applySound]; [self setNeedsDisplay:YES];
        return;
    }
    if (modFieldDrag >= 0) {
        [self dragModField:dragValue + (p.y - dragStart.y) / scale];
        return;
    }
    if (dragKnob < 0) return;
    if (dragKnob >= kFxDrag) {
        int id = [self paramForDrag:dragKnob];
        params::set(current, id, RingValue(id, dragValue + (p.y - dragStart.y) / scale));
        edited = true;
        if (!host || !host->editParameter(id, current)) [self applySound];
        [self setNeedsDisplay:YES];
        return;
    }
    ui::setKnob(current.voice, (int)dragKnob, dragValue + (p.y - dragStart.y) / scale);
    edited = true;
    [self knobEdited:(int)dragKnob];
    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent*)e {
    if (wtDrawing) { wtDrawing = false; [self applySound]; } // one engine update per stroke
    if (wtSpecDrag >= 0) { wtSpecDrag = -1; [self setNeedsDisplay:YES]; } // 0.31.0
    if (wtPosDrag >= 0 && host) host->parameterGesture(wtPosDrag ? params::WtPosB : params::WtPosA, false);
    wtPosDrag = -1;
    if (dragSource >= 0 && dropKnob >= 0) { // drop a source on a knob: new route (or reuse)
        int slot = ui::addRoute(current.routes, ui::matrixSources()[dragSource], (ModRoute::Dest)ui::knobDest(dropKnob));
        if (slot >= 0) { matrixPage = slot / 4; edited = true; [self applySound]; }
        else NSBeep(); // matrix full
    } else if (dragSource >= 0 && dropAux >= 0 && dropAux < (int)current.routes.size()) { // badge on an AUX chip
        current.routes[dropAux].aux = (int)ui::matrixSources()[dragSource];
        edited = true; [self applySound];
    } else if (dragSource >= 0 && dropFx >= 0) { // drop a source on an FX card: route to that unit's main amount
        int u = current.fx.order.slot[dropFx];
        int slot = ui::addRoute(current.routes, ui::matrixSources()[dragSource], (ModRoute::Dest)ui::fxUnitDest(u));
        if (slot >= 0) { matrixPage = slot / 4; edited = true; [self applySound]; } // the matrix stays in view; click the card for its ranges
        else NSBeep();
    }
    if (fxMove >= 0) { // drop: move the unit to the landing slot
        NSPoint p = [self convertPoint:e.locationInWindow fromView:nil];
        int s = [self fxSlotAt:p];
        if (s >= 0) fxDrop = s;
        bool click = hypot(p.x - dragStart.x, p.y - dragStart.y) < 4;
        if (click) { // a click (no drag) opens the unit's detail panel, or closes it
            int u = current.fx.order.slot[fxMove];
            fxDetail = fxDetail == u ? -1 : u;
            if (fxDetail >= 0) msegEdit = -1;
        } else if (fxDrop >= 0 && current.fx.order.move(fxMove, fxDrop)) { edited = true; [self applySound]; }
    }
    fxMove = -1; fxDrop = -1;
    if (fxRowDrag >= 0) {
        int id = fxDetail >= 0 ? FxRowParam(fxDetail, fxRowDrag) : -1;
        if (id >= 0 && host) host->parameterGesture(id, false);
        fxRowDrag = -1;
    }
    if (voiceDrag >= 0 && host) host->parameterGesture(voiceDrag ? params::UnisonBlend : params::GlideTime, false);
    voiceDrag = -1;
    if (arpDrag >= 0 && host) host->parameterGesture(arpDrag ? params::ArpSwing : params::ArpGate, false);
    arpDrag = -1; patDrag = -1;
    dragSource = -1; dropKnob = -1; dropFx = -1; dropAux = -1; curveDrag = -1; routeDrag = -1; modFieldDrag = -1;
    msegPt = -1; msegSeg = -1; msegLoopEdge = -1; lfoXDrag = -1; warpAmtDrag = -1; filterXDrag = -1;
    if (dragKnob >= 0 && host) host->parameterGesture([self paramForDrag:dragKnob], false);
    dragKnob = -1;
    [self setNeedsDisplay:YES];
}

- (void)scrollWheel:(NSEvent*)e {
    NSPoint p = [self convertPoint:e.locationInWindow fromView:nil];
    if (browserOpen) {
        static double bacc = 0;
        bacc -= e.scrollingDeltaY / (e.hasPreciseScrollingDeltas ? 20.0 : 1.0);
        int st = (int)bacc;
        if (st != 0) { bacc -= st; bscroll += st; [self setNeedsDisplay:YES]; }
        return;
    }
    if (p.x < 798) return;
    static double acc = 0;
    acc -= e.scrollingDeltaY / (e.hasPreciseScrollingDeltas ? kRowH : 1.0);
    int steps = (int)acc;
    if (steps != 0) { acc -= steps; scroll += steps; [self refilter]; }
}

static int NoteForKey(unichar ch) {
    static const char* keys = "awsedftgyhujk";
    const char* p = strchr(keys, (char)ch);
    return (ch && ch < 128 && p) ? (int)(p - keys) : -1;
}

// 0.32.0: cmd-Z / shift-cmd-Z step the WT editor's history while it is open and this view has focus;
// otherwise the key goes on to the host (its own undo).
- (BOOL)performKeyEquivalent:(NSEvent*)e {
    if (wtEdit >= 0 && self.window.firstResponder == self && (e.modifierFlags & NSEventModifierFlagCommand)) {
        NSString* k = e.charactersIgnoringModifiers.lowercaseString;
        if ([k isEqualToString:@"z"]) { [self wtStep:(e.modifierFlags & NSEventModifierFlagShift) != 0]; return YES; }
    }
    return [super performKeyEquivalent:e];
}

- (void)keyDown:(NSEvent*)e {
    if (!host || !host->playsNotes()) { [super keyDown:e]; return; } // let the DAW keep its keys
    if (e.isARepeat) return;
    NSString* s = e.charactersIgnoringModifiers;
    if (s.length == 0) return;
    unichar ch = [s characterAtIndex:0];
    if (ch == NSLeftArrowFunctionKey || ch == NSUpArrowFunctionKey) { [self stepPreset:-1]; return; }
    if (ch == NSRightArrowFunctionKey || ch == NSDownArrowFunctionKey) { [self stepPreset:1]; return; }
    if (ch == 'z') { octave = std::max(-3, octave - 1); return; }
    if (ch == 'x') { octave = std::min(3, octave + 1); return; }
    int n = NoteForKey(ch);
    if (n >= 0) host->noteOn(48 + 12 * octave + n, .85f);
}

- (void)keyUp:(NSEvent*)e {
    if (!host || !host->playsNotes()) { [super keyUp:e]; return; }
    NSString* s = e.charactersIgnoringModifiers;
    if (s.length == 0) return;
    int n = NoteForKey([s characterAtIndex:0]);
    if (n >= 0)
        for (int o = -3; o <= 3; ++o) host->noteOff(48 + 12 * o + n); // release even if octave changed mid-note
}
@end

