# MUEW

An original wavetable software synthesizer, built to run as an instrument in
Ableton Live (and any AU/VST3 host) on macOS. All DSP is written from scratch;
no code, presets, wavetables, or design assets from Serum or any other product.

## Phase 1 status: DSP core (complete, tested)

Header-only C++17, zero dependencies:

- `wavetable.h` — band-limited wavetables generated mathematically in code
  (sine, triangle, saw, square, 25% pulse), one mipmap level per octave,
  fractional-level interpolation for smooth pitch sweeps.
- `oscillator.h` — wavetable oscillator, detune in semitones, automatic
  mipmap selection per frequency.
- `filter.h` — TPT state-variable filter (LP/BP/HP/Notch/Peak), stable across
  the full cutoff and resonance range.
- `envelope.h` — ADSR with attack/decay/sustain/release stages.
- `lfo.h` — Hz-rate LFO (sine/triangle/saw/square), bipolar.
- `voice.h` — voice: 2 oscillators, filter, amp + mod envelopes, LFO, and a
  modulation matrix (LFO/env/velocity -> pitch/cutoff/level routes).
- `synth.h` — 16-voice polyphony, oldest-voice stealing, soft-clipped master.
- `wav_writer.h` — 16-bit PCM WAV output.
- `render_demo.cpp` — renders an original 7-second phrase to
  `out/muew-demo.wav` through the real engine.

## Build, test, render

```
make          # builds demo + tests
make test     # 95 checks across DSP, FX, licensing, preset bank, wavetable editor
              # envelope timing, polyphony/stealing, clipping, modulation)
make render   # writes out/muew-demo.wav
```

The test run caught a real DSP bug: the first-pass Chamberlin filter goes
unstable at high cutoff + high resonance, so the filter is the TPT form.

## Phase 1.5 status: FX rack + presets (complete, tested)

- `fx.h` — stereo chorus (quadrature-LFO modulated delay), stereo delay with
  cross-feedback, and a Schroeder-style reverb (4 damped combs + 2 allpasses
  per channel, detuned per side). Fixed chain: chorus -> delay -> reverb.
- `preset.h` — portable preset format (flat key/value lines) covering voice
  params, mod routes, and FX settings; exact save/load round-trip.
- `Synth::renderStereo` — interleaved stereo output through the FX chain.
- 5 more tests (19 total): chorus modulates and stays bounded, delay echo
  lands at the set time, reverb tail decays and stays finite, preset
  round-trip equality, full stereo FX render bounded.

## Phase 2 (macOS): AU wrapper

Ableton Live loads AUv2/VST3 plugins; the plugin format is an SDK, so "no
APIs" stops at the format boundary — we write 100% of the synth and use only
Apple's/Steinberg's format headers. Preset system, minimal native UI, and a
simple 3-device license key scheme follow there.

## Phase 2 prep: licensing + factory preset bank (complete, tested)

- `license.h` — offline 3-device licensing, zero dependencies. HMAC-SHA256
  signed keys (`MUEW3-XXXX-...`) carry the device limit inside the signed
  payload, so the limit cannot be raised by editing local files. Activation
  records are HMAC tokens bound to the key id and device hash, and the store
  file (~/.muew/license) carries an HMAC checksum so hand-edited entries are
  detected. SHA-256 and HMAC are implemented from the FIPS 180-4 / RFC 2104
  specs in this repo; primitives are tested against published vectors
  (RFC 4231).
- `license_tool.cpp` — `muew-license` CLI: generate / validate / activate /
  deactivate / status. Vendor secret via MUEW_VENDOR_SECRET (dev fallback
  compiled in; the AU wrapper phase will embed the matching key in the
  plugin).
- `preset_bank.h` + `presets/` — factory bank of 8 original presets
  (init-saw, warm-pad, punchy-bass, bright-lead, soft-keys, airy-strings,
  pluck, sub-bass) in the portable .muew format; every file round-trips
  exactly and renders bounded, non-silent audio in tests.
- `render_preset.cpp` — renders any bank preset through an original phrase
  (e.g. `build/muew-render-preset warm-pad`).
- 48 more tests (67 total): hash/HMAC vectors, key sign/validate/tamper,
  the 3-device limit incl. deactivation reuse, store persistence + forged
  entry detection, bank integrity and per-preset render checks.
- Verified artifacts: out/muew-preset-warm-pad.wav and
  out/muew-preset-punchy-bass.wav with waveform/L-R/spectrogram analyses.

## Phase 2c status: wavetable editor core (complete, tested)

- src/wavetable_editor.h: custom tables from harmonic (additive) specs
  (setHarmonic n amp phase) or freehand samples (drawSample, smooth,
  normalize); in-repo iterative radix-2 FFT; band-limited mipmap rebuild
  per octave matching the built-in tables' scheme; morph(a, b, t);
  .muewwt flat-text serialization (magic "muew-wavetable 1") with exact
  round trip.
- Wavetable.addCustomTable registers editor tables as extra shape slots
  (index >= Shape::Count); VoiceParams.osc1Shape/osc2Shape use them
  directly, fully band-limited through the existing oscillator path.
- tests/tests_wavetable_editor.cpp: 20 checks (FFT round trip, additive
  builds, per-level band-limiting, morph, serialization, synth integration
  at 440 Hz and at high pitch). Total suite: 95 checks via make test.
- Demo: src/render_demo_wt.cpp renders a phrase with the built-in saw vs a
  custom "hollow" table (odd harmonics + 0.15 h2); spectrogram-verified.

## 0.2 modulation-depth milestone

- Seven original oscillator phase-warp modes: Sync, Bend+, Bend-, PWM,
  Quantize, Fold, and bypass. Warp remains inside the band-limited wavetable
  path and every mode is bounded under high-frequency stress tests.
- A point-based MSEG supports authored breakpoints, looping spans, one-shot
  operation, release, and per-sample interpolation.
- The matrix now routes LFO1, LFO2, mod envelope, MSEG1, and velocity into
  both oscillator pitches, both warp amounts, oscillator mix, filter cutoff,
  and filter resonance.
- `render_demo_mod_depth.cpp` demonstrates dual oscillator Sync/Fold motion,
  looping MSEG timbre animation, and the existing stereo FX rack.

## 0.3.0 preset/content milestone

