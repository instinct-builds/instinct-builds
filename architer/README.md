# ARCHITER

A native macOS character-sheet builder for tabletop RPGs — built from scratch,
no APIs, no dependencies. Original code and content with genre-standard
mechanics (ability modifiers, proficiency, advantage, spell slots).

## What's in 3.87.0

- **App icon**: original ink-and-brass d20 line art ships as the bundle
  icon - all ten macOS sizes rendered from a 1024 base plus a
  thicker-stroked small variant, assembled into the .icns at DMG time so
  no binary sits in git.
- **Real bundle version**: CFBundleVersion now carries the release version
  instead of a hardcoded "2".
- **Long-roster visual gate**: the render harness closes the owed gate -
  an eight-member roster through the party detail panel and the strip
  (viz-party-long-480/720, viz-party-long-strip-720), with the glance line
  derived over all eight members.
- **README catch-up**: the condensed log below covers 2.50.0-3.86.0.

## Version history, 2.50.0-3.86.0 (condensed)

One line per shipped version; the full entries live in git history.

- 2.50.0: journal entry reorder - chevron nudges on each entry persist the user's order, and the sheet exports + session recap follow it (recap now lists today's entries in journal order, not creation time)
- 2.51.0: journal entry collapse - long entries get a disclosure triangle (one-line preview when collapsed), state persisted per entry as optional isCollapsed; exports and recap always carry the full text
- 2.52.0: session digest entries land collapsed - JournalEntry(sessionDigest:) owns digest construction in ArchiterCore (tested), AppModel slims to one append
- 2.53.0: collapse-all/expand-all in the journal header - BlockCard gains an optional trailing accessory, isLong moves model-side and shared, setAllJournalCollapsed persists per entry
- 2.54.0: journal filter field in the header - case-insensitive date/title/body match with a shown/total count, display-only, pairs with collapse-all
- 2.55.0: copy single journal entry - per-row doc.on.doc button puts the entry's shareText (export head + body) on the pasteboard
- 2.56.0: duplicate journal entry - per-row plus.square.on.square button inserts a fresh-stamped copy right below the original
- 2.57.0: journal entry size labels - rows show 'N lines' for multiline entries and 'N words' for single-line ones, glanceable bulk without expanding
- 2.58.0: session digest naming prompt - the divider's book button opens an inline title field pre-filled with the session title; custom names ride the digest into the journal
- 2.59.0: journal entry templates - a From template menu stamps combat debrief, NPC meeting, or loot log outlines in as new entries, section headers prefilled and stamped today
- 2.60.0: journal search highlight - while the header filter is active, body hits surface as a highlighted snippet line under each matching row (first hit with a brass wash, '+N more' for extra lines), no expansion needed
- 2.61.0: journal entry pin/lock - a per-row pin fixes an entry at the top of the journal (piling in pin order), immune to reorder moves, with date/title/body read-only and move/delete hidden until unpinned
- 2.62.0: digest body format options - the session-divider naming row gains a Condensed/By actor picker; byActor groups roll lines under each roller (no-character rolls under 'Table'), and the choice is remembered via architer.digestFormat
- 2.63.0: copy filtered journal - while the header filter is active, a 'Copy filtered' button puts only the visible entries (head + body, display order) on the pasteboard; the 2.54.0 match rule moves model-side as JournalEntry.matchesFilter so view, export, and tests agree
- 2.64.0: journal bulk totals - the header shows a live 'N lines · M words' summary over the visible entries, following the filter; model-side JournalEntry.bulkSummary, unit-tested
- 2.65.0: session recap preamble - a per-character 'Recap intro' field in the journal block; its line is prepended to every Copy today recap (optional, decodeIfPresent, blank clears to nil)
- 2.66.0: journal timestamp export option - an Exports menu toggle drops per-entry creation times from Markdown/HTML/PDF journal heads for clean archival sheets (default on keeps the 2.47.0 stamped heads); JournalEntry.exportHeadWithoutTime, threaded through every export path
- 2.67.0: roll-history session naming - a pencil on each session divider opens an inline rename field; the custom name replaces the generated 'Session N - <day>' title, rides the digest as its fallback title, and persists (keyed by the session's oldest roll stamp, stable as new rolls land; blank restores the generated title; undated runs stay unnameable)
- 2.68.0: named sessions in session-log exports - custom session names (2.67.0) annotate the day headers of session-log.txt, session-log.md, and the compact-PDF appendix, so exported logs read like the named history pane (namedDayGroups: sessions never span days, names list oldest-first, days with no named session keep their plain title)
- 2.69.0: session stats line - each roll-history divider gains a compact summary under its title (roll count, high/low totals, natural 20/1 tallies over kept d20 dice only; crits appear only when nonzero), giving the table a glanceable per-session read without opening the digest
- 2.70.0: copy session from the divider - a copy button next to the rename pencil writes the session as paste-ready plain text (title including custom name, 2.69.0 stats line, rolls oldest first), for notes without filing a journal digest
- 2.71.0: session notes - a free-text note per session (persisted alongside its name, edited in the same inline divider form), shown italic under the stats line, carried into copy text between the stats line and the rolls, and following its session's name into session-log export and compact-PDF headers in parentheses
- 2.72.0: export this session - a divider button writes the session as its own Markdown file via save panel (custom name as title, note, 2.69.0 stats line, oldest-first roll table with the session-log pipe escaping; filename sanitized for / and :)
- 2.73.0: self-describing digests - a filed digest's body opens with the session's stats line (2.69.0) and its note (2.71.0) when set, so a journal digest reads standalone without cross-referencing the history pane
- 2.74.0: 'Latest session' history scope - a checkbox in the History header shows only the newest session's rolls (pane, count, and Copy all follow); composes with the character scope and text filter
- 2.75.0: session span in the stats line - dividers, digests, share text, and exports now read '9 rolls - high 28 - low 6 - span 2h 14m' (first to last roll); lone and undated sessions print no span
- 2.76.0: day-summary line on export day headers - 'Today - Night watch - 3 sessions - 4 rolls' across the text log, Markdown log, and compact-PDF appendix; also fixes the 2.68.0 name annotation silently dropping on the export path (oldest-first order collapsed each day into one session keyed by its newest roll, so pane-set names missed)
- 2.77.0: Copy day - a calendar button on the divider that opens each day copies the whole day's rolls as text (named, summarized day header + chronological lines), the day-level counterpart of copy-session; follows the visible scope and filters
- 2.78.0: Crits-only history toggle - a History-bar chip filters to rolls with a kept natural 20 or 1 (the crits the table saw), composing with the character scope, Latest session, and the text filter. Explicit public inits on DieResult/RollResult so the render harness can build crafted history rolls
- 2.79.0: Delete roll from history - each history card gets a trash button that removes just that entry (mis-rolls happen; Clear stays all-or-nothing). removingFirst drops only the first matching roll
- 2.80.0: Per-session delete - each session divider gets a trash button that drops the whole session (re-segmented from the full log so filtered views still delete every roll) plus its custom name and note. removingAll drops one instance per removed entry
- 2.81.0: Undo delete - an Undo button in the History bar restores the last per-roll or per-session delete (full snapshot: rolls, session name, and note). One level, in memory; the next roll or Clear consumes it
- 2.82.0: Edit roll label - a pencil on each history card swaps the title for an inline field and renames the label in place; blank restores the expression. relabelingFirst trims, renames the first match, and clears on blank
- 2.83.0: Copy single roll - a copy icon on each history card puts that roll's own history line on the pasteboard (reuses the 2.41.0 historyLine contract, already unit-tested there)
- 2.84.0: Star a roll - a star toggle on each history card marks the memorable ones (manual curation next to the automatic crits filter), with a Starred chip in the History bar composing with the other scopes. RollResult.starred is optional (decodeIfPresent) so old saves decode unchanged and nil stays unencoded
- 2.85.0: Copy starred - a Copy starred button in the History bar (visible while stars exist) copies just the starred rolls oldest-first with a count header: the night's highlight reel in one click
- 2.86.0: Unstar all - an Unstar all button in the History bar (visible while stars exist) clears every star in one tap, the reset half of the copy-then-reset highlight-reel loop; clearingStars in ArchiterCore nils stars so saved logs stay lean
- 2.87.0: Session stars - a star button on each session divider stars every roll in the session in one tap (toggles clear when all are starred): bulk curation for the whole-fight-was-the-night case, filled divider star shows the state
- 2.88.0: Starred-only Markdown export - an Export starred button in the History bar (visible while stars exist) saves the highlight reel as a .md file: count heading plus the starred rolls oldest first as a table, matching the session export's shape. The star arc's output side, past the pasteboard
- 2.89.0: Starred digest - a Digest starred button in the History bar (visible while stars exist) files the highlight reel into the journal as one entry titled 'Starred rolls (N)', same shape as a session digest. The star arc reaches the journal
- 2.90.0: Starred-only session-log range - SessionLogRange gains 'Starred only', so the session-log text/Markdown exports and the compact-PDF appendix can carry just the starred rolls; unstamped starred rolls are kept (starring is deliberate, not a date range)
- 2.91.0: Reroll-and-star - a starred card's roll-again carries the star onto the new roll, so the table's highlight reel survives the re-roll. The original keeps its own star; the carry no-ops when the reroll records nothing (incoming damage, unparseable expression)
- 2.92.0: Per-roll notes - a free-text note on any roll, shown under the card's label (note.text button, inline field, blank clears) and carried into the session-log text export (indented note line), the Markdown export (dash-appended Roll cell, pipes escaped), and the compact-PDF appendix (indented, greyed). Optional Codable field, so old saves decode unchanged
- 2.93.0: Notes in share text - a noted roll's note rides every paste as an indented line under its roll: the Copy and Copy starred blocks (historyText), Day copy, session share, and both digest layouts (condensed and byActor). One shared shareLines helper; session-log rows and copy-one-roll keep the single-line contract
- 2.94.0: Notes in the session recap's ROLLS section - the raw roll list rides the shared shareLines helper, so a noted roll's note appears indented under its line there too, matching every copy/share block and digest. Unnoted rolls keep the single-line contract
- 2.95.0: Notes in session/starred Markdown exports - a noted roll's note rides its table cell, dash-appended and pipe-escaped, in the per-session and starred Markdown files. One shared markdownRollCell helper behind all three Markdown exporters; the session export proof now writes after the roll note lands so the Fireball row shows its story
- 2.96.0: History filter matches note text - the Filter rolls field now searches a roll's note alongside its label and expression, so a DM filtering for the story finds the roll that carries it. Same case/diacritic-insensitive match; blank-query and no-hit behavior unchanged
- 2.97.0: Copy filtered label in dice history - with a history filter drafted the bar's Copy reads Copy filtered, so the button says when the filter narrows what it copies. The action already rides visibleHistory (notes included via shareLines); this is the discoverability label, matching the journal's explicit Copy filtered precedent
- 2.98.0: Filtered-copy header - Copy filtered now prepends 'Filtered: <query> (N of M)' to the paste, so a narrowed copy says what it is, matching Copy starred's header precedent. Core filteredShareText (unit-tested, notes ride via shareLines), AppModel copyFilteredRollsToPasteboard, the Copy filtered button routes through it when a query is drafted; unfiltered Copy is unchanged
- 2.99.0: Digest filtered rolls - file the filtered history subset into the journal as one digest entry titled with the query, notes riding the digest body; button appears beside Copy filtered only while a filter is active
- 3.0.0: named filter presets - save the current history filter under a name and re-apply it from the filter bar's bookmark menu; case-insensitive upsert keeps menu order, presets persist across launches
- 3.0.1: collapse the Copy/Digest/star cluster while the preset naming form is open so the filter bar never wraps
- 3.1.0: export filtered rolls as Markdown - the starred export's table shape headed by the query and hit count, notes riding the roll cells; completes the filtered family (find, say, declare, file, save, export)
- 3.2.0: collapse the star cluster into a Starred menu when the filter cluster is also visible - the bar stays on one line; one-tap buttons kept when no filter is drafted
- 3.3.0: delete filtered rolls - remove the filter-visible subset behind an inline confirm, with one undo step via the existing full-snapshot HistoryDeletion
- 3.3.1: collapse Digest/Export filtered and Copy while the filtered-delete confirm is open - the 3.0.1 discipline applied to the confirm state so the bar never wraps
- 3.4.0: Clear-button confirm parity - emptying the whole log asks inline first, the same idiom as Delete filtered; clusters collapse while the confirm is open
- 3.5.0: Undo names its target - the button reads Undo delete (N rolls) from the deletion's removed count
- 3.6.0: filter-preset rename - presets menu gains a Rename submenu with an inline form; the rename keeps the preset's filter and position
- 3.7.0: preset-form conflict hints - save and rename forms say why they stay open; blank name disables the button, a clash names the existing preset, save-overwrite notes the replace
- 3.7.1: hint-proof wording - the save-overwrite line describes the replace note with Save enabled instead of borrowing the rename's rejection wording
- 3.8.0: active preset marker - the bookmark fills and the menu checkmarks the preset whose query the filter text exactly matches
- 3.9.0: save-form prefill from the active preset - the name draft starts with the matched preset's name instead of the raw query text
- 3.10.0: filter clear X - a small clear button appears next to the filter field while it holds text
- 3.11.0: filtered count names its noted rolls - the bar reads N of M, K with notes when the subset carries notes
- 3.12.0: filter-bar overflow - Digest/Export/Delete collapse into an ellipsis menu when a filter is set; Copy filtered and Journal stay top-level; the delete confirm still opens inline
- 3.13.0: starred count on the filtered count - the bar reads "N of M, K with notes, S starred", mirroring 3.11.0's noted count
- 3.13.1: keep the filtered count to one line - lineLimit(1) + minimumScaleFactor(0.85) + layoutPriority(1) so the notes/starred suffixes scale instead of wrapping
- 3.14.0: bar chips never wrap - Latest session/Crits/Starred labels take their ideal one-line width under bar pressure, same treatment as the 3.13.1 count
- 3.14.1: star menu label keeps its full width - lineLimit(1) + fixedSize() so the 3.14.0 chip fix's pressure lands on the filter field, not the menu label; star menu out-prioritizes the filter field - layoutPriority(1) on the menu itself (label-level fixedSize lost to the menu chrome's compression)
- 3.14.2: absorb the bar deficit for real - filter field maxWidth 160 -> 110 and the count's notes suffix compacts to "noted"; every label right of the field stays whole
- 3.15.0: pin favorite macros - a pin toggle on each macro row floats it to the top of its owner group; pins persist, survive edits, and drop their key when lifted
- 3.15.1: strengthen the macro-pin proof - a second table macro is added at the end of the harness and pinned, so the render shows it jumping above Fireball with a filled accent pin
- 3.16.0: delete-filtered count preview - the overflow Delete item names the count it would remove ("Delete 6 filtered rolls..."), the only pre-click signal since the 3.12.0 collapse; label builder in ArchiterCore with unit tests, harness records the exact menu string
- 3.17.0: session-delete label names the session - the trash hover now reads 'Delete session "Ember Warrens delve" (10 rolls) from history', the only pre-click target signal since the delete fires without a confirm; label builder in ArchiterCore with unit tests, harness records the exact strings
- 3.18.0: undo count on hover - the Undo hover names what the restore brings back ("Restore session \"Ember Warrens delve\" (9 rolls)" when the deleted session was named, count-only otherwise); label builder in ArchiterCore with unit tests, harness records the live and named cases
- 3.19.0: apply a history roll to HP - a heart action on each roll card applies the total to the selected character (plain click = damage with defenses folded in, right-click offers healing), one Binding write = one undo step named in the Edit menu while on top; VitalsBlock goes public for the applied-state render
- 3.20.0: DC / target checks - a target DC on macros and the dice bar records onto the roll, history cards show a derived met/missed badge (attack rolls follow the genre-standard nat-20/nat-1 auto rule, checks stay pure arithmetic), Roll Again preserves the contest through RerollSpec, and the session stats line counts DC met x/y only when targeted rolls exist (untargeted sessions byte-identical); no undo surface - roll recording was never undoable
- 3.21.0: combo macros - a macro can carry 2+ self-contained parts (label + expression + optional damage type); one tap rolls each part in order as its own history entry through the existing roll paths (reroll, star, apply-to-HP, journal, stats all per part), the stored expression becomes the derived summary, the row editor gains a parts form with add/remove and a collapse back to single, and pre-3.21.0 macro files decode unchanged
- 3.22.0: initiative tracker - a Dice-pane section tracks combat order: entries (sheet-linked with the character's live initiative bonus, or ad-hoc name + bonus), Roll all through the dice engine without touching History, per-entry reroll and hand-editable totals, total-desc order with ties on bonus then insertion, the active turn advancing and wrapping into round counts, End combat clearing totals/round while keeping entries for the rerun, and JSON persistence so a fight survives quitting
- 3.23.0: sheet-to-dice bridge - save a sheet attack as a combo macro (attack + damage parts, per-character scope, refresh-on-resave upsert)
- 3.24.0: condition advisory banner in the dice pane - pre-roll visibility for hindrances/exhaustion the roller already enforces (advisory-only, hidden when clean)
- 3.25.0: level-up preview sheet - derived N -> N+1 delta (proficiency, hit dice, slot deltas, notes line) with Confirm riding the existing levelUp machinery
- 3.26.0: group checks - whole-roster skill rolls with per-participant conditions/exhaustion riding the existing enforcement path; ephemeral derived verdict (half or more beats the DC); history stays one auditable, rerollable entry per participant
- 3.27.0: reroll carries its character - Roll Again on another character's entry re-derives conditions from THAT character (RerollSpec.characterID, optional so old history decodes unchanged); group specs now store the raw bonus + normal mode so re-derivation never double-applies the penalty
- 3.28.0: concentration checks on damage - incoming damage to a concentrating character forces a CON save (DC max(10, damage/2), derived from what actually landed); a fail drops the spell with a notes milestone; the save rides rollCheck so conditions, identity stamps, and reroll come free
- 3.29.0: party overview strip - read-only roster cards on every tab (name, level, HP bar + temp badge, condition/concentration chips with +N truncation); tap selects via the sidebar's own binding; hidden at a roster of one so single-character chrome and renders stay untouched
- 3.30.0: condition timers - rounds countdowns on active conditions (built-in rawValue / custom UUID keys, decodeIfPresent), ticking once per initiative round wrap across the whole roster through the per-character undo snapshot path; a timer at 0 ends the condition with a notes milestone; party-strip chips carry the remaining rounds
- 3.31.0: group saves - whole-roster saving throws riding the 3.26.0 group machinery (per-character proficiencies, save-kind semantics, exhaustion the only tag); rider: label kind detection learns saves (attack/save/check) so solo saves stop being condition-hindered, aligning with the model's own semantics
- 3.32.0: character delete confirmation - the roster trash arms an inline confirm (caption + destructive Delete + Cancel) matching the history-delete/clear patterns; Delete fires only from the armed state and warns the undo stack dies with the character
- 3.33.0: concentration duration timers - casting a concentration spell derives a rounds countdown from its duration text (minutes/hours converted, unparseable gets no timer rather than a wrong one); the initiative round wrap ticks it and drops concentration at 0 with a notes milestone; every concentration exit clears the timer; spells row shows the countdown with a stepper
- 3.34.0: encounter difficulty estimate - party thresholds derive from roster levels, enemy strength is entered row by row (count x CR, fractions supported), genre-standard count multiplier and band verdict with the raw derivation shown; honest-limits caption in the UI; rows persist table-wide like macros; Dice tab section under the initiative tracker
- 3.35.0: party-strip concentration countdown - a running concentration timer rides the chip ('Concentrating: Faerie Fire (9)'), matching the condition countdowns; read-only, derived at render
- 3.36.0: CR on initiative entries + live-fight estimate - enemy CRs ride the tracker (entered once, never duplicated); the encounter section derives a live verdict with the derivation and the un-CR'd exclusion captioned
- 3.37.0: start fight - planner rows push into the tracker as individual CR'd entries (replace with armed confirm, global per-CR numbering, flat bonus 0, invalid rows skipped); the live estimate then derives from the push
- 3.38.0: tracker-entry rename - the pencil swaps the row's name for an inline field; blank keeps the current name; CR and total ride along untouched
- 3.39.0: add to fight - planner rows append as a wave (non-idempotent by design); numbering continues per CR value through renames, turn state carries, arrivals sink until rolled; the live verdict re-derives over the bigger fight
- 3.40.0: initiative bonus edit-in-place + one-click add party - the last frozen row field edits like CR/total (invalid keeps), and the roster joins the tracker in one tap with name dedup
- 3.41.0: award XP from the fight - the planner-tracker loop closes: pool derives from tracker CRs (base pays, adjusted budgets), preview with equal-split/full-pool toggle and live re-split, level-up notes, one undo step per character
- 3.42.0: milestone-safe leveling - level is a floor: hand-raised levels hold through XP awards until the track passes them, award preview reads the stored level so it agrees with the apply, (milestone) caption on the XP row
- 3.43.0: encounter library + labeled enemy rows - named encounters save and reload (labels carried), overwrite/load-replace/delete arm confirms, and labeled rows number by the label field so waves stay rename-proof
- 3.44.0: pre-fight restore + fight recap - Start fight snapshots the displaced tracker one level deep (Restore pre-fight arms a confirm, consumed on use, never chains), awardFightXP records what the fight paid, and End combat files a derived recap line (CR breakdown, rounds, XP recipients) to the selected character's journal; idle trackers file nothing. Retires the 3.37.0 cannot-be-undone caveat
- 3.45.0: table log + party rest - the party-level session record (manual entries + the fight recap dual-files its identical derived line; deletes arm inline, day label derives from createdAt) and one-tap short/long rest for the whole roster, each member riding their own undo stack; rough up via the tracked selected binding so the rest/undo proof restores the true pre-rest state (second build read 'back to 0' off a stale stack frame); undo check now prints explicit booleans
- 3.46.0: saved-encounter tactics notes (lenient decode, overwrite keeps note+identity, inline edit) + cross-character journal party search (read-only lens with attribution, derived never stored) + 3 core tests; add the 3.46.0 core tests (untracked at 5c10b8b - commit -a misses new files)
- 3.47.0: party damage/heal + table-log export
- 3.48.0: library difficulty bands + party-search jump
- 3.49.0: table-log entry edit + encounter share text
- 3.50.0: library rename and duplicate
- 3.51.0: party-condition apply
- 3.52.0: party condition-remove - the scoped-out sibling of 3.51.0's apply
- 3.53.0: party condition summary row - who's holding what plus clocks at a glance
- 3.54.0: party summary click-through - tap a name, land on their sheet
- 3.55.0: condition-remove targeting - remove from a chosen subset
- 3.56.0: condition apply-to-subset - grant to a chosen few
- 3.57.0: summary-row expiry highlight - a clock at 1 reads in accent
- 3.58.0: condition notes on the summary line - the why in parens
- 3.59.0: header reclaim - Note at field width, Condition without the suffix
- 3.60.0: custom conditions on the summary line - name-identity party apply/remove, one iteration rule with the chips
- 3.61.0: rests run out timed conditions, built-in and custom
- 3.62.0: per-character rests run out timed conditions (parity)
- 3.63.0: one flag-derived roll-condition marker producer in Core
- 3.64.0: typed notes ride the party-apply log line
- 3.65.0: removal log carries the dropped note, per holder
- 3.66.0: undo logs restored conditions, table log filters by condition
- 3.67.0: redo logs re-removed conditions, table-log filter persists across launches
- 3.68.0: party detail panel - every condition's note and clock at full width
- 3.69.0: persist history query and prove multi-row party chip wrap
- 3.70.0: Edit menu names condition undo steps - apply, remove, round-wrap tick
- 3.71.0: incapacitating conditions break concentration on landing - derived Core classification, one shared apply walk, undo restores both
- 3.72.0: end-of-turn save-ends conditions
- 3.73.0: condition immunity by lineage (derived grants + stored set, all party apply paths)
- 3.74.0: max-HP reduction (derived effective max, long-rest lift)
- 3.75.0: drain-on-damage (tagged damage types lower max HP by HP taken)
- 3.76.0: typed party damage (optional type through typed applyDamage, one log line)
- 3.77.0: Max -N drain chip on party strip and detail
- 3.78.0: partial max-HP restore (core rule, party + targeted path, one log line)
- 3.79.0: drain chip pinned out of overflow (strip HP row) + visual proof renders for drain surfaces; party HP buttons get their own row (truncated at narrow width); drained vitals render; vitals action row split (heal/temp own row, buttons fixed-size) and armor row no longer truncates at narrow width; vitals polish (Damage field, hit die picker, passive plates) + full drained render; vitals 480 polish (rest buttons, spend hit die, init misc, initiative row)
- 3.80.0: drain recovery on long rest (per-character partial lift, Core rule + suite + proof + control); retry hdiutil verify on runner EAGAIN; full-height recovery render
- 3.81.0: long rest log line names drain lifted (party and per-character) + proof
- 3.82.0: per-character long rest drain-lift log proof (sheet button, repeated partial lifts, undrained no-op)
- 3.83.0: Split gold (party) - exact-copper loot split across the roster (Core rule, suite, proof, control)
- 3.84.0: per-member include/exclude on Split gold (checkbox row, derived preview, log names who was left out) + proof + render
- 3.85.0: Split gold Amount accepts coin suffixes (CoinAmount parser, pot logged as coins, sub-copper pots rejected) + suite + proof; widen party Amount field so typed coin hauls are not clipped
- 3.86.0: party table facts - AC, passive Perception, inspiration per detail row plus a derived glance line (Core, suite, proof, render)

## What's in 2.49.0

- **Roll a session into the journal**: session dividers in dice history
  gain a one-tap button that drops the whole session's rolls into the
  journal as one entry - titled by the session, rolls oldest-first,
  stamped under today's date. Hidden while auto-log is on (the rolls are
  already journaled), matching the per-roll pencil.

