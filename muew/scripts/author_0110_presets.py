#!/usr/bin/env python3
"""0.11.0 MUEW factory content: (1) browser metadata for the existing bank -
character tags from browser characterTags() and a one-line `desc` - which
changes no sound; (2) 31 new presets that lean on the sub oscillator, noise
and filter 2, filling out Texture, FX, Keys and Pad. Writes presets/<slug>.muew
and appends new slugs to presets/bank.txt (append only). Run from muew/, then
scripts/embed_factory_bank.py."""
src = open("scripts/author_0100_presets.py").read()
exec(src[:src.index("new = []")])  # write(), layered() and the shared macro routes

META = {
    "airy-strings": (["soft", "wide"], "Slow string ensemble with an airy top; BRIGHT opens the filter, SPREAD widens it."),
    "bright-lead": (["bright"], "Simple, cutting two-saw lead with delayed vibrato. A good starting point for melodies."),
    "init-saw": (["clean"], "One plain saw through an open filter. The blank page for building your own sound."),
    "pluck": (["bright", "clean"], "Short filtered pluck; the envelope snaps the cutoff shut for a tight, clicky attack."),
    "punchy-bass": (["dark", "clean"], "Dry, punchy mono-style bass with a fast filter envelope for kick-friendly lows."),
    "soft-keys": (["soft", "warm"], "Mellow triangle keys with a slow release. Sits under vocals without fighting them."),
    "sub-bass": (["dark", "clean"], "Pure sine sub. Almost no harmonics, so it works under any other bass."),
    "warm-pad": (["warm", "wide", "soft"], "Detuned saw pad with a slow attack and a rounded low pass."),
    "fold-growl": (["aggressive", "dark"], "Wave-folded bass that growls as the fold amount moves. Push WARP for more bite."),
    "reese-drift": (["dark", "wide"], "Two detuned saws beating slowly against each other: the classic drum and bass reese."),
    "sync-bite": (["aggressive"], "Hard-synced bass with a snappy envelope on the sync amount for a vocal bite."),
    "rubber-sub": (["dark", "warm"], "Round sub bass with a short pitch bend on each note for a rubbery bounce."),
    "glass-sync-lead": (["bright", "clean"], "Glassy sync lead with vibrato; velocity brightens the tone."),
    "hollow-fifths": (["clean"], "Band-passed fifths with a hollow, reedy tone. Plays chords as single notes."),
    "acid-squelch": (["aggressive", "bright"], "Resonant low pass with a sharp envelope. Play short notes and ride RESO."),
    "pwm-solo": (["warm"], "Pulse width modulated solo lead with a vintage, slightly chorused tone."),
    "night-bloom": (["dark", "evolving"], "Dark pad that opens and closes over several seconds, shaped by MSEG 1."),
    "vector-choir": (["wide", "soft"], "Vocal-ish pad moving between two tones. Wide and gentle."),
    "frozen-lake": (["bright", "soft", "wide"], "Cold, glassy pad with a long reverb tail and a high shimmer."),
    "tidal-wash": (["wide", "evolving"], "A slow filter sweep that rises and falls like a wave under the chord."),
    "prism-keys": (["bright", "clean"], "Quantized, slightly digital keys with a sparkly top end."),
    "velvet-ep": (["soft", "warm"], "Soft electric piano; harder playing adds bark through velocity."),
    "bell-tines": (["bright", "clean"], "Metallic bell tones with a long ring. Nice for arpeggios."),
    "fold-pluck": (["aggressive", "bright"], "Percussive folded pluck with a short, gritty decay."),
    "marimba-wood": (["warm", "clean"], "Short wooden mallet tone. Works for fast melodic patterns."),
    "echo-pluck": (["bright", "wide"], "Bright pluck feeding a synced stereo delay for instant rhythm."),
    "bent-circuit": (["aggressive", "evolving"], "Stepped MSEG glitches over a bent oscillator. Hold a note and let it run."),
    "chrome-motion": (["bright", "evolving"], "Rhythmic gated texture with a metallic edge that keeps moving."),
    "rising-tide": (["evolving", "wide"], "Long build-up riser: pitch and filter climb together for the drop."),
    "laser-drop": (["aggressive", "bright"], "A fast pitch dive zap for transitions and hits."),
    "hyper-saw": (["bright", "wide"], "Seven-voice supersaw lead. Big and bright out of the box."),
    "anthem-stack": (["wide", "bright"], "Stacked unison pad for festival chords."),
    "reese-grind": (["dark", "aggressive"], "Reese bass through soft clipping for a grinding, heavy low end."),
    "hoover-rise": (["aggressive", "wide"], "Rave hoover with detuned unison and pitch swoop."),
    "fold-screamer": (["aggressive", "bright"], "Folded lead through distortion and compression. Loud and forward."),
    "crushed-keys": (["soft", "warm"], "Bitcrushed lofi keys with a dusty, tape-like softness."),
    "wide-pluck": (["wide", "bright"], "Unison pluck spread across the stereo field."),
    "growl-stack": (["aggressive", "dark"], "Unison growl bass with distortion; WARP moves the growl."),
    "sync-wobble": (["aggressive", "evolving"], "Tempo-synced wobble bass. The LFO follows the host tempo."),
    "tempo-gate": (["evolving", "wide"], "Trance gate pad synced to the host tempo."),
    "triplet-pluck": (["bright", "clean"], "Pluck with triplet-synced motion for rolling grooves."),
    "drift-motion": (["warm", "evolving"], "Keys that drift in tone over time through slow LFO 3 and LFO 4 motion."),
    "vowel-morph": (["evolving", "bright"], "Talking wavetable lead that sweeps through vowel frames."),
    "harmonic-rise": (["evolving", "wide", "soft"], "Pad that adds harmonics as it swells, moving through its wavetable."),
    "glass-draw": (["bright", "clean"], "Glassy wavetable keys; each note starts bright and settles."),
    "sub-pressure": (["dark"], "Deep bass with the sub oscillator one octave down for club pressure."),
    "breath-flute": (["soft", "warm"], "Breathy flute: filtered noise in parallel with a soft tone."),
    "formant-talker": (["bright", "evolving"], "Formant filter 2 swept by LFO 3 for a talking lead."),
    "comb-pluck": (["bright", "clean"], "Comb-filtered pluck with a metallic, tuned ring."),
}