- **Preset format v2** (`muew-preset 2`): adds name, category, author and tags, LFO2, both oscillator warp modes/amounts, and MSEG time, loop and breakpoints. Version-1 files still load; fields they lack keep the defaults 0.2.0 used, so old presets sound the same. Unknown future versions are refused instead of guessed.
- **Factory bank**: 30 original presets across Bass, Lead, Pad, Keys, Pluck, Texture and FX. `presets/bank.txt` sets the order. The index is the AU factory preset number, and numbers 0-7 keep their 0.2.0 sounds so saved host projects don't shift.
- **One bank, two front ends**: `scripts/embed_factory_bank.py` generates `src/factory_bank.h` from the `.muew` files. The AU and the standalone app both compile that header. A test fails if the header drifts from the files.
- **Standalone browser**: category chips, search over name, category and tags, favorites saved between launches, prev/next buttons, arrow keys, and a scrolling list. Loading a preset changes the real engine state. The knobs edit real fields, so the oscillator previews, MSEG curve, modulation slots and FX cards all show the loaded sound. Double-click a knob to return it to the preset value, or hold Shift while dragging for fine control. Z and X shift the keyboard octave.
- **Tests**: `muew-tests-bank` checks exact round-trips, v1 compatibility, manifest/embedding parity, metadata, browser filtering, bounded non-silent output for every preset at three pitches, and that the modulation is audible. `muew-tests-ui` checks the UI model. The AU host test now selects and renders all 30 presets through the host API.
- Edit sounds in `scripts/author_factory_presets.py`, then run `python3 scripts/author_factory_presets.py && python3 scripts/embed_factory_bank.py` from `muew/`.

## 0.4.0 Audio Unit editor

- The AU now ships a Cocoa editor. Hosts such as Ableton Live read `kAudioUnitProperty_CocoaUI` and load `MUEWViewFactory_0_4` from `MUEW.component`. The plugin window shows the same designed instrument and preset browser as the standalone app.
- The editor code is shared (`app/MUEWEditorView.*`). It talks to the sound only through `MUEWEditorHost`. The standalone binds it to its in-process synth. The AU binds it to AU properties:
  - Factory loads go through `PresentPreset`, so the host shows the preset name.
  - Knob edits send the full sound through the private property `kMUEWProperty_PresetState`.
  - The editor watches `kMUEWProperty_StateGeneration`, so host-side preset changes and project recall show up in the open window.
- AU state is now thread-safe. Host and editor changes are staged under a lock, and the render thread picks them up at the top of the next block.
- Project recall saves the full sound (`muewState` in ClassInfo), so edits made in the editor survive a Live set reload. 0.3-style class info (preset number only) still loads.
- `au/au_view_host.mm` is a CI harness that loads the editor the way a DAW does, drives it with real mouse events, and checks that the host, editor and AU stay in sync.
- Not yet: AU parameters for host automation. That is the next milestone.

## 0.5.0 Automation and MIDI mapping

- The AU publishes 12 parameters that Live can automate and MIDI-map: Warp A, Osc Mix, Warp B, Osc B Detune, Cutoff, Resonance, Attack, Release, MSEG Time, Chorus Mix, Delay Mix and Reverb Mix. They use real units (Hz, seconds, semitones, percent), and log-scaled ones display that way.
- Parameter IDs are append-only (`src/au_params.h`), like the factory bank, so saved automation keeps pointing at the same control.
- Parameters are views onto the current sound, not a separate copy:
  - Loading a preset moves every parameter to that preset's values, and the host is told.
  - Automating a parameter changes the sound and marks it as custom.
  - Project recall stores the full sound, so automated values come back with the set.
- Editor knobs are parameters now. A drag sends begin/end gesture events plus value changes, so Live records automation from the MUEW window. Host automation moves the editor's knobs as it plays; the editor follows at 30 Hz.
- Parameter changes are lock-free from any thread, including a host's render thread. They're folded into the sound at the start of the next block.
- CI proof:
  - The host test checks the parameter list, info, get/set, scheduled ramps, clamping, preset-to-parameter sync, an audible cutoff sweep, recall, and survival across re-initialize.
  - The editor harness checks that knob drags reach a DAW-style automation listener as gestures, and that host automation reaches the open editor.
  - auval and host-test logs ship with the artifact.

## 0.6.0 Macros and user presets

- Four macro knobs sit in the header: BRIGHT, WARP, RESO and SPREAD. They're new mod sources (`Macro1-4`, appended as source IDs 5-8) and AU parameters 12-15, so Live can automate and MIDI-map them.
- Every factory preset routes the macros the same way:
  - BRIGHT: cutoff +3 octaves
  - WARP: warp A/B +0.7
  - RESO: resonance +4
  - SPREAD: osc B +0.3 semitones and level +0.25
- Clean oscillators got a warp mode (BEND+ on A, FOLD on B) so WARP always does something. At warp 0, those modes produce the clean waveform.
- With the macros at 0, all 30 factory presets render sample-identical to 0.5.0. That was checked stereo, with FX, on two notes. The bank test also keeps the 0.2.0 warm-pad file sample-identical.
- Macro positions are part of the sound. They're saved in user presets and project state (a `macros` line, written only when a macro is set, so factory files are unchanged).
- User presets:
  - `+ Save` in the browser names the sound and writes a `.muew` file to `~/Music/MUEW/Presets`.
  - `Export` writes a shareable `.muew` anywhere.
  - The `User` chip lists saved presets. They also show up in category chips, search and favorites.
  - The app and the AU share the folder.
  - In Live, loading a user preset shows its name as the plugin's preset.
- The code is `src/user_presets.h` (portable, tested on Linux) and `ui::Library` (factory bank followed by user presets, so AU factory numbers never move).

## 0.7.0 Unison and a deeper FX rack

- Unison on both oscillators: 1-8 stacked voices each, with detune (outer
  voices up to +-1 semitone), a shared stereo width and blend. Pick the voice
  count with the pips under each oscillator display; UNISON A/B and WIDTH are
  knobs (AU parameters 16-18) and mod destinations (7-9). One voice per
  oscillator is the classic mono path, so every earlier preset renders
  sample-identical.
- FX rack grows to six stages in signal order: distortion (soft clip, fold,
  bitcrush), chorus, delay, compressor (one knob), reverb and a 3-band EQ.
  Click a stage's light to switch it; drag its ring to set drive, mix or
  amount. Drive and compressor are AU parameters 19-20; the macros can drive
  the distortion (mod destination 10).
- Eight new factory sounds (AU numbers 30-37): Hyper Saw, Anthem Stack, Reese
  Grind, Hoover Rise, Fold Screamer, Crushed Keys, Wide Pluck, Growl Stack.
  Authored by scripts/author_070_presets.py; bank.txt stays append-only.

## 0.8.0 Editable mod matrix

- **16-slot matrix**, shown four rows at a time with page tabs (1-4, 5-8,
  9-12, 13-16). Each row has a source menu, a destination menu, a bipolar
  depth bar (drag; shift for fine; double-click resets to a quarter of full
  scale) with a readout in real units (st, oct, Q, %), and a clear button.
  Changing a destination keeps the route's relative depth.
- **Drag to assign**: drag any of the 12 source badges (LFO 1-4, ENV 2,
  ENV 3, MSEG, velocity, macros 1-4) onto a knob to create a route. Valid
  knobs show a dashed target while dragging. Every knob with routes draws a
  teal mod ring showing how far modulation can push it.
- **New modulators**: LFO 3 and LFO 4 (four shapes, free rate 0.02-20 Hz or
  tempo sync at 1/1, 1/2, 1/4, 1/8, 1/16, 1/4T, 1/8T, 1/4D, 2/1) and ENV 3
  (ADSR). LFO 1/2 can also sync. They cost nothing until a route uses them.
