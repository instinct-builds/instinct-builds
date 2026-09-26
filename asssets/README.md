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

## 1.22.0: board templates and Share Round

- The + next to BOARDS now offers Blank Board or From Template…. The
  template picker shows a small drawing of each layout, with its slot
  count.
- Three original templates ship with ASSSETS:
  - Moodboard 3x3: nine image slots, a note for the feeling and a starter
    palette.
  - Brand Direction A/B: two side-by-side sections, each with a hero, two
    details and a one-line note.
  - Product Launch: a hero feeding square, story and banner slots, with
    arrows.
- Empty slots show a dashed "Drop an image" card. Dropping an image on a
  slot fills just that slot. Add to Board fills empty slots in reading
  order first, then lays out the rest as usual. A slot keeps its size, and
  the image is cropped from the middle to fill it (Crop… still adjusts
  it). Right-click a card and choose Remove Image (Keep Slot) to empty it
  again. The header counts empty slots.
- Save as Template… (board right-click menu or Export menu) saves any
  board's sections, headings, notes, palettes and arrows, with every image
  turned into an empty slot. Your templates appear under YOUR TEMPLATES in
  the picker. Right-click one to rename or delete it.
- Share Round (Gallery + Summary)… builds the board's review gallery with
  the round summary PDF inside the same folder and zip. The gallery page
  gets a "Round summary (PDF)" button, so the client has both in one
  place.
- Logic and tests: `BoardTemplate.swift`, `BoardTemplateTests.swift`.

## 1.23.0: client approval from the gallery, import preview, Arrange

- Every image in a shared review gallery now has Approve and Request
  changes next to the heart and the note, on the grid and in the
  lightbox (keys A and C). Press the same button again to clear it. The
  choice is saved in the same "Download feedback" file as an optional
  `status` field, so feedback files from older galleries still import,
  and galleries shared before 1.23 keep working.
- File > Import Client Feedback… now opens a preview first. For each file
  it shows the reviewer, the board the round came from, and a count of
  picks, approvals, change requests and notes. Each image gets a row with
  its thumbnail and note, and any status change is shown as old -> new.
  Images that aren't in the library are flagged as skipped. If that
  reviewer already sent feedback on this round, the sheet says theirs
  will be replaced. Nothing changes until you press Import.
- On import, Approve / Request changes set the card's Approved / Changes
  status on the round's board (the 1.21 status and filter), and the
  client's note shows in the card's thread under their name.
- Arrange: the board's tidy button is now a menu. It has Tidy Into Rows
  plus, for two or more selected cards, align left / center / right /
  top / middle / bottom, distribute horizontally / vertically (three or
  more cards) and match widths / heights. Right-clicking a selection
  gives the same options. Image cards keep their shape when matched,
  frames move as cards, and each action is one undo step.
- Logic and tests: `BoardFeedback.swift`, `BoardFeedbackTests.swift`.

## 1.24.0: boards follow versions, nudge, copy and paste

- The inspector has an ON BOARDS list: every board card that shows this
  asset or another version of it, with the version on the card and an
  arrow when a newer one exists. Click a row to open that board with the
  card selected.
- Board cards that show an older version in a stack get a "Final
  available" (or "v3 available") chip. Click it, or right-click and pick
  Update to Final, to swap in the newest version. The Review menu has
  Update All to Newest (N), and the board subtitle counts newer versions.
- Updating keeps the card's size and position. The crop stays when the
  new file has the same shape; otherwise it resets to a centered crop.
  Pins and comments from earlier rounds stay on the card. An approved
  card goes back to Open with a reply that says what changed. The board
  is saved in Versions as "Before Update to Newest" first, and one Undo
  reverts it.
- Arrow keys nudge the selected cards by 1 pt; Shift moves one grid step.
  Nudging a section moves what is inside it.
- ⌘C copies the selected cards, ⌘V pastes them on this board or another
  one. Arrows between copied cards come along. Pasting on the same board
  steps down and right each time.
- Logic and tests: `BoardFollow.swift`, `BoardFollowTests.swift`.

