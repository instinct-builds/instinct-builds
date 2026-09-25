# Instinct Builds — Product Boundaries and Roadmaps

Working date: 2026-09-10. Owner: PM/principal-engineer task agent.

The three products take Roll20's character sheet, Xfer Serum 2, and Adobe
Stock as functional reference points. The accepted scope is lawful original
products: original code, original branding, and original content, with
functional parity as inspiration only - never literal 1:1 duplication. This
document is the durable scope contract for all three.

## Hard boundaries (all products)

- No copied proprietary code, UI artwork, branding, or trademarks.
- No copyrighted content: no Adobe Stock assets, no Serum presets/wavetables,
  no publisher rulebook text.
- No scraping of any asset database. Asset products work with the user's own
  files and properly licensed sources only.
- Game-mechanics math and general synthesis techniques are functional ideas
  and are fine; expression (names, text, art, code) must be original.

## Product 1 — ARCHITER (character-sheet builder) — IN BUILD

Comparable core workflow to a Roll20-style sheet: create/edit characters,
auto-computed stats, dice automation, sheet layout customization, export.

Status: core engine built and tested (24 passing tests); SwiftUI macOS app
written; DMG packaging script ready (runs on macOS).

Suite status 2026-09-10 evening: ARCHITER 43/43 tests (v0.3 custom rulesets
+ templated blocks done); MUEW 95 checks (DSP, FX, licensing, preset bank,
wavetable editor core); ASSSETS 34/34 tests (library, thumbnails/palette,
smart collections, PSD composite previews).

Roadmap:
- v0.1 (current): abilities, saves, skills, vitals, attacks, inventory,
  notes; block builder (reorder/hide/resize); dice roller; MD/HTML export;
  JSON autosave.
- v0.2 (done): PDF export with print layout (own PDF writer, verified with
  poppler); undo/redo (per-character stacks, Cmd-Z in the app). Remaining:
  multiple characters window.
- v0.3 (done): custom rulesets (user-defined abilities/skills with
  score/modifier tables; two original built-ins: Starfarer and Gumshoe),
  templated blocks ({placeholder} rendering incl. custom abilities, unknown
  tokens shown as [?name]), carried-over scores on ruleset switch,
  export/PDF support, legacy-JSON compatibility. Remaining: iCloud sync.
- v1.0: signed + notarized DMG, app icon, Sparkle auto-update.

## Product 2 — MUEW (software synthesizer for Ableton Live)

Comparable core workflow to Serum 2: wavetable synthesis as a plugin inside a
DAW. Honest constraints:
- Ableton loads AUv2/VST3 plugins on macOS. Both require Apple's or
  Steinberg's SDKs/headers (VST3 also carries a license agreement). "No APIs"
  is not literally possible for a DAW plugin — the plugin format IS an API.
  We use the SDKs but write 100% of the synth ourselves.
- Distribution "on up to 3 devices" = our own simple license-key scheme, not
  iLok-style DRM.

Roadmap:
- Phase 1 (can start on Linux): DSP core in C++ — wavetable oscillator
  (mipmapped, band-limited), 2 multi-mode filters, 4 envelopes/LFOs,
  modulation matrix, polyphony + voice management, effects (chorus, delay,
  reverb), WAV render test harness. Original wavetables generated
  mathematically.
- Phase 2 (macOS): AUv2 wrapper via Core Audio SDK so Ableton sees it as an
  instrument; preset system; minimal native UI.
- Phase 2b (done on Linux): offline license keys (3 activations, HMAC-signed)
  + factory preset bank of 8 original presets; 67 tests passing.
- Phase 2c (done on Linux): wavetable editor core - custom tables from
  harmonic (additive) specs or freehand samples, in-repo radix-2 FFT,
  band-limited mipmap rebuild per octave, morph between tables, .muewwt
  text serialization, custom shape slots the synth oscillators use directly.
  20 checks passing (95 total).
- Phase 3: full wavetable editor UI, signed installer DMG (licensing already
  built and tested; the DMG embeds the activation check).

## Product 3 — ASSSETS (creative-asset manager)

Comparable core workflow to Adobe Stock's app experience: browse, preview,
and organize PSD mockups, vectors, images, video — but the library is the
user's own files plus assets from legitimately licensed sources they connect.
We do not and cannot ship Adobe Stock's database.

Roadmap:
- Phase 1: local library — import folders of PSD/AI/SVG/PNG/JPG/video,
  thumbnails, tags, collections, fast search.
- Phase 2 (done): thumbnails + color palette extraction (own PNG/BMP
  decode, own PNG encode, median-cut palette; QuickLook fallback in the
  macOS shell); smart collections (saved predicate queries with live
  membership); PSD composite previews (own decoder: 8-bit RGB/grayscale,
  raw + PackBits RLE, parsed from the documented file structure; layer
  stacks, 16/32-bit, CMYK/Lab stay QuickLook-only in the macOS shell).
  AI files are PDF-based composites - QuickLook-only, out of core scope.
- Phase 3: connectors the user authorizes to their own licensed sources;
  purchase/download flows only via the provider's official terms.

## Delivery reality

Real DMGs require a macOS build host (Apple toolchain, hdiutil, codesign).
This Linux environment compiles and tests every core engine; final .app
assembly happens via scripts/make_dmg.sh on a Mac. Progress is reported at
milestones with real artifacts, not on a fixed timer.