- **Host tempo**: the Audio Unit reads tempo through
  kAudioUnitProperty_HostCallbacks each block; the standalone runs at 120 BPM.
- **Presets**: routes and the new modulator settings are saved in the preset
  and AU state (the published parameter list stays at 21). Presets without the
  new modulators write no new lines, and all 38 earlier factory sounds render
  byte-identical to 0.7.0. Four new factory sounds (39-42): Sync Wobble,
  Tempo Gate, Triplet Pluck, Drift Motion. The standalone opens on Sync Wobble.
- Tests: `tests/tests_matrix.cpp` (route editing model, sync rates against
  tempo, round trips, unknown-source rejection), an AU host test for a route
  set through state plus host-tempo sync, and an editor harness step that
  drags LFO 3 onto CUTOFF, sets depth and sync, and checks the AU's sound.

## 0.9.0 User wavetables

Each oscillator can now play its own wavetable: up to 16 frames of 256
samples, band-limited per frame and crossfaded by a frame position.

- Shape `USER` (index 5). Clicking an oscillator's name cycles SINE, TRI, SAW,
  SQUARE, PULSE, USER. Clicking its display opens the wavetable editor over
  the OSCILLATORS panel, starting from the current shape.
- Editor: freehand DRAW mode (strokes are interpolated so fast moves leave no
  gaps, with the neighbour frames shown as ghosts) and HARM mode (32
  harmonic bars). The frame strip selects a frame and moves WT POS onto it.
  Buttons: + ADD, DUP, DELETE, MORPH (crossfades every frame between the
  first and last), SMOOTH, NORMAL, IMPORT and EXPORT (.wav; files made of
  2048-sample cycles import one frame per cycle).
- WT POS A/B: AU parameters 21 and 22, a drag bar in each display, and two
  new mod matrix destinations (WT POS A = 11, WT POS B = 12), so an envelope,
  LFO or MSEG can sweep the table.
- Presets store tables in optional `wtpos`, `wt1`, `wt2` lines. Older
  presets load unchanged; every 0.8.0 factory preset renders byte-identical.
- Three new factory presets (42-44): Vowel Morph, Harmonic Rise, Glass Draw.

## 0.10.0 Sub, noise and filter 2

