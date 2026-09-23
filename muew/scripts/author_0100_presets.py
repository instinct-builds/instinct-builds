#!/usr/bin/env python3
"""0.10.0 additions to the MUEW factory bank: sounds built on the sub
oscillator, noise and filter 2 (comb, formant, band pass; serial and
parallel). Writes presets/<slug>.muew and appends new slugs to
presets/bank.txt (append only). Run from muew/, then
scripts/embed_factory_bank.py."""
src = open("scripts/author_090_presets.py").read()
exec(src[:src.index("# sources: 0 LFO1")])  # shared write() and macro routes

# dests: ... 13 SubLevel 14 NoiseLevel 15 Filter2Cutoff
# filter2 types: 0 off 1 LP 2 BP 3 HP 4 comb 5 formant; routing 0 serial 1 parallel
def layered(slug, *a, sub=None, noise=None, f2=None, **k):
    write(slug, *a, **k)
    p = "presets/%s.muew" % slug
    L = open(p).read().splitlines()
    extra = []
    # Same order and default-omission as Preset::serialize.
    if sub: extra.append("sub %s %d %d" % (g(sub[0]), sub[1], sub[2]))
    if noise: extra.append("noise %s %s" % (g(noise[0]), g(noise[1])))
    if f2: extra.append("filter2 %d %s %s %d" % (f2[0], g(f2[1]), g(f2[2]), f2[3]))
    i = next(n for n, l in enumerate(L) if l.startswith("routes "))
    open(p, "w").write("\n".join(L[:i] + extra + L[i:]) + "\n")
    return slug

new = []
new.append(layered("sub-pressure", "Sub Pressure", "Bass", ["sub", "deep", "mono"], 2, 3, -12, 0.35, 650, 1.1,
                   (0.002, 0.35, 0.8, 0.15), (0.002, 0.25, 0, 0.15), [(1, 2, 2.2), (2, 13, 0.3)], (2, 1, 0.08, 0, 0.3, 0.6),
                   (1, 0, 2, 1), (0, 0, 0, 0), (0.01, 0.4, 0, 0.3), (0, 0), None, None,
                   dist=(0, 0.25, 0.3), comp=0.4, sub=(0.6, 1, 0)))
new.append(layered("breath-flute", "Breath Flute", "Lead", ["noise", "breathy", "airy"], 0, 1, 12, 0.35, 5000, 0.7,
                   (0.06, 0.4, 0.85, 0.35), (0.02, 0.5, 0, 0.3), [(0, 0, 0.12), (11, 14, 0.35), (1, 2, 0.6)], (2, 1, 0.05, 0, 0.3, 0.8),
                   (1, 0, 2, 1), (0, 0, 0, 0), (0.005, 0.25, 0, 0.3), (0, 0), None, None,
                   delay=(1, 0.3, 0.45, 0.25, 0.18), reverb=(1, 0.7, 0.5, 0.3),
                   noise=(0.45, 0.6), f2=(2, 1600, 1.6, 1), l1=(5.2, 0), eq=(6, 7, 5)))
new.append(layered("formant-talker", "Formant Talker", "Lead", ["formant", "vowel", "talking"], 2, 2, 7, 0.4, 9000, 0.6,
                   (0.01, 0.3, 0.9, 0.25), (0.01, 0.3, 0, 0.2), [(9, 15, 2.5)], (3, 3, 0.15, 0.15, 0.6, 0.7),
                   (1.2, 1, 2, 1), (0, 0, 3, 0), (0.01, 0.4, 0, 0.3), (0, 0), None, None,
                   delay=(1, 0.375, 0.5, 0.3, 0.2), reverb=(1, 0.5, 0.45, 0.2),
                   sub=(0.3, 1, 0), f2=(5, 180, 2.5, 0)))
new.append(layered("comb-pluck", "Comb Pluck", "Pluck", ["comb", "metallic", "resonant"], 2, 4, 12, 0.3, 11000, 0.6,
                   (0.001, 0.5, 0, 0.4), (0.001, 0.35, 0, 0.3), [(1, 15, 2.0), (2, 2, 1.0)], (2, 1, 0.1, 0, 0.5, 0.7),
                   (1, 0, 2, 1), (0, 0, 0, 0), (0.01, 0.4, 0, 0.3), (0, 0), None, None,
                   delay=(1, 0.25, 0.375, 0.35, 0.22), reverb=(1, 0.6, 0.5, 0.25),
                   noise=(0.15, 0.8), f2=(4, 330, 6.5, 0), eq=(5, 7, 5)))

bank = open("presets/bank.txt").read()
have = {l.strip() for l in bank.splitlines() if l.strip() and not l.startswith("#")}
add = [s for s in new if s not in have]
if add:
    open("presets/bank.txt", "a").write("\n".join(add) + "\n")
print("appended:", add)
