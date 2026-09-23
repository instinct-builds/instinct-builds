// MUEWEditorView.mm - shared MUEW editor implementation (see MUEWEditorView.h).
#import "MUEWEditorView.h"
#include "user_presets.h"
#include "au_params.h"
#include <cmath>

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

@implementation MUEWEditorView

- (instancetype)initWithFrame:(NSRect)f {
    if ((self = [super initWithFrame:f])) {
        self.wantsLayer = YES;
        currentIndex = -1; edited = false; chip = 0; scroll = 0; dragKnob = -1; octave = 0;
        NSArray* favs = [MUEWDefaults() arrayForKey:@"MUEWFavorites"];
        for (NSString* s in favs) favorites.insert(std::string(s.UTF8String));
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
    visible = ui::visiblePresets(filter, favorites, ui::library(), chip == kUserChip);
    int rows = [self listRows];
    int maxScroll = std::max(0, (int)visible.size() - rows);
    scroll = std::clamp(scroll, 0, maxScroll);
    [self setNeedsDisplay:YES];
}

- (void)controlTextDidChange:(NSNotification*)n {
    filter.query = std::string(search.stringValue.UTF8String ?: "");
    scroll = 0;
    [self refilter];
}

- (void)applySound {
    if (host) host->applyPreset(current, ui::library().factoryNumber(currentIndex), edited);
}

- (void)knobEdited:(int)k {
    if (!host || !host->editParameter(ui::knobParam(k), current)) [self applySound];
}

- (void)adoptPreset:(const Preset&)p index:(int)index edited:(bool)wasEdited {
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
    return p[k];
}
- (BOOL)oscRowKnob:(int)k {
    return k == ui::WarpA || k == ui::Mix || k == ui::WarpB || k == ui::Detune || ui::isUnison(k);
}
- (CGFloat)knobRadius:(int)k {
    if (ui::isMacro(k)) return 13;
    if ([self oscRowKnob:k]) return 19;
    return (k == ui::Cutoff || k == ui::Resonance) ? 30 : 25;
}
// Unison strip under each oscillator display: 8 voice pips + readout.
- (NSRect)unisonStrip:(int)osc { return NSMakeRect(osc ? 252 : 46, [self top] - 151, 190, 18); }
- (NSRect)unisonPip:(int)osc voice:(int)i {
    NSRect r = [self unisonStrip:osc];
    return NSMakeRect(r.origin.x + 6 + i * 13, r.origin.y, 13, r.size.height);
}
// FX rack: 3 x 2 cards in signal order DIST, CHORUS, DELAY / COMP, REVERB, EQ.
- (CGFloat)fxCardH { return ([self top] - 286 - 44 - 58 - 6) / 2; }
- (NSRect)fxCard:(int)i {
    CGFloat h = [self fxCardH];
    return NSMakeRect(468 + (i % 3) * 104, i < 3 ? 58 + h + 6 : 58, 96, h);
}
- (NSPoint)fxRingCenter:(int)i { NSRect r = [self fxCard:i]; return NSMakePoint(r.origin.x + 26, r.origin.y + 27); }
- (NSRect)fxLed:(int)i { NSRect r = [self fxCard:i]; return NSMakeRect(NSMaxX(r) - 26, NSMaxY(r) - 24, 22, 18); }
// AU parameter behind each FX ring (-1: the EQ has no ring).
static int FxParam(int i) {
    static const int id[6] = {params::DistDrive, params::ChorusMix, params::DelayMix, params::CompAmount, params::ReverbMix, -1};
    return (i >= 0 && i < 6) ? id[i] : -1;
}
static bool& FxEnabled(Preset& p, int i) {
    switch (i) {
    case 0: return p.fx.dist.enabled;
    case 1: return p.fx.chorus.enabled;
    case 2: return p.fx.delay.enabled;
    case 3: return p.fx.comp.enabled;
    case 4: return p.fx.reverb.enabled;
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
    NSString* label = dragKnob == k ? S(ui::knobReadout(current.voice, k)) : S(ui::knobLabel(k));
    bool macro = ui::isMacro(k);
    CGFloat lw2 = std::max<CGFloat>(60, rad * 2 + 32);
    TextA(label, NSMakeRect(c.x - lw2 / 2, c.y - rad - (macro ? 18 : 25), lw2, 13), macro ? 8 : 10,
          dragKnob == k ? accent : C(0xa8b2c1), macro ? NSFontWeightSemibold : NSFontWeightMedium, NSTextAlignmentCenter);
}

- (void)waveIn:(NSRect)r shape:(int)shape warpMode:(int)wm warp:(double)w color:(NSColor*)col {
    FillRound(r, 7, C(0x0a0d12));
    [C(0x1c232d) setStroke];
    NSBezierPath* mid = [NSBezierPath bezierPath];
    [mid moveToPoint:NSMakePoint(r.origin.x + 6, NSMidY(r))]; [mid lineToPoint:NSMakePoint(NSMaxX(r) - 6, NSMidY(r))];
    mid.lineWidth = 1; [mid stroke];
    std::vector<float> wv = ui::waveform(table, shape, wm, w, 240);
    NSBezierPath* p = [NSBezierPath bezierPath];
    for (int i = 0; i < 240; ++i) {
        CGFloat x = r.origin.x + 8 + (r.size.width - 16) * i / 239.0;
        CGFloat y = NSMidY(r) + std::clamp((double)wv[i], -1.1, 1.1) * r.size.height * .36;
        i ? [p lineToPoint:NSMakePoint(x, y)] : [p moveToPoint:NSMakePoint(x, y)];
    }
    [[col colorWithAlphaComponent:.25] setStroke]; p.lineWidth = 5; [p stroke];
    [col setStroke]; p.lineWidth = 1.8; [p stroke];
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
- (void)sourcePreview:(ModRoute::Source)src in:(NSRect)r color:(NSColor*)col {
    FillRound(NSInsetRect(r, -4, -4), 5, C(0x0f141b));
    const VoiceParams& v = current.voice;
    std::vector<MSEG::Point> pts;
    if (src == ModRoute::Source::MSEG1) {
        pts = v.mseg1Points;
    } else if (src == ModRoute::Source::ModEnv) {
        double a = std::max(v.modA, 0.001), d = std::max(v.modD, 0.001), rel = std::max(v.modR, 0.001);
        double total = a + d + rel + (a + d + rel) * 0.4;
        double t1 = a / total, t2 = (a + d) / total, t3 = 1.0 - rel / total;
        double sus = std::clamp(v.modS, 0.0, 1.0) * 2 - 1;
        pts = {{0, -1}, {t1, 1}, {t2, sus}, {t3, sus}, {1, -1}};
    } else if (src == ModRoute::Source::Velocity) {
        pts = {{0, -1}, {1, 1}};
    } else if ((int)src >= (int)ModRoute::Source::Macro1 && (int)src <= (int)ModRoute::Source::Macro4) {
        double m = v.macros[(int)src - (int)ModRoute::Source::Macro1] * 2 - 1; // current macro position
        pts = {{0, m}, {1, m}};
    } else {
        int shape = src == ModRoute::Source::LFO1 ? v.lfo1Shape : v.lfo2Shape;
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
    [self panel:NSMakeRect(478, top - 260, 306, 260) title:@"FILTER + AMP"];
    [self panel:NSMakeRect(798, 38, b.size.width - 822, top - 38) title:@"PRESET BROWSER"];

    // Oscillators
    const VoiceParams& v = current.voice;
    NSRect wa = NSMakeRect(46, top - 125, 190, 76), wb = NSMakeRect(252, top - 125, 190, 76);
    [self waveIn:wa shape:v.osc1Shape warpMode:v.osc1WarpMode warp:v.osc1Warp color:C(0x5adac8)];
    [self waveIn:wb shape:v.osc2Shape warpMode:v.osc2WarpMode warp:v.osc2Warp color:C(0x9d7df2)];
    Text([NSString stringWithFormat:@"OSC A  \u2022  %s  \u2022  %s", ui::shapeName(v.osc1Shape), ui::warpName(v.osc1WarpMode)],
         NSMakeRect(50, top - 47, 190, 16), 10, C(0x5adac8), NSFontWeightSemibold);
    Text([NSString stringWithFormat:@"OSC B  \u2022  %s  \u2022  %s", ui::shapeName(v.osc2Shape), ui::warpName(v.osc2WarpMode)],
         NSMakeRect(256, top - 47, 190, 16), 10, C(0x9d7df2), NSFontWeightSemibold);
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
    [self knob:ui::WarpA accent:C(0x5adac8)];
    [self knob:ui::UniDetuneA accent:C(0x5adac8)];
    [self knob:ui::Mix accent:C(0x5adac8)];
    [self knob:ui::Width accent:C(0xc3cbd6)];
    [self knob:ui::WarpB accent:C(0x9d7df2)];
    [self knob:ui::UniDetuneB accent:C(0x9d7df2)];
    [self knob:ui::Detune accent:C(0x9d7df2)];

    // Filter + amp
    TextA(S(ui::filterModeName(v.filterMode)), NSMakeRect(640, top - 27, 128, 14), 9, C(0xf2ab55), NSFontWeightSemibold, NSTextAlignmentRight);
    [self knob:ui::Cutoff accent:C(0xf2ab55)];
    [self knob:ui::Resonance accent:C(0xf2ab55)];
    [self msegIn:NSMakeRect(686, top - 138, 86, 94)];
    [self knob:ui::Attack accent:C(0x6cb6ff)];
    [self knob:ui::Release accent:C(0x6cb6ff)];
    [self knob:ui::MsegTime accent:C(0x5adac8)];

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

    // Modulation + effects
    CGFloat low = top - 286;
    [self panel:NSMakeRect(24, 38, 760, low - 48) title:@"MODULATION + EFFECTS"];
    CGFloat cardTop = low - 44, cardH = cardTop - 58;
    for (int i = 0; i < 4; ++i) {
        CGFloat x = 44 + i * 104;
        bool has = i < (int)current.routes.size();
        bool mseg = has && current.routes[i].source == ModRoute::Source::MSEG1;
        FillRound(NSMakeRect(x, 58, 96, cardH), 8, mseg ? C(0x21423e) : C(0x202630));
        Text([NSString stringWithFormat:@"SLOT %d", i + 1], NSMakeRect(x + 10, cardTop - 20, 80, 12), 8, C(0x5f6b7b), NSFontWeightSemibold);
        if (!has) { Text(@"EMPTY", NSMakeRect(x + 10, cardTop - 40, 80, 16), 11, C(0x3b4552), NSFontWeightSemibold); continue; }
        const ModRoute& rt = current.routes[i];
        Text(S(ui::sourceName(rt.source)), NSMakeRect(x + 10, cardTop - 40, 80, 16), 11, mseg ? C(0x66e2d0) : C(0xb9c2ce), NSFontWeightSemibold);
        Text(@"\u2193", NSMakeRect(x + 10, cardTop - 58, 80, 16), 11, C(0x5f6b7b));
        Text(S(ui::destName(rt.dest)), NSMakeRect(x + 10, cardTop - 76, 80, 16), 11, C(0xeaf1f8), NSFontWeightMedium);
        double amt = ui::routeDisplayAmount(rt);
        NSRect bar = NSMakeRect(x + 10, cardTop - 96, 76, 6);
        FillRound(bar, 3, C(0x111820));
        CGFloat mid = NSMidX(bar), w = amt * bar.size.width / 2;
        FillRound(NSMakeRect(w >= 0 ? mid : mid + w, bar.origin.y, std::fabs(w), 6), 3, mseg ? C(0x66e2d0) : C(0x6cb6ff));
        TextA([NSString stringWithFormat:@"%+.2f", rt.amount], NSMakeRect(x + 10, cardTop - 114, 76, 12), 9, C(0x8793a3), NSFontWeightMedium, NSTextAlignmentCenter);
        [self sourcePreview:rt.source in:NSMakeRect(x + 12, 72, 72, 44) color:mseg ? C(0x66e2d0) : C(0x6cb6ff)];
    }
    // FX rack, signal order left to right, top to bottom.
    const FXParams& f = current.fx;
    char det[6][40];
    snprintf(det[0], 40, "%s", ui::distModeName(f.dist.mode));
    snprintf(det[1], 40, "RATE %.2f Hz", f.chorus.rateHz);
    snprintf(det[2], 40, "%.0f / %.0f ms", f.delay.timeLSec * 1000, f.delay.timeRSec * 1000);
    snprintf(det[3], 40, "RATIO %.1f:1", 1.5 + 6.5 * std::clamp(f.comp.amount, 0.0, 1.0));
    snprintf(det[4], 40, "DECAY %.2f", f.reverb.decay);
    snprintf(det[5], 40, "%+.0f  %+.0f  %+.0f dB", f.eq.lowDb, f.eq.midDb, f.eq.highDb);
    static const char* names[6] = {"DISTORTION", "CHORUS", "DELAY", "COMPRESS", "REVERB", "EQ"};
    static const char* ringLabel[6] = {"DRIVE", "MIX", "MIX", "AMOUNT", "MIX", ""};
    for (int i = 0; i < 6; ++i) {
        NSRect r = [self fxCard:i];
        bool on = FxEnabled(const_cast<Preset&>(current), i);
        NSColor* acc = i == 0 ? C(0xf27a55) : i == 3 ? C(0x6cb6ff) : i == 5 ? C(0x5adac8) : C(0xf2ab55);
        FillRound(r, 8, on ? C(0x1d2530) : C(0x181d25));
        Text(S(names[i]), NSMakeRect(r.origin.x + 10, NSMaxY(r) - 20, 70, 13), 9, on ? acc : C(0x5f6b7b), NSFontWeightSemibold);
        NSRect led = [self fxLed:i];
        FillRound(NSMakeRect(NSMidX(led) - 4, NSMidY(led) - 4, 8, 8), 4, on ? acc : C(0x303947));
        Text(S(det[i]), NSMakeRect(r.origin.x + 10, NSMaxY(r) - 34, 80, 11), 8, on ? C(0x8793a3) : C(0x4a5462), NSFontWeightMedium);
        if (i == 5) { // EQ: response curve instead of a ring
            NSRect plot = NSMakeRect(r.origin.x + 8, r.origin.y + 8, r.size.width - 16, 38);
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
            [(on ? acc : C(0x3b4552)) setStroke]; curve.lineWidth = 1.6; [curve stroke];
            continue;
        }
        double val = params::get(current, FxParam(i)) / 100.0;
        bool dragging = dragKnob == kFxDrag + i;
        NSPoint c = [self fxRingCenter:i];
        NSBezierPath* ring = [NSBezierPath bezierPath];
        [ring appendBezierPathWithArcWithCenter:c radius:15 startAngle:225 endAngle:-45 clockwise:YES];
        [C(0x303947) setStroke]; ring.lineWidth = 3; [ring stroke];
        NSBezierPath* arc = [NSBezierPath bezierPath];
        [arc appendBezierPathWithArcWithCenter:c radius:15 startAngle:225 endAngle:225 - 270 * val clockwise:YES];
        [(on ? acc : C(0x4a5462)) setStroke]; arc.lineWidth = 3; [arc stroke];
        Text(S(ringLabel[i]), NSMakeRect(r.origin.x + 48, r.origin.y + 29, 44, 11), 8, C(0x6f7b8b), NSFontWeightSemibold);
        Text([NSString stringWithFormat:@"%.0f%%", val * 100], NSMakeRect(r.origin.x + 48, r.origin.y + 12, 44, 16), 12,
             dragging ? acc : (on ? C(0xd5dce5) : C(0x5f6b7b)), NSFontWeightMedium);
    }
}

// ---- interaction ----
- (NSInteger)hitKnob:(NSPoint)p {
    for (int k = 0; k < ui::KnobCount; ++k) {
        NSPoint c = [self knobCenter:k];
        CGFloat reach = [self oscRowKnob:k] ? 6 : 8; // osc-row knobs sit 60 pt apart
        if (hypot(p.x - c.x, p.y - c.y) < [self knobRadius:k] + reach) return k;
    }
    for (int i = 0; i < 6; ++i) {
        if (FxParam(i) < 0) continue;
        NSPoint c = [self fxRingCenter:i];
        if (hypot(p.x - c.x, p.y - c.y) < 22) return kFxDrag + i;
    }
    return -1;
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

- (void)mouseDown:(NSEvent*)e {
    [self.window makeFirstResponder:self];
    NSPoint p = [self convertPoint:e.locationInWindow fromView:nil];
    dragKnob = [self hitKnob:p];
    dragStart = p;
    if (dragKnob >= kFxDrag) { // FX ring: drive / mix / amount, published as AU parameters
        int id = [self paramForDrag:dragKnob];
        if (host) host->parameterGesture(id, true);
        dragValue = params::get(current, id) / 100.0;
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
    for (int i = 0; i < 6; ++i)
        if (NSPointInRect(p, [self fxLed:i])) { // toggle an FX stage
            bool& en = FxEnabled(current, i);
            en = !en;
            edited = true;
            [self applySound];
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
    if (dragKnob < 0) return;
    NSPoint p = [self convertPoint:e.locationInWindow fromView:nil];
    double scale = (e.modifierFlags & NSEventModifierFlagShift) ? 600.0 : 150.0; // shift = fine
    if (dragKnob >= kFxDrag) {
        int id = [self paramForDrag:dragKnob];
        params::set(current, id, std::clamp(dragValue + (p.y - dragStart.y) / scale, 0.0, 1.0) * 100.0);
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
    if (dragKnob >= 0 && host) host->parameterGesture([self paramForDrag:dragKnob], false);
    dragKnob = -1;
    [self setNeedsDisplay:YES];
}

- (void)scrollWheel:(NSEvent*)e {
    NSPoint p = [self convertPoint:e.locationInWindow fromView:nil];
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