- Sub oscillator: SINE, TRI or SQUARE, one or two octaves below oscillator A
  (it follows A's pitch modulation). Noise: white through a tone control
  (0 = dark, 1 = white), seeded per note so renders repeat exactly.
- Filter 2: LOW PASS, BAND PASS, HIGH PASS, COMB (feedback comb tuned to the
  cutoff, resonance sets the feedback) and FORMANT (three vowel formants;
  cutoff sweeps A-E-I-O-U). SERIAL runs it after filter 1; PARALLEL runs it
  beside filter 1 on the same input and mixes the two.
- Editor: the FILTER panel has two pages. FILTER 2 + SUB holds F2 CUTOFF,
  F2 RESONANCE, a live response plot of filter 2 (click it to change the
  type, SER / PAR below it), SUB with octave and shape pills, NOISE and TONE.
  A dot on the tab shows when page 2 is in use.
- AU parameters 23-27: Sub Level, Noise Level, Noise Tone, Filter 2 Cutoff,
  Filter 2 Resonance. Mod destinations 13-15: SUB, NOISE, F2 CUTOFF.
- Presets add optional `sub`, `noise` and `filter2` lines. Every 0.9.0
  factory preset renders byte-identical.
- Four new factory presets (45-48): Sub Pressure, Breath Flute, Formant
  Talker, Comb Pluck.

## 0.37.0 Selected-frame spectral tools

The WT editor's SPEC page adds FOCUS, BLUR, ALIGN and FLIP on the selected
256-sample frame. FOCUS smoothly gates partials quieter than 18% of the
strongest; BLUR averages magnitudes across five adjacent harmonics, preserving
phase; ALIGN sets the active partials to sine phase; FLIP reverses the cycle
by conjugating its spectrum. Other frames remain untouched. Each click gets a
labelled undo step, and the result lives in the normal AU/preset table state.
The preview still supports separate whole-table FORMANT, STRETCH, TILT and
ODD/EVEN. `tests_frame37.cpp` checks spectral properties, single-frame edits,
undo/redo and state round-trip; `render_demo_frame37.cpp` renders an original
four-scene phrase (base, FOCUS, BLUR, ALIGN+FLIP).

## 0.38.0 Frame-range operations

Shift-click a second frame in the WT strip to select the inclusive range
between the earlier frame and the clicked one; shift-click again to extend
from that anchor. Ordinary click clears it. The selected thumbnail band gets
a colored rail, and the SPEC preview shows both endpoint frame numbers.
FOCUS, BLUR, ALIGN and FLIP then transform the range as one labelled undo
step. Frames outside it stay untouched; a click without a range still edits
one frame. The selection is UI-only, not serialized into the sound.

## 0.39.0 Spectral partial edit

The SPEC preview's 32 partial bars are selectable. Click one to see its
harmonic number and level relative to the strongest partial in dB; -3/+3
chips change only that harmonic, retaining phase and the other partials.
A selected frame gets one undo step; with a selected frame range, the same
click is one labelled batch undo across that range. Silence stays silence,
and a silent harmonic is not invented by gain. The saved table contains the
edit; the selected bar is UI-only.

## 0.40.0 Full harmonic viewport

The SPEC page's > button expands the spectral bars, replacing the compact
waveform and frame-tool chips with a larger 32-bin spectrum. Four page chips
(1-32, 33-64, 65-96, 97-127) and the mouse wheel reach every editable
harmonic. Selection, level readout and -3/+3 dB buttons work on any page.
CREATE explicitly seeds a silent selected partial at -24 dB relative to the
strongest partial with sine phase; it never overwrites an existing partial
and does nothing on an all-silent frame. A frame range is still one undo
step. The view/page selection stays UI-only; the created harmonic is stored
in the normal table state.

## 0.41.0 Harmonic brush

In the expanded SPEC spectrum, Option-drag across bars to paint their
absolute levels on a -48 to +12 dB scale. Fast movement fills skipped
harmonics. The editor replays the whole gesture from a frozen table baseline
on every move, so gains do not compound; grey caps show each painted
harmonic's original level. A selected frame range receives the same gesture
on every frame. Mouse-up records one undo step (or none for a no-op). The
brush never creates silent partials; the explicit CREATE control still owns
that decision. The painted table is stored in the ordinary sound state.

## 0.42.0 Brush range-edge falloff

The expanded SPEC view adds an EDGE slider (0-100%) when an inclusive frame
range is selected. At zero, harmonic painting still writes uniformly to each
frame as before. At 100%, the first and last selected frames remain exactly
untouched, while the middle receives the full brush stroke; intermediate
frames blend the harmonic gains in dB space. Short one- and two-frame ranges
stay full-strength. A miniature strength rail above the frame thumbnails
shows the taper before painting. The EDGE control does not change the sound
by itself, and the brush gesture still makes only one undo step. The level
blend is replayed from the gesture's frozen baseline, including on long drags.

## 0.43.0 Spectral profile clipboard

In expanded SPEC, COPY stores all 127 relative harmonic magnitudes from the
selected frame. Choose a destination frame or range, set BLEND, and toggle
PREVIEW to compare the proposed spectrum against the real frame's pale
original-level ticks. PREVIEW does not change the AU sound or consume undo.
PASTE blends those ratios into existing harmonics while preserving their
individual destination phases. The EDGE setting tapers the paste across a
selected frame range. Silent destination harmonics stay silent unless SEED is
explicitly armed, in which case new harmonics use a predictable sine phase.
SEED resets off after PASTE. COPY and PREVIEW are in-memory editor state, not
part of the preset. One PASTE takes one undo step and stored sound state
round-trips through existing presets.

## 0.44.0 Harmonic-span spectral transfer

After COPY, Shift-drag across the expanded SPEC bars to choose an inclusive
harmonic span, across whichever page is open. The selected bins have a warm
highlight and the H-first-to-last span appears above them. PREVIEW shows
three readings together: amber source-profile ticks in the chosen span, pale
destination ticks, and filled proposed result bars. Only the selected
harmonics transfer on PASTE; every harmonic outside the span keeps its
relative magnitude and phase. SEED remains the explicit gate for silent bins,
BLEND scales the transfer, EDGE tapers a selected frame range, and the paste
is one undo step. COPY resets the span to all 127 harmonics.

## 0.45.0 Spectral span feather

The expanded SPEC profile controls add FEATHER (0-8 harmonics) below BLEND.
It softens a selected span's transfer just outside each harmonic edge: a
three-bin feather gives the nearest outside harmonic 75% transfer strength,
the next 50%, and the last 25%, while all selected harmonics stay at full
strength. Amber span shading and source ticks fade across the same ramp, so
PREVIEW shows the exact region that PASTE will change. Zero is the previous
hard boundary. Destination phases, the SEED gate, selected frame-range EDGE,
and one-step undo behavior remain unchanged.

## 0.46.0 Spectral transfer polarity

REVERSE is a non-destructive, in-memory option for a copied spectral profile.
Within the selected harmonic span it reflects source ratios low-to-high: H4
reads source H16, H5 reads H15, and so on. The feather bins just outside the
span keep their own original source ratio but retain their tapered transfer
strength. PREVIEW's amber ticks show exactly those source ratios and the
filled bars show the prospective result. BLEND, frame-range EDGE, explicit
SEED for silent bins, phase preservation, and single-step undo stay intact.
A new COPY starts normal again; neither the switch nor its clipboard state is
serialized. The resulting edited wavetable is saved in the usual preset state.

## 0.47.0 Span page-handoff

Shift-drag a copied profile span across the expanded spectrum, then move onto
another 32-bin page chip without releasing the mouse. The viewport changes
and the anchored span reaches the nearest bin of that page (H33 when moving
right from page 1, H32 when moving left from page 2). Move back over the bars
to place the exact far endpoint. Page 4 ends at H127, never H128. The span
readout keeps its absolute harmonic numbers; the shading and source/proposed
ticks show only the visible part of that same span on each page. Ordinary chip
clicks and wheel page navigation never change the span. This is editor-only
navigation: the original DSP, REVERSE, feather, SEED, EDGE, phase and undo
semantics are unchanged.

## 0.48.0 ARP step ratchets

Each ON step in the ARP pattern has a top-edge count badge. Click the badge
to cycle 1-4 strikes of that step's selected note at its existing velocity.
The strikes divide that step's length evenly, with GATE applied to each
substep. The next arp note is still selected once per step, not once per
strike. REST remains silent, a following TIE suppresses retriggers so it
holds through, and non-pattern playback is unchanged. In HOST SYNC the
ratchets follow the host beat and swing grid; the step boundaries stay put.
The new optional `arpr` line stores 16 counts only when one differs from 1.
Old `arpx` lines stay byte-identical and load with one strike per step.

## 0.49.0 ARP octave lane

Each ON step may shift its selected pitch by -1, 0 or +1 octave; ratchets repeat the shifted pitch. TIE holds the previous sounding pitch and REST stays silent. The lower step badge cycles the octave, while the top badge still controls ratchets. An optional `arpo` line stores non-default shifts without changing `arpx` or `arpr`, so older patterns and factory sounds retain their values.

## 0.50.0 ARP step chance

Each ON step can play with 100, 75, 50 or 25 percent chance. Click the center step badge to cycle it; unchanged 100% cells stay visually quiet. A skipped ON acts like REST and cannot be revived by a following TIE. Fixed mode hashes absolute step cycles, so host seek and rewind repeat; the LIVE switch opts into changing passes. The optional `arpc` line stores chance and LIVE without changing old pattern data or factory sound.

## 0.51.0 Noise character

The FILTER 2 + SUB page adds CLASSIC, AIR, GRAIN and DUST character with continuous COLOR. CLASSIC uses the old NOISE TONE and renders old presets byte-identically. The new modes shape airy hiss, stepped grains or soft dusty impulses; COLOR changes each mode. `noisex` is optional, leaving the old `noise` line and 40 AU parameter IDs unchanged.

## 0.52.0 Noise color modulation

NOISE COLOR is append-only destination 32 in the modulation matrix. Route an LFO, MSEG, velocity or macro to sweep the AIR, GRAIN or DUST COLOR control within 0-100%; CLASSIC ignores it. Routes use the existing `route` line, with no new AU parameter ID. Old factory presets keep their exact sound and state.

## 0.53.0 Stereo noise WIDTH

FILTER 2 + SUB adds a compact noise WIDTH control. At zero, the original single noise source and its mono rendering remain untouched. Above zero, an independent right-hand noise stream opens the stereo field, including in HQ mode; `noisew` is optional so old preset lines and the 40 AU parameter IDs stay unchanged.

## 0.54.0 Live matrix metering

Every occupied matrix row now has a thin white live marker on its depth bar.
The marker is signed and normalized to that destination's full depth: left
of center means negative contribution and right means positive. The fixed
colored bar and white handle remain the editable route amount. Voice-route
meters show the largest absolute contribution from active voices during the
last render block, including response curve and AUX scaling; they clear after
release. FX macro routes show their static contribution even without notes,
while FX LFO routes follow the rack's block-rate activity. Unsupported
source/destination pairs show no activity. The AU publishes all 16 values to
its hosted editor and the standalone uses the same engine readings. Meter
work does not add modulation or change rendered audio.

## 0.55.0 Noise BURST

FILTER 2 + SUB has a noise-only BURST control. OFF preserves the original
sustained noise, including factory sounds. Set 5-500 ms to fade the noise from
full to zero after each note onset; repeated notes retrigger it. The burst
affects both noise channels equally, including HQ output, without changing
oscillators, sub, filter or the main amp envelope. It also follows a routed
NOISE level when the base level is zero. The optional `noiseb <seconds>` preset
line stores the setting; no AU parameter IDs were added.

## 0.56.0 Matrix peak hold

A small colored pip above each matrix activity bar catches short route peaks
for 180 ms, then fades over roughly 420 ms while the live white indicator
continues to follow the latest signed render value. Opposite-polarity peaks
can replace a weaker hold immediately. Holds reset on route or preset edits,
and vacant or unsupported routes do not show them. This is only display
ballistics in the standalone and AU editors: no new sound or preset state.

## 0.57.0 Noise burst shape

The optional note-on noise burst now has an attack fraction (0-80% of the
fixed total duration) and a decay curve (-1 fast, 0 linear, +1 slow). The
SHAPE chip opens a larger editor over the modulation matrix with a live
amplitude preview, leaving the crowded FILTER 2 + SUB controls in place.
With BURST OFF, noise remains sustained and ignores both shape settings.
Older bursts retain their byte-exact linear behavior; old presets and the 40
AU parameter IDs stay unchanged. The optional `noiseenv <attack> <curve>`
line saves non-default shaping.

## 0.58.0 Stereo output and saturation

The Engine header now shows the left and right output levels after MUEW's
soft master. A brief amber SAT badge means that the signal entering that
master reaches the soft-saturation region. This is a tone/headroom hint,
not a clip warning: MUEW's `tanh` master bounds its finite output below
full scale, and a plugin cannot see clipping later in the DAW or interface.
No new preset state or AU parameter IDs. The standalone and AU show the
same actual rendered output, including FX and preset trim.

## 0.59.0 Matrix modulation range

Each active matrix route now shows a short signed min/max trace beneath its
editable depth bar. The engine measures both extremes of real voice samples
and rack LFO ticks, including a bipolar LFO crossing zero within one render
block; the editor retains roughly half a second of recent extremes. The thin
live indicator, short held peak pip, and bright depth handle remain separate.
The trace is display-only, clears on route or preset changes, and adds no sound
state, factory presets, or AU parameter IDs.

## 0.60.0 Noise burst tempo sync

The optional noise-only burst duration can use the shared tempo divisions
(1/1, 1/2, 1/4, 1/8, 1/16, triplets, dotted quarter or two bars). TIME in
the larger BURST SHAPE panel steps through FREE and those divisions. FREE
remains the default 5-500 ms control in FILTER 2 + SUB; touching that bar
returns to FREE without changing attack or curve. A synced burst follows
valid host tempo, whether or not transport is playing. If no usable host
clock exists, it uses 120 BPM deterministically, including after a previously
valid clock disappears. The optional `noisebsync <division>` preset line
preserves the FREE duration for switching back; old preset sound and the
40 AU parameter IDs remain unchanged.

## 0.61.0 Output detail

Click the Engine meter (outside its HQ switch) to open a read-only output
panel. LEFT and RIGHT show the actual latest post-master block peaks in
dBFS, plus a one-second held peak per channel. Silence reads -∞. SAT is
explained as MUEW's pre-master soft saturation, never a downstream DAW
clip warning. The separate panel avoids crowding the header, and it cannot
change the sound or add an AU parameter. Factory sounds and all 40 AU IDs
remain unchanged.

## 0.62.0 Noise burst note latch

A synced noise BURST takes its duration from the current host BPM at note-on.
A tempo jump or loss of the host clock cannot retime that hit while it plays;
the next note picks up the changed BPM or deterministic 120 BPM fallback. The
FREE duration, existing preset format, 108 factory sounds, and all 40 AU
parameter IDs stay the same.

## 0.63.0 Noise burst velocity response

The BURST SHAPE editor adds VEL DEPTH from 0 to 100%. At zero, existing
noise is unchanged. With an enabled burst, nonzero depth makes soft notes'
noise layer quieter while hard notes retain their level; the existing voice
velocity still applies to all layers. The shape preview shows a velocity-60
example. This is optional `noisebvel <depth>` preset state, default zero;
old presets and sustained-noise sounds stay byte-identical, and no new AU
parameter is published.

## 0.64.0 Noise burst velocity time

The BURST SHAPE panel adds VEL TIME. At zero, the exact old duration and
audio remain. Above zero, softer notes shorten the burst up to their note
velocity fraction while maximum-velocity hits keep the chosen FREE or synced
time. Each computed duration is latched at note-on, so host tempo jumps and
clock loss never retime a playing hit; the next hit uses the latest valid BPM
or 120 BPM fallback. This is optional `noisebvtime <depth>` preset state with
default zero, no new AU parameter ID, and no change to sustained noise.

## 0.65.0 Noise burst keyboard time

KEY TIME is a bipolar depth in BURST SHAPE. Positive settings shorten
higher-note bursts and lengthen lower-note bursts; negative settings reverse
that slope. C4 is neutral. The multiplier is bounded to one-quarter to four
times the FREE or synced duration, calculated at note-on after any velocity
time scaling and latched for the whole note. A host tempo jump cannot change
the active hit; a new note uses the current BPM or the 120 fallback. Depth
zero skips the new math, preserving existing audio. The optional
`noisebkey <depth>` line defaults to zero; no new AU parameter ID.

## 0.66.0 Noise burst velocity color

VEL COLOR is the sixth and final BURST SHAPE control. With an enabled burst
in AIR, GRAIN or DUST, soft notes can pull the existing COLOR toward a darker
texture while hard notes keep the original setting. This note-local offset
combines with the existing matrix NOISE COLOR route before clamping to the
0-100% range. At zero depth, old renders remain byte-identical. CLASSIC and
BURST OFF ignore the new depth. The optional `noisebvcolor <depth>` preset
line defaults to zero, without adding an AU parameter ID.

## 0.67.0 Stereo delay wet ducking

DELAY now has DUCK depth and RELEASE below its existing six controls in the
compact eight-row FX detail layout. A linked detector follows the input at
the delay's current rack position. A 3 ms attack pushes only the wet taps
down during a dry hit; the adjustable 20-1200 ms release brings echoes back
between hits. The feedback write occurs before the wet gain, preserving the
delay's tail. At zero depth, the detector is skipped and the old audio path
is byte-identical. The optional `delayduck <depth> <release ms>` preset line
is absent for old sounds and needs no new AU parameter ID.

## 0.68.0 Sweepable EQ middle bell

The three-band EQ keeps its low 180 Hz shelf and high 6 kHz shelf fixed, but
the middle bell can now move between 200 Hz and 8 kHz with Q from 0.3 to 8.
The five-row compact detail shows LOW, MID GAIN, HIGH, MID FREQ and MID Q
beside a response plot calculated from the same biquad coefficients used by
the audio engine. Defaults remain 1.2 kHz / Q 0.9, so existing factory
sounds and old preset audio keep their bytes. An optional `eqmid <hz> <Q>`
line saves non-default values; no new AU parameter ID is published.

## 0.69.0 Chorus stereo spread

The CHORUS detail adds a fifth SPREAD row. At 0%, left and right modulation
taps move together; 50% is the original 90-degree quadrature stereo phase;
100% moves the right tap 180 degrees away from the left. This changes only
the right tap's phase, not its gain, delay range or rate. Old sounds use the
50% default and retain their audio bytes. A non-default value saves as an
optional `chorusspread <0..1>` preset line with no new AU parameter ID.

## 0.70.0 ARP per-step gate

STEP EDIT switches the 16-cell pattern lane to select-only. A selected ON cell
can follow the global GATE or store a 5-100% override with the larger inspector
slider. REST and TIE are read-only. The gate of the originating ON note also
controls ratchet subhits and the terminal release after a TIE; a TIE never
replaces that gate with its own value. `arpg` is optional and absent in old
patches, which continue to inherit global GATE. The AU parameter set stays at
40, and old factory sounds remain unchanged.

## 0.71.0 ARP per-step semitone offset

STEP EDIT pairs the existing GATE row with a PITCH row. ON steps can offset
the selected note by -12 to +12 semitones, with a centered slider and RESET 0;
REST and TIE stay read-only. The semitone shift combines with the existing
octave shift after source-key velocity selection, then clamps to MIDI 0-127.
Ratchets repeat the resulting pitch and TIE holds it. The optional `arps` line
is omitted for neutral patterns, keeping older patches and factory audio
unchanged. No new AU parameter ID is published.

## 0.72.0 ARP pattern actions

The STEP EDIT preview has an ACTIONS subview with COPY, PASTE, ROTATE left,
ROTATE right and UNDO. Each action handles the complete seven-field step tuple
(kind, velocity, ratchet, octave, chance, gate, pitch), even on REST/TIE cells.
Only the active LEN steps rotate; dormant cells do not move. PASTE and ROTATE
are atomic undo actions, while COPY changes only the editor clipboard. A preset
switch or external state change clears clipboard/history. This editor-only
feature adds no preset key or AU parameter, and does not restart the arp clock.

## 0.73.0 PHASER stereo spread

The PHASER detail panel adds SPREAD below MIX. At zero the two allpass
sweeps align, at 50% the existing quarter-cycle offset is unchanged, and at
100% the right sweep is half a cycle ahead. A double-click returns to 50%.
Only a nondefault value writes `phaserspread <0..1>` to the preset; old files
retain their text and sound, and no AU parameter ID is added.


## 0.74.0 ARP ACTIONS feedback

The ACTIONS footer shows the copied source cell and undo count. COPY A STEP
means the clipboard is empty; COPY preserves the original source number after
PASTE or ROTATE. Preset switches and external state adoption clear both the
clipboard and its source number. No sound, preset or AU parameter changes.


## 0.75.0 ARP REST/TIE read-only inspector

Selecting REST or TIE in STEP EDIT shows dim GATE/PITCH rails without
slider thumbs, and labels both right-hand value slots with the step kind.
Buttons are muted; clicks remain inert. The seven stored fields are not
removed or reset, so a later COPY/PASTE still transports hidden data.
ON steps retain the original live two-row inspector.


## 0.76.0 ARP pitch indicators

The bottom kind strip of each active ON pattern cell shows a signed semitone
offset when nonzero, in cyan. A neutral ON cell looks exactly as before.
REST/TIE keep their kind marks, even if hidden pitch data is stored. No
sound, preset format, AU parameter or click-target changes.


## 0.77.0 ARP dormant-step inspector

An out-of-LEN selected step says OUTSIDE LEN and presents dim, inert rails
instead of showing or changing its hidden gate and pitch. Changing LEN later
reveals the original step fields intact. This is editor-only behavior; no
sound, preset format, or AU parameter changes.

## 0.78.0 Keyboard focus safety

Standalone piano shortcuts run only while the editor itself owns key focus, the window is key, no editing panel is open, and no Command, Control or Option modifier is held. Text entry remains native, with a visible search-field focus ring. The editor tracks exact note-on pitches per physical key, releasing them on key-up, focus loss, window deactivation and overlay entry. Escape dismisses the top layer (output readout, full browser, wavetable editor, then a small edit panel); Return closes only the read-only output panel. AU host keys remain host-owned. The macOS keyboard host test checks key suppression, focus transitions, note releases, and captures text, output, browser focus pixels.

## 0.79.0 Preset browser keyboard cursor

The full browser's Up/Down keys propose a preset by stable slug, with an amber
outlined row distinct from the loaded green row. No sound changes until Return
loads that exact visible slug, leaving the browser open. A refilter clears a
removed cursor rather than picking a different sound. Escape closes and drops
the proposal. The search field keeps native text navigation; AU keys remain
host-owned. This editor-only change adds no preset format or AU parameters.

## 0.80.0 Search-to-list keyboard handoff

Tab from the full browser's Search field transfers keyboard focus to the result
list without selecting or loading a sound. A visible teal list-region outline
separates this state from Search's own focus ring. Up/Down continue from an
existing slug-stable amber cursor or choose first/last only when none exists;
Return still commits only the visible cursor. Shift-Tab returns to Search with
its query intact. Search keeps native text, arrows, Return and Escape. The AU
host still owns plugin keys. No DSP, preset format or AU parameter changes.

## 0.80.1 Search caret proof

The hosted keyboard-focus harness puts the native Search caret inside a filtered
query, tabs to the list and Shift-Tabs back, then checks the exact text selection
range. Both Search-focused states are captured beside the list-focused frame.
No DSP, preset schema or AU parameter IDs change.

## 0.81.0 Browser accessibility pilot

The architecture and limits are mapped in `docs/accessibility-architecture.md`.
The native Search remains native; the custom-drawn browser exposes a named
virtual results list with only its visible rows. Row names include exact preset
name, category, position, and separate proposed/loaded states. Merely querying
or traversing rows is inert; deliberate row press resolves a current, visible
slug before loading it. A row held across a refilter is invalid. The macOS
host harness queries the AppKit tree, states and actions. This is a browser
results pilot, not a claim that the full instrument supports VoiceOver.

## 0.82.0 External AX trust-boundary probe

A separate executable queries the standalone window over AXUIElement IPC for
its native Search and named preset results, then probes row details and press.
The application posts focused layout, selection and value notifications when
results, cursor and loaded state change. CI records the external probe log. A
macOS Accessibility/TCC refusal is logged as blocked, not rebranded as a pass;
see `docs/voiceover-manual-checklist.md` for the manual VoiceOver/AU-host pass.
The in-process 0.81.0 evidence remains the limit until IPC actually succeeds.

## 0.83.0 Accessible browser navigation

The native Search and virtual result list are joined by stable virtual Bank,
Type, and sort controls, plus Close. Their press actions use the same browser
helpers as mouse clicks. The labels report selected state; controls survive a
refilter or sort while a closed browser removes them and invalidates retained
handles. The macOS keyboard host and separate AX IPC client probe filtering,
ordering, inert traversal, stale actions and list updates. Save, import, export,
ratings, dialog focus return, VoiceOver speech and AU-host AX traversal remain
outside this slice.

## 0.84.0 Loaded-sound browser actions

Favorite, five rating choices, Save, Import and Export now share mouse and AX paths. Detail controls name the loaded sound, survive refiltering and refuse stale actions after load/close. Native file dialogs are exercised through launch/cancel/return. Desktop proof watchdogs bound modal and IPC waits independently of the main loop. VoiceOver speech and real AU-host AX traversal remain unclaimed.

## 0.85.0 Matrix trace reset

RESET TRACE below the matrix clears peak-hold and signed range-history displays across all 16 slots without changing the live indicator, route depths, sound or running notes. The next live poll can capture fresh history. This is editor-only state, not a new parameter or preset field.

## 0.86.0 Type-to-refine

A printable key from the standalone browser result list appends to the existing query in native Search and returns text focus there. The actual AppKit text event is used, including Shift; deletion and later input remain native. No sound is loaded or note played. Tab returns to the list without inventing a proposed row. Modified shortcuts and function keys are excluded. The AU still leaves keyboard routing to its host.

0.87.0 adds a MIN RATING floor to the standalone browser sidebar: five stars at the bottom-left set the lowest personal rating shown, clicking the lit star clears it, unrated sounds are hidden while a floor is set, and sidebar counts, favorites, search, tags and sorts all compose with it. Each star is also a labelled Accessibility button. The compact chips clear the floor. No DSP, preset or AU parameter changes. macOS pixels and AU host proof are pending CI.

0.88.0 adds CLEAR FILTERS to the standalone browser header. It appears only while a bank, type, favorites, character tag, rating floor or search is active. One click (or AX press, "Clear all filters") resets all of them together and empties the Search field, keeping sort and ratings and loading nothing. No DSP, preset or AU parameter changes. macOS compile and pixels are pending CI.

0.89.0 adds SURPRISE ME to the standalone browser header. One click (or AX press, "Surprise me, load a random sound from N shown") loads one random sound from the list currently shown, so every filter narrows the dice. It never repeats the loaded sound when another choice exists, does nothing on an empty list, and plays no note. No DSP, preset or AU parameter changes. macOS compile and pixels are pending CI.

0.90.0 adds BACK to the standalone browser header, beside SURPRISE ME. Every load records the sound it replaced (up to 32). BACK reloads them newest first without adding to its own history, and is inert with nothing earlier. It plays no note. AX label: "Back to previous sound, available / nothing earlier". No DSP, preset or AU parameter changes. macOS compile and pixels are pending CI.

0.91.0 makes the heart at the right edge of each browser row a favorite toggle. Unfavorited rows show a dim outline heart. Clicking it flips that sound's favorite without loading, selecting or playing anything. Rows keep loading on any other click, and the rating stars are unchanged. No DSP, preset or AU parameter changes. macOS compile and pixels are pending CI.

0.92.0 lets the browser table sort in both directions. Clicking the active column header (or pressing its Accessibility button) reverses it, and the arrow flips to match. Choosing a different column starts at that column's natural direction: Bank, Name and Type ascending, Rating descending. Ties keep bank order either way, and the direction is saved between launches. AX labels read "Sort: Name, selected, descending". No DSP, preset or AU parameter changes. macOS compile and pixels are pending CI.

0.93.0 adds LFO RATE modulation: four new matrix destinations, LFO1 RATE to LFO4 RATE (numeric IDs 33-36, appended). Amount is in octaves of rate, so +1.00 oct doubles the speed, full scale is plus or minus four octaves, and synced LFOs scale their synced rate the same way. Any voice source can drive them (velocity, key, wheel, aftertouch, bend, macros, envelopes, MSEGs, or a lower-numbered LFO). An LFO cannot drive its own or a lower-numbered LFO's rate, so rate routing has no cycles; such a route shows LOWER LFO ONLY and is ignored. Non-LFO sources are read one sample late. Existing presets and projects render sample-identically, and no AU parameters were added. macOS compile and pixels are pending CI.

0.94.0 adds envelope TIME modulation: AMP ENV TIME, MOD ENV TIME and ENV3 TIME (numeric IDs 37-39, appended). Each scales that envelope's attack, decay and release together by 2^octaves, so +1.00 oct makes the envelope twice as slow and -1.00 oct twice as fast (full scale plus or minus four octaves, clamped at 16 times either way). Any voice source can drive them, for example velocity for harder notes with a snappier attack. An envelope cannot drive its own time (shown as NOT ITSELF); sources are read one sample late. Unrouted envelopes and all factory presets render sample-identically, and no AU parameters were added. macOS compile and pixels are pending CI.

0.95.0 adds a LEVEL A matrix destination (numeric ID 40, appended) so oscillator A can be modulated the way LEVEL B already is. The amount is an offset around unity gain: -100% mutes oscillator A, -50% halves it, +50% is 1.5 times, clamped at 1.5 times. Mix balance still works as before and LEVEL A multiplies on top. Unrouted sounds and all factory presets render sample-identically, and no AU parameters were added. macOS compile and pixels are pending CI.

0.96.0 adds UNDO and REDO for sound edits in the editor. Every knob, matrix, menu and panel edit made in the MUEW window is a step in a history of up to 64 snapshots (heavy user wavetables evict older steps sooner). One drag is one step, however long it runs. Cmd-Z undoes, Shift-Cmd-Z redoes, and two small UNDO / REDO buttons under the MUEW logo do the same and dim when there is nothing to do; both are exposed to accessibility as "Undo last edit, available / nothing to undo" and "Redo edit, available / nothing to redo". Loading a preset or opening a different sound starts a fresh history, and a new edit after an undo discards the redo branch. The wavetable editor keeps its own local Cmd-Z while it is open. Limits to know: only edits made in the MUEW editor are undoable. Parameter changes from the host (DAW automation, the generic host UI, MIDI-mapped controls) are not recorded and cannot be undone here; if the host changes the sound you are editing, the history is kept, but undoing an earlier step also restores the older values of any parameters the host changed since. Sounds, factory presets and AU parameters are unchanged. macOS compile and pixels are pending CI.

0.97.0 adds a REVERT button next to UNDO and REDO. It returns an edited sound to the loaded preset in one step, and it is itself undoable: Cmd-Z brings the edits back. It dims when the sound already matches the loaded preset, and is exposed to accessibility as "Revert to loaded sound, available / nothing to revert". It only reaches editor edits and the loaded preset; host automation is still outside the history. UNDO and REDO now also decide the edit marker (the asterisk after the name) by comparing with the loaded preset, so undoing back to the loaded sound clears it. macOS compile and pixels are pending CI.

0.98.0 gives the standalone app a real macOS menu bar. MUEW menu: About MUEW, Hide MUEW (Cmd-H), Hide Others, Show All, Quit MUEW (Cmd-Q). Edit menu: Undo (Cmd-Z), Redo (Shift-Cmd-Z), Revert to Loaded Sound, Cut, Copy, Paste, Select All. Window menu: Minimize (Cmd-M) and Close (Cmd-W). Before this the standalone had no menu bar, so Cmd-Q, Cmd-H, Cmd-M and Cmd-W did nothing and the menu bar showed nothing for MUEW. Undo and Redo are enabled only when there is something to undo or redo, and while the wavetable editor is open they drive its own local history exactly as Cmd-Z does. A focused text field (preset search) keeps its own text undo. The AU plug-in is unchanged: it never owns a menu bar. macOS compile and pixels are pending CI.

0.99.0 makes the standalone playable from hardware MIDI. On launch it connects every MIDI source (USB keyboards, controllers, virtual ports, IAC), follows plugging and unplugging, and listens on all channels: notes with velocity, mod wheel (CC1), sustain (CC64), pitch bend, channel and polyphonic aftertouch, and CC120 / CC123 all sound / notes off. The controller map is the AU's, so the matrix performance sources (wheel, aftertouch, bend, key) respond the same way in both. SysEx, program change and other controllers are ignored, and a message cut short is dropped rather than half-played. The computer keyboard still plays as before. The AU is unchanged (the host owns its MIDI). macOS compile and a real device test are pending: CI proves the path with a virtual MIDI source, not with a physical keyboard.

0.100.0 makes the standalone reopen on the sound you quit on. Quit (or switch away) and the current sound, including unsaved edits, is stored in the app's preferences; the next launch restores it as the same library sound with edits still marked, or as a plain edited sound when it was not a library one. A stored sound that can no longer be read is ignored and the usual starting sound loads. Not stored: undo history (a fresh launch starts a clean one), the browser filters, and anything for the AU (the host saves the plugin's own state). Setting MUEW_NO_SESSION skips restore and save. Linux tests cover the stored format; the app wiring is compile-checked and launch-checked by CI only.

