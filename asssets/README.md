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

## 1.4.0: Find Similar (plus 1.3.x fixes)

- Find Similar: ⌥⌘F, the right-click menu, or the SIMILAR section in the
  inspector. The grid switches to "Similar to X", ranked by look. Near
  copies (resized, re-exported, recompressed or lightly edited) come first
  with a green "Near copy" badge, then look-alikes with a percentage. Once
  looks have been compared, the inspector shows the 8 closest matches for
  whatever you select.
- How it works (`Similarity.swift`): a 64-bit difference hash of each
  preview (9x8 grayscale grid) catches shape and structure, and a palette
  distance catches mood. The score is 70% hash and 30% palette. Near copy
  means at most 6 of 64 bits differ. Hashes are cached per asset and path,
  and files render off the main thread.
- Duplicates now have an "Include look-alikes" switch that also groups
  near copies, not just byte-identical files.
- Fixes: Find Duplicates rescans watch folders first. Re-adding a folder
  you already watch rescans it right away. The sidebar reads "N assets"
  now that the count includes your own files.

## 1.5.0: contact sheets and brand kits

- File > Contact Sheet & Brand Kit… (⇧⌘P) works on the current selection
  if more than one asset is selected, otherwise on the current view. It's
  also on any collection or smart collection's right-click menu and in the
  selection bar's Export menu.
- The contact sheet is a US Letter landscape PDF drawn with CoreGraphics in
  the ASSSETS dark style. The cover has the title, counts by kind, the date,
  the combined palette (up to 8 swatches with hex codes) and a mosaic.
  After that, 12 assets per page, each with its thumbnail, name, kind,
  resolution and palette strip. A preview sheet (PDFKit) shows the pages
  before you save.
- The brand kit is one zip: `Contact Sheet.pdf`, a `Files/` folder (as shown
  or originals), and `Palette.ase` (Adobe Swatch Exchange, for Photoshop,
  Illustrator, InDesign and Affinity) plus `Palette.json` for Figma/Sketch
  scripts and design tokens.
- Logic and tests: `BrandKit.swift` (ASE writer, combined-palette voting,
  page layout) and `BrandKitTests.swift`.
- CI harness: every screenshot now starts from the same fresh catalog. CI
  also uploads the rendered contact-sheet PDF and a listing of a demo
  kit's contents.

## 1.6.0: suggested tags and lighter contact sheets

- ASSSETS now reads each asset on your Mac and suggests tags: up to three
  color names from its palette, light or dark, vivid or muted, square,
  landscape or portrait, 4k+, print-ready (A4/Letter at 300 dpi), small,
  transparent (only when pixels are actually see-through), tileable (from
  the seam check), short or long for video and audio, and quiet or loud for
  WAV files from their real peak level. Nothing leaves the Mac and no
  service or key is involved.
- Suggestions show in the inspector under the tags as dashed chips. Tap one
  to add it, x to dismiss it for that asset, or Accept all. The batch
  inspector has Accept all for the whole selection.
- Suggestions are searchable and work in smart-collection tag rules before
  you accept them, but they stay separate from your own tags: they aren't
  written as keywords and a dismissed one never comes back.
- Tags are read on launch, on import and when a watch folder picks up new
  files, off the main thread.
- Contact sheets embed JPEG thumbnails instead of raw pixels, so a sheet of
  the whole bundled library is a fraction of its old size. Transparent art
  is flattened onto the card color first.
- Logic and tests: `AutoTags.swift` and `AutoTagTests.swift`. CI adds two
  screenshots (search by a suggested tag, audio suggestions) and checks the
  size of a whole-library contact sheet.

## 1.7.0: compare and picks

- Select 2 to 4 assets and press Compare in the selection bar (or ⌥⌘C).
  They open full-window side by side. With exactly 2 you can switch to
  Swipe (S) and drag the divider between them.
- Zoom and pan are shared: drag to pan, pinch or +/- to zoom (up to 800%),
  0 or Fit to reset. Every pane shows the same region, so detail, grain
  and edges line up.
- Under each pane: resolution, palette with the colors only that asset has
  ringed in white, and the tags the others lack. Tags every asset shares
  are listed along the bottom.
- Keep/reject pass: K keeps, X rejects, Tab moves on (the next undecided
  asset gets focus after each call). Return saves, Esc closes without
  writing anything.
- Saving tags keeps "pick" and rejects "rejected" and adds a Picks smart
  collection the first time. Assets stay in their own collections, so a
  compare never moves files around; re-deciding later swaps the tag.
