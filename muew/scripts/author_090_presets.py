#!/usr/bin/env python3
"""0.9.0 additions to the MUEW factory bank: sounds built on user wavetables
(key frames generated here by additive synthesis) and WT POS modulation. Writes presets/<slug>.muew
and appends new slugs to presets/bank.txt (append only). Earlier presets are
the authored files themselves. Run from muew/, then scripts/embed_factory_bank.py."""
import math, struct
def g(x): return '%g' % x
def f32(x): return struct.unpack('f', struct.pack('f', x))[0]
def frame(partials):
    # partials: {harmonic: amplitude}; sine phase; peak-normalized, 256 samples
    v = [sum(a * math.sin(2 * math.pi * h * i / 256) for h, a in partials.items()) for i in range(256)]
    pk = max(abs(x) for x in v) or 1
    return [f32(max(-1.0, min(1.0, x / pk))) for x in v]
def wtline(n, frames): return "wt%d %d " % (n, len(frames)) + " ".join('%.9g' % x for f in frames for x in f)
MACROS = [(5, 2, 3), (6, 5, 0.7), (6, 6, 0.7), (7, 4, 4), (8, 1, 0.3), (8, 3, 0.25)]
SPREAD_UNISON = [(8, 7, 0.4), (8, 8, 0.4)]
WARP_DRIVE = [(6, 10, 0.4)]
OFF = dict(chorus=(0, 0.6, 6, 15, 0.35), delay=(0, 0.28, 0.42, 0.35, 0.22), reverb=(0, 0.55, 0.45, 0.28))

def write(slug, name, cat, tags, o1, o2, det, lvl, cut, res, amp, mod, routes, unison, lfo34, sync, env3, wtpos, wt1, wt2,
          chorus=OFF['chorus'], delay=OFF['delay'], reverb=OFF['reverb'], dist=None, eq=None, comp=None,
          l1=(5, 0), l2=(0.35, 1), w1=(0, 0), w2=(0, 0), fm=0, mseg=(1, 0, [(0, 0), (0.15, 1), (0.55, -0.3), (1, 0)])):
    routes = routes + MACROS + (SPREAD_UNISON if max(unison[0], unison[1]) > 1 else []) + (WARP_DRIVE if dist else [])
    assert len(routes) <= 16, slug
    L = ["muew-preset 2", "name " + name, "category " + cat, "author MUEW Factory", "tags " + " ".join(tags),
         "osc1Shape %d" % o1, "osc2Shape %d" % o2, "osc2Detune " + g(det), "osc2Level " + g(lvl),
         "filterCutoff " + g(cut), "filterReso " + g(res), "filterMode %d" % fm,
         "amp " + " ".join(map(g, amp)), "mod " + " ".join(map(g, mod)), "lfo1Rate " + g(l1[0]), "lfo1Shape %d" % l1[1],
         "lfo2 %s %d" % (g(l2[0]), l2[1]),
         "warp1 %d %s" % (w1[0], g(w1[1])), "warp2 %d %s" % (w2[0], g(w2[1])),
         "mseg %s %d %d" % (g(mseg[0]), mseg[1], len(mseg[2])) + "".join(" %s %s" % (g(t), g(v)) for t, v in mseg[2]),
         "unison %d %d %s %s %s %s" % (unison[0], unison[1], g(unison[2]), g(unison[3]), g(unison[4]), g(unison[5])),
         ]
    # Same order and default-omission as Preset::serialize, so files round-trip.
    if tuple(lfo34) != (1, 0, 2, 1): L.append("lfo34 %s %d %s %d" % (g(lfo34[0]), lfo34[1], g(lfo34[2]), lfo34[3]))
    if any(sync): L.append("sync %d %d %d %d" % tuple(sync))
    if tuple(env3) != (0.01, 0.4, 0, 0.3): L.append("env3 " + " ".join(map(g, env3)))
    if any(wtpos): L.append("wtpos %s %s" % tuple(map(g, wtpos)))
    if wt1: L.append(wtline(1, wt1))
    if wt2: L.append(wtline(2, wt2))
    L.append("routes %d" % len(routes))
    L += ["route %d %d %s" % r for r in [(s, d, g(a)) for s, d, a in routes]]
    L.append("chorus %d " % chorus[0] + " ".join(map(g, chorus[1:])))
    L.append("delay %d " % delay[0] + " ".join(map(g, delay[1:])))
    L.append("reverb %d " % reverb[0] + " ".join(map(g, reverb[1:])))
    if dist: L.append("dist 1 %d %s %s" % (dist[0], g(dist[1]), g(dist[2])))
    if eq: L.append("eq 1 %s %s %s" % tuple(map(g, eq)))
    if comp is not None: L.append("comp 1 " + g(comp))
    open("presets/%s.muew" % slug, "w").write("\n".join(L) + "\n")
    return slug