## 1.25.0: usage rights and credits

- The inspector has a RIGHTS section: license (Own work, Licensed,
  Client-supplied, Editorial-only), credit line, source, allowed uses and
  an optional end date. A chip shows where it stands: Rights OK, Rights
  end in N days, Rights expired, Editorial only or No rights info. Save
  Rights (⌘↩) stores it and writes it to the file's .xmp sidecar
  (photoshop:Credit, dc:source, xmpRights:UsageTerms and Marked, plus
  asssets:License and asssets:RightsExpires). Everything else in an
  existing sidecar is kept. Files that arrive with these fields fill in
  their rights on import.
- New smart collections: Rights Expiring (ends within 30 days), Rights
  Expired and No Rights Info. They are added once to new and existing
  libraries; deleting one keeps it deleted. Smart rules can also filter
  on rights.
- Batch export, contact sheets, review galleries and Share Round ask
  first when an asset is expired or editorial-only, listing each one.
  Adding such an asset to a board says so, and board cards that use one
  show a red chip. Click the chip to open the asset.
- Credits: review galleries get a Credits button and panel, and each
  image shows its credit in the lightbox. Round summary PDFs end with a
  credits list, and contact sheets get a credits page. Turn it off with
  Include Credits Page in the board Export menu.
- Logic and tests: `Rights.swift`, `RightsTests.swift`.

## 1.29.0: Place into Mockup

- **Put your art into a mockup without Photoshop.** Select an image and choose Place into Mockup… (inspector, right-click, or ⌥⌘P). Pick any layered PSD mockup in the library, the ten bundled ones or your own, and ASSSETS finds its design layer (the smart-object layer, like "Your Design" or "Screen Design") and draws the art into it in perspective. The layer's shape is the mask, so rounded screens and printed areas stay clean, and the shading and glare layers above still sit on top. Everything renders on your Mac.
- **Fill or Fit, and choose what shows.** Fill covers the design area. Drag the frame on the artwork to pick the part that shows, or drag its corner to zoom. Fit shows the whole artwork with a background of your choice (white, paper, slate or black). A mockup with more than one design layer lets you pick the layer.
- **Saved as a version.** Save as New Version writes a PNG next to the library and stacks it on the mockup, titled "Art on Mockup". It takes the art's rights, credit and license files, since the artwork is what a client licenses, plus the tags of both. Bundled art is marked as ASSSETS bundled library, so the render is never flagged for missing rights. Undo removes it from the library.
- **Place into All Mockups** renders the art into every mockup at once, stacks each render on its mockup, and opens the results as one contact sheet.
- Logic and tests: `MockupPlacement.swift` (design-layer choice, corner finding for tilted layers, the perspective mapping, Fill/Fit regions), `MockupPlacementTests.swift`.

## 1.28.0: lossless duplicate merge and Library Health

- **Nothing lost when merging duplicates.** Find Duplicates (⌥⌘D) used to keep only tags, favorite and collection from the copies it removed. Now the copy you keep also takes the highest star rating, a color label, license files, client notes and version stack from the others. It takes their rights too when it has none. Board cards and client picks that pointed at a removed copy now point at the kept one instead of disappearing.
- **See it before it happens.** Each set in the review sheet shows every copy with its rating, label, rights, license files and board cards. Click a copy to keep it. A summary line lists exactly what will move over ("★★★★ rating · Purple label · 2 license files · 1 board card follows"). When copies carry different rights, the set is flagged "Rights differ" and waits until you pick whose rights to keep. "Merge All" skips those sets until then.
- **Library Health** (sidebar, or ⌥⌘L) lists what needs attention, each with its fix:
  - missing files, with Locate…
  - license files whose stored copy is gone, with Detach
  - sets of identical files, with Review…
  - licensed assets with no credit, with Select to fill them in at once
  - unused files in the Licenses folder, with Clean Up
  - files over 200 MB
  Checks that pass are listed too, so an empty section never reads as "not checked". Clean Up is the only action that touches files on disk, and it only deletes unused copies inside the library's Licenses folder.
