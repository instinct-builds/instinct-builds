# ARCHITER

A native macOS character-sheet builder for tabletop RPGs — built from scratch,
no APIs, no dependencies. Original code and content with genre-standard
mechanics (ability modifiers, proficiency, advantage, spell slots).

## What's in 2.21.0

- Compact PDF flows in two columns: after the header, abilities, and
  vitals, the line-based sections (skills, spells, features, inventory,
  personality, notes, journal) set in two balanced 254pt columns with a
  24pt gutter, spilling from the left column to the right and then to
  the next page. Skills and inventory go single-file inside a column
  instead of the old full-width two-up grid, so nothing collides across
  the gutter.
- Section keep-together: a compact section header never strands within
  five lines of a column bottom - it starts the next column instead.
- The attacks table still spans the full page width: the column flow
  suspends for the table and resumes beneath it.

## What's in 2.20.0

- Defenses on the dice path: the vitals damage field now doubles as dice
  notation - type "2d6+3", pick a damage type, hit Roll. The roll lands
  in history labeled with the defense adjustment ("fire damage taken
  (resisted: 14 -> 7)") and the adjusted total applies to HP, temp HP
  absorbing first. Immunity zeroes, vulnerability doubles; untyped or
  undefended types apply raw. The flat-amount Apply path is unchanged.
- Sample sheet: Wren's vault story now grants fire resistance, so the
  defenses row and the resisted-roll label show in renders.

## What's in 2.19.0

- Exhaustion meets movement, era-aware: 2014-style step 2 halves every
  speed and step 5 zeroes them; 2024-style shaves 5 ft per step (floor
  0) - matching the step notes the tracker already shows. The vitals
  speed line and every export readout use the adjusted values.
- Prone costs movement: while prone, the speed line appends "stand up
  costs X ft, crawl at half", computed from the effective speed (so it
  composes with exhaustion). Immobilizing conditions still win
  outright: 0 ft, no partial readout.
- Sample sheet: Wren is prone with exhaustion 2, showing both
  interactions (15 ft walk, 15 ft swim, stand up costs 7 ft).

## What's in 2.18.0

