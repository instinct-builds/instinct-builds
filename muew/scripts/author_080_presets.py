#!/usr/bin/env python3
"""0.8.0 additions to the MUEW factory bank: sounds built on the editable mod
matrix, LFO 3/4 (tempo synced or free) and ENV 3. Writes presets/<slug>.muew
and appends new slugs to presets/bank.txt (append only). Earlier presets are
the authored files themselves. Run from muew/, then scripts/embed_factory_bank.py."""
def g(x): return '%g' % x
MACROS = [(5, 2, 3), (6, 5, 0.7), (6, 6, 0.7), (7, 4, 4), (8, 1, 0.3), (8, 3, 0.25)]
SPREAD_UNISON = [(8, 7, 0.4), (8, 8, 0.4)]
WARP_DRIVE = [(6, 10, 0.4)]
OFF = dict(chorus=(0, 0.6, 6, 15, 0.35), delay=(0, 0.28, 0.42, 0.35, 0.22), reverb=(0, 0.55, 0.45, 0.28))

def write(slug, name, cat, tags, o1, o2, det, lvl, cut, res, amp, mod, routes, unison, lfo34, sync, env3,
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
new = []
new.append(write("sync-wobble", "Sync Wobble", "Bass", ["wobble", "synced", "dubstep"], 2, 3, -12, 0.55, 420, 2.2,
                 (0.005, 0.3, 0.9, 0.15), (0.005, 0.2, 0, 0.1), [(9, 2, 2.6), (10, 5, 0.35), (11, 0, 7), (9, 10, 0.25)],
                 (3, 1, 0.12, 0, 0.5, 0.7), (2, 0, 1, 1), (0, 0, 4, 3),
                 (0.001, 0.06, 0, 0.05), dist=(0, 0.4, 0.7), eq=(3, -1, 1), comp=0.5, w1=(2, 0.15)))
new.append(write("tempo-gate", "Tempo Gate", "Pad", ["gated", "synced", "trance"], 2, 2, 7, 0.5, 900, 0.9,
                 (0.3, 1, 0.9, 1.2), (0.5, 1, 0.6, 1), [(9, 2, 3.2), (10, 9, -0.4), (1, 2, 0.6)],
                 (5, 4, 0.25, 0.2, 0.9, 0.8), (2, 3, 0.25, 1), (0, 0, 5, 9),
                 (0.001, 0.3, 1, 0.3), chorus=(1, 0.35, 5, 12, 0.25), delay=(1, 0.375, 0.5, 0.35, 0.2),
                 reverb=(1, 0.8, 0.4, 0.3), comp=0.35))
new.append(write("triplet-pluck", "Triplet Pluck", "Pluck", ["triplet", "synced", "bright"], 1, 4, 12, 0.4, 2400, 1.4,
                 (0.002, 0.45, 0, 0.35), (0.002, 0.25, 0, 0.2), [(11, 2, 2.4), (9, 6, 0.45), (10, 1, 0.12), (2, 2, 0.8)],
                 (1, 1, 0.1, 0.1, 0.5, 0.8), (3, 1, 0.3, 0), (0, 0, 7, 0),
                 (0.001, 0.35, 0, 0.3), delay=(1, 0.333, 0.5, 0.42, 0.28), reverb=(1, 0.6, 0.5, 0.22), w2=(1, 0.2)))
new.append(write("drift-motion", "Drift Motion", "Keys", ["evolving", "drift", "warm"], 0, 1, 0.08, 0.5, 1800, 0.6,
                 (0.01, 1.2, 0.5, 0.9), (0.01, 0.8, 0.2, 0.6), [(9, 1, 0.18), (10, 5, 0.3), (11, 2, 1.6), (3, 6, 0.2)],
                 (2, 2, 0.12, 0.1, 0.7, 0.75), (0.13, 0, 0.21, 1), (0, 0, 0, 0),
                 (1.8, 2.5, 0.3, 1.5), chorus=(1, 0.4, 4, 12, 0.3), reverb=(1, 0.7, 0.5, 0.3), eq=(1, 0, 2),
                 w1=(1, 0.15)))

bank = open("presets/bank.txt").read()
have = {l.strip() for l in bank.splitlines() if l.strip() and not l.startswith("#")}
add = [s for s in new if s not in have]
if add:
    open("presets/bank.txt", "a").write("\n".join(add) + "\n")
print("appended:", add)
