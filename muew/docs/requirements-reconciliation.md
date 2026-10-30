# MUEW: original instructions vs verified coverage (0.120.0)

Reconciles what Spence actually asked for (and the changes he accepted)
against what is verified now. Internal phase labels are not the measure.

## 1. "A 1:1 duplicate of Serum 2" (accepted rescope: lawful original with comparable capability)

Comparable-capability coverage, all exercised by the Linux suite (67 binaries,
1755 checks) and/or the AU host harness on CI Mac:

- Dual band-limited wavetable oscillators with 7 warp modes, sub + noise,
  unison; ladder/comb/morph filter models with dual routing - engine tests.
- Envelopes, LFOs (drawable), dual MSEGs with looping, 12-slot mod matrix
  with curves and aux sources, MIDI performance sources - engine + host tests.
- 10-unit FX rack with reorder, per-unit editors, rack LFOs, dynamics,
  oversampling - engine + FX tests + hosted UI proofs.
- Arpeggiator with host sync, ratchets, octave shift - engine + host tests.
- 108 factory presets, user presets, favorites/ratings/search browser - bank
  tests + external AX probe (run green, CI run 699).
- Wavetable editor: additive/freehand draw, morph, undo/redo, spectral tools
  (formant/stretch/tilt/odd-even), frame tools, partial selection, brush,
  WAV/AIFF import with pitch detect, 3D frame view - engine tests PLUS the
  hosted AU editor harness driving the real UI with clicks and asserting the
  resulting AU state (open/draw/duplicate/harmonic edit, morph rebuild,
  64-frame AIFF import, spectral FORMANT/TILT apply, undo, compare, live
  morph, 76 snapshots). This is substantive UI coverage, not screenshot-only.

Known deltas vs Serum 2 class (accepted scope line, not defects): no
third-party content, original factory bank only; parked items (24 matrix
slots, microtuning E, matrix/VOL MIDI learn) are Instinct decisions, not
user requirements.

## 2. "Must work as an instrument inside Ableton Live"

- AUv2 instrument, universal binary, auval green every release; exposes all
  108 factory presets to hosts; sample-accurate MIDI timing, parameter
  automation (set/get roundtrip x40, scheduled ramps, recall through
  ClassInfo), offline-bounce invariants (finite/bounded/non-silent),
  DAW-style hosted editor session - all CI Mac, real AudioUnit API.
- NOT VERIFIED: Ableton Live itself. No shipping DAW has hosted the AU.
  REAPER was rejected as a standing lane (EULA: trial is evaluation-only,
  license is spend). This is the one original requirement without direct
  evidence; it is partially de-risked by auval + the host harness, and
  first-load confirmation lands when Spence (or any real Live install) opens it.

## 3. "Installable on up to 3 of my devices"

- Tamper-checked 3-device licensing, engine-tested (tests_license).
- DMG with MUEW.app + MUEW.component + INSTALL.txt (Apple-documented
  Open Anyway flow, no quarantine stripping); AU component version now tracks
  the app release (0.120.0/120) with a build-time drift check.
- 0.1.1 opened on Spence's Mac historically; 0.120.0 first-launch on his
  hardware is unverified but the install path is unchanged.

## 4. "Installable .dmg, not a web app" / "looks like a commercial plugin"

- DMG assembled and verified in CI; designed AppKit UI (custom knob arcs,
  lanes, browser, editors) with parent-inspected proof PNGs every batch.

## 5. "No paid APIs, no keys, no external dependencies"

- Header-only C++17, zero dependencies; the MUEW CI steps perform no network
  installs. Build uses only Xcode toolchain on the runner.

## Remaining limits (exact)

1. Ableton Live itself unverified (see 2).
2. Physical MIDI controller, real-mouse drag import, Finder double-click
   association: real-machine items for Spence; CI covers the API paths
   (CoreMIDI virtual source, pasteboard, open-file).
3. Literal VoiceOver speech output and in-host native dialogs/focus return
   (AX checklist item 4): open; cross-process AX browser coverage is green.
4. Notarization: not present; ad-hoc + Open Anyway is the documented path.
   Developer ID is a public-distribution decision for the owner.
