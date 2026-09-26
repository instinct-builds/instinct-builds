// 0.67.0: stereo delay wet ducking, release, state, reset and legacy preservation.
#include "../src/preset.h"
#include "../src/factory_bank.h"
#include "../src/ui_model.h"
#include <cmath>
#include <cstdio>
#include <limits>
#include <vector>
using namespace muew;
static int failed = 0;
static void ok(bool b, const char* label) { std::printf("%s %s\n", b ? "ok:  " : "FAIL:", label); failed += !b; }
static std::vector<float> render(DelayParams p, int n, bool collision, bool rightTrigger = false) {
    StereoDelay d; d.init(1000); d.set(p);
    std::vector<float> out(n);
    for (int i = 0; i < n; ++i) {
        float l = i == 0 || (collision && i == 20 && !rightTrigger) ? 1.f : 0.f;
        float r = i == 0 || (collision && i == 20 && rightTrigger) ? 1.f : 0.f;
        d.process(l, r); out[i] = l;
    }
    return out;
}
int main() {
    DelayParams p; p.enabled = true; p.timeLSec = p.timeRSec = .02; p.feedback = .5; p.mix = 1;
    auto old = render(p, 100, true);
    p.duckReleaseMs = 1200;
    auto old2 = render(p, 100, true);
    ok(old == old2, "depth zero remains byte-identical across release settings");
    p.duckDepth = 1; p.duckReleaseMs = 20;
    auto fast = render(p, 100, true);
    ok(fast[20] < old[20] * .7f, "dry onset ducks coincident wet repeat");
    auto right = render(p, 100, true, true);
    ok(right[20] < old[20] * .7f, "right-only dry onset ducks left wet repeat (stereo link)");
    auto solo = render(p, 100, false);
    ok(solo[20] > 0 && solo[20] < old[20], "wet return recovers between dry hits");
    ok(fast[40] > .01f, "cross-feedback echo memory remains after a ducked return");
    p.duckReleaseMs = 1200;
    auto slow = render(p, 100, true);
    ok(slow[40] < fast[40], "longer release keeps later repeats quieter");
    StereoDelay reset; reset.init(1000); reset.set(p);
    for (int i=0; i<55; ++i) {float l = i == 0 ? 1.f : 0.f, r=l; reset.process(l,r);}
    reset.init(1000); reset.set(p);
    StereoDelay fresh; fresh.init(1000); fresh.set(p);
    bool same = true;
    for (int i=0; i<100; ++i) {float a=i==0?1.f:0.f,b=a,c=a,d=c;reset.process(a,b);fresh.process(c,d);same &= a==c && b==d;}
    ok(same, "host Reset clears detector and delay memory");
    FXParams f; f.delay.duckDepth = .75; f.delay.duckReleaseMs = 430;
    ok(ui::fxControlCount(FxDelay) == 8 && ui::fxGet(f, FxDelay, 6) == .75 && ui::fxGet(f, FxDelay, 7) == 430,
       "compact delay panel has eight controls and reads duck settings");
    ui::fxSet(f, FxDelay, 6, -2); ui::fxSet(f, FxDelay, 7, 5000);
    ok(f.delay.duckDepth == 0 && f.delay.duckReleaseMs == 1200, "panel edits clamp safely");
    Preset q = factoryPresets()[7];
    ok(q.serialize().find("delayduck") == std::string::npos, "old factory sound has no added preset line");
    q.fx.delay.duckDepth = .75; q.fx.delay.duckReleaseMs = 430;
    auto text=q.serialize(); Preset back;
    ok(back.parse(text) && back==q && back.serialize()==text && text.find("delayduck 0.75 430")!=std::string::npos,
       "new settings survive preset and AU-state text round-trip");
    Preset damaged; damaged.parse(factoryPresets()[7].serialize()+"delayduck 4 -200\n");
    ok(damaged.fx.delay.duckDepth == 1 && damaged.fx.delay.duckReleaseMs == 20, "out-of-range values clamp");
    Preset invalid; invalid.parse(factoryPresets()[7].serialize()+"delayduck nan inf\n");
    ok(invalid.fx.delay.duckDepth == 0 && invalid.fx.delay.duckReleaseMs == 250, "nonfinite values leave defaults");
    std::printf("%s\n", failed ? "DELAY DUCK TESTS FAILED" : "ALL DELAY DUCK TESTS PASSED");
    return failed ? 1 : 0;
}