0.101.0 adds a CI relaunch proof for session restore: the packaged app is launched four times against a throwaway home. Launch 1 edits the cutoff and quits; launch 2 must come back on the same sound with the edit and the edited mark; launch 3 stores garbage; launch 4 must fall back to the plain starting sound. Each launch has a 60 s watchdog inside the app and an 80 s bound in the script. The hook is MUEW_SESSION_REPORT / MUEW_SESSION_STEP and does nothing unless set.

0.102.0 handles MIDI program change in the standalone (this replaces the 0.99.0 note that it is ignored): program N loads factory sound N (programs 0 to 107, the same numbers the AU lists; higher numbers do nothing). The load happens on the main thread, like clicking the sound, so the editor shows it and it is undoable like any load. User presets are not addressable by program number. The AU is unchanged, the host owns program change there.

0.103.0 remembers where the standalone window was left and reopens it there (position only; the editor has a fixed size). Not in effect when MUEW_NO_SESSION is set. CI cannot move a window, so this is a one-line AppKit frame autosave that is compile-checked only.

0.104.0 makes MIDI CC7 (channel volume, any channel) the standalone's output volume: a squared taper, 127 is exactly unity and untouched means no processing at all, so a controller's volume slider no longer does nothing. It is applied after the synth and ramped over each audio block, so moves do not click. The level meters still show the synth's own output, before this gain. The gain lives in the app, not in any sound: it is not saved in presets, not in the session, not an AU parameter, and the AU is unchanged (the host has its own faders). Resets to full on each launch.