def meta(slug, char, desc):
    p = "presets/%s.muew" % slug
    L = open(p).read().splitlines()
    for n, l in enumerate(L):
        if l.startswith("tags"):
            have = l.split()[1:]
            L[n] = " ".join(["tags"] + have + [t for t in char if t not in have])
            break
    L = [l for l in L if not l.startswith("desc ")]
    i = next(n for n, l in enumerate(L) if l.startswith("tags")) + 1
    L.insert(i, "desc " + desc)  # same position as Preset::serialize
    open(p, "w").write("\n".join(L) + "\n")

for s, (c, d) in META.items(): meta(s, c, d)

A = dict(chorus=OFF['chorus'], delay=OFF['delay'], reverb=OFF['reverb'])
ENV3 = (0.01, 0.4, 0, 0.3); NOSYNC = (0, 0, 0, 0); L34 = (1, 0, 2, 1); NOWT = (0, 0)
def P(slug, name, cat, tags, desc, **k):
    # Compact authoring: defaults for the rare fields, then desc after tags.
    d = dict(o=(2, 2), det=7, lvl=0.5, cut=6000, res=0.5, amp=(0.01, 0.3, 0.8, 0.3), mod=(0.01, 0.3, 0, 0.2),
             routes=[], uni=(1, 1, 0.1, 0.1, 0.5, 0.7), lfo34=L34, sync=NOSYNC, env3=ENV3)
    for key in list(d): d[key] = k.pop(key, d[key])
    layered(slug, name, cat, tags, d['o'][0], d['o'][1], d['det'], d['lvl'], d['cut'], d['res'], d['amp'], d['mod'],
            d['routes'], d['uni'], d['lfo34'], d['sync'], d['env3'], NOWT, None, None, **k)
    meta(slug, [], desc)
    return slug