## What's in 2.48.0

- **Session dividers in dice history**: the history list now splits into
  numbered sessions under its sticky headers - "Session 2 - Today",
  "Session 1 - Yesterday". A new session starts when the calendar day
  rolls over or when neighbouring rolls sit more than four hours apart,
  so coming back after a long break opens a fresh session on the next
  roll. Numbering runs oldest-first, so a session keeps its number as
  the night goes on.

## What's in 2.47.0

- **Journal timestamps in exports**: stamped journal entries (auto-logged
  rolls, new hand-written entries) render their creation time in the
  PDF, HTML and Markdown exports - "2026-09-24 06:51 - 4d6kh3" - closing
  the loop with the session recap. Unstamped entries from older saves
  keep their date-title head.

## What's in 2.46.0

- **Session recap**: a Copy today button on the sheet's journal block
  copies one shareable text block - today's journal entries, then today's
  rolls, oldest first, ready to paste into the group chat. Auto-logged
  roll entries now carry the roll's day and creation stamp, and
  hand-written entries stamp on creation, so the recap knows what
  happened today. Entries from older saves sit out of "today" until
  re-saved.

## What's in 2.45.0

- **Auto-log rolls to the journal**: a Journal toggle in the dice history
  header makes every roll that lands in history also land in the selected
  character's journal - a true session record. While it is on, the
  per-card journal pencil hides (the roll is already there). Persisted,
  off by default.