0.105.0 moves the 0.104.0 volume gain into src/output_gain.h (same behavior) so it can be proven: the Linux test checks unity is bit-identical and the ramps land on target, and the CI virtual MIDI source now also sends a CC7 and checks the whole chain on macOS (the event arrives parsed as 5th of 5, sets the gain target to its tapered value, and a rendered block ramps to it and then holds).

0.106.0 keeps the standalone audible across audio device changes. When headphones, AirPods or a display's speakers connect or disconnect, macOS stops the audio engine; until now the app then stayed silent until relaunch. It now listens for the engine's configuration-change notification and restarts the engine on the new route. CI has a proof: the packaged app stops its engine, posts that notification and must report the engine running again. A runner with no audio device prints SKIPPED, not passed. A real headphone plug-in is not tested.

0.107.0 makes hardware performance visible in the standalone. Until now the editor's performance display (the mod wheel, pressure and bend readouts the matrix sources show, the last note, the sustain light) was only fed by the AU; in the standalone a MIDI keyboard moved the sound but the display stayed dead. The MIDI thread now records those values and the existing 15 Hz UI timer shows them; computer-keyboard notes count as the last note. The CI virtual-source proof feeds the arrived events through the same tracker into the editor and reads the display text back (wheel 1.000, bend 1.000, note 60, sustain, pressure).

