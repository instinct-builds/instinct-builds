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
