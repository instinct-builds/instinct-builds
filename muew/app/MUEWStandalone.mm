// MUEWStandalone.mm - MUEW standalone instrument. Every control edits the
// real engine state, and the preset browser loads the same authored factory
// bank the AU exposes (src/factory_bank.h), filtered by category, search
// and favorites.
#import <AppKit/AppKit.h>
#import <AVFoundation/AVFoundation.h>
#include "synth.h"
#include "ui_model.h"
#include <cmath>
#include <mutex>
#include <set>
#include <string>
#include <vector>

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
    return @[@"All", @"Bass", @"Lead", @"Pad", @"Keys", @"Pluck", @"Texture", @"FX", @"\u2605 Favs"];
}

@interface MUEWView : NSView <NSSearchFieldDelegate> {
@public
    Synth* synth;
    std::mutex* lock;
    Preset current;
    int currentIndex;
    bool edited;
    PresetFilter filter;
    int chip;
    std::set<std::string> favorites;
    std::vector<int> visible;
    int scroll;
    Wavetable table;
    NSInteger dragKnob;
    NSPoint dragStart;
    double dragValue;
    int octave;
    NSSearchField* search;
}
- (void)loadPresetIndex:(int)i;
@end

@implementation MUEWView

- (instancetype)initWithFrame:(NSRect)f {
    if ((self = [super initWithFrame:f])) {
        self.wantsLayer = YES;
        currentIndex = -1; edited = false; chip = 0; scroll = 0; dragKnob = -1; octave = 0;
        NSArray* favs = [[NSUserDefaults standardUserDefaults] arrayForKey:@"MUEWFavorites"];
        for (NSString* s in favs) favorites.insert(std::string(s.UTF8String));
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

- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)isFlipped { return NO; }

- (void)saveFavorites {
    NSMutableArray* a = [NSMutableArray array];
    for (const auto& s : favorites) [a addObject:S(s)];
    [[NSUserDefaults standardUserDefaults] setObject:a forKey:@"MUEWFavorites"];
}

- (void)refilter {
    visible = ui::visiblePresets(filter, favorites);
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
    if (!synth) return;
    std::lock_guard<std::mutex> g(*lock);
    synth->setParams(current.voice, current.routes);
    synth->setFX(current.fx);
}

- (void)loadPresetIndex:(int)i {
    const auto& bank = factoryPresets();
    if (i < 0 || i >= (int)bank.size()) return;
    currentIndex = i;
    current = bank[i];
    edited = false;
    [self applySound];
    // Keep the loaded preset in view.
    for (int r = 0; r < (int)visible.size(); ++r)
        if (visible[r] == i) {
            int rows = [self listRows];
            if (r < scroll) scroll = r;
            if (r >= scroll + rows) scroll = r - rows + 1;
        }
    [self setNeedsDisplay:YES];
}

- (void)stepPreset:(int)dir {
    const std::vector<int>& order = visible.empty() ? ui::visiblePresets({}, favorites) : visible;
    int pos = -1;
    for (int r = 0; r < (int)order.size(); ++r) if (order[r] == currentIndex) pos = r;
    int n = (int)order.size();
    if (n == 0) return;
    pos = pos < 0 ? 0 : (pos + dir + n) % n;
    [self loadPresetIndex:order[pos]];
}

// ---- geometry ----
- (CGFloat)top { return self.bounds.size.height - 100; }
- (CGFloat)listTop { return [self top] - 150; }
- (int)listRows { return (int)std::floor(([self listTop] - 76) / kRowH); }
- (NSPoint)knobCenter:(int)k {
    CGFloat t = [self top];
    NSPoint p[] = {{98, t - 194}, {195, t - 194}, {308, t - 194}, {405, t - 194},
                   {536, t - 94}, {637, t - 94}, {536, t - 200}, {637, t - 200}, {732, t - 200}};
    return p[k];
}
- (CGFloat)knobRadius:(int)k { return (k == ui::Cutoff || k == ui::Resonance) ? 30 : 25; }
- (NSRect)chipRect:(int)i {
    CGFloat t = [self top];
    return NSMakeRect(812 + (i % 3) * 51, t - 90 - (i / 3) * 22, 46, 18);
}
- (NSRect)favToggleRect { return NSMakeRect(812, 46, 150, 20); }
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
    NSBezierPath* ring = [NSBezierPath bezierPath];
    [ring appendBezierPathWithArcWithCenter:c radius:rad startAngle:225 endAngle:-45 clockwise:YES];
    [C(0x303947) setStroke]; ring.lineWidth = 4; [ring stroke];
    NSBezierPath* arc = [NSBezierPath bezierPath];
    if (k == ui::Detune) // bipolar: draw from center
        [arc appendBezierPathWithArcWithCenter:c radius:rad startAngle:90 endAngle:225 - 270 * v clockwise:v > .5];
    else
        [arc appendBezierPathWithArcWithCenter:c radius:rad startAngle:225 endAngle:225 - 270 * v clockwise:YES];
    [accent setStroke]; arc.lineWidth = 4; [arc stroke];
    double a = (225 - 270 * v) * M_PI / 180;
    NSBezierPath* line = [NSBezierPath bezierPath];
    [line moveToPoint:c];
    [line lineToPoint:NSMakePoint(c.x + cos(a) * (rad - 7), c.y + sin(a) * (rad - 7))];
    [C(0xeaf1f8) setStroke]; line.lineWidth = 2; [line stroke];
    NSString* label = dragKnob == k ? S(ui::knobReadout(current.voice, k)) : S(ui::knobLabel(k));
    TextA(label, NSMakeRect(c.x - rad - 16, c.y - rad - 25, rad * 2 + 32, 15), 10,
          dragKnob == k ? accent : C(0xa8b2c1), NSFontWeightMedium, NSTextAlignmentCenter);
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

- (void)msegIn:(NSRect)r {
    FillRound(r, 7, C(0x0a0d12));
    const auto& pts = current.voice.mseg1Points;
    if (current.voice.mseg1Loop && pts.size() > 2) {
        CGFloat x0 = r.origin.x + 6 + (r.size.width - 12) * pts[1].time;
        CGFloat x1 = r.origin.x + 6 + (r.size.width - 12) * pts.back().time;
        FillRound(NSMakeRect(x0, r.origin.y + 4, x1 - x0, r.size.height - 8), 3, C(0x5adac8, .10));
    }
    NSBezierPath* p = [NSBezierPath bezierPath];
    for (size_t i = 0; i < pts.size(); ++i) {
        NSPoint q = NSMakePoint(r.origin.x + 6 + (r.size.width - 12) * pts[i].time,
                                NSMidY(r) + pts[i].value * (r.size.height * .38));
        i ? [p lineToPoint:q] : [p moveToPoint:q];
    }
    [C(0x5adac8) setStroke]; p.lineWidth = 1.6; [p stroke];
    for (const auto& pt : pts) {
        NSPoint q = NSMakePoint(r.origin.x + 6 + (r.size.width - 12) * pt.time, NSMidY(r) + pt.value * (r.size.height * .38));
        [C(0xeaf1f8) setFill];
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(q.x - 2, q.y - 2, 4, 4)] fill];
    }
    Text(current.voice.mseg1Loop ? @"MSEG 1 \u2022 LOOP" : @"MSEG 1", NSMakeRect(r.origin.x + 6, NSMaxY(r) - 15, r.size.width - 8, 12), 8, C(0x66e2d0), NSFontWeightSemibold);
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
    TextA([NSString stringWithFormat:@"%d FACTORY PRESETS  \u2022  UNIVERSAL AUv2", kFactoryPresetCount],
          NSMakeRect(b.size.width - 280, b.size.height - 51, 252, 18), 10, C(0x758192), NSFontWeightMedium, NSTextAlignmentRight);

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
    [self knob:ui::WarpA accent:C(0x5adac8)];
    [self knob:ui::Mix accent:C(0x5adac8)];
    [self knob:ui::WarpB accent:C(0x9d7df2)];
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
    // Browser: list
    CGFloat lt = [self listTop];
    int rows = [self listRows];
    const auto& bank = factoryPresets();
    for (int r = 0; r < rows && scroll + r < (int)visible.size(); ++r) {
        int idx = visible[scroll + r];
        CGFloat y = lt - (r + 1) * kRowH;
        bool sel = idx == currentIndex;
        if (sel) FillRound(NSMakeRect(806, y, b.size.width - 836, kRowH - 1), 4, C(0x293c3b));
        Text(S(bank[idx].info.name), NSMakeRect(814, y + 2, 88, 14), 10, sel ? C(0x75ead8) : C(0xc3cbd6),
             sel ? NSFontWeightSemibold : NSFontWeightRegular);
        TextA(S(bank[idx].info.category), NSMakeRect(904, y + 3, 40, 12), 8, C(0x5f6b7b), NSFontWeightMedium, NSTextAlignmentRight);
        bool fav = favorites.count(kFactoryPresetTexts[idx].slug) > 0;
        TextA(fav ? @"\u2605" : @"\u2606", NSMakeRect(946, y + 2, 16, 14), 10, fav ? C(0xf2ab55) : C(0x3b4552),
              NSFontWeightRegular, NSTextAlignmentCenter);
    }
    if (visible.empty())
        TextA(@"No presets match", NSMakeRect(806, lt - 40, b.size.width - 836, 16), 10, C(0x5f6b7b), NSFontWeightMedium, NSTextAlignmentCenter);
    if ((int)visible.size() > rows) { // scroll indicator
        CGFloat trackH = lt - 76, thumbH = std::max(24.0, trackH * rows / visible.size());
        CGFloat thumbY = lt - thumbH - (trackH - thumbH) * scroll / std::max(1, (int)visible.size() - rows);
        FillRound(NSMakeRect(b.size.width - 30, thumbY, 3, thumbH), 1.5, C(0x3b4552));
    }
    // Browser footer
    [C(0x29313d) setFill]; NSRectFill(NSMakeRect(812, 72, b.size.width - 850, 1));
    bool curFav = currentIndex >= 0 && favorites.count(kFactoryPresetTexts[currentIndex].slug);
    Text(curFav ? @"\u2605  FAVORITE" : @"\u2606  ADD TO FAVORITES", NSMakeRect(812, 50, 110, 14), 9,
         curFav ? C(0xf2ab55) : C(0x8793a3), NSFontWeightSemibold);
    TextA([NSString stringWithFormat:@"%d / %d", (int)visible.size(), kFactoryPresetCount], NSMakeRect(912, 50, 50, 14), 9,
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
        Text(@"\u2193", NSMakeRect(x + 10, cardTop - 60, 80, 16), 11, C(0x5f6b7b));
        Text(S(ui::destName(rt.dest)), NSMakeRect(x + 10, cardTop - 80, 80, 16), 11, C(0xeaf1f8), NSFontWeightMedium);
        double amt = ui::routeDisplayAmount(rt);
        NSRect bar = NSMakeRect(x + 10, 84, 76, 6);
        FillRound(bar, 3, C(0x111820));
        CGFloat mid = NSMidX(bar), w = amt * bar.size.width / 2;
        FillRound(NSMakeRect(w >= 0 ? mid : mid + w, bar.origin.y, std::fabs(w), 6), 3, mseg ? C(0x66e2d0) : C(0x6cb6ff));
        TextA([NSString stringWithFormat:@"%+.2f", rt.amount], NSMakeRect(x + 10, 66, 76, 12), 9, C(0x8793a3), NSFontWeightMedium, NSTextAlignmentCenter);
    }
    struct FxCard { const char* name; bool on; double mix; std::string detail; };
    char d0[32], d1[32], d2[32];
    snprintf(d0, sizeof d0, "RATE %.2f Hz", current.fx.chorus.rateHz);
    snprintf(d1, sizeof d1, "%.0f / %.0f ms", current.fx.delay.timeLSec * 1000, current.fx.delay.timeRSec * 1000);
    snprintf(d2, sizeof d2, "DECAY %.2f", current.fx.reverb.decay);
    FxCard fx[3] = {{"CHORUS", current.fx.chorus.enabled, current.fx.chorus.mix, d0},
                    {"DELAY", current.fx.delay.enabled, current.fx.delay.mix, d1},
                    {"REVERB", current.fx.reverb.enabled, current.fx.reverb.mix, d2}};
    for (int i = 0; i < 3; ++i) {
        CGFloat x = 468 + i * 104;
        FillRound(NSMakeRect(x, 58, 96, cardH), 8, C(0x1b222c));
        Text(S(fx[i].name), NSMakeRect(x + 10, cardTop - 22, 60, 14), 10, fx[i].on ? C(0xf2ab55) : C(0x5f6b7b), NSFontWeightSemibold);
        FillRound(NSMakeRect(x + 78, cardTop - 17, 8, 8), 4, fx[i].on ? C(0xf2ab55) : C(0x303947));
        TextA(S(fx[i].detail), NSMakeRect(x + 6, cardTop - 44, 84, 12), 8, C(0x8793a3), NSFontWeightMedium, NSTextAlignmentCenter);
        NSPoint c = NSMakePoint(x + 48, 104);
        double mv = fx[i].on ? fx[i].mix : 0;
        NSBezierPath* ring = [NSBezierPath bezierPath];
        [ring appendBezierPathWithArcWithCenter:c radius:20 startAngle:225 endAngle:-45 clockwise:YES];
        [C(0x303947) setStroke]; ring.lineWidth = 3; [ring stroke];
        NSBezierPath* arc = [NSBezierPath bezierPath];
        [arc appendBezierPathWithArcWithCenter:c radius:20 startAngle:225 endAngle:225 - 270 * mv clockwise:YES];
        [C(0xf2ab55) setStroke]; arc.lineWidth = 3; [arc stroke];
        TextA([NSString stringWithFormat:@"MIX %.0f%%", mv * 100], NSMakeRect(x + 6, 66, 84, 12), 9, C(0xa8b2c1), NSFontWeightMedium, NSTextAlignmentCenter);
    }
}