0.108.0 stops notes sticking when a MIDI controller is unplugged. A key or the pedal held at the moment of unplugging never sends its note-off, so the note used to sound until restart. When the standalone sees a connected source disappear it now releases all notes once (the same all-notes-off as CC123, which also lifts a held sustain). This cuts any computer-keyboard note that is down at that instant, which is the safe direction. The CI virtual-source proof creates the source, disposes it and checks the input drops it and delivers exactly one all-notes-off.

0.109.0 adds Edit > All Notes Off (Cmd-period) to the standalone: one keystroke silences everything, including a note stuck from a flaky controller, a held sustain and any computer-keyboard note down. It releases the editor's held keys, then asks the engine for all-notes-off (the same call as MIDI CC123) and clears the sustain light. The AU is unchanged; the host owns its own notes. The focus host checks the menu item (title, Cmd-period, action) and that invoking it reaches the host exactly once.

0.110.0 gives the app an icon (until now the Dock and Finder showed a generic one): a dark rounded tile with a glowing teal wave and an amber playhead, drawn in the editor's own palette. The 1024 px artwork is committed as base64 text (app/icon/MUEW-icon-1024.png.b64, generator beside it) so a patch can carry it; the DMG script expands it to an .icns with sips and iconutil, names it in Info.plist, and CI checks the .icns exists and renders back to a picture, which is uploaded as MUEW-<version>-app-icon.png for a look. The plug-in has no icon (Audio Units show the host's own).

0.111.0 fixes the small-size look of the icon: the 16, 32 and 64 px images (Dock at small size, Finder lists, the title of the DMG window) now come from a second, thicker-stroke artwork (app/icon/MUEW-icon-small-256.png.b64, same generator with MUEW_STROKE=0.085) because the fine line of the large icon vanishes there; 128 px and up are unchanged. CFBundleVersion is now 111 (it had stayed at 73 while the marketing version moved).

0.112.0 lets the standalone open .muew sound files: double-click one in Finder, drop it on the Dock icon, or "Open With" MUEW. The app is registered for the .muew extension, imports the file into the user sounds exactly like the Import button (author kept, "Imported" if none, never overwriting), and loads it. If MUEW was not running, the file opens after the normal start. CI writes a minimal sound file, launches the packaged app with it, and requires that the loaded sound is that file, unedited, and that it landed in the user folder; the Linux test covers the import itself. Not tested in CI: LaunchServices actually routing a Finder double-click (the delegate method is the standard openFile path, but the proof drives the same import through a launch hook).