- Logic and tests: `Duplicates.swift`, `LibraryHealth.swift`, `LosslessMergeTests.swift`.

## 1.27.0: license files and rights presets

- **License files.** Attach the paperwork behind a license (order PDF, receipt, email export) to one asset or a whole selection: use the button in the Rights section or drop files onto it. ASSSETS keeps a copy in the library, so the original can move. Click a file to open it in Quick Look. In the batch inspector, each file shows how many of the selected assets it's attached to, with "Add to all".
- **In reports and bundles.** The Rights Report lists each asset's license files in the PDF and in a "License files" CSV column. Exporting a report also copies the files into a folder next to it. Gallery, round summary and credits pages name the files on record. Galleries only include the files themselves when you turn on "Include License Files in Galleries", because license paperwork can carry prices.
- **Rights presets.** Save an asset's rights, or the fields a selection shares, as a preset with its license files, then apply it with one click from the chips at the top of the Rights section. A preset can set the end date 1-3 years from the day it's applied. The credit supports {title} and {n}.
- **Export guard.** Sharing, exporting (files, presets, boards), contact sheets and galleries now all check rights first. A sheet lists what's expired or editorial-only and offers Cancel, "Leave Out N" (go ahead with only the cleared assets) or "Export Anyway".

## 1.26.0: bulk rights, renewals and the rights report

- Select several assets and the inspector shows RIGHTS for all of them.
  Fields that differ read "Mixed" and stay as they are unless you edit
  them. Apply to N changes only what you touched. Credits can use {title}
  and {n}, e.g. "Photo: {title} / Northlight" for one agency order. The
  end date can be left alone, set or removed for the whole selection.
- Extend 1 Year moves each end date on by a year, counting from today
  when it has already passed. Mark Renewed records today as the renewal
  date and sets a fresh one-year term. Both work on one asset or a
  selection, write the sidecars (asssets:RightsRenewed) and undo in one
  step.
- Rights Report (PDF + CSV) for a board (Export menu), a collection or
  smart collection (right-click) or a selection (inspector). Landscape
  pages list every asset with status, license, credit, source, allowed
  uses, end and renewal dates. Problems sort first, then things ending
  soon, missing info and OK. A CSV with the same rows is saved next to
  the PDF.
- The sidebar shows Rights to Check under Library when anything is
  expired or ending within 30 days. Its count is red for expired and
  amber for ending soon, and the Rights Expired and Rights Expiring smart
  collections get the same colored counts.
- At launch, a banner lists licenses that ended since ASSSETS was last
  opened. Review selects them in Rights Expired.
- Logic and tests: `BulkRights.swift`, `BulkRightsTests.swift`.

## 1.30.0: editable placement recipes

- Each new placed render stores a recipe in the library catalog: the original art and PSD mockup IDs, design-layer name, Fill/Fit mode, crop and background. Earlier flat versions still open normally.
- A rendered version has Edit Placement in the inspector and context menu. The sheet reopens with its choices, previews the current sources and saves a **new** version, keeping the old render and its rights intact. Place into All saves one recipe per result.
- Missing artwork or PSDs show a warning on the rendered asset; Edit asks to locate a moved source (keeping its identity), or explicitly choose a replacement when the original library record is gone. Never auto-substitute a similarly named file. If a PSD's design layer changed, the sheet asks the user to choose a layer before saving.
- Logic and tests: `PlacementRecipe` and `PlacementSourceStatus` in `MockupPlacement.swift`, with persistence and source-resolution tests.

## 1.31.0: batch place several artworks into one mockup

- Select at least two still artworks, then choose Batch Place into Mockup from the Asset menu or context menu. Pick one layered PSD, its design layer, Fill/Fit and background. A grid previews every artwork in that mockup, with each artwork's own rights and credit underneath. No remote rendering or paid API.
- Place N Artworks renders one image per artwork, saves separate editable recipes and art-specific rights/license files, and stacks each with its own source artwork (not all on one shared mockup stack). One Undo reverts the library operation. The batch reports partial results when a source file is missing.
- The 1.29 one-art-into-all-mockups path is unchanged. The 1.30 Edit Placement action can reopen each new batch render separately.