- Logic and tests: `Compare.swift` (session, shared zoom/pan math, diff,
  picks) and `CompareTests.swift`. CI adds compare and compare-swipe
  screenshots.

## 1.8.0: export presets

- Export > Presets… (selection bar, inspector Export menu, or ⌥⌘E) opens
  a sheet with five presets:
  - Web: JPEG at 2400 px on the long edge, plus a 1200 px `@1x`
  - Social Square: JPEG 1080 × 1080
  - Story: JPEG 1080 × 1920
  - 4K PNG: 3840 px on the long edge
  - Print TIFF: full size, 300 dpi, LZW
  Long-edge presets never upscale.
- Crop: Center, or Detail-aware, which slides the square and story crops
  toward the most detailed part of the image (edge energy on a small copy)
  instead of an empty margin. The sheet outlines every crop on the first
  asset before you export.
- File names follow a pattern, `{title}-{preset}` by default, with
  `{w}`, `{h}`, `{n}` and `{collection}`. A live example shows the result.
  Existing files are never overwritten.
- Exports use the asset as shown (effect, PSD layers, tiling and seam fix).
  "Export Picks with Presets…" exports everything kept in compare.
- Rendering runs off the main thread with ImageIO. No services or keys.
- Compare polish: Swipe now hugs the image's shape instead of
  letterboxing, a mouse wheel zooms and trackpad scrolling pans.
- Logic and tests: `ExportPresets.swift` and `ExportPresetTests.swift`.
  CI exports every preset for three mockups and lists each file's pixel
  size and dpi.

## 1.9.0: client review gallery

