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