# sources: 0 LFO1 1 ENV2 2 Vel 3 LFO2 4 MSEG 5-8 Macro1-4 9 LFO3 10 LFO4 11 ENV3
# dests: 0 O1Pitch 1 O2Pitch 2 Cutoff 3 O2Level 4 Reso 5 O1Warp 6 O2Warp 7 UniA 8 UniB 9 Width 10 Drive
# lfo34 = (rate3 Hz, shape3, rate4 Hz, shape4); shapes 0 sine 1 tri 2 saw 3 square
# sync per LFO 1-4: 0 free 1 1/1 2 1/2 3 1/4 4 1/8 5 1/16 6 1/4T 7 1/8T 8 1/4D 9 2/1
# sources: 0 LFO1 1 ENV2 2 Vel 3 LFO2 4 MSEG 5-8 Macro1-4 9 LFO3 10 LFO4 11 ENV3
# dests: ... 10 Drive 11 WtPosA 12 WtPosB; shape 5 = the oscillator's user table
def formant(centers, n=40, width=2.2):
    return {h: sum(math.exp(-((h - c) / width) ** 2) for c in centers) / h ** 0.3 + (0.35 if h == 1 else 0) for h in range(1, n + 1)}
VOWELS = [(3.5, 12), (2.2, 9), (1.5, 11), (2.5, 4.5), (1.4, 3.2), (2.2, 9), (3.5, 12), (5, 14)]
vowel = [frame(formant(c)) for c in VOWELS]
rise = [frame({h: 1.0 / h for h in range(1, 2 + int(1.9 ** k))}) for k in range(8)]
glass = [frame({1: 1, 3: 0.4 * k / 3, 7: 0.3 * k / 3, 11: 0.22 * k / 3, 15: 0.15 * (k / 3) ** 2}) for k in range(4)]
hollow = [frame({2: 1, 5: 0.5, 9: 0.25}), frame({2: 1, 4: 0.6, 6: 0.45, 8: 0.3})]
new = []
new.append(write("vowel-morph", "Vowel Morph", "Lead", ["vowel", "wavetable", "talking"], 5, 2, -12, 0.25, 6000, 0.8,
                 (0.01, 0.3, 0.85, 0.3), (0.01, 0.3, 0, 0.2), [(9, 11, 0.5), (1, 2, 0.5)], (3, 1, 0.1, 0, 0.5, 0.7),
                 (1, 1, 2, 1), (0, 0, 2, 0), (0.01, 0.4, 0, 0.3), (0.5, 0), vowel, None,
                 delay=(1, 0.375, 0.5, 0.3, 0.2), reverb=(1, 0.6, 0.45, 0.22)))
new.append(write("harmonic-rise", "Harmonic Rise", "Pad", ["wavetable", "evolving", "swell"], 5, 5, 12, 0.4, 9000, 0.6,
                 (1.2, 2, 0.9, 2.5), (0.8, 1.5, 0.6, 1.2), [(11, 11, 1.0), (11, 12, 0.8), (3, 9, 0.2)], (5, 3, 0.3, 0.2, 0.9, 0.8),
                 (1, 0, 2, 1), (0, 0, 0, 0), (4, 2, 0.8, 3), (0, 0.1), rise, rise,
                 chorus=(1, 0.3, 5, 12, 0.25), reverb=(1, 0.85, 0.4, 0.35), comp=0.3))
new.append(write("glass-draw", "Glass Draw", "Keys", ["wavetable", "glass", "bell"], 5, 5, 12, 0.3, 12000, 0.5,
                 (0.002, 1.4, 0.2, 0.8), (0.002, 0.9, 0, 0.6), [(1, 11, 1.0), (2, 11, 0.3), (1, 12, 0.6)], (1, 1, 0.1, 0.1, 0.5, 0.8),
                 (1, 0, 2, 1), (0, 0, 0, 0), (0.01, 0.4, 0, 0.3), (0, 0), glass, hollow,
                 chorus=(1, 0.5, 3, 10, 0.2), reverb=(1, 0.7, 0.5, 0.3)))

bank = open("presets/bank.txt").read()
have = {l.strip() for l in bank.splitlines() if l.strip() and not l.startswith("#")}
add = [s for s in new if s not in have]
if add:
    open("presets/bank.txt", "a").write("\n".join(add) + "\n")
print("appended:", add)
