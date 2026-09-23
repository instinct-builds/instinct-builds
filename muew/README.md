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