## 1.32.0: placement presets

- Save a named batch placement setup: the exact library mockup, named design layer, Fill/Fit mode and background. Select two or more artworks later, open Batch Place into Mockup and choose a preset to populate the sheet and preview grid. Presets store no artwork, so each batch keeps the current selection and each art's own rights.
- Named presets live in the catalog across launches. Saving under an existing case-insensitive name updates it, and Manage can delete presets; both are undoable. A removed/moved mockup or renamed layer does not silently switch sources: the sheet shows the problem and keeps current settings until the mockup is located or a fresh preset is saved.
- Core logic and persistence tests live in `MockupPlacement.swift`, `Studio.swift` and `MockupPlacementTests.swift`.

## 1.33.0: per-art batch framing

- Each artwork in Batch Place has its own Crop control. Drag the outlined visible region to move it or its corner to zoom; the mockup preview rerenders that artwork with its framing. Reset returns to the automatic center crop. In Fit, the whole art is shown, so the Crop control is disabled and no crop is saved.
- Per-art crops persist in the new render's editable placement recipe. The named preset still sets only the shared mockup, layer, Fill/Fit and background; choosing one leaves each artwork's framing and rights intact. The 1.33 native proof includes two distinct adjusted artworks and the results, while the plain batch demo checks the no-crop path.

## 1.34.0: source and placed framing together

- Every artwork card in Batch Place shows a compact source view with the exact visible Fill region outlined next to the live placed mockup. A darkened surround marks what the mockup crops away, with SOURCE · FRAME and PLACED labels. In Fit the whole source stays visible without a crop outline; the placed preview shows its margins. These are read-only comparisons; Crop/Adjusted opens the existing per-art drag editor.
- Changing the shared mockup, design layer, mode, background or a single artwork's crop rerenders the placed view and updates the source frame. No extra recipe data or remote rendering is needed. Native CI proof covers the regular batch and two distinct adjusted frames.

## 1.35.0: focused batch comparison

- Inspect on a batch artwork opens a larger, read-only source-frame and placed-mockup comparison without closing the batch or making a render. The source uses that art's current crop and the same Fill/Fit setting as its compact card; the placed side shows the actual local preview with the chosen mockup and design layer. Back to Batch preserves every artwork's choices.
- Adjust Crop from the focused view returns to the batch and opens that artwork's drag editor. Fit keeps the full artwork and disables crop adjustment. No new stored data or service is needed. A native `batch-focus` screenshot checks the enlarged layout at 1024x768.

## 1.36.0: browse artworks in focused comparison

- Previous and Next inside Inspect Placement move through the current batch in order, keeping the large source framing beside the placed mockup. A position label makes the current artwork clear, and the controls disable at the ends instead of wrapping. Inspect and Adjust Crop continue to target the artwork shown. Back to Batch returns to all three editable cards without saving or changing their choices.
- The native `batch-focus` and `batch-focus-next` captures check both the first custom crop and the next unadjusted artwork at 1024x768. The existing batch-crop proof and recipe assertions remain.

## 1.37.0: arrow-key review in focused comparison

- Left and right arrow keys invoke the focused Inspect Placement sheet's Previous and Next actions without Command. The shortcuts live on those sheet buttons, so the disabled state at the first and last artwork also disables its key action. These are not installed as global key monitors: the batch sheet and the per-art crop editor retain their own keyboard behavior.
- `batch-focus`, `batch-focus-next` and `batch-focus-last` native captures show the controls at the first, middle and last artworks. Keyboard activation itself needs an interactive check; screenshots only prove placement and disabled states.

## 1.38.0: native Fit-mode proof

- The focused comparison now has a native `batch-focus-fit` proof: Blueprint 2K in the Poster Frame Mockup with Fit and Slate background selected. The shot should show the whole art beside a placed render with visible background margin, the footer caption "Fit shows the whole artwork", and a disabled Adjust Crop button. The core Fit rendering test checks margin pixels; source and crop handling are otherwise unchanged.