- File > Export Review Gallery… (⌥⌘G, or Review Gallery… in the selection
  bar's Export menu) builds a "<name> Review" folder and a zip of it:
  `index.html`, `images/` (2000 px JPEG) and `thumbs/` (640 px). Export
  Current View as Review Gallery… does the same for whatever is on screen.
- The page is one offline file in the ASSSETS dark style: a grid with
  palettes, a lightbox with tags, a heart per asset, a notes box, a
  Favorites-only filter and a name field. No server, CDN, fonts or
  tracking; it opens from the zip in any browser. Progress is kept in the
  browser until the client presses Download feedback, which saves a small
  JSON file.
- File > Import Client Feedback… reads one or more of those files.
  Favorites get the `client-pick` tag and land in a Client Picks smart
  collection; notes show in the inspector under CLIENT NOTES with the
  reviewer's name. Re-importing the same reviewer's file replaces their
  earlier notes; several reviewers can comment on the same asset.
  Unknown assets are counted and skipped.
- 1.8.0 fixes: crop labels in the presets sheet no longer overlap, and the
  crop help line wraps instead of truncating.
- Logic and tests: `ReviewGallery.swift` (manifest, page, feedback format,
  import) and `ReviewGalleryTests.swift`. CI builds a gallery, lists the
  zip, screenshots the page and lightbox in headless Chrome, and shows an
  imported feedback file in the app.

## 1.10.0: version stacks

- Files whose names differ only by a version marker are grouped into one
  stack: `v2`, `v03`, `ver 4`, `rev5`, `draft`, `final`, `final 2`,
  `final final`, `copy`, `copy 2`, plus the unmarked original. Plain
  numbers such as "Vector 01" or "Grid 4K" are not treated as versions,
  and an image never stacks with a video of the same name. Detection runs
  after imports and watch-folder scans, and a new round joins its
  existing stack.
- A stack shows as one card (the newest version) with a "3 versions"
  badge and a pile edge behind it. Click the badge to show every version
  in the grid; click again to collapse. A search that matches only an
  older version still shows that version.
- Stack menu in the selection bar: Stack as Versions (⌘G) groups any
  selection by hand; Unstack (⇧⌘G) splits it. Unstacked files are left
  alone by auto-detection from then on.
- The inspector's VERSIONS strip lists the stack oldest to newest. Click a
  version to inspect it. "Compare with v2" opens the shown version and the
  one before it in compare; ⌘-click any other version and press Compare 2
  to open that pair. Right-click a version to remove it from the stack.
- 1.9.0 fixes: gallery and brand kit zips no longer carry a `__MACOSX`
  folder (CI now fails if one appears), and crop labels in the presets
  sheet sit in a legend above the image with numbered frame tags, so a
  crop at the edge can't clip its label.
- Logic and tests: `VersionStacks.swift` and `VersionStackTests.swift`.

## 1.11.0: ratings and color labels

- Star ratings (0-5) and color labels (red, orange, yellow, green, blue,
  purple). With assets selected, or one open in the viewer, press 1-5 to
  rate, 0 to clear, and 6-9 for red, yellow, green and blue labels.
  Pressing a label key again removes it. Rating and Label are also in the
  Asset menu and the right-click menu, and the inspector has clickable
  stars and label dots under the title.
- Cards show the label as a dot and a tinted edge, and the stars on the
  right side of the info line.
- Filter chips next to the media chips: a minimum-rating menu and label
  toggles (any of the chosen labels), with a clear button. Save as Smart
  carries them into the new collection, and the smart collection editor
  has Rating and Label rows.
- Compare has a "Keep:" menu. Keeps can get at least 3, 4 or 5 stars when
  you press Done, or leave ratings alone (the default). The choice is
  remembered between launches.
- Imported and watched files get their real pixel size (or PSD, SVG, WAV
  details) and palette as soon as they come in, instead of "Local file"
  and gray placeholder swatches. Older catalogs are fixed on launch.
- 1.10.0 polish: collapsed stacks have a clearer two-card pile edge, and
  the grid header reads "4 items · 7 files" when stacks hide versions.
- Logic and tests: `Ratings.swift` and `RatingTests.swift`; rating and
  label rules in `SmartStudio.swift`, keep ratings in `Compare.swift`.

## 1.12.0: cull mode, undo, sorting

- Asset > Cull Current View (⌥⌘K) goes through whatever the grid shows,
  one asset at a time, full window. 1-5 rate and move to the next asset,
  0 clears, X rejects (and clears stars), 6-9 label, arrows or Space
  browse, U jumps to the next unrated asset, A turns auto-advance on or
  off, Esc or Return ends. A progress bar counts rated or rejected assets,
  and a strip of neighbors shows each one's stars or reject mark.
- Undo and redo (⌘Z, ⇧⌘Z) for ratings, labels, rejects, tags, favorites,
  moves, stacking, compare passes, duplicate merges and removals. The Edit
  menu names the step ("Undo Rating"). Undo only puts back what that edit
  changed, so suggested tags, file sizes and new watched files that
  arrived in between stay. Text fields keep their own undo. History holds
  the last 50 edits for the session.
- Sort menu in the grid header: Date Added, Name, Rating or Label. Each
  collection and smart collection remembers its own sort. Ties keep the
  date-added order, and stacks still collapse to their newest version.
- When the window is too narrow for the media chips, they fold into one
  "All Media" menu instead of being squeezed and cut off.
- Logic and tests: `Culling.swift` (sort, cull session, reject toggle,
  undo history) and `CullingTests.swift`.

## 1.13.0: keywords and metadata round-trip

- Imported and watched files bring their own metadata: keywords become
  tags, a title replaces the file-name title, and stars and color labels
  carry over (a -1 rating arrives as rejected). ASSSETS reads an `.xmp`
  sidecar first, then XMP embedded in JPEG, PNG, TIFF or PSD, then IPTC
  keywords and object name. Lightroom color labels and Bridge's default
  label names (Select, Second, Approved, Review, To Do) both map.
- File > Write Metadata to Files (.xmp sidecars), also in the selection
  bar's Export menu, writes title, tags, rating and label to
  `<name>.xmp` next to each of your files. The original files are never
  modified. An existing sidecar keeps everything else in it (develop
  settings, camera data, other fields); only those four fields change.
  Bundled library files are skipped.
- Export with Presets has "Embed title, tags, rating and label", which
  writes them into the exported JPEG and TIFF copies. The choice is
  remembered.
- KEYWORDS in the sidebar lists every tag with its count (top 10, or show
  all). Click one to filter the grid (a removable chip appears by the
  filters, and Save as Smart includes it). Right-click to rename or merge
  into another keyword across the whole library; smart collection rules
  follow, and ⌘Z undoes it. How-it-got-here tags (file type, imported,
  watched, bundled) stay out of the list and out of sidecars.
- The collection title keeps priority in the grid header: at narrow
  widths the Sort and Save as Smart controls shrink to icons first.
- Logic and tests: `XmpMetadata.swift` and `XmpMetadataTests.swift`
  (Lightroom sidecar, JPEG with XMP and IPTC, PNG iTXt, round-trip,
  write-back that keeps other settings, rename and merge).

## 1.14.0: batch rename and folder-structure export

- Batch Rename (⌥⌘R, File menu, or Rename in the selection bar) retitles
  the selected assets from a pattern. Tokens: `{title}`, `{collection}`,
  `{kind}`, `{date}`, `{rating}`, `{label}`, `{n}` (two digits) and
  `{n:000}` (pad to as many digits as zeros), with a start number. A live
  list shows each new title next to the old one and flags titles that
  would repeat. It is one undo step (⌘Z). Only titles in ASSSETS change;
  files on disk keep their names, and exports and sidecars pick up the
  new titles.
- Export with Presets has a FOLDERS pattern, for example
  `{collection}/{label}` or `{rating}`. Each file goes into its own
  subfolder inside the folder you pick. Empty means flat, as before. Name
  clashes are handled per subfolder, and a pattern can never write outside
  the chosen folder (`..`, `.` and slashes inside names are removed). The
  file-name pattern also accepts the new tokens. Both are remembered.
- The label name next to the stars in the inspector stays on one line.
  When the inspector is too narrow it hides instead of wrapping one
  letter per line.
- Logic and tests: `BatchRename.swift` and `BatchRenameTests.swift`.

## 1.15.0: search by color

- The swatch button at the end of the search field opens Search by Color:
  15 swatches, your recent colors, the system eyedropper (pick a color
  anywhere on screen), the color panel, and a hex field. Picking a color
  filters the grid to assets with a palette color near it and ranks them
  closest first. An asset where the color dominates ranks above one where
  it is a small accent.
- A tolerance slider goes from Close to Loose. Distances are CIEDE2000,
  where about 2 is a barely visible difference and 12-16 is the same
  color family.
- The active color shows as a chip next to the rating and label filters.
  Click it to clear. Save as Smart keeps the color, so a search becomes a
  live collection.
- Click any swatch under COLOR PALETTE in the inspector to search for that
  color. Right-click still copies the hex.
- Smart collections have a Color rule ("contains a color near #254BB4")
  with its own tolerance. Favorites only moved onto the Label row so the
  editor keeps its height on small screens.
- The last 6 colors are kept with the library.
- Logic and tests: `ColorSearch.swift` and `ColorSearchTests.swift`
  (Lab conversion, the published CIEDE2000 reference pairs, ranking,
  the smart rule and old-catalog decoding, recent colors).

## 1.16.0: moodboards

- BOARDS in the sidebar holds free-form moodboards. Press + or use
  Add to Board > New Board from Selection in any asset's menu. Drag
  assets from the grid onto a board in the sidebar to add them.
- Selecting a board swaps the grid for a canvas on a dot grid. Drag cards
  to move them, drag the corner handle to resize (images keep their
  shape; notes and palette cards resize freely). Snap to grid is on by
  default and can be turned off per board.
- Notes: double-click to write, Done or click away to save. Palette cards:
  right-click an image > Add Palette Card, then right-click a swatch card
  to search the library by any of its colors or copy the hex codes.
- Right-click any card to bring it to front, send it to back or remove it.
  Delete removes the selected card. Tidy lays the board out in rows. Zoom
  buttons and a click on the percentage fit the whole board.
- Export the board as a 2x PNG or a PDF from the header or
  the sidebar menu. Real thumbnails are rendered before export, so video
  and vector cards come out as images, not placeholders.
- Every board edit is one undo step. Removing an asset from the library
  takes it off every board; palette cards made from it stay.
- The Search by Color popover's eyedropper button now reads "Pick" and
  no longer clips.
- Logic and tests: `Moodboard.swift` and `MoodboardTests.swift` (flow
  layout and wrapping, snapping, drop points, aspect-locked resize,
  z-order, palette cards, tidy and export bounds, catalog round-trip, and
  catalogs from before 1.16).

## 1.17.0: focus and presenting

- The inspector can be hidden with the toolbar button or ⌥⌘I, so the grid
  or a board gets the full window width. Drag its left edge to resize it
  (290-420 pt; double-click resets it). Both settings are kept between
  launches. A board that was fitted refits when the space changes.
- Present (the play button in the board header, or Present in the
  sidebar menu) shows the board full screen. It starts with the whole
  board, then steps through the cards row by row with the arrow keys,
  Space or Return. The card in focus zooms in, the rest dim. 0 goes back
  to the whole board, Esc leaves full screen. Click a card to jump to it.
- Share as Review Gallery (Export menu or sidebar) builds the 1.9 client
  gallery from the board's assets in reading order, with the rendered
  board on top. Each image on the board is clickable and opens that
  asset's review panel; favorites show a heart on the board too.
  Feedback files import the same way as before.
- Logic and tests: `Moodboard.readingOrder`, `Moodboard.fit`,
  `ReviewGallery.Board` and `ReviewGallery.spots` in
  `MoodboardTests.swift` (row grouping, fit and clamping, spot fractions,
  manifest round-trip, galleries from before 1.17).

## 1.18.0: canvas editing

- Select several cards: shift- or ⌘-click to add and remove, drag a
  rectangle on empty canvas (shift keeps what was already selected), or
  ⌘A. Drag any selected card to move them all. Delete removes them, Esc
  clears the selection, and the right-click menu brings them forward,
  sends them back or frames them. The inspector shows the selected assets.
- Alignment guides: while dragging, the group snaps to the edges and
  centers of other cards within a few points and a pink line shows what
  it lined up with. Away from any guide it falls back to the grid (when
  snap is on).
- Sections: the dashed-rectangle button (or Put in New Section) frames
  the selection with a label, or adds an empty section. Moving a section
  moves everything inside it, including nested sections. Double-click the
  label to rename it. Sections stay behind the cards, show in exports,
  galleries and Present, and Tidy leaves them and their cards alone.
- Duplicate Board in the board menu, and New Board from Collection / New
  Board from Smart Collection (first 48 assets) in those menus.
- Logic and tests: frames, moving sets, marquee hit testing, guides,
  group z-order, tidy and duplicate in `Moodboard.swift`,
  `MoodboardTests.swift`.

## 1.19.0: board annotation

- Arrows: select one card and drag its arrow handle onto another card, or
  select two cards and choose Connect with Arrow. Arrows run edge to edge
  and follow both cards as you move or resize them. Double-click an
  arrow's middle to label it; right-click it to reverse or delete it.
  Removing a card removes its arrows, and Duplicate Board keeps them.
- Headings: the text-size button adds large type straight on the canvas,
  with no card behind it. Resizing a heading scales its text, and
  double-clicking edits it.
- Crop: right-click an image card and choose Crop… to pick the part it
  shows. Drag the frame to move it or the corner to size it, or pick a
  shape (1:1, 4:5, 4:3, 3:2, 16:9). The file is never changed, and Show
  Whole Image undoes the crop. The card keeps its width and takes the
  crop's shape.
- Arrows, labels, headings and crops show in Present, PNG/PDF export and
  shared review galleries.
- Logic and tests: connectors, edge geometry, hit testing, headings and
  crop math in `Moodboard.swift`, `MoodboardTests.swift`.

## 1.20.0: client rounds on boards and board versions

- Share a board as a review gallery (Export > Share as Review Gallery…,
  or the people button in the board header). ASSSETS remembers which
  board the gallery came from.
- When the client's feedback file comes back, Import Client Feedback…
  puts it back on that board: a pink pin with the reviewer's initials on
  every card they picked, and their comment at the bottom of the card.
  Several reviewers stack on the same card. Importing a newer file from
  the same reviewer replaces their earlier round. Assets still get the
  `client-pick` tag and the Client Picks smart collection as before.
- The people menu has Picked by Client Only, which fades every card no
  client picked, plus Show Comments, a reviewer picker and Clear Client
  Rounds. The header shows how many cards were picked and by whom.
- Versions: the clock button opens the versions list. Save Version keeps
  the cards and arrows as they are, with an optional name. Each version
  shows when it was saved and what has changed since. Restore puts it
  back and first saves the current layout as "Before restoring ...", so
  nothing is lost. Right-click a version to rename or delete it. A board
  keeps its last 30 versions, and Duplicate Board starts a fresh history.
- Older library files open unchanged; boards without rounds or versions
  look the same as in 1.19.
- Logic and tests: `BoardReview.swift`, `BoardReviewTests.swift`.

## 1.21.0: comments and approval on boards

- Every card with client feedback, a status or replies has a badge in its
  corner. Click it, or right-click the card and choose Comments & Status…,
  to open the card's thread. The thread shows who picked it, the client's
  comments, and your replies under them. Type in the reply box and press
  Reply (or Command-Return). Replies are signed with the name under the
  box. Right-click a reply to edit or delete it.
- Status: mark a card Approved, Changes or Open in its thread, from the
  Status submenu, or for a whole selection with "Mark N as". Approved
  cards get a green badge and Changes cards get an amber one. The header
  shows how many cards are approved.
- The people menu has a Status filter (All Cards, Open, Approved,
  Changes, each with its count). It fades every card that doesn't match
  and works alongside Picked by Client Only.
- Export Round Summary PDF… writes one page to send back to the client:
  the board name, date, reviewers and status counts, then every image
  card in reading order with its thumbnail, status, picks, comments and
  replies.
- Statuses and replies are saved with the board and survive restoring a
  version. Duplicate Board starts without them.
- Logic and tests: `BoardApproval.swift`, `BoardApprovalTests.swift`.
