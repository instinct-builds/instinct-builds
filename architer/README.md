# ARCHITER

A native macOS character-sheet builder for tabletop RPGs — built from scratch,
no APIs, no dependencies. Original code and content with genre-standard
mechanics (ability modifiers, proficiency, advantage, spell slots).

## What's in 0.5.0

- **Ruleset era presets**: switch the sheet between 2014-style and 2024-style
  d20 mechanics (original expression, mechanics only):
  - Rest behavior: long rests return half your spent hit dice (2014 style)
    or all of them (2024 style).
  - Exhaustion: six steps with named side effects (2014 style) vs ten steps
    as a flat penalty applied automatically to every d20 roll (2024 style).
  - Weapon handling: 2024-style sheets show a mastery trait per weapon
    (Cleave, Graze, Nick, Push, Sap, Slow, Topple, Vex - effects written in
    our own words).
  - Spell preparation: prepared count limit follows level + casting modifier
    (2014 style) or a fixed by-level count (2024 style), shown live over the
    spell list.
- Era picker on the sheet header and in the character wizard.

## What's in 0.4.0

- **Level-up assistant**: roll the hit die or take the average, HP and notes
  update, slots/proficiency follow level automatically.
- **Compendium detail**: spells expand in place - components, ritual and
  concentration badges, full original description.
- **12 calling presets** in the wizard (was 6): barbarian, bard, druid, monk,
  paladin, sorcerer join the original six.
- Skills now lay out in two columns with brass roll chips.

## What's in 0.3.0

- **Design language**: dark "ink and brass" tabletop theme, serif display type,
  4pt spacing grid, custom-styled controls throughout - stat plates, slot and
  death-save pips, HP resource bar, brass roll buttons, inset fields, elevated
  block cards, hero identity header with XP progress. All 0.2.0 features intact.

## What's in 0.2.0

- **Full sheet**: identity (lineage/calling/background/alignment/XP with
  auto level-up), six abilities with saves, 17 skills with
  none/proficient/expert tiers, vitals (HP with damage/heal/temp workflows,
  armor-based AC, initiative, speed, hit dice, death saves, 14 conditions,
  exhaustion), attacks derived from abilities or pinned, features with
  limited uses and recharge, personality/backstory, notes.
- **Spellcasting**: full/half/third/pact progressions with correct slot
  tables, slot tracking with one-tap cast/restore, spell attack and save DC,
  prepared toggles, and a built-in 54-spell library with original write-ups.
- **Inventory**: currency (pp/gp/ep/sp/cp), weight tracking with encumbrance
  bands against STR-based capacity, equipped/attuned flags, and a built-in
  weapon/armor/gear library (13 armors, 18 weapons, 16 gear items).
- **Dice automation**: full notation (d20, 2d6+3, 4d6kh3, 4d6dl1, mixed),
  advantage/disadvantage, labeled checks rolled straight from the sheet
  (abilities, saves, skills, attacks, damage, death saves, hit dice), and a
  200-roll labeled history.
- **Sheet builder**: reorder/show/hide/resize blocks, custom templated blocks
  with {placeholders}, and whole custom rulesets (Starfarer, Gumshoe, or
  hand-built abilities/skills) layered on the same character.
- **Creation wizard**: calling presets (Fighter, Wizard, Rogue, Cleric,
  Ranger, Warlock) that fill HP, hit die, saves, and suggested skills;
  standard array, 27-point buy, or manual scores; skill picker.
- **Persistence & export**: autosave per character (JSON in Application
  Support), per-character undo/redo, Markdown/HTML/multipage-PDF export.
- Sample character (Wren Halloway, level 5 wizard) from the File menu to see
  a filled sheet.

## Build

```
swift build                 # library + app + renderer
swift test                  # core test suite
scripts/make_dmg.sh         # ARCHITER.app + DMG (VERSION=0.2.0)
swift run architer-render out/   # PNG renders + PDF/HTML/MD of the sample sheet
```

Requires macOS 14+.