## 1.39.0: relink a relocated folder

- Library Health offers Relink Folder for missing imported files. Enter the old folder root and choose the new folder; Preview Exact Paths lists each affected asset with its old and proposed path. Only the same relative path under the chosen new root counts as a match. Missing targets, destinations already owned by another asset, non-files, and symlinks escaping the chosen folder are not relinked. Files outside the old root remain out of scope. No basename search or automatic substitution.
- Relink N Matches rechecks both catalog and disk against the preview immediately before writing. If the set changed, it replaces the preview and asks for review again. The accepted matches change in one undoable catalog operation, preserving asset IDs, rights, boards and editable recipes; disk files are untouched. The native CI demo shows a two-match/one-unmatched preview and checks two relinks while the unmatched path stays old.

## 1.40.0: watched folders follow a relocation

- When the old root itself, or one of its descendants, is watched, the Relink Moved Folder preview now shows the exact old-to-new watched-folder mapping beside the asset paths. Move watched folder(s) is a visible opt-in toggle, on only when the new directories exist and do not overlap another watch. A missing directory, conflicting watch or directory escaping the chosen root shows why the watch will stay old. A watched ancestor outside the old root is called out as out of scope, not silently rewritten.
- Revalidation checks the watch mapping alongside the asset matches. If either changes before Relink, it asks for a fresh review. Accepted watched roots change in the same undoable catalog operation as matched asset paths. The CI demo confirms two source relinks, one unmatched file left old and one watched root moved; tests cover move, overlap and missing destination.

## 1.41.0: grouped folder-relocation preview

- Relink Moved Folder groups the preview by outcome with clear section counts: Unmatched, Ambiguous and Matched. Each section can be collapsed or expanded without changing the preview's accepted matches or the watch-folder toggle. Problem groups appear before matches so a large relocation does not bury failures below hundreds of safe mappings. Empty groups still say zero, and rows retain exact old/new paths and reasons.
- The native `folder-relink` and `folder-relink-collapsed` shots check full and collapsed group layout at 1024x768. The post-apply CI marker still verifies two relinks, one untouched missing file and a moved watch root.

## 1.42.0: review changed source files

- ASSSETS records each new imported or watched source's size, modification date and SHA-256. Older catalogs get a baseline on their next health scan; until then a change made before that first scan cannot be distinguished from the original. Regular scans avoid rehashing unchanged size/date pairs. Check Again hashes every source, including unchanged stat pairs; changes during hashing are skipped for a later scan. A timestamp-only touch with the same hash quietly updates the baseline.
- Library Health lists files whose bytes changed at the same path. Review shows the exact asset and source path; Refresh Source rechecks the bytes, then updates its thumbnail, palette and file facts. The record's ID, rights, user tags, board references and placed versions remain. The old bytes cannot be restored by undoing the catalog change. Native CI shots show the changed source, review prompt and refreshed state; the marker checks retained rights and board membership.

## 1.43.0: source refresh receipts

- Review now compares the known and current file sizes, resolution and palette before accepting changed bytes. If the file changes after review, refresh stops and asks for another scan and review. The exact reviewed fingerprint and derived metadata are accepted together; user tags, rights and board references remain on the same asset.
- Each accepted refresh writes a dated receipt in the catalog with the source path, before/after fingerprints and file facts. Library Health displays recent receipts and can expand the full history. The receipt is metadata, not an original-file backup; it cannot recover prior bytes. Older catalogs decode with no receipts. Core tests check receipt persistence, retained rights and board references, and rejection of duplicate acceptance. CI tests the receipt on disk and captures the native review/history views.

## 1.44.0: source changes on the asset

- Imported assets show a Source Changes section in the inspector. An unreviewed source detected by Library Health gets a visible warning and a Review in Library Health button; the check opens a fresh full scan, not a guess based on cached history. Assets with receipts show a newest-first timeline with date, source path, size, file facts, palette swatches and truncated before/after hashes. Show all expands longer timelines. Records belong to the asset ID even after a relink; each receipt keeps the path used at that refresh.
- The section is explicit that catalog receipts do not retain the prior file bytes. New native CI shots check both pending and refreshed per-asset inspector states at the runner's compact screen size.

