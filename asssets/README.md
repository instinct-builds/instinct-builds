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

## 0.5.0: smart collections

- `SmartStudio.swift` (core, tested) - rule-based collections whose
  membership is recomputed live: words, media kinds, required tags,
  favorites only, source collection, and palette tone (warm / cool /
  neutral / vivid, classified from each asset's palette).
- Four starter smart collections are added once; deleting one keeps it
  deleted. Renaming a collection updates the rules that point at it.
- App: Smart Collections sidebar section with live counts, "Save as Smart"
  from any search or media filter, a rules editor with a live match
  preview, rule summary in the browser header, and "In Smart Collections"
  chips in the inspector.

## 0.6.0: PSD layer previews

- `PsdLayers.swift` (core, tested) - reads the PSD layer and mask section
  (RLE and raw channels, group markers, hidden flags, opacity, blend
  modes) and rebuilds the composite with any layers switched on or off.
  `PsdWriter` writes layered PSDs with a merged image, so Finder, Preview
  and Photoshop show the same result.
- `MockupFactory.swift` + `asssets-mockgen` - four original layered
  mockups (phone screen, poster frame, packaging box, business card) at
  1600 x 1200, with smart-object placeholder layers, shadows, glare and an
  alternate hidden backdrop. They are drawn from code at build time and
  added to the bundled starter library, so no binary files live in git.
- App: a Layers panel in the inspector for any .psd, with eye toggles,
  blend mode and opacity per layer, a live composite in the preview, and
  PNG export that honors the toggles. The file on disk is never changed.
  PSD cards get a PSD badge and real "PSD - W x H - N layers" metadata.

## 0.7.0: bigger bundled library

- 26 more original files, drawn from code at build time by `asssets-mockgen`
  and shipped inside the DMG (57 real starter files, 129 assets in total):
  - 6 more layered PSD mockups: laptop screen, tablet on a desk, tote bag,
    billboard, magazine spread and coffee cup. Each has a smart-object
    layer, shadows, lighting and a hidden alternate backdrop.
  - `LibraryFactory.swift`: 8 seamless 2048 px textures (terrazzo, brushed
    metal, marble, halftone, woven linen, topo lines, watercolor, cork) and
    12 editorial vectors (Bauhaus grids, contour landscapes).
  - `scripts/recompress_png.py` re-deflates the generated PNGs as RGB with
    the Python standard library, since the core PNG writer stores data.
- The Layers panel now sits at the top of the inspector with tighter rows,
  so all of a mockup's layers show without scrolling.
- PSD color swatches come from the actual composite rather than the
  collection default. 0.6.0 installs are updated on first launch.
- The "Favorite Motion & Sound" smart collection is now "Favorite Clips",
  so it fits in the sidebar. A collection the user edited keeps its name.

## 0.8.0: texture tiling and seam fixing

- `Seamless.swift` (core, tested): measures whether an image repeats
  without a seam by comparing the wrap-around edges with neighboring
  pixels inside the image. It also makes any image tileable (offset and
  blend) and builds tiled images.
- App: textures get a 1x / 2x2 / 3x3 repeat preview on the inspector
  image, plus a live seam badge. "Seamless" appears when the image passes
  the check. "Visible seam - Fix" blends the edges for the preview and
  export only; the file on disk is never changed. PNG export follows the
  repeat and fix settings, capped at 6144 px.
- The "seamless" tag on bundled textures is now checked against the pixels
  on install. All 8 generated 0.7 textures pass. The older 4K-named
  textures fail the check, so they lose the tag and get the Fix button.
- CI screenshots: textures-tiling (terrazzo 3x3) and seam-fix (a legacy
  texture repeated 2x2 with Fix on).

## 0.9.0: full-window viewer (includes the 0.8.1 fixes)

- Space opens the selected asset in a full-window viewer. Arrow keys move
  through the visible assets and wrap at the ends. Esc, Space or a click
  on the backdrop closes it. There is also an eye button in the toolbar.
  The viewer respects the current effect, PSD layer toggles and texture
  repeat, plays footage and audio, and shows the position ("3 of 28"),
  palette, tags and a favorite button. Typing in the search field is
  never taken over. Navigation order lives in `Viewer.swift` (core,
  tested).
- 0.8.1: the repeat control and seam badge sit on a solid dark backing, so
  they are readable over light textures.
- 0.8.1: bundled PNG and JPEG files take their color swatches from the
  pixels rather than the collection default. Earlier installs are updated
  on first launch.

## 1.0.0: drag out (includes the 0.9.1 fix)

- Drag any card, the viewer image, or the "Drag out" chip in the inspector
  into Finder, Keynote, Figma or any app that accepts files. When the
  preview matches the file, you get the original file (PSD, SVG, PNG, WAV,
  MP4). When layer toggles, an effect, tiling or seam fixing are on, or the
  asset is a generated study, you get a PNG of exactly what the preview
  shows, named after the asset ("Phone Screen Mockup (layers).png").
  Decision and file naming live in `DragOut.swift` (core, tested).
- Dragging onto sidebar collections still moves assets. That payload uses a
  private type (`co.instinct.asssets.selection`, declared in Info.plist)
  that only ASSSETS can see, so Finder never gets text clippings.
- 0.9.1: the viewer backdrop is now a blur material under 90% black, so the
  window behind it no longer shows through.

## 1.1.0: batch export

- Export a selection to a folder with Edit > Export Selection As Shown (⌘E),
  Export Original Files (⇧⌘E), the Export menu in the selection bar, or the
  right-click menu. "As shown" follows the drag-out rules. "Originals"
  copies every file that exists and renders PNGs only for generated
  studies. Nothing is overwritten: name clashes become "Name 2.png", like
  Finder. When the export finishes, Finder opens with the new files
  selected.
- Multi-file drag-out: with several assets selected, drag the "Drag N files"
  handle in the selection bar to drop all of them at once. Dragging a
  single card still gives you just that asset.
- Reveal in Finder (⇧⌘R, plus the selection bar and right-click menu) works
  on the whole selection.

## 1.2.0: watch folders

- File > Watch Folder… (⇧⌘I) or the + next to WATCH FOLDERS in the sidebar.
  New images, PSDs, vectors, footage and audio in watched folders (up to 4
  levels deep; hidden files and app bundles are skipped) show up in the
  Inbox collection within a few seconds, and again whenever ASSSETS comes
  to the front.
- Re-scans are idempotent. A file already in the library is never added
  twice, even if you moved it to another collection. A watched file you
  remove from the library stays removed; importing it by hand brings it
  back. Watching a parent folder replaces its watched subfolders.
- Missing files: when one of your imported files is moved or deleted in
  Finder, its card gets an orange Missing badge. A "Missing Files" row
  appears under LIBRARY, and the inspector offers Locate… (relink, keeping
  tags, collection and favorite) or Remove. The flag clears on its own if
  the file comes back. Bundled library files are repaired on launch instead.
- Export works the same everywhere: the inspector's Export button exports
  as shown, and its arrow offers the original file. Single assets get a save
  panel with the planned name.
- Logic and tests: `syncWatch`, `addWatchFolder`, `missingIDs` in
  `Studio.swift`, with tests in `WatchFolderTests.swift`.

## 1.3.0: duplicates, sharing, collapsible sidebar

- File > Find Duplicates… (⌥⌘D) compares file contents across imports,
  watch folders and the bundled library. Only files with the same size get
  a SHA-256 hash, and it runs in the background. Each set of identical files
  shows the copies side by side with their collection and path. "Keep This"
  keeps one copy; the kept copy picks up the others' tags, favorite, and
  collection (if it was only sitting in Imported or Inbox). The other
  copies leave the library, but files on disk are never touched. "Keep
  Suggested for All" picks a favorite first, then a copy filed in a real
  collection, then the bundled original, then the oldest. Removed copies
  never come back through watch folders.
- Share: the system share menu (AirDrop, Mail, Messages, Notes and so on)
  is in the inspector, the batch inspector, the selection bar and the
  right-click menu. It shares the same files as drag-out: the original, or
  a PNG of the preview.
- Sidebar sections collapse when you click their header, and stay that way
  across launches, so WATCH FOLDERS and the rest are reachable on small
  screens.
- Logic and tests: `Duplicates.swift` and `DuplicateTests.swift`.