- Per-character dice macros: macros can now bind to a character or stay
  table-wide. The Dice tab groups them ("Wren Halloway" above "Table"),
  and a "For <name> only" toggle picks the scope at save time. Scoped
  macros persist in the same dice-macros.json - files from before 2.18
  load as table-wide, untouched. Same-named macros can coexist across
  scopes (table "Initiative" vs Wren's "Initiative").
- Macro rolls are labeled: rolling a macro records history under its
  name, not the raw expression.
- Tool checks roll from the sheet: each tool proficiency row gains an
  ability menu (DEX default, per-roll choice - tools borrow their
  ability from the check) and a Roll button wired into the
  condition-aware roller, closing the gap from 2.15.0.

## What's in 2.17.0

- Print-friendly compact PDF: a second layout style for export -
  ink-light (no boxes, fills, or color), tighter spacing, abilities and
  vitals as text lines. File menu gains "Export Compact PDF...";
  "Export PDF..." keeps the styled layout.
- Both PDF layouts now include the proficiencies and tool lines in the
  header (previously Markdown/HTML only).

## What's in 2.16.0

- Conditions meet movement: grappled and restrained drop every speed
  (walking and extra modes) to 0, per the genre-standard rule. Custom
  conditions gain a "Speed 0" flag with the same effect. The vitals
  summary and the speed line in Markdown, HTML, and PDF exports show
  "0 ft (immobilized)" while it lasts - no more stale movement on a
  grabbed character.
- Sample sheet: Wren is currently grappled (vine snare) to show the
  interaction.

## What's in 2.15.0

- Tool proficiencies as a structured list: each tool carries a training
  tier (proficient or expertise) and the sheet computes the bonus over
  the raw ability modifier (tier multiplier x proficiency bonus) for
  tool checks. Edited in the identity block, exported in the identity
  head of Markdown and HTML. Old saves decode with an empty list;
  armor/weapon/language proficiencies stay in the free-text field.
- Sample sheet: Wren is expert with calligrapher's supplies and trained
  with a forgery kit.

## What's in 2.14.0

- Custom conditions: name your own states (homebrew, module-specific)
  with the same side-effect flags the built-ins carry - attack
  disadvantage and check disadvantage. They drive effective roll mode
  exactly like built-in conditions, show up in the roll UI's
  disadvantage source list, and export in the conditions line of
  Markdown, HTML, and PDF. Old saves decode with none.
- Sample sheet: Wren is "Vault-marked" (hinders checks) after the
  singing vault.

## What's in 2.13.0

- Movement modes: fly, swim, climb, and burrow speeds alongside walking
  speed, with hover (fly only) and a free-text source note. Shown in the
  vitals block and exported to Markdown, HTML, and PDF as one movement
  line. Old saves decode with walking speed only.
- Sample sheet: Wren gains an original Tideglass clasp curio that grants
  a swim speed.

## What's in 2.12.0

- Companions block: familiars, mounts, pets, and hirelings on the
  sheet with kind, AC, current/max HP (clamped), and notes. Its own
  draggable/hideable block, exported to Markdown, HTML, and PDF. Old
  saves gain the block on decode with an empty list.

## What's in 2.11.0

- Defenses: damage resistances, immunities, and vulnerabilities picked
  from the standard damage-type list. Typed damage applied in the
  vitals block adjusts automatically - resistance halves (rounded
  down) before temp HP, vulnerability doubles, immunity zeroes.
  Defenses show in the defenses row and all three exports.

## What's in 2.10.0

- Stowed gear: mark items stowed (dropped, cached, left at camp) to
  exclude them from carried weight and encumbrance. Stowed rows dim,
  the carried line shows the stowed total, and exports tag stowed
  items. Old saves decode with nothing stowed.

## What's in 2.9.0

- Custom spells: "Add custom" creates a spell straight on the sheet,
  and expanding any spell now edits it inline - name, level, school,
  casting time, range, duration, components, concentration/ritual,
  and detail text. Library spells can be personalized the same way.

## What's in 2.8.0

- Custom skills: add your own skills (name + governing ability) to the
  skills block and remove any skill from the list. Duplicate and blank
  names are refused; custom skills roll, export, and feed passive
  scores like built-in ones.

## What's in 2.7.0

- Ammunition tracking: opt-in ammo counter per attack, spent
  automatically on each attack roll (floor zero, attack disabled when
  empty). Library bows and crossbows start tracked at 20. Ammo counts
  appear in Markdown, HTML, and PDF exports. Old saves decode with
  tracking off.

## What's in 2.6.0

- Passive senses: Perception, Investigation, and Insight computed as
  10 + skill bonus, shown as stat plates in the vitals block and
  included in Markdown, HTML, and PDF exports.

## What's in 2.5.0

- Journal block: dated session-log entries on the sheet (date, title,
  text), draggable/hideable like every other block, exported to
  Markdown, HTML, and PDF. Old saves gain the block on decode.

## What's in 2.4.0

- Character portraits: pick any image for the identity block (downscaled
  to a bounded PNG inside the sheet file), initials placeholder when
  unset, and the HTML export embeds the portrait. ARCHITER ships no
  artwork - the portrait is always the user's own image.

## What's in 2.3.0

- Attunement tracker: the inventory header shows attuned items against
  the genre-standard cap of 3 ("Attuned 2/3") and flags the sheet when a
  character is over the limit.

## What's in 2.2.0

- Per-character roll history: every roll is tagged with the selected
  character, and the Dice tab history can filter between the whole table
  log and the current character's rolls. Older saved rolls stay in the
  shared log.

## What's in 2.1.0

- Versatile weapons: attacks added from the weapon library carry their two-handed damage die; a 1H/2H toggle on the attack row switches the rolled damage expression (genre-standard grip behavior). Roll labels note "(two-handed)".

## What's in 2.0.0

- **Currency consolidation**: one tap converts loose change into the
  fewest coins at the same total value (electrum folds into gold), so a
  loot haul stops sprawling across five denominations.

## What's in 1.9.0

- **Dice macros**: save the current dice notation as a named shortcut on
  the Dice tab - the table's usual rolls become one tap. Macros persist
  app-wide alongside the character files; invalid expressions never save.

## What's in 1.8.0

- **Compendium filters**: spells filter by school alongside the level
  picker; weapons filter by damage type. Filter options come from the
  library itself, so they stay honest as content grows.

## What's in 1.7.0

- **Character files**: export the selected character as a portable
  `.architer.json` file and import character files back - imports always
  get a fresh id, so a file can never overwrite the original. Lives in
  the File menu next to the sheet exports.

## What's in 1.6.0

- **Ruleset editor**: edit any ruleset in your library in place - rename
  it, add/remove abilities and skills, reassign each skill's ability.
  Saving normalizes the draft (blank entries dropped, dangling skills
  remapped) so a broken ruleset never reaches the library.

## What's in 1.5.0

- **Roll history persistence**: the last 50 rolls survive quitting the app
  mid-session, saved next to the character files; clearing history clears
  the saved record too.

## What's in 1.4.0

- **Compendium favorites**: star the spells, weapons, and armor you reach
  for; a favorites-only filter sits in the compendium toolbar. Favorites
  persist app-wide alongside the character files.

## What's in 1.3.0

- **Session restore**: the app reopens exactly where you left it - the
  last-selected character and the last-used detail tab (Sheet / Builder /
  Dice) survive relaunch.

## What's in 1.2.0

- **Critical hits**: an attack that rolls a natural 20 now automatically
  follows up with a "(CRIT)" damage roll - every damage die doubled,
  modifiers untouched.

## What's in 1.1.0

- **Print pass**: the PDF export now echoes the ink-and-brass theme (brass
  section headers and rules) and catches up to recent features - the header
  names the ruleset era and any custom ruleset, the attacks table gains a
  mastery column on 2024-style sheets, concentration and exhaustion notes
  print.

## What's in 1.0.0

- **Concentration tracker**: casting a concentration spell moves
  concentration to it (ending any previous one); a banner at the top of the
  Spells block shows what you're holding and can drop it.
- **Renders now exercise the dice**: the CI render harness seeds a few rolls
  so the dice screenshot shows the roll cards.

## What's in 0.9.0

- **Roll cards**: history entries are now styled cards - each die shows as
  a chip (dropped dice struck out), the advantage alternate sits beside the
  total, and natural 20s glow green while natural 1s burn red. The sheet's
  inline dice block shows the latest roll as the same card.

## What's in 0.8.0

- **Compendium browser**: a book icon in the sidebar opens a searchable
  library window - spells (filter by level, search name/school/text, ritual
  and concentration badges, full original descriptions), weapons (damage,
  range, finesse, properties), and armor (AC, category, cost). One click
  adds a spell to the character's list, a weapon to attacks, or equips
  armor. All entries are original content.

## What's in 0.7.0

- **Conditions that fight back**: hindering conditions now fold into the
  dice. Poisoned, blinded, prone, restrained, and frightened impose
  disadvantage on attack rolls; poisoned and frightened hinder ability
  checks. Chosen advantage cancels to a straight roll (genre-standard), and
  the roll history names the source - "Longsword attack (disadvantage:
  Poisoned)". A warning chip appears by the roll-mode picker while a
  hindering condition is active.

## What's in 0.6.0

- **Ruleset library**: shape your own game - edit a character's custom
  abilities and skills in the builder, then "Save as ruleset..." to keep the
  template in a persisted library. Apply any saved ruleset to any character
  later, or delete it from the library. The built-in Starfarer and Gumshoe
  examples still ship alongside.

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
