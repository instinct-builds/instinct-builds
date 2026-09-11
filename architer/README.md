# ARCHITER

A native macOS character-sheet builder for tabletop RPGs. Original software;
not affiliated with or derived from Roll20 or any other product.

## What it is

- **Sheet**: a living character sheet — identity, six abilities with
  auto-computed modifiers and saving throws, vitals (HP/AC/initiative/speed/
  passive perception), skills with proficiency tiers, attacks, inventory, notes.
- **Builder**: the sheet is made of blocks. Reorder them, show/hide them, and
  resize them; the layout is saved per character and honored by every export.
- **Dice**: full notation (`d20`, `2d6+3`, `4d6kh3`, `4d6dl1`, compound
  expressions), d20 advantage/disadvantage, roll history.
- **Export**: one keystroke to Markdown or a self-contained styled HTML sheet
  (Cmd-E / Cmd-Shift-E).
- **Persistence**: characters autosave as JSON in Application Support.

## Architecture

- `ArchiterCore` — platform-independent engine: dice parser/roller
  (seedable RNG for deterministic tests), character model, rules math, sheet
  layout model, JSON store, Markdown/HTML exporters. No dependencies.
- `ARCHITERApp` — SwiftUI macOS app (macOS 14+). On non-macOS platforms the
  target builds as a stub so the core and tests run anywhere.

## v0.3 status: custom rulesets + templated blocks (complete, tested)

- CustomRules.swift: user-defined rulesets with their own ability and skill
  tables (name, modifier math). Two original built-ins: Starfarer
  (Physique/Reflex/Logic/Presence) and Gumshoe (investigative abilities).
- Character.apply(ruleset:) keeps scores for abilities that carry over.
- CustomBlock + TemplateRenderer: sheet blocks whose body uses {placeholders}
  ({name}, {level}, {hp}, {c.<customAbility>}, {c.<customAbility>.mod}, ...);
  unknown tokens render as [?name] so template mistakes are visible.
- Export (MD/HTML) and PDF export render custom abilities, skills, and
  blocks after the standard sections. Legacy JSON (no custom fields) still
  decodes - decodeIfPresent defaults plus a regression test.
- 10 new tests (43 total).

## v0.2 status: PDF export + undo (complete, tested)

- `PDFExport.swift` — dependency-free PDF 1.4 writer (Letter pages,
  standard-14 Helvetica, text/rect/line operators, xref/trailer) plus a
  print layout that honors the sheet's block visibility and order: header,
  six ability boxes with saves, vitals chips, two-column skills, attacks
  table, two-column inventory, wrapped notes, footers with page numbers.
  Multi-page flow for long sheets. Output verified against poppler
  (pdftotext) and rendered-page inspection.
- `UndoStack.swift` — value-type undo/redo snapshots for character edits
  (bounded history, redo cleared on branch). Wired into the macOS app as
  Cmd-Z / Cmd-Shift-Z with per-character stacks, plus an "Export PDF…"
  command next to the existing Markdown/HTML exports.
- 9 more tests (33 total): PDF structure (header/trailer/xref byte offsets),
  content presence, escaping, hidden blocks excluded, multi-page flow; undo
  walk-back, redo branching, no-op pushes, bounded history.

## Build and test

```
swift build          # builds core everywhere; app UI compiles on macOS
swift test           # 43 tests over dice, rules, persistence, export, PDF, undo, custom rules
```

## Package a DMG (requires macOS)

```
scripts/make_dmg.sh   # produces ARCHITER-0.1.0.dmg
```

A DMG cannot be produced on Linux (requires Apple's toolchain for the final
.app assembly and hdiutil); the script performs the whole flow on a Mac.

## Rules content

Game mechanics (modifier math, proficiency curve) are functional rules and
not copyrightable expression. All names, text, and presentation here are
original. No text, stat blocks, or trademarks from any publisher's books.