## What's in 2.44.0

- **Session-log Markdown export**: File > Export Session Log (Markdown)
  saves the same rolls and range as the text export, as one Markdown
  table per day (time, roll, total) - drops straight into Obsidian or
  Notion session notes.

## What's in 2.43.0

- **Reroll variants**: right-click a history card's reroll button to roll
  again With Advantage / With Disadvantage (checks) or With +2 / With -2
  (anything rerollable) - mode flips request a new d20 mode so conditions
  still apply; modifiers shift the check bonus or append to the
  expression, and defense notes recompute on the new total.

## What's in 2.42.0

- **Session-log text export**: File > Export Session Log saves the
  character's rolls as a day-grouped plain-text file - the same rolls and
  range the compact-PDF appendix would print, no PDF required.

## What's in 2.41.0

- **Session-log appendix date range**: the compact-PDF appendix can now print
  all rolls, today only, or the last 7 days (File > Compact PDF: Session Log
  Range). Range is persisted; unstamped pre-2.35.0 rolls only appear in
  "All rolls", since an unplaceable roll inside a date range would mislead
  the printout.

## What's in 2.40.0

- Roll again from history: every roll card on the Dice tab gains a
  reroll button. Rolls made in 2.40.0+ replay their undecorated inputs,
  so condition tags and outgoing-defense notes recompute against the
  character as they are right now; older rolls reroll the same notation
  under their recorded label. Incoming-damage rolls are the one
  exception - no reroll button, because rolling again is not taking
  more damage.