// ---- interaction ----
- (NSInteger)hitKnob:(NSPoint)p {
    for (int k = 0; k < ui::KnobCount; ++k) {
        NSPoint c = [self knobCenter:k];
        if (hypot(p.x - c.x, p.y - c.y) < [self knobRadius:k] + 8) return k;
    }
    return -1;
}

- (void)mouseDown:(NSEvent*)e {
    [self.window makeFirstResponder:self];
    NSPoint p = [self convertPoint:e.locationInWindow fromView:nil];
    dragKnob = [self hitKnob:p];
    dragStart = p;
    if (dragKnob >= 0) {
        if (e.clickCount == 2 && currentIndex >= 0) { // double-click restores the preset value
            ui::knobField(current.voice, (int)dragKnob) = ui::knobField(const_cast<VoiceParams&>(factoryPresets()[currentIndex].voice), (int)dragKnob);
            [self applySound];
        }
        dragValue = ui::knobValue(current.voice, (int)dragKnob);
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
            filter.category = (i >= 1 && i <= 7) ? factoryCategories()[i - 1] : std::string();
            scroll = 0;
            [self refilter];
            return;
        }
    }
    if (NSPointInRect(p, [self favToggleRect]) && currentIndex >= 0) {
        std::string slug = kFactoryPresetTexts[currentIndex].slug;
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
                std::string slug = kFactoryPresetTexts[idx].slug;
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
    ui::setKnob(current.voice, (int)dragKnob, dragValue + (p.y - dragStart.y) / scale);
    edited = true;
    [self applySound];
    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent*)e { dragKnob = -1; [self setNeedsDisplay:YES]; }

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
    if (e.isARepeat) return;
    NSString* s = e.charactersIgnoringModifiers;
    if (s.length == 0) return;
    unichar ch = [s characterAtIndex:0];
    if (ch == NSLeftArrowFunctionKey || ch == NSUpArrowFunctionKey) { [self stepPreset:-1]; return; }
    if (ch == NSRightArrowFunctionKey || ch == NSDownArrowFunctionKey) { [self stepPreset:1]; return; }
    if (ch == 'z') { octave = std::max(-3, octave - 1); return; }
    if (ch == 'x') { octave = std::min(3, octave + 1); return; }
    int n = NoteForKey(ch);
    if (n >= 0 && synth) { std::lock_guard<std::mutex> g(*lock); synth->noteOn(48 + 12 * octave + n, .85f); }
}

- (void)keyUp:(NSEvent*)e {
    NSString* s = e.charactersIgnoringModifiers;
    if (s.length == 0) return;
    int n = NoteForKey([s characterAtIndex:0]);
    if (n >= 0 && synth) {
        std::lock_guard<std::mutex> g(*lock);
        for (int o = -3; o <= 3; ++o) synth->noteOff(48 + 12 * o + n); // release even if octave changed mid-note
    }
}
@end

@interface AppDelegate : NSObject <NSApplicationDelegate> {
    NSWindow* w; MUEWView* v; AVAudioEngine* engine; AVAudioSourceNode* source; Synth synth; std::mutex lock;
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
    v = [[MUEWView alloc] initWithFrame:f];
    v->synth = &synth; v->lock = &lock;
    w.contentView = v;
    int start = ui::indexOfSlug("night-bloom");
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