## 1.45.0: one-by-one changed-source review queue

- Library Health keeps a stable ordered queue of changed files. Show queue lists the pending sources and marks the current selection; selecting a row does not accept its bytes. Review opens the before/after confirmation for just that file. Cancel leaves every source pending. After an accepted refresh, the next pending file is selected in the same sheet and the queue stays in view; Check Again preserves the selection if that file remains pending. There is no bulk acceptance.
- The native CI demo changes two imported files, shows both pending in the queue, accepts only one and verifies one receipt with the other still pending. A second native shot checks the remaining selected row at 1024x768. Tests cover selection across scans, advancing after an acceptance and the end of the queue.

## 1.46.0: small before/after source preview

- New imports and watched files retain a small 240-pixel JPEG preview bound to the exact approved source digest; older catalogs can get a baseline and preview on a health scan if their source has not yet changed. The snapshot is capped at 120 KB and stored in Application Support, not in the catalog or the original file. If a source changed before its first 1.46 capture, the old visual cannot be reconstructed; review explicitly shows no approved old snapshot. Audio or unsupported files may have no visual preview.
- Reviewing a changed source shows the saved small preview beside a transient preview rendered from current disk bytes, followed by size, file facts and palette. It rechecks the source digest before presenting and again before accepting. After refresh, the old snapshot is removed and a new miniature is captured for the accepted bytes. Neither preview is a source backup, and the review says old source bytes cannot be restored. CI captures a native side-by-side screenshot and asserts both previews are available in the demo.

## 1.47.0: bounded visual references in source history

- Each accepted source refresh can retain a small Before and After JPEG with its metadata receipt. These are 240-pixel, at most 120 KB each, stored beside the catalog, not original sources. The first refresh of an older source may lack a Before snapshot. Unsupported media may have no visual snapshot.
- The most recent five receipts per asset may keep these preview pairs (at most 1.2 MB per asset); older receipt metadata remains, while older preview files are deleted. Removing an asset deletes its preview files. The previews cannot restore the source file.
- Library Health history and the asset inspector show the previews and say when a snapshot is absent. CI verifies both sides of a native accepted-refresh demo, alongside the existing source history receipt and rights/board checks.

## 1.48.0: focused source receipt

- Each Source Changes receipt in an asset inspector has a View receipt control. The dedicated, read-only sheet gives the acceptance date, small Before/After snapshots, source path, full size and dimensions, complete palette lists and complete SHA-256 digests together. The images are only visual references; neither is a source backup or a way to restore older bytes.
- Missing images on older or unsupported receipts are marked as absent. CI opens the focused receipt from a native accepted-refresh demo and verifies the two images and changed digest.

## 1.49.0: navigate source receipts

- The focused receipt sheet now has Older and Newer controls with a position count. It stays scoped to the same asset's accepted receipts, newest first, and only presents catalog facts plus small bounded visual references where available. The first and last controls disable at the ends; nothing in history changes when browsing.
- CI creates two accepted source refreshes and captures the older receipt in the same focused sheet, proving the navigation and both snapshot sides without implying recovery of original file bytes.

## 1.50.0: keyboard receipt navigation

- In a focused receipt timeline, the left arrow moves to an older accepted receipt and the right arrow moves newer. These are the same disabled-at-the-ends controls as the visible buttons. A shortcut hint sits beside the non-restoration warning, so keyboard use never hides the snapshot-only framing.

## 1.51.0: find source receipts

- Library Health's read-only Source refresh history now searches source filenames without regard to case and can narrow by inclusive acceptance dates. A result count, Clear control and empty state make the filter explicit; Show All applies to matching receipts, not the unfiltered history. The stored catalog remains unchanged.
- A native demo shows a Northlight filename match after an accepted source refresh, while core tests cover filename, date boundaries and ordering. Receipt images remain bounded and snapshot-only; neither the search nor the history view can restore original bytes.
