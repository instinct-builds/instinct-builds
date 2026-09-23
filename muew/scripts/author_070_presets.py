#!/usr/bin/env python3
"""0.7.0 additions to the MUEW factory bank: unison stacks and the new FX rack
(distortion, EQ, compressor). Writes presets/<slug>.muew for each sound and
appends new slugs to presets/bank.txt (append only). Earlier presets are the
authored files themselves. Run from muew/, then scripts/embed_factory_bank.py."""
def g(x): return '%g' % x
# Standard macro routes every factory preset carries (0.6.0):
# Bright -> cutoff, Warp -> warp A/B, Reso -> resonance, Spread -> pitch B / level B.
MACROS = [(5, 2, 3), (6, 5, 0.7), (6, 6, 0.7), (7, 4, 4), (8, 1, 0.3), (8, 3, 0.25)]
# 0.7.0 extras: Spread widens the unison stacks; Warp pushes the drive on distorted sounds.
SPREAD_UNISON = [(8, 7, 0.4), (8, 8, 0.4)]
WARP_DRIVE = [(6, 10, 0.4)]
OFF = dict(chorus=(0, 0.6, 6, 15, 0.35), delay=(0, 0.28, 0.42, 0.35, 0.22), reverb=(0, 0.55, 0.45, 0.28))

def write(slug, name, cat, tags, o1, o2, det, lvl, cut, res, amp, mod, routes, unison,
          chorus=OFF['chorus'], delay=OFF['delay'], reverb=OFF['reverb'], dist=None, eq=None, comp=None,
          l1=(5, 0), l2=(0.35, 1), w1=(0, 0), w2=(0, 0), fm=0, mseg=(1, 0, [(0, 0), (0.15, 1), (0.55, -0.3), (1, 0)])):
    routes = routes + MACROS + (SPREAD_UNISON if max(unison[0], unison[1]) > 1 else []) + (WARP_DRIVE if dist else [])
    L = ["muew-preset 2", "name " + name, "category " + cat, "author MUEW Factory", "tags " + " ".join(tags),
         "osc1Shape %d" % o1, "osc2Shape %d" % o2, "osc2Detune " + g(det), "osc2Level " + g(lvl),
         "filterCutoff " + g(cut), "filterReso " + g(res), "filterMode %d" % fm,
         "amp " + " ".join(map(g, amp)), "mod " + " ".join(map(g, mod)), "lfo1Rate " + g(l1[0]), "lfo1Shape %d" % l1[1],
         "lfo2 %s %d" % (g(l2[0]), l2[1]), "warp1 %d %s" % (w1[0], g(w1[1])), "warp2 %d %s" % (w2[0], g(w2[1])),
         "mseg %s %d %d" % (g(mseg[0]), mseg[1], len(mseg[2])) + "".join(" %s %s" % (g(t), g(v)) for t, v in mseg[2]),
         "unison %d %d %s %s %s %s" % (unison[0], unison[1], g(unison[2]), g(unison[3]), g(unison[4]), g(unison[5])),
         "routes %d" % len(routes)]
    L += ["route %d %d %s" % r for r in [(s, d, g(a)) for s, d, a in routes]]
    L.append("chorus %d " % chorus[0] + " ".join(map(g, chorus[1:])))
    L.append("delay %d " % delay[0] + " ".join(map(g, delay[1:])))
    L.append("reverb %d " % reverb[0] + " ".join(map(g, reverb[1:])))
    if dist: L.append("dist 1 %d %s %s" % (dist[0], g(dist[1]), g(dist[2])))
    if eq: L.append("eq 1 %s %s %s" % tuple(map(g, eq)))
    if comp is not None: L.append("comp 1 " + g(comp))
    open("presets/%s.muew" % slug, "w").write("\n".join(L) + "\n")
    return slug

# unison = (voices A, voices B, detune A, detune B, width, blend)
# sources: 0 LFO1 1 ModEnv 2 Vel 3 LFO2 4 MSEG1 5-8 Macro1-4
# dests: 0 O1Pitch 1 O2Pitch 2 Cutoff 3 O2Level 4 Reso 5 O1Warp 6 O2Warp 7 UniA 8 UniB 9 Width 10 Drive
new = []
new.append(write("hyper-saw", "Hyper Saw", "Lead", ["supersaw", "unison", "wide"], 2, 2, 12, 0.35, 7000, 0.7,
                 (0.005, 0.3, 0.85, 0.3), (0.005, 0.4, 0.2, 0.3), [(1, 2, 1.2), (2, 2, 0.6)], (7, 5, 0.3, 0.22, 0.9, 0.8),
                 delay=(1, 0.3, 0.45, 0.3, 0.18), reverb=(1, 0.6, 0.45, 0.2), eq=(0, -1, 2), comp=0.35))