# sources: 0 LFO1 1 ENV2 2 Vel 3 LFO2 4 MSEG 5-8 Macro1-4 9 LFO3 10 LFO4 11 ENV3
# dests: 0 O1Pitch 1 O2Pitch 2 Cutoff 3 O2Level 4 Reso 5 O1Warp 6 O2Warp 7 UniA 8 UniB 9 Width 10 Drive
#        11 WtPosA 12 WtPosB 13 SubLevel 14 NoiseLevel 15 Filter2Cutoff
# sub=(level, octave 1|2, shape 0 sine 1 tri 2 square); noise=(level, tone)
# f2=(type 0 off 1 LP 2 BP 3 HP 4 comb 5 formant, cutoff Hz, reso, routing 0 serial 1 parallel)
# dist=(mode 0 soft 1 fold 2 crush, drive, mix); warp modes 0 clean 1 sync 2 bend+ 3 bend- 4 pwm 5 quantize 6 fold
REV = (1, 0.8, 0.45, 0.32); REVL = (1, 0.92, 0.4, 0.4); DLY = (1, 0.375, 0.5, 0.4, 0.22); CHO = (1, 0.4, 6, 14, 0.3)
new = [
# --- Texture (6)
P("wind-tunnel", "Wind Tunnel", "Texture", ["noise", "air", "dark", "evolving", "wide"],
  "Filtered noise wind with a slow band pass sweep. Hold one note for a whole bar.",
  o=(0, 0), lvl=0, cut=3000, res=0.6, amp=(1.5, 1, 0.9, 2.5), routes=[(9, 15, 2.5), (0, 2, 0.8)],
  lfo34=(0.07, 0, 2, 1), l1=(0.11, 1), noise=(0.8, 0.45), f2=(2, 700, 3.5, 0), chorus=CHO, reverb=REVL),
P("rain-glass", "Rain Glass", "Texture", ["noise", "glass", "bright", "evolving"],
  "Bright noise through a resonant comb, like rain on a window. Works as a bed under keys.",
  o=(0, 1), det=24, lvl=0.2, cut=12000, res=0.3, amp=(0.4, 1, 0.8, 2), routes=[(9, 15, 1.2), (10, 14, 0.3)],
  lfo34=(0.4, 3, 6.5, 3), noise=(0.55, 0.9), f2=(4, 1800, 5, 1), delay=(1, 0.33, 0.47, 0.45, 0.25), reverb=REVL),
P("deep-space", "Deep Space", "Texture", ["drone", "dark", "wide", "evolving"],
  "Slow detuned drone with a sub underneath and a wide, drifting top. Great for intros.",
  o=(2, 1), det=-12.08, lvl=0.35, cut=900, res=0.3, amp=(2.5, 1, 0.85, 4), uni=(5, 3, 0.25, 0.2, 0.9, 0.8),
  routes=[(9, 2, 1.2), (10, 9, 0.3)], lfo34=(0.05, 1, 0.09, 0), sub=(0.2, 1, 0), noise=(0.08, 0.3), reverb=REVL),
P("static-field", "Static Field", "Texture", ["noise", "crackle", "aggressive", "evolving"],
  "Crackling bitcrushed noise with a stepped band pass. Layer under drums for grit.",
  o=(3, 0), lvl=0, cut=8000, res=0.5, amp=(0.2, 1, 0.9, 1), routes=[(10, 15, 3), (9, 14, 0.4)],
  lfo34=(2, 3, 0.3, 2), sync=(0, 0, 5, 0), noise=(0.6, 0.7), f2=(2, 2500, 4, 0), dist=(2, 0.6, 0.6), reverb=REV),
P("lunar-choir", "Lunar Choir", "Texture", ["choir", "formant", "soft", "wide", "evolving"],
  "Formant filtered unison saws that sing slow vowels. Soft and very wide.",
  o=(2, 2), det=0.08, lvl=0.6, cut=7000, res=0.3, amp=(1.2, 1, 0.9, 2.5), uni=(5, 5, 0.2, 0.22, 1, 0.8),
  routes=[(9, 15, 1.8)], lfo34=(0.13, 1, 2, 1), f2=(5, 220, 2, 0), chorus=CHO, reverb=REVL),
P("machine-room", "Machine Room", "Texture", ["industrial", "rhythmic", "dark", "aggressive"],
  "Synced gated metal hum with a comb filter. A dark, busy background loop.",
  o=(3, 4), det=0.5, lvl=0.6, cut=2500, res=0.8, amp=(0.01, 1, 0.9, 0.5), routes=[(9, 2, 2), (10, 15, 1.5)],
  lfo34=(4, 3, 1, 2), sync=(0, 0, 4, 3), sub=(0.3, 2, 2), f2=(4, 110, 5, 1), dist=(0, 0.4, 0.4), delay=DLY, comp=0.4),
# --- FX (6)
P("noise-riser", "Noise Riser", "FX", ["riser", "noise", "bright", "evolving"],
  "White noise build: the high pass and band pass climb over about eight seconds.",
  o=(0, 0), lvl=0, cut=700, res=0.4, fm=2, amp=(0.8, 1, 1, 1.5), env3=(8, 0.1, 1, 1),
  routes=[(11, 2, 4.5), (11, 15, 4)], noise=(0.9, 0.8), f2=(2, 300, 2.5, 0), reverb=REVL, delay=DLY),
P("impact-boom", "Impact Boom", "FX", ["hit", "sub", "dark", "aggressive"],
  "Cinematic impact: a sub dive, a noise burst and a long tail. Play low.",
  o=(0, 2), det=-12, lvl=0.3, cut=1500, res=0.2, amp=(0.001, 2.5, 0, 2.5), mod=(0.001, 1.2, 0, 1),
  routes=[(1, 0, 12), (1, 1, 12), (1, 2, 3), (11, 14, 0.8)], env3=(0.001, 0.25, 0, 0.2),
  sub=(0.8, 1, 0), noise=(0.1, 0.4), dist=(0, 0.5, 0.5), reverb=REVL, comp=0.6),
P("downlifter", "Downlifter", "FX", ["fall", "sweep", "wide", "evolving"],
  "Falling pitch and filter sweep for the bar after a drop.",
  o=(2, 2), det=0.2, lvl=0.6, cut=12000, res=0.4, amp=(0.001, 4, 0, 1), mod=(0.001, 4, 0, 1), uni=(5, 1, 0.3, 0.1, 1, 0.8),
  routes=[(1, 0, 12), (1, 2, 3), (1, 14, 0.5)], noise=(0.25, 0.7), reverb=REVL, delay=DLY),
P("alarm-sweep", "Alarm Sweep", "FX", ["siren", "sync", "bright", "aggressive"],
  "Synced siren that sweeps up and down with LFO 3. Great for build-ups.",
  o=(3, 2), det=12, lvl=0.3, cut=8000, res=0.5, routes=[(9, 0, 5), (9, 1, 5), (3, 2, 0.4)],
  lfo34=(2, 1, 2, 1), sync=(0, 0, 3, 0), delay=DLY, reverb=REV, dist=(0, 0.3, 0.3)),
P("tape-stop", "Tape Stop", "FX", ["stop", "pitch", "warm", "dark"],
  "One note that slows to a halt like a stopped tape machine.",
  o=(2, 3), det=-12, lvl=0.4, cut=5000, res=0.3, amp=(0.001, 1.6, 0, 0.3), env3=(1.2, 0.1, 1, 0.2),
  routes=[(11, 0, -24), (11, 1, -24), (11, 2, -4)], sub=(0.4, 1, 0), dist=(0, 0.3, 0.3)),
P("glitch-burst", "Glitch Burst", "FX", ["glitch", "stepped", "aggressive", "bright"],
  "Stepped random-feeling pitch and filter glitches driven by square LFOs.",
  o=(3, 2), det=7, lvl=0.5, cut=6000, res=0.6, amp=(0.001, 0.6, 0.4, 0.3), routes=[(9, 0, 12), (10, 2, 2.5), (10, 15, 2)],
  lfo34=(8, 3, 3, 3), sync=(0, 0, 5, 7), w1=(5, 0.6), noise=(0.15, 0.9), f2=(4, 600, 4, 1), dist=(2, 0.5, 0.5), delay=DLY),
# --- Pad (5)
P("ember-pad", "Ember Pad", "Pad", ["warm", "soft", "sub"],
  "Warm saw pad with a sine sub for weight. Macro BRIGHT opens the embers.",
  o=(2, 2), det=0.1, lvl=0.6, cut=1800, res=0.3, amp=(0.8, 1, 0.85, 2), uni=(3, 3, 0.15, 0.15, 0.8, 0.8),
  routes=[(0, 2, 0.3)], l1=(0.2, 1), sub=(0.3, 1, 0), chorus=CHO, reverb=REV),
P("glass-cathedral", "Glass Cathedral", "Pad", ["bright", "wide", "evolving"],
  "Big bright pad with a comb filter 2 shimmer and a long hall.",
  o=(1, 2), det=12, lvl=0.4, cut=10000, res=0.3, amp=(1.5, 1, 0.9, 3.5), uni=(3, 5, 0.12, 0.2, 1, 0.8),
  routes=[(9, 15, 0.8)], lfo34=(0.2, 0, 2, 1), f2=(4, 880, 3, 1), chorus=CHO, reverb=REVL),
P("dust-pad", "Dust Pad", "Pad", ["lofi", "noise", "warm", "soft"],
  "Lofi pad: soft saws, a bed of warm noise and gentle bitcrush.",
  o=(2, 1), det=0.15, lvl=0.5, cut=2500, res=0.2, amp=(0.6, 1, 0.8, 1.8), routes=[(0, 2, 0.2)], l1=(0.3, 0),
  noise=(0.12, 0.25), dist=(2, 0.25, 0.3), chorus=CHO, reverb=REV),
P("frost-bloom", "Frost Bloom", "Pad", ["cold", "evolving", "bright", "wide"],
  "Cold pad whose band pass filter 2 blooms open every few seconds.",
  o=(3, 2), det=7, lvl=0.5, cut=9000, res=0.4, amp=(1.2, 1, 0.9, 3), uni=(3, 3, 0.2, 0.2, 1, 0.8),
  routes=[(9, 15, 2.5), (10, 4, 0.2)], lfo34=(0.1, 1, 0.07, 0), f2=(2, 1200, 2, 0), reverb=REVL, delay=DLY),
P("velvet-drone", "Velvet Drone", "Pad", ["drone", "dark", "warm", "soft"],
  "Dark, soft low drone with a triangle sub. Good for film beds.",
  o=(1, 2), det=-12, lvl=0.35, cut=700, res=0.3, amp=(2, 1, 1, 4), routes=[(9, 2, 0.6)], lfo34=(0.08, 0, 2, 1),
  sub=(0.45, 1, 1), noise=(0.05, 0.2), reverb=REVL, comp=0.3),
# --- Keys (4)
P("felt-piano", "Felt Piano", "Keys", ["piano", "soft", "warm"],
  "Muted, felt-like piano tone with a gentle hammer thump from the noise.",
  o=(1, 0), det=12, lvl=0.3, cut=2200, res=0.2, amp=(0.002, 1.8, 0, 0.6), mod=(0.001, 0.8, 0, 0.5),
  routes=[(1, 2, 1.2), (2, 2, 0.8), (11, 14, 0.6)], env3=(0.001, 0.05, 0, 0.05), noise=(0.1, 0.3), reverb=REV),
P("clav-funk", "Clav Funk", "Keys", ["clav", "funky", "bright", "clean"],
  "Snappy pulse clav with a band pass filter 2 for that plucked-string bite.",
  o=(4, 3), det=0, lvl=0.6, cut=6000, res=0.5, amp=(0.001, 0.6, 0.15, 0.1), mod=(0.001, 0.2, 0, 0.1),
  routes=[(1, 2, 2), (2, 15, 1)], f2=(2, 1400, 2.5, 1), comp=0.5, eq=(0, 3, 2)),
P("digital-organ", "Digital Organ", "Keys", ["organ", "drawbar", "bright", "clean"],
  "Drawbar-style organ: stacked sine and square with sub octave and a fast LFO for rotary shimmer.",
  o=(0, 3), det=12, lvl=0.3, cut=9000, res=0.1, amp=(0.005, 0.1, 1, 0.08), routes=[(0, 9, 0.3), (0, 3, 0.1)],
  l1=(6.5, 0), sub=(0.4, 1, 0), chorus=CHO),
P("music-box", "Music Box", "Keys", ["bell", "tiny", "bright", "soft"],
  "Tiny, bright music box tines with a short ring and a small room.",
  o=(0, 1), det=24, lvl=0.35, cut=14000, res=0.2, amp=(0.001, 1.2, 0, 1), routes=[(2, 3, 0.3)], f2=(3, 500, 0.7, 0),
  delay=(1, 0.25, 0.375, 0.2, 0.15), reverb=REV),
# --- Bass (4)
P("growl-formant", "Growl Formant", "Bass", ["growl", "formant", "aggressive", "dark"],
  "Talking growl bass: formant filter 2 swept by synced LFO 3 over a heavy sub.",
  o=(2, 3), det=-12, lvl=0.5, cut=3000, res=0.5, amp=(0.002, 0.3, 0.9, 0.12), routes=[(9, 15, 2.8), (9, 5, 0.3)],
  lfo34=(2, 1, 2, 1), sync=(0, 0, 4, 0), w1=(6, 0.3), sub=(0.5, 1, 0), f2=(5, 200, 2.5, 0), dist=(0, 0.5, 0.5), comp=0.5),
P("deep-house-sub", "Deep House Sub", "Bass", ["sub", "round", "warm", "clean"],
  "Round sine and triangle sub bass with a soft filter pluck. Sits under a kick.",
  o=(0, 1), det=12, lvl=0.2, cut=900, res=0.2, amp=(0.002, 0.5, 0.7, 0.1), mod=(0.001, 0.2, 0, 0.1),
  routes=[(1, 2, 1.5)], sub=(0.4, 1, 1), comp=0.3),
P("noise-bass", "Noise Bass", "Bass", ["noise", "gritty", "aggressive", "bright"],
  "Gritty bass where each note starts with a noise snap through the high pass filter 2.",
  o=(3, 2), det=0.1, lvl=0.5, cut=1500, res=0.6, amp=(0.001, 0.4, 0.7, 0.1), mod=(0.001, 0.15, 0, 0.1),
  routes=[(1, 2, 2.5), (11, 14, 0.6)], env3=(0.001, 0.08, 0, 0.05), sub=(0.4, 1, 2), noise=(0.1, 0.8),
  f2=(3, 2000, 1, 1), dist=(0, 0.4, 0.4)),
P("comb-reese", "Comb Reese", "Bass", ["reese", "comb", "dark", "wide"],
  "Reese bass with a moving comb filter for a metallic, phasing low end.",
  o=(2, 2), det=0.15, lvl=0.8, cut=2500, res=0.4, amp=(0.005, 0.3, 0.9, 0.2), uni=(3, 3, 0.2, 0.2, 0.6, 0.7),
  routes=[(9, 15, 1.2)], lfo34=(0.15, 1, 2, 1), sub=(0.35, 1, 0), f2=(4, 90, 4, 0), dist=(0, 0.3, 0.3)),
# --- Pluck (3)
P("kalimba-drop", "Kalimba Drop", "Pluck", ["kalimba", "wooden", "warm", "clean"],
  "Thumb piano pluck with a short comb ring and a soft bounce delay.",
  o=(0, 1), det=12, lvl=0.3, cut=5000, res=0.3, amp=(0.001, 0.5, 0, 0.4), routes=[(2, 15, 1)],
  f2=(4, 520, 3, 1), noise=(0.05, 0.5), delay=(1, 0.25, 0.375, 0.3, 0.18), reverb=REV),
P("harp-ripple", "Harp Ripple", "Pluck", ["harp", "bright", "soft", "wide"],
  "Soft harp pluck with a bright high end and wide reverb. Made for arpeggios.",
  o=(1, 2), det=12, lvl=0.2, cut=7000, res=0.3, amp=(0.001, 1.2, 0, 1.2), mod=(0.001, 0.6, 0, 0.5),
  routes=[(1, 2, 1.5)], chorus=CHO, reverb=REVL),
P("snap-pluck", "Snap Pluck", "Pluck", ["snap", "short", "bright", "aggressive"],
  "Very short plucked saw with a noise snap on the attack. Cuts through busy mixes.",
  o=(2, 3), det=0.1, lvl=0.5, cut=3000, res=0.4, amp=(0.001, 0.25, 0, 0.2), mod=(0.001, 0.12, 0, 0.1),
  routes=[(1, 2, 3)], env3=(0.001, 0.04, 0, 0.03), noise=(0.1, 0.9), dist=(0, 0.2, 0.3), delay=DLY),
# --- Lead (3)
P("whistle-lead", "Whistle Lead", "Lead", ["whistle", "breathy", "soft", "clean"],
  "Pure whistle with a little breath noise and slow vibrato.",
  o=(0, 1), det=12, lvl=0.1, cut=8000, res=0.2, amp=(0.05, 0.3, 0.9, 0.3), routes=[(0, 0, 0.15)], l1=(5, 0),
  noise=(0.12, 0.7), f2=(2, 2500, 2, 1), delay=DLY, reverb=REV),
P("band-saw-lead", "Band Saw Lead", "Lead", ["nasal", "bandpass", "bright", "aggressive"],
  "Nasal saw lead through a band pass filter 2 in series. Velocity opens it.",
  o=(2, 2), det=0.08, lvl=0.8, cut=12000, res=0.3, uni=(3, 3, 0.1, 0.12, 0.6, 0.7), routes=[(2, 15, 1.5), (0, 0, 0.1)],
  l1=(5.5, 0), f2=(2, 1500, 2.5, 0), dist=(0, 0.35, 0.4), delay=DLY),
P("sub-lead", "Sub Lead", "Lead", ["mono", "fat", "warm", "dark"],
  "Fat square lead with a square sub an octave below. Great for low melodies.",
  o=(3, 2), det=-12, lvl=0.3, cut=2200, res=0.4, amp=(0.005, 0.3, 0.9, 0.2), mod=(0.005, 0.4, 0.2, 0.2),
  routes=[(1, 2, 1.2)], sub=(0.5, 1, 2), comp=0.4),
]
bank = open("presets/bank.txt").read()
have = {l.strip() for l in bank.splitlines() if l.strip() and not l.startswith("#")}
add = [s for s in new if s not in have]
if add:
    open("presets/bank.txt", "a").write("\n".join(add) + "\n")
print("new presets:", len(new), "appended:", len(add))
