# MUEW acceptance evidence (0.120.0, launch-readiness)

Run-specific facts below cite the 0.119.0 CI run 699; 0.120.0 re-runs the same gates
(product code is unchanged - harness, installer text, docs and versions only).

Every claim below maps to the proof that supports it. "CI" means the
macOS-build workflow at the tip commit. CI proofs run on a real Mac through
the real APIs, without human hands; hardware-scoped means the physical device
or a person's own machine is what remains unconfirmed.

## Proven, CI-grade

| Claim | Proof |
| --- | --- |
| DSP core correct (engine, filters, envelopes, polyphony, FX) | Linux suite: 67 binaries, 1755 checks, all green at tip |
| Factory bank intact, 108 presets, renders unchanged | factory_render_hash: 108 / 2727dea86d2a97e2 (Linux g++); CI step "Confirm factory render bytes against verified 0.52.0 on this Mac" (old-vs-new same toolchain) |
| AU passes Apple validation | CI "Build, sign, install and validate MUEW AU" (auval) |
| AU works in a DAW-style host: automation, macros, user presets, unison, FX rack | CI "Host MUEW AU editor like a DAW" + captured editor PNGs |
| Standalone app builds, designed UI renders | CI "Build designed MUEW standalone app + DMG" + "Capture MUEW designed UI proof" |
| Keyboard focus and Shift-Tab handoff | CI "Prove standalone keyboard focus and capture three focus states" |
| Session persistence across relaunch | CI "Standalone session relaunch proof" |
| MIDI learn: map persists across relaunch | CI "Standalone MIDI learn relaunch proof" |
| MIDI learn: real CoreMIDI source through learn to parameter move | CI "Standalone CoreMIDI learn proof" (virtual source; REAL PASS connected=1 learned=1 moved=1 cutoff=18000 map=74:4) |
| Clean behavior on audio device unplug | CI "Standalone audio device change proof" |
| .muew document opens via open-file path | CI "Standalone open-file proof" |
| Preset browser readable/drivable from outside the app (accessibility) | CI "Probe standalone accessibility from a separate process" |
| DMG assembles and contains expected bundle | CI "Verify MUEW app and distribution" |

## Real API paths proven in CI; physical/hardware confirmation still Spence-side

- .muew double-click Finder association and real-mouse drag import.
- MIDI learn on a physical controller. The CI proof uses a real CoreMIDI
  virtual source through the real API path; hardware scope is narrower, not
  absent - a physical controller on Spence's machine remains the open item.
- Actual shipping-DAW load: auval and DAW-style host tests pass, but no
  shipping DAW has hosted the AU yet. REAPER's EULA grants its free trial
  for evaluation purposes only (60 days from install), which does not cover
  recurring CI use as a test host; a license would be spend. This gap
  stands until a lawful host route is agreed. Live itself remains
  confirmable only on an install.

## Known limits of "finished"

- Ad-hoc signed, not notarized. Per Apple Support HT102445 ("Safely open apps
  on your Mac"), current macOS blocks unidentified-developer apps with a
  "cannot check for malicious software" dialog; the documented override in
  that case is System Settings > Privacy & Security > Open Anyway, after
  which macOS saves the exception. This is the supported procedure if a
  machine blocks the app, not a promise about every machine's policy.
  Quarantine stripping is not required and is not recommended.
  Developer ID + notarization is a public-distribution decision for the owner.
- Accessibility: the external-process AX probe RAN GREEN for 0.119.0
  (CI run 699, ax_ipc_client.log: trusted=1, ends "AX IPC PASS", no 77
  blocked marker), so checklist items 1-3 (browser list, rows, traversal,
  sort, propose/press, close) are covered by real cross-process AX evidence.
  Still open: checklist item 4 (behavior inside a real AU host, native
  save/import dialogs, focus return) and literal VoiceOver speech output -
  the probe is an AX client, not VoiceOver.

## Provenance notes

- DMG payload contents were not inspected by mounting; the old INSTALL.txt
  quarantine advice was confirmed from the source script at b5e0010 that
  generated the DMG (the Linux archive tool could not read the HFS payload).
  The 0.119.0 artifact itself downloads (run 699 artifact 11319777784,
  verified by the build relay).
- Parked scope (not defects): 24 matrix slots, microtuning E, MIDI learn for
  matrix amounts and VOL.
