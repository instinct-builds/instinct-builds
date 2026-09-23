# ASSSETS

An original local creative-asset manager for macOS: PSD mockups, Illustrator
files, vectors, images, and video — organized, tagged, and searchable. The
library is the user's own files and properly licensed assets only. ASSSETS
does not ship, scrape, or mirror anyone else's stock database.

## Phase 1 status: library core (complete, tested)

- `Asset.swift` — asset model + kind detection for psd/ai/svg/eps/png/jpg/
  gif/webp/tiff/bmp/mp4/mov/webm, collections, tags.
- `Metadata.swift` — header-level dimension parsing straight from file bytes
  (PNG IHDR, JPEG SOF scan, GIF header, PSD header, SVG width/height/viewBox).
  No platform image APIs.
- `Library.swift` — recursive folder import (idempotent re-import updates in
  place), tags (normalized), collections, structured search (text over
  filename/path/tags + kind filter + required tags + minimum megapixels),
  exact JSON persistence.
- `AsssetsApp` — SwiftUI macOS shell: grid browser, kind/collection sidebar,
  live search, folder import. Compile-guarded; Linux builds run a stub so the
  core and tests work everywhere.

## Phase 2 status: thumbnails + palette extraction (complete, tested)

- `Pixels.swift` — real raster decoding without platform image APIs:
  zlib/DEFLATE inflate (stored, fixed and dynamic Huffman, Adler-32 checked,
  written to RFC 1950/1951), PNG decode for 8-bit gray/gray-alpha/RGB/RGBA/
  palette with all five scanline filters, PNG encode (valid everywhere:
  stored-DEFLATE IDAT, CRC32 chunk checksums), uncompressed 24/32-bit BMP
  decode, and box-average thumbnail downscale.
- `Palette.swift` — dominant-color extraction by median-cut quantization
  (deterministic, transparent pixels ignored), returned as weighted colors
  with hex strings.
- `Library.generateDerivatives(thumbnailsDir:)` — per image asset: palette
  (6 colors, hex) stored on the asset + a 256px PNG thumbnail written to the
  library's thumbnails dir; idempotent, and both fields persist in the
  library JSON.
- macOS shell: grid cells now show the derived PNG thumbnail, with a
  QuickLook (QLThumbnailGenerator) fallback for PSD/AI/video/JPEG/TIFF, and
  a palette swatch strip under each asset.
- Smart collections: saved queries (kind, tags, text, minimum megapixels)
  whose membership evaluates live against the library on every read; they
  persist in the library JSON, and pre-smart-collection files still decode.
  The macOS sidebar lists them alongside manual collections.
- 17 more tests (25 total): inflate against a real zlib stream + corrupt
  stream rejection + stored round-trip, PNG quadrant colors, all filter
  types, encode/decode round-trip, BMP bottom-up, palette weights/hexes,
  thumbnail averaging/no-upscale, and the end-to-end library derivative
  flow incl. persistence.
- Verified artifact: out/asssets-derivatives-contact-sheet.png — an original
  rendered scene, its derived 256px thumbnail, and the extracted 6-color
  palette, all produced by this code and visually inspected.

## Build and test

```
swift build
swift test   # 21 tests: metadata, import, search, persistence, zlib/PNG/BMP
             # decode, PNG encode, palette, thumbnails, derivatives
```

## Next

Phase 2 remainder: PSD/AI composite previews (via QuickLook on macOS).
Phase 3: connectors the user authorizes to their own licensed sources.

## Phase 2c status: PSD composite previews (complete, tested)

- Sources/AsssetsCore/PsdPixels.swift: own decoder for the flattened
  composite image every Maximize-Compatibility PSD stores: 8-bit RGB or
  grayscale (with optional alpha channel), raw or PackBits RLE per
  scanline, parsed from the documented Adobe file structure. No
  third-party code; layer stacks, 16/32-bit depth, CMYK/Lab stay
  QuickLook-only in the macOS shell. AI files (PDF-based) are also
  QuickLook-only - out of core scope.
- Library.generateDerivatives now builds thumbnails and palettes for .psd
  assets alongside PNG/BMP.
- Tests/AsssetsCoreTests/PsdPixelsTests.swift: 9 tests over real
  PackBits-encoded fixtures (raw/RLE equivalence, RGB+alpha, grayscale,
  grayscale+alpha, rejected variants, truncation, end-to-end library
  derivatives). 34 total via swift test.

## 0.4.0: studio workflow pass

- `Studio.swift` (core, tested) - the app's catalog model now lives in the
  core: search over titles/tags/colors, multi-asset batch tagging, favorite
  toggles, drag-to-collection moves, empty user collections, rename, and
  remove-from-library that never touches files on disk.
- Upgrade-safe bundled library: every bundled record has a stable key, so
  relaunches and upgrades never duplicate assets. 0.3 catalogs migrate in
  place: starter media leaves "Imported" for its real collection while user
  favorites and tags survive. Removed bundled assets stay removed.
- `MediaPreview.swift` (core, tested) - real WAV waveform peaks (RIFF chunk
  walk, 16/24/32-bit PCM and float) and a small SVG reader for native vector
  previews.
- App: wider styled sidebar with counts and drop targets, compact preview
  with a visible effect strip, ⌘/⇧-click multi-select, batch inspector,
  context menus, selection bar, video posters and looping playback, audio
  playback, full-resolution PNG export.
- CI: fresh-install, relaunch and 0.3-upgrade tests on the real app, plus
  screenshots at two window sizes.