new.append(write("anthem-stack", "Anthem Stack", "Pad", ["supersaw", "unison", "big"], 2, 2, -12, 0.5, 4200, 0.5,
                 (0.35, 1.2, 0.85, 1.8), (0.8, 1.5, 0.5, 1.2), [(1, 2, 0.8), (3, 9, -0.2)], (8, 6, 0.35, 0.3, 1, 0.85),
                 chorus=(1, 0.3, 5, 12, 0.2), delay=(1, 0.4, 0.6, 0.3, 0.15), reverb=(1, 0.85, 0.4, 0.35), comp=0.3, l2=(0.15, 0)))
new.append(write("reese-grind", "Reese Grind", "Bass", ["reese", "distorted", "dark"], 2, 2, 0.1, 0.8, 650, 1.3,
                 (0.01, 0.3, 0.9, 0.2), (0.01, 0.3, 0, 0.2), [(3, 2, 1.1), (3, 5, 0.25)], (4, 4, 0.18, 0.15, 0.45, 0.7),
                 dist=(0, 0.45, 0.8), eq=(3, -2, -1), comp=0.5, l2=(0.18, 1), w1=(3, 0.1)))
new.append(write("hoover-rise", "Hoover Rise", "Lead", ["hoover", "unison", "rave"], 4, 2, -12, 0.45, 3800, 0.9,
                 (0.01, 0.4, 0.8, 0.35), (0.01, 0.4, 0.2, 0.3), [(4, 0, 3), (4, 1, 3), (0, 5, 0.25)], (8, 4, 0.55, 0.4, 1, 0.9),
                 chorus=(1, 0.6, 6, 14, 0.35), reverb=(1, 0.55, 0.45, 0.2), dist=(0, 0.3, 0.5), comp=0.4,
                 l1=(1.2, 1), w1=(4, 0.35), mseg=(0.6, 0, [(0, 0.8), (0.2, -0.3), (0.5, 0.05), (1, 0)])))
new.append(write("fold-screamer", "Fold Screamer", "Lead", ["fold", "distorted", "aggressive"], 3, 2, 7, 0.35, 5000, 1.2,
                 (0.005, 0.25, 0.8, 0.2), (0.005, 0.5, 0.3, 0.2), [(1, 2, 1.5), (4, 5, 0.4)], (3, 1, 0.12, 0.25, 0.6, 0.75),
                 delay=(1, 0.25, 0.375, 0.35, 0.2), dist=(1, 0.35, 0.6), eq=(-2, 4, 1), comp=0.45, w1=(6, 0.2),
                 mseg=(0.8, 1, [(0, 0), (0.5, 1), (1, 0)])))
new.append(write("crushed-keys", "Crushed Keys", "Keys", ["lofi", "bitcrush", "soft"], 1, 0, 12, 0.3, 3000, 0.5,
                 (0.003, 0.9, 0.35, 0.5), (0.003, 0.6, 0, 0.3), [(2, 2, 1.2)], (2, 1, 0.1, 0.25, 0.5, 0.8),
                 chorus=(1, 0.5, 3, 10, 0.25), reverb=(1, 0.6, 0.55, 0.28), dist=(2, 0.55, 0.5), eq=(1, 0, -3)))
new.append(write("wide-pluck", "Wide Pluck", "Pluck", ["unison", "wide", "short"], 2, 3, 12, 0.3, 4200, 0.8,
                 (0.001, 0.3, 0, 0.25), (0.001, 0.22, 0, 0.1), [(1, 2, 2.4), (2, 2, 0.6)], (5, 3, 0.2, 0.15, 1, 0.8),
                 delay=(1, 0.375, 0.25, 0.4, 0.25), reverb=(1, 0.5, 0.5, 0.18), comp=0.35))
new.append(write("growl-stack", "Growl Stack", "Bass", ["growl", "unison", "distorted"], 3, 2, -12, 0.5, 1100, 1.8,
                 (0.003, 0.3, 0.75, 0.12), (0.005, 0.4, 0.2, 0.1), [(4, 5, 0.6), (4, 2, 1.4)], (3, 1, 0.15, 0.25, 0.5, 0.8),
                 dist=(0, 0.6, 0.9), eq=(2, 2, -2), comp=0.6, w1=(6, 0.25),
                 mseg=(0.5, 1, [(0, 0), (0.25, 1), (0.5, 0.1), (0.75, 0.8), (1, 0)])))

bank = open("presets/bank.txt").read()
have = [l.strip() for l in bank.splitlines() if l.strip() and not l.startswith("#")]
add = [s for s in new if s not in have]
if add:
    open("presets/bank.txt", "a").write("\n".join(add) + "\n")
print("wrote %d, appended %d" % (len(new), len(add)))