## What's in 2.39.0

- Compact-PDF session-log appendix: a new opt-in toggle ("Compact PDF:
  Session Log Appendix") appends the exported character's roll history to
  compact PDF exports as a chronological record - oldest rolls first,
  grouped under the same "Today"/"Yesterday"/date headers as the Dice
  tab - starting on its own page so the sheet and the log file
  separately. Off by default: the compact layout is for cheap printing,
  so extra pages stay opt-in.

## What's in 2.38.0

- History grouped by day: the Dice tab history now sorts under sticky
  date headers - "Today", "Yesterday", or the date - that stay pinned
  while you scroll, built on 2.35.0's timestamps. Rolls with no recorded
  time (pre-2.35.0) collect under "Undated". Scope and text filters
  apply first, so searching "fire" groups only the matching days.

## What's in 2.37.0

- Inventory consume/restock buttons: every item row gains one-tap - and
  + buttons around the quantity (replacing the stepper), so using a
  potion mid-fight is one click. Every tap is a normal edit on the
  character, so Cmd-Z walks back consumptions one at a time; the model
  clamps at 0 (consume disables) and 999 (restock disables). Pairs with
  2.34.0: depleted rows can then vanish from compact PDFs.

## What's in 2.36.0

- Per-macro damage-type tags: edit a macro and pick a type ("Fireball -
  fire"), and rolls from it carry the same outgoing-defense note attack
  damage gets - "Fireball (fire: resist 7 - immune 0 - vuln 28)". The
  row shows a small type chip next to the expression; duplicating a
  macro keeps its tag. Macros saved before this version decode
  unchanged and roll exactly as before, and an unknown stored tag fails
  safe to untyped.

## What's in 2.35.0

- Roll history timestamps: every roll now records when it was made. The
  Dice tab history rows show a small clock time (hover for the full
  date), and the Copy export gains a leading "[HH:mm]" time column -
  "[18:42] Stealth check: 25 (1d20+7)". Rolls saved before this version
  have no recorded time: they decode unchanged and export in the 2.32.0
  format.

## What's in 2.34.0

- Compact-PDF option to hide empty inventory rows: File > Compact PDF:
  Hide Empty Rows toggles a persisted preference, and compact exports
  (both orientations) then drop zero-quantity rows - depleted potions,
  spent ammo - noting the hidden count ("(2 empty rows hidden)") so
  nothing vanishes silently. An all-depleted pack prints "All items
  depleted" instead of a blank section. The styled full-sheet PDF and
  every other export are unchanged.

## What's in 2.33.0

- Per-character free-roller type memory: the Dice tab damage-type picker
  now remembers a choice per character - Wren's free rolls stay typed
  fire while Bruk's stay untyped. Characters with no choice yet inherit
  the table-wide selection made with no character selected (the 2.30.0
  behavior), and choosing "No type" for a character is an explicit
  opt-out that beats a typed table default.

## What's in 2.32.0

- Roll history export: a Copy button on the Dice tab History row copies
  the shown rolls to the clipboard as text - one line per roll, oldest
  first ("Stealth check: 25 (1d20+7)"), ready to paste into session
  notes. It exports exactly what you see: the All/character scope and
  2.29.0's text filter both apply.

## What's in 2.31.0

- Compact-PDF landscape export: File > Export Compact PDF (Landscape)...
  lays the compact sheet out on a rotated letter page - wider columns for
  long inventory/feature lines and wide tables. Portrait stays the
  default; the styled layout and all existing exports are unchanged. The
  whole compact layout flows off the page size, so 2.25.0's widow guard
  and 2.28.0's running header work in both orientations.

## What's in 2.30.0

- The free-roller damage-type picker now remembers its selection across
  app launches (persisted like the last-selected character). Pick "fire"
  once and every free roll stays typed until you switch back to "No
  type". The saved raw-value vocabulary is pinned by a test so a future
  case rename can't silently drop the selection.

## What's in 2.29.0

- Dice history filters: a "Filter rolls" field on the Dice tab narrows
  history by label or expression text (case- and diacritic-insensitive),
  composing with the All/character scope picker - "fire" finds the typed
  damage rolls, "2d6" the matching expressions, a macro name its rolls.
  While a filter is active a "shown of total" count appears next to it.

## What's in 2.28.0

- Compact-PDF running header: continuation pages (page 2+) now carry the
  character name at the top left and "continued" at the top right, with a
  rule underneath - loose pages stay attributable at the table. Page 1
  keeps its big title block, single-page exports get nothing extra, and
  the styled layout is unchanged.

## What's in 2.27.0

- Free-roller defense notes: the Dice tab's free roller gains a damage-type
  picker next to Roll. Typed rolls record with the same outgoing-defense
  annotation attack rolls carry - what the total deals against resistance,
  immunity, and vulnerability (e.g. "2d10+3 (fire: resist 7 - immune 0 -
  vuln 28)"). "No type" keeps rolls untyped exactly as before. Pairs with
  2.24.0's attack-side notes; quick-add to journal carries the note too.

## What's in 2.26.0

- Macro duplicate button: every saved dice macro row (character and
  table-wide) now has a duplicate control. The copy keeps the expression
  and owner binding, lands in the same macro group, and is named
  "<name> copy" - bumped to "copy 2", "copy 3", ... when that name is
  taken. Scoped ids mean another character's same-named macro never
  forces a bump.

## What's in 2.25.0

- Compact-PDF widow guard: a section header now travels with its first
  entry. Headers are held back until the first entry's space check runs,
  so a header can never sit alone at the bottom of a column while its
  content starts the next one. Applies to every compact section; the
  styled layout is unchanged.

## What's in 2.24.0

- Outgoing-defense notes: attack damage rolls now carry what the total
  deals against each defense on the target - "Fire Bolt damage (fire:
  resist 6 - immune 0 - vuln 26)" - using the same halve-down / zero /
  double math as incoming defenses (2.20.0). Typed attacks get the note;
  untyped roll plain.
- Journal quick-add: every roll card has a pencil - one tap appends the
  roll (label, total, expression) to the selected character's journal.

## What's in 2.23.0

- Per-tool default ability, persisted: the ability menu on a tool
  proficiency row now saves with the sheet, so Calligrapher's supplies
  stays on INT (or whatever the table uses) across launches instead of
  resetting to DEX. Saves written before 2.23 decode unchanged (no
  default = DEX as before).
- Macro edit-in-place: every macro row on the Dice tab has a pencil;
  name and expression become editable inline with save (disabled until
  the expression parses) and cancel. Character-bound macros keep their
  owner when renamed.

## What's in 2.22.0

- Compact PDF entry keep-together: a feature's name and detail lines, a
  journal entry's head and body, a personality label and its value, a
  companion's stat line, and each spell-level list now move as a unit -
  if the entry doesn't fit at the bottom of a column, it starts the next
  column or page instead of splitting. Entries taller than a full column
  still flow normally. The styled layout is unchanged.

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
