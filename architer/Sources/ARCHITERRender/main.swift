#if os(macOS)
import SwiftUI

import AppKit
import ARCHITERUI
import ArchiterCore

// Renders the app's key views with a rich sample character to PNGs, plus the
// PDF/HTML/Markdown exports, so CI can attach visual proof to each build.
// Usage: architer-render <output-directory>

func renderPNG<V: View>(_ view: V, width: CGFloat, name: String, outDir: String,
                        minHeight: CGFloat = 120, maxHeight: CGFloat = .infinity) {
    let hosting = NSHostingView(rootView: view)
    hosting.frame = NSRect(x: 0, y: 0, width: width, height: 100)
    hosting.layoutSubtreeIfNeeded()
    let fitting = hosting.fittingSize
    let size = NSSize(width: width, height: min(max(fitting.height, minHeight), maxHeight))
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.title = name
    window.contentView = hosting
    hosting.frame = NSRect(origin: .zero, size: size)
    window.layoutIfNeeded()
    hosting.layoutSubtreeIfNeeded()
    guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
        print("render failed (no bitmap): \(name)")
        return
    }
    hosting.cacheDisplay(in: hosting.bounds, to: rep)
    if let data = rep.representation(using: .png, properties: [:]) {
        let path = "\(outDir)/\(name).png"
        do {
            try data.write(to: URL(fileURLWithPath: path))
            let nonWhite = data.count
            print("rendered \(name).png (\(nonWhite) bytes, \(Int(size.width))x\(Int(size.height)))")
        } catch {
            print("render failed (write): \(name): \(error)")
        }
    } else {
        print("render failed (png encode): \(name)")
    }
    window.close()
}

@MainActor
func run(model: AppModel, character: Character, outDir: String) {
    // Seed roll history so the dice render and the sheet's inline dice block
    // exercise the roll cards (kept/dropped chips, advantage, crit glow).
    // 2.45.0 proof: auto-log on - every roll below also lands in the
    // journal, so the sheet render's journal block lists them (exports
    // keep the pristine character for byte-stability).
    model.autoLogRollsToJournal = true
    model.roll("4d6kh3")
    model.roll("2d6+3")
    model.rollCheck("Stealth check", bonus: 7, mode: .advantage)
    model.roll("1d8+1d4+2")
    model.roll("d20")
    // Seed macros so the dice render shows both groups (character + table),
    // and a tool roll so history shows the 2.18 roll-from-sheet path.
    model.saveMacro(name: "Fireball", expression: "8d6", damageType: "fire")
    // 2.36.0 proof: a typed macro roll lands in history with the
    // outgoing-defense note, and the macro row shows its tag chip.
    model.rollMacro(DiceMacro(name: "Fireball", expression: "8d6", damageType: "fire"))
    model.saveMacro(name: "Sneak attack", expression: "1d8+4d6+3", forCharacter: character.name)
    let tool = character.toolProficiencies[0]
    model.rollCheck("\(tool.name) check (INT)", bonus: character.toolBonus(tool, ability: .intelligence))
    // 2.24.0 proofs: an attack whose damage history entry carries the
    // outgoing-defense note. While auto-log (2.45.0) is on the roll already
    // lands in the journal, so the manual quick-add (the hidden pencil
    // path) stays out - otherwise the entry would duplicate.
    if let fireBolt = character.attacks.first(where: { $0.name == "Fire Bolt" }) {
        model.rollAttack(fireBolt, for: character)
        if !model.autoLogRollsToJournal, let rolled = model.rollHistory.first {
            model.addRollToJournal(rolled)
        }
    }
    // 2.37.0 proof: a zero-quantity row renders its consume button
    // disabled in the gear block below.
    if var sel = model.selected?.wrappedValue {
        sel.inventory.append(InventoryItem(name: "Arrows", quantity: 0, weight: 1, category: "Ammunition"))
        model.selected?.wrappedValue = sel
    }
    let width: CGFloat = 1180
    // Render the model's copy: the journal quick-add above mutated it.
    let sheetCharacter = model.selected?.wrappedValue ?? character
    renderPNG(
        SheetColumnView(character: .constant(sheetCharacter))
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: width, name: "sheet-full", outDir: outDir)
    renderPNG(
        BuilderView(character: .constant(character))
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: width, name: "builder", outDir: outDir, minHeight: 700)
    // Seeded after the sheet render so the resisted total lands in dice
    // history without lowering the sheet's HP bar.
    model.rollIncomingDamage("2d6+3", type: .fire)
    // 2.40.0 proof: roll the oldest raw roll again from its card - history
    // gains a second 4d6kh3 entry at the top, stamped now.
    if let oldest = model.rollHistory.last { model.rollAgain(oldest) }
    // 2.43.0 proof: roll the Fire Bolt damage again with +2 - history
    // gains a second Fire Bolt damage card reading "2d10+3 + 2", the
    // defense note recomputed on the higher total.
    if let bolt = model.rollHistory.first(where: { $0.label?.contains("Fire Bolt damage") == true }) {
        model.rollAgain(bolt, variant: .plusTwo)
    }
    // 2.38.0/2.48.0 proof: backdate the three oldest rolls so the history
    // divides into "Session 2 - Today" / "Session 1 - Yesterday" under its
    // sticky headers. The third-oldest is
    // the character's own check, which also puts a Yesterday group into the
    // 2.39.0 session-log appendix proof below.
    if model.rollHistory.count >= 3,
       let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) {
        model.rollHistory[model.rollHistory.count - 1].rolledAt = yesterday
        model.rollHistory[model.rollHistory.count - 2].rolledAt = yesterday.addingTimeInterval(3600)
        model.rollHistory[model.rollHistory.count - 3].rolledAt = yesterday.addingTimeInterval(7200)
    }
    renderPNG(
        DiceRollerView()
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: width, name: "dice", outDir: outDir, minHeight: 420, maxHeight: 1100)
    // 2.74.0 proof: the Latest session scope - the pane shows only the
    // newest session's rolls (the Yesterday group is gone).
    renderPNG(
        DiceRollerView(initialLatestSession: true)
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: width, name: "dice-latest-session", outDir: outDir, minHeight: 420, maxHeight: 1100)
    // 2.38.0/2.48.0 proof: the session-divided history list in a fixed
    // frame, with a crafted roll set spanning Today and Yesterday.
    var h1 = DiceRoller(seed: 11).rollD20(mode: .normal)
    h1.label = "Stealth check"
    var h2 = DiceRoller(seed: 12).rollD20(mode: .advantage)
    h2.label = "Perception check"
    var y1 = DiceRoller(seed: 13).rollD20(mode: .normal)
    y1.label = "Arcana check"
    var y2 = DiceRoller(seed: 14).rollD20(mode: .disadvantage)
    y2.label = "Athletics check"
    if let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) {
        y1.rolledAt = yesterday
        y2.rolledAt = yesterday.addingTimeInterval(3600)
        renderPNG(
            HistoryListView(rolls: [h1, h2, y2, y1])
                .padding()
                .background(Theme.surface)
                .environmentObject(model),
            width: 800, name: "history-groups", outDir: outDir, minHeight: 620, maxHeight: 620)
        // 2.49.0 proof: with auto-log OFF the session dividers gain their
        // digest-into-journal button (the main dice render keeps it hidden
        // while the toggle is on, matching the pencil rule).
        model.autoLogRollsToJournal = false
        renderPNG(
            HistoryListView(rolls: [h1, h2, y2, y1])
                .padding()
                .background(Theme.surface)
                .environmentObject(model),
            width: 800, name: "history-session", outDir: outDir, minHeight: 620, maxHeight: 620)
        // 2.69.0 proof: every divider carries a stats line - the top
        // session here includes a seeded natural 20 ("nat 20 \u{00D7}1").
        var crit = DiceRoller(seed: 1).rollD20(mode: .normal)
        for seed in 1...UInt64(200) {
            let candidate = DiceRoller(seed: seed).rollD20(mode: .normal)
            if candidate.dice.first(where: { $0.kept })?.value == 20 {
                crit = candidate
                break
            }
        }
        crit.label = "Death save"
        renderPNG(
            HistoryListView(rolls: [crit, h2, y2, y1])
                .padding()
                .background(Theme.surface)
                .environmentObject(model),
            width: 800, name: "history-session-stats", outDir: outDir, minHeight: 620, maxHeight: 620)
        // 2.58.0 proof: the book button opens an inline naming field on
        // the divider, pre-filled and editable before filing.
        renderPNG(
            HistoryListView(rolls: [h1, h2, y2, y1],
                            initialNamingSession: 2,
                            initialDigestTitle: "Lantern Street heist")
                .padding()
                .background(Theme.surface)
                .environmentObject(model),
            width: 800, name: "history-digest-name", outDir: outDir, minHeight: 620, maxHeight: 620)
        // 2.67.0 proof: rename the newest session - the divider carries
        // the custom name (and the pencil opens the same inline field),
        // while a digest filed from it takes the name as its title.
        let crafted = [h1, h2, y2, y1]
        if let session = model.namedSessions(crafted).first, let key = session.key {
            model.renameSession(key, to: "Ember Warrens delve")
            // 2.71.0: the note shows under the stats line and rides the
            // copy text.
            model.setSessionNote(key, to: "The bridge over the Ember")
            renderPNG(
                HistoryListView(rolls: crafted)
                    .padding()
                    .background(Theme.surface)
                    .environmentObject(model),
                width: 800, name: "history-session-named", outDir: outDir, minHeight: 620, maxHeight: 620)
            renderPNG(
                HistoryListView(rolls: crafted,
                                initialRenamingSession: session.number,
                                initialSessionNameDraft: "Ember Warrens delve")
                    .padding()
                    .background(Theme.surface)
                    .environmentObject(model),
                width: 800, name: "history-session-rename", outDir: outDir, minHeight: 620, maxHeight: 620)
            let namedDigest = JournalEntry(sessionDigest: model.namedSessions(crafted)[0])
            try? (namedDigest.title + "\n\n" + namedDigest.text)
                .write(to: URL(fileURLWithPath: "\(outDir)/history-session-named-digest.md"),
                       atomically: true, encoding: .utf8)
            // 2.70.0 proof: the divider's copy button text - title,
            // stats line, rolls oldest first.
            try? sessionShareText(model.namedSessions(crafted)[0])
                .write(to: URL(fileURLWithPath: "\(outDir)/session-copy.txt"),
                       atomically: true, encoding: .utf8)
        }
        model.autoLogRollsToJournal = true
    }
    // Proof render for 2.23.0: a macro row mid edit-in-place.
    renderPNG(
        MacroRowView(macro: DiceMacro(name: "Fireball", expression: "8d6", damageType: "fire"),
                     startEditing: true)
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: 800, name: "macro-edit", outDir: outDir, minHeight: 60)

    // Exports as files.
    let pdf = SheetPDFExporter.export(character)
    try? pdf.write(to: URL(fileURLWithPath: "\(outDir)/sample-sheet.pdf"))
    // 2.68.0 proof: name today's session - the session-log exports and
    // the compact-PDF appendix carry the custom name in their day header.
    // 2.71.0: its note follows in parentheses.
    if let key = model.namedSessions(model.rollHistory).first?.key {
        model.renameSession(key, to: "Ember Warrens delve")
        model.setSessionNote(key, to: "The bridge over the Ember")
    }
    // 2.92.0 proof: note a roll - the Fireball carries the table's story
    // under its label; the compact-PDF appendix and the session-log
    // text/Markdown exports below all carry the note with it.
    if let fireball = model.rollHistory.first(where: { $0.label?.hasPrefix("Fireball") == true }) {
        model.noteRoll(fireball, to: "The bridge collapses behind them")
    }
    // 2.72.0 proof: the divider's export - the session as its own
    // Markdown file (name as title, note, stats, table). Written after
    // the roll note lands so 2.95.0's note-carrying cells show here.
    try? sessionMarkdown(model.namedSessions(model.rollHistory)[0])
        .write(to: URL(fileURLWithPath: "\(outDir)/session-export.md"),
               atomically: true, encoding: .utf8)
    // 2.39.0/2.41.0 proof: the compact export carries the character's
    // session-log appendix, ranged to Today - the Yesterday group is
    // filtered out, the rerolled 4d6kh3 stays.
    let compactPdf = SheetPDFExporter.export(character, style: .compact,
                                             sessionRolls: model.rollHistory.forCharacter(character.name).within(.today),
                                             sessionNames: model.sessionNames,
                                             sessionNotes: model.sessionNotes)
    try? compactPdf.write(to: URL(fileURLWithPath: "\(outDir)/sample-sheet-compact.pdf"))
    // 2.42.0 proof: the same rolls as a plain-text session log, honoring
    // the same range - Today only, day-grouped, no PDF.
    let logRolls = model.rollHistory.forCharacter(character.name).within(.today)
    let logText = sessionLogText(character: character.name, range: .today,
                                 rows: sessionLogRows(logRolls, names: model.sessionNames, notes: model.sessionNotes))
    try? logText.write(to: URL(fileURLWithPath: "\(outDir)/session-log.txt"),
                       atomically: true, encoding: .utf8)
    // 2.44.0 proof: the same Today rolls as a Markdown table.
    let logMd = sessionLogMarkdown(character: character.name, range: .today,
                                   groups: namedDayGroups(Array(logRolls.reversed()), names: model.sessionNames, notes: model.sessionNotes))
    try? logMd.write(to: URL(fileURLWithPath: "\(outDir)/session-log.md"),
                     atomically: true, encoding: .utf8)
    // 2.77.0 proof: the copy-day text for the newest day - the named,
    // summarized header, then the day's rolls oldest first.
    let fullHistory = model.rollHistory.forCharacter(character.name)
    let copyDays = summarizedDayGroups(namedDayGroups(Array(fullHistory.reversed()),
                                                      names: model.sessionNames,
                                                      notes: model.sessionNotes))
    if let newestDay = copyDays.last {
        try? dayShareText(newestDay).write(to: URL(fileURLWithPath: "\(outDir)/day-copy.txt"),
                                           atomically: true, encoding: .utf8)
    }
    // 2.49.0 proof: digest the newest session into the journal as one
    // entry - the recap below then carries it, titled by the session.
    if let session = sessionSegments(model.rollHistory).first {
        model.addSessionToJournal(session)
    }
    // 2.50.0 proof: nudge the digest entry up two spots - the re-rendered
    // sheet's journal block (chevrons on every entry) and the recap below
    // follow the user's explicit order.
    if var sel = model.selected?.wrappedValue,
       let digest = sel.journal.last(where: { $0.title.hasPrefix("Session ") }) {
        sel.moveJournalEntry(digest.id, by: -2)
        model.selected?.wrappedValue = sel
        renderPNG(
            SheetColumnView(character: .constant(sel))
                .padding()
                .background(Theme.surface)
                .environmentObject(model),
            width: width, name: "journal-reorder", outDir: outDir)
        // 2.51.0/2.52.0 proof: the digest lands collapsed on its own -
        // the re-render shows it as a one-line preview while the recap
        // below keeps the full text.
        renderPNG(
            SheetColumnView(character: .constant(sel))
                .padding()
                .background(Theme.surface)
                .environmentObject(model),
            width: width, name: "journal-collapse", outDir: outDir)
        // 2.53.0 proof: the header's collapse-all puts every long entry
        // into its one-line preview at once.
        sel.setAllJournalCollapsed(true)
        model.selected?.wrappedValue = sel
        renderPNG(
            SheetColumnView(character: .constant(sel))
                .padding()
                .background(Theme.surface)
                .environmentObject(model),
            width: width, name: "journal-collapse-all", outDir: outDir)
        // 2.55.0 proof: the digest's one-entry share block, exactly what
        // the row copy button puts on the pasteboard.
        if let digestEntry = sel.journal.first(where: { $0.title.hasPrefix("Session ") }) {
            try? digestEntry.shareText.write(to: URL(fileURLWithPath: "\(outDir)/journal-entry-copy.txt"),
                                             atomically: true, encoding: .utf8)
        }
        // 2.56.0 proof: duplicate the digest - the copy lands right below
        // with a fresh id and stamp, so the recap below counts 14 today.
        if let digestId = sel.journal.first(where: { $0.title.hasPrefix("Session ") })?.id {
            sel.duplicateJournalEntry(digestId)
            model.selected?.wrappedValue = sel
            renderPNG(
                JournalBlock(character: .constant(sel))
                    .padding()
                    .background(Theme.surface)
                    .environmentObject(model),
                width: width, name: "journal-duplicate", outDir: outDir)
            // 2.57.0 proof: every row carries its size label - "9
            // lines" on the digests, word counts on the roll entries.
            renderPNG(
                JournalBlock(character: .constant(sel))
                    .padding()
                    .background(Theme.surface)
                    .environmentObject(model),
                width: width, name: "journal-size", outDir: outDir)
        }
        // 2.54.0 proof: the header filter narrows the journal by
        // title/body text - "fire bolt" keeps the attack, both damage
        // entries, and the digest (whose body mentions them), with the
        // match count in the header.
        sel.setAllJournalCollapsed(false)
        model.selected?.wrappedValue = sel
        renderPNG(
            JournalBlock(character: .constant(sel), initialFilter: "fire bolt")
                .padding()
                .background(Theme.surface)
                .environmentObject(model),
            width: width, name: "journal-filter", outDir: outDir)
        // 2.60.0 proof: while the filter is active, body hits surface
        // as highlighted snippet lines - "fire bolt" matches deep in
        // entries without expanding them.
        renderPNG(
            JournalBlock(character: .constant(sel), initialFilter: "fire bolt")
                .padding()
                .background(Theme.surface)
                .environmentObject(model),
            width: width, name: "journal-highlight", outDir: outDir)
        // 2.63.0 proof: the filtered journal as one share block -
        // exactly what "Copy filtered" puts on the pasteboard.
        try? JournalEntry.shareText(entries: sel.journal.filter { $0.matchesFilter("fire bolt") })
            .write(to: URL(fileURLWithPath: "\(outDir)/journal-filtered-copy.txt"),
                   atomically: true, encoding: .utf8)
        // 2.59.0 proof: the From template menu stamps a combat debrief
        // outline in as a new entry - section headers prefilled, stamped
        // today, appended last (the recap below counts 15).
        if let combat = JournalTemplate.builtIn.first {
            sel.addJournalEntry(from: combat)
            model.selected?.wrappedValue = sel
            renderPNG(
                JournalBlock(character: .constant(sel))
                    .padding()
                    .background(Theme.surface)
                    .environmentObject(model),
                width: width, name: "journal-templates", outDir: outDir)
        }
        // 2.61.0 proof: pin the combat debrief - it jumps to the top
        // with a filled brass pin, its fields go read-only, and its
        // move/delete buttons drop off the row.
        if let tplId = sel.journal.last(where: { $0.title == "Combat debrief" })?.id {
            sel.setJournalEntryPinned(tplId, true)
            model.selected?.wrappedValue = sel
            renderPNG(
                JournalBlock(character: .constant(sel))
                    .padding()
                    .background(Theme.surface)
                    .environmentObject(model),
                width: width, name: "journal-pinned", outDir: outDir)
        }
        // 2.62.0 proof: the same session digested by actor - lines
        // grouped under each roller instead of one flat list (the
        // recap below counts 16).
        if let session = sessionSegments(model.rollHistory).first {
            sel.journal.append(JournalEntry(sessionDigest: session, format: .byActor))
            model.selected?.wrappedValue = sel
            renderPNG(
                JournalBlock(character: .constant(sel))
                    .padding()
                    .background(Theme.surface)
                    .environmentObject(model),
                width: width, name: "journal-format", outDir: outDir)
        }
    }
    // 2.65.0 proof: the recap preamble rides at the top of the recap
    // below - one line of context, no retyping per share.
    if var sel = model.selected?.wrappedValue {
        sel.recapPreamble = "Session at the Athenaeum, party of 4"
        model.selected?.wrappedValue = sel
    }
    // 2.46.0 proof: today's journal entries and rolls as one shareable
    // recap block - the same text the sheet's Copy today button copies.
    let recap = sessionRecap(character: model.selected?.wrappedValue ?? character,
                             rolls: model.rollHistory)
    try? recap.write(to: URL(fileURLWithPath: "\(outDir)/session-recap.txt"),
                     atomically: true, encoding: .utf8)
    // 2.66.0 proof: the journal-timestamp option on a journal that
    // actually carries stamps - the same journal exported with the
    // default stamped heads and with times dropped.
    if let sel = model.selected?.wrappedValue {
        try? SheetExporter.exportMarkdown(sel)
            .write(to: URL(fileURLWithPath: "\(outDir)/journal-withtime.md"),
                   atomically: true, encoding: .utf8)
        try? SheetExporter.exportMarkdown(sel, journalTimestamps: false)
            .write(to: URL(fileURLWithPath: "\(outDir)/journal-notime.md"),
                   atomically: true, encoding: .utf8)
    }
    let compactLandscapePdf = SheetPDFExporter.export(character, style: .compact, orientation: .landscape)
    try? compactLandscapePdf.write(to: URL(fileURLWithPath: "\(outDir)/sample-sheet-compact-landscape.pdf"))
    // 2.34.0 proof: compact export with zero-quantity rows collapsed.
    var depleted = character
    depleted.inventory.append(InventoryItem(name: "Arrows", quantity: 0, weight: 1, category: "Ammunition"))
    depleted.inventory.append(InventoryItem(name: "Chalk", quantity: 0, category: "Gear"))
    let collapsedPdf = SheetPDFExporter.export(depleted, style: .compact, collapseEmptyInventory: true)
    try? collapsedPdf.write(to: URL(fileURLWithPath: "\(outDir)/sample-sheet-compact-collapsed.pdf"))
    // 2.47.0 proof: stamped journal entries render their creation time in
    // exports. The pristine sample sheet above stays byte-stable; this
    // export renders the model's copy with auto-logged (stamped) entries.
    let stampedPdf = SheetPDFExporter.export(model.selected?.wrappedValue ?? character)
    try? stampedPdf.write(to: URL(fileURLWithPath: "\(outDir)/sample-sheet-stamped.pdf"))
    try? SheetExporter.exportHTML(character).write(toFile: "\(outDir)/sample-sheet.html", atomically: true, encoding: .utf8)
    try? SheetExporter.exportMarkdown(character).write(toFile: "\(outDir)/sample-sheet.md", atomically: true, encoding: .utf8)
    // 2.78.0 proof: the crits-only filter - a deterministic natural 20
    // joins the history last so no other artifact changes, and the pane
    // shows only rolls with a kept natural 20 or 1.
    var critProof = RollResult(expression: "d20",
                               dice: [DieResult(sides: 20, value: 20, kept: true)],
                               modifier: 5, total: 25, alternateTotal: nil)
    critProof.label = "Death save"
    critProof.characterName = character.name
    critProof.rolledAt = Date()
    model.rollHistory.insert(critProof, at: 0)
    renderPNG(
        DiceRollerView(initialCritsOnly: true)
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: width, name: "dice-crits", outDir: outDir, minHeight: 420, maxHeight: 1100)
    // 2.79.0 proof: per-roll delete - the crafted crit (the newest roll)
    // leaves the history; the txt records the log before and after.
    let beforeDelete = model.rollHistory
    if let victim = beforeDelete.first { model.deleteRoll(victim) }
    func deleteLine(_ r: RollResult) -> String {
        "  " + (r.label ?? r.expression) + " = \(r.total)"
    }
    let beforeLines = beforeDelete.prefix(4).map(deleteLine)
    let afterLines = model.rollHistory.prefix(4).map(deleteLine)
    let deleteLines = ["Per-roll delete (2.79.0)", "",
                       "before (\(beforeDelete.count) rolls):"] + beforeLines
        + ["", "after (\(model.rollHistory.count) rolls):"] + afterLines
    try? deleteLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/history-delete.txt"),
               atomically: true, encoding: .utf8)
    renderPNG(
        DiceRollerView()
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: width, name: "dice-delete", outDir: outDir, minHeight: 420, maxHeight: 1100)
    // 2.80.0 proof: per-session delete - the oldest session leaves the
    // history via its divider's trash; the txt records the session list
    // before and after.
    let sessionsBefore = model.namedSessions(model.rollHistory)
    if let oldest = sessionsBefore.last { model.deleteSession(oldest) }
    let sessionsAfter = model.namedSessions(model.rollHistory)
    func sessionLine(_ s: RollSession) -> String {
        "  " + s.title + " - \(s.rolls.count) rolls"
    }
    let beforeSessionLines = sessionsBefore.map(sessionLine)
    let afterSessionLines = sessionsAfter.map(sessionLine)
    let sessionDeleteLines = ["Per-session delete (2.80.0)", "",
                              "before (\(sessionsBefore.count) sessions):"] + beforeSessionLines
        + ["", "after (\(sessionsAfter.count) sessions):"] + afterSessionLines
    try? sessionDeleteLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/session-delete.txt"),
               atomically: true, encoding: .utf8)
    renderPNG(
        DiceRollerView()
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: width, name: "dice-session-delete", outDir: outDir, minHeight: 420, maxHeight: 1100)
    // 3.17.0 proof: the session trash's hover label names its target -
    // the only pre-click signal, since the delete fires without a
    // confirm. The txt records the exact label for the remaining
    // sessions, built by the same ArchiterCore function the view calls.
    do {
        let sessions = model.namedSessions(model.rollHistory)
        let lines = ["Session delete label (3.17.0)",
                     "the trash hover names the session and its roll count:"]
            + sessions.map { "  \"\($0.title)\" -> \"\(sessionDeleteLabel($0))\"" }
            + ["the delete fires without a confirm; one undo step restores it"]
        try? lines.joined(separator: "\n")
            .write(to: URL(fileURLWithPath: "\(outDir)/session-delete-label.txt"),
                   atomically: true, encoding: .utf8)
    }
    // 3.18.0 proof: the Undo hover names what the restore brings back.
    // Recorded while lastDeletion is live from the 2.80.0 session
    // delete (unnamed, so count-only), plus the named-session case
    // from the same builder.
    do {
        var lines = ["Undo hover label (3.18.0)",
                     "the hover names what the restore brings back (the button keeps its count):"]
        if let deletion = model.lastDeletion {
            lines.append("  live: \"\(undoDeleteLabel(removedCount: deletion.removedCount, sessionName: deletion.sessionName))\"")
        }
        lines.append("  named session: \"\(undoDeleteLabel(removedCount: 9, sessionName: "Ember Warrens delve"))\"")
        try? lines.joined(separator: "\n")
            .write(to: URL(fileURLWithPath: "\(outDir)/undo-delete-label.txt"),
                   atomically: true, encoding: .utf8)
    }
    // 2.81.0 proof: undo delete - the session deleted for the 2.80.0
    // proof comes back, name and note included; the txt records the
    // after-delete and after-undo states. (The 2.79.0/2.80.0 renders
    // above already show the Undo button, live after each delete.)
    model.undoDelete()
    let sessionsUndone = model.namedSessions(model.rollHistory)
    let undoneSessionLines = sessionsUndone.map(sessionLine)
    let undoLines = ["Undo delete (2.81.0)", "",
                     "after session delete (\(sessionsAfter.count) sessions):"] + afterSessionLines
        + ["", "after undo (\(sessionsUndone.count) sessions):"] + undoneSessionLines
    try? undoLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/session-undo.txt"),
               atomically: true, encoding: .utf8)
    renderPNG(
        DiceRollerView()
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: width, name: "dice-undo", outDir: outDir, minHeight: 420, maxHeight: 1100)
    // 2.82.0 proof: edit roll label - the newest card's label is renamed
    // in place; the txt records the title before and after.
    if let target = model.rollHistory.first {
        let beforeTitle = target.label ?? target.expression
        model.renameRoll(target, to: "Fire Bolt, into the dark")
        let afterTitle = model.rollHistory.first?.label ?? "<missing>"
        let relabelLines = ["Edit roll label (2.82.0)", "",
                            "before: \(beforeTitle)",
                            "after:  \(afterTitle)"]
        try? relabelLines.joined(separator: "\n")
            .write(to: URL(fileURLWithPath: "\(outDir)/roll-relabel.txt"),
                   atomically: true, encoding: .utf8)
    }
    renderPNG(
        DiceRollerView()
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: width, name: "dice-relabel", outDir: outDir, minHeight: 420, maxHeight: 1100)
    // 2.83.0 proof: copy single roll - the renamed card's own history
    // line is what its copy button puts on the pasteboard.
    if let top = model.rollHistory.first {
        let copyLines = ["Copy single roll (2.83.0)", "", top.historyLine]
        try? copyLines.joined(separator: "\n")
            .write(to: URL(fileURLWithPath: "\(outDir)/roll-copy.txt"),
                   atomically: true, encoding: .utf8)
    }
    renderPNG(
        DiceRollerView()
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: width, name: "dice-copy-roll", outDir: outDir, minHeight: 420, maxHeight: 1100)
    // 2.84.0 proof: star a roll - the renamed card gets the table's
    // star, and the Starred filter then shows only it.
    if let top = model.rollHistory.first {
        model.toggleStar(top)
        let starLines = ["Star a roll (2.84.0)", "",
                         "starred: \((model.rollHistory.first?.label ?? model.rollHistory.first?.expression) ?? "<missing>")",
                         "starred rolls in history: \(model.rollHistory.starredRolls.count)"]
        try? starLines.joined(separator: "\n")
            .write(to: URL(fileURLWithPath: "\(outDir)/roll-star.txt"),
                   atomically: true, encoding: .utf8)
    }
    renderPNG(
        DiceRollerView(initialStarredOnly: true)
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: width, name: "dice-star", outDir: outDir, minHeight: 420, maxHeight: 1100)
    // 2.85.0 proof: copy starred - the exact paste the Copy starred
    // button produces for the one starred roll.
    let starredCopyLines = ["Copy starred (2.85.0)", "",
                            model.rollHistory.starredShareText]
    try? starredCopyLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/starred-copy.txt"),
               atomically: true, encoding: .utf8)
    renderPNG(
        DiceRollerView()
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: width, name: "dice-starred-copy", outDir: outDir, minHeight: 420, maxHeight: 1100)
    // 2.86.0 proof: unstar all - with a second roll starred, one tap
    // clears every star; the bar then shows neither Copy starred nor
    // Unstar all, and the history itself is untouched.
    if model.rollHistory.count > 1 {
        model.toggleStar(model.rollHistory[1])
    }
    let preUnstar = model.rollHistory.starredRolls.count
    model.unstarAll()
    let unstarLines = ["Unstar all (2.86.0)", "",
                       "starred rolls before: \(preUnstar)",
                       "starred rolls after: \(model.rollHistory.starredRolls.count)",
                       "history intact: \(model.rollHistory.count) rolls"]
    try? unstarLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/roll-unstar-all.txt"),
               atomically: true, encoding: .utf8)
    renderPNG(
        DiceRollerView()
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: width, name: "dice-unstar-all", outDir: outDir, minHeight: 420, maxHeight: 1100)
    // 2.87.0 proof: session stars - one tap on the divider stars every
    // roll in the newest session; rolls outside it stay unstarred.
    if let topSession = model.namedSessions(model.rollHistory).first {
        // Capture the outside set BEFORE toggling: RollResult equality
        // includes the star, so post-star rolls no longer match their
        // pre-star copies inside topSession.rolls.
        let outsideRolls = model.rollHistory.filter { !topSession.rolls.contains($0) }
        model.toggleSessionStars(topSession)
        let outsideStarred = model.rollHistory.filter {
            outsideRolls.contains($0) && $0.starred == true
        }.count
        let sessionStarLines = ["Session stars (2.87.0)", "",
                                "session: \(topSession.title)",
                                "rolls in session: \(topSession.rolls.count)",
                                "starred after one tap: \(model.rollHistory.starredRolls.count)",
                                "rolls outside session: \(outsideRolls.count)",
                                "starred outside session: \(outsideStarred)"]
        try? sessionStarLines.joined(separator: "\n")
            .write(to: URL(fileURLWithPath: "\(outDir)/session-star.txt"),
                   atomically: true, encoding: .utf8)
    }
    renderPNG(
        DiceRollerView()
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: width, name: "dice-session-star", outDir: outDir, minHeight: 420, maxHeight: 1100)
    // 2.88.0 proof: starred export - the exact Markdown file the Export
    // starred button saves, for the nine session-starred rolls.
    try? starredMarkdown(model.rollHistory)
        .write(to: URL(fileURLWithPath: "\(outDir)/starred-export.md"),
               atomically: true, encoding: .utf8)
    renderPNG(
        DiceRollerView()
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: width, name: "dice-starred-export", outDir: outDir, minHeight: 420, maxHeight: 1100)
    // 2.89.0 proof: starred digest - the reel filed into the journal as
    // one entry; the journal block shows it with its count title.
    model.addStarredToJournal()
    if let sel = model.selected?.wrappedValue,
       let entry = sel.journal.last {
        let digestLines = ["Starred digest (2.89.0)", "",
                           "journal entry: \(entry.title)",
                           "body lines: \(entry.text.components(separatedBy: "\n").count)",
                           "journal entries: \(sel.journal.count)"]
        try? digestLines.joined(separator: "\n")
            .write(to: URL(fileURLWithPath: "\(outDir)/starred-digest.txt"),
                   atomically: true, encoding: .utf8)
        renderPNG(
            JournalBlock(character: .constant(sel))
                .padding()
                .background(Theme.surface)
                .environmentObject(model),
            width: width, name: "dice-starred-digest", outDir: outDir)
    }
    // 2.90.0 proof: the session-log exports honor the Starred only
    // range - the character's day-grouped log carrying just her starred
    // rolls, as text and as Markdown.
    let starredLogRolls = model.rollHistory.forCharacter(character.name).within(.starred)
    try? sessionLogText(character: character.name, range: .starred,
                        rows: sessionLogRows(starredLogRolls, names: model.sessionNames, notes: model.sessionNotes))
        .write(to: URL(fileURLWithPath: "\(outDir)/session-log-starred.txt"),
               atomically: true, encoding: .utf8)
    try? sessionLogMarkdown(character: character.name, range: .starred,
                            groups: namedDayGroups(Array(starredLogRolls.reversed()),
                                                   names: model.sessionNames, notes: model.sessionNotes))
        .write(to: URL(fileURLWithPath: "\(outDir)/session-log-starred.md"),
               atomically: true, encoding: .utf8)
    // 2.91.0 proof: reroll-and-star - rolling a starred card again
    // carries the star onto the new top of history; the original keeps
    // its own star, so the highlight reel survives the re-roll. Runs
    // last: the extra roll must not disturb any earlier proof's counts.
    if let topStarred = model.rollHistory.first(where: { $0.starred == true }) {
        let preCount = model.rollHistory.count
        let preStarred = model.rollHistory.starredRolls.count
        model.rollAgain(topStarred)
        let newTop = model.rollHistory.first
        let rerollStarLines = ["Reroll-and-star (2.91.0)", "",
                               "source: \(topStarred.label ?? topStarred.expression) (starred)",
                               "history before: \(preCount) rolls, \(preStarred) starred",
                               "history after: \(model.rollHistory.count) rolls, \(model.rollHistory.starredRolls.count) starred",
                               "new top: \(newTop?.label ?? newTop?.expression ?? "<missing>")",
                               "new top starred: \(newTop?.starred == true)",
                               "original still starred: \(model.rollHistory.contains(topStarred))"]
        try? rerollStarLines.joined(separator: "\n")
            .write(to: URL(fileURLWithPath: "\(outDir)/reroll-star.txt"),
                   atomically: true, encoding: .utf8)
        renderPNG(
            DiceRollerView()
                .padding()
                .background(Theme.surface)
                .environmentObject(model),
            width: width, name: "dice-reroll-star", outDir: outDir, minHeight: 420, maxHeight: 1100)
    }
    // 2.92.0 proof (render + lines): the noted Fireball card shows the
    // note under its label; the export carriage is proven by the
    // session-log files written above, which now include the note.
    let notedRoll = model.rollHistory.first(where: { $0.note != nil })
    let notedCount = model.rollHistory.filter { $0.note != nil }.count
    let rollNoteLines = ["Per-roll notes (2.92.0)", "",
                         "roll: \(notedRoll?.label ?? "<missing>")",
                         "note: \(notedRoll?.note ?? "<missing>")",
                         "noted rolls in history: \(notedCount)"]
    try? rollNoteLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/roll-note.txt"),
               atomically: true, encoding: .utf8)
    renderPNG(
        DiceRollerView()
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: width, name: "dice-roll-note", outDir: outDir, minHeight: 420, maxHeight: 1100)
    // 2.93.0 proof: the note rides every share block and the digest -
    // the same indented line under the Fireball, wherever it is pasted.
    func shareExcerpt(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        guard let i = lines.firstIndex(where: { $0.contains("Fireball") }) else { return "<missing>" }
        return lines[i...min(i + 1, lines.count - 1)].joined(separator: "\n")
    }
    if let newest = model.namedSessions(model.rollHistory).first {
        let noteShareLines = ["Notes in share text (2.93.0)", "",
                              "copy starred:", shareExcerpt(model.rollHistory.starredShareText), "",
                              "session digest (condensed):", shareExcerpt(JournalEntry.digestBody(session: newest, format: .condensed)), "",
                              "session share:", shareExcerpt(sessionShareText(newest))]
        try? noteShareLines.joined(separator: "\n")
            .write(to: URL(fileURLWithPath: "\(outDir)/notes-share.txt"),
                   atomically: true, encoding: .utf8)
    }
    // 2.96.0 proof: the history filter searches note text - "bridge"
    // finds the noted Fireball though neither its label nor its
    // expression says bridge; "dragon" still finds nothing.
    let filterProof = ["History filter matches note text (2.96.0)", "",
                       "query \"bridge\" (\(model.rollHistory.matching("bridge").count) hit):",
                       model.rollHistory.matching("bridge").historyText,
                       "query \"dragon\": \(model.rollHistory.matching("dragon").count) hits"]
    try? filterProof.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/history-filter-note.txt"),
               atomically: true, encoding: .utf8)
    // 2.98.0 proof: the filtered copy's header - the exact string the
    // Copy filtered button puts on the pasteboard with "bridge" drafted.
    try? model.rollHistory.matching("bridge")
        .filteredShareText(query: "bridge", ofTotal: model.rollHistory.count)
        .write(to: URL(fileURLWithPath: "\(outDir)/filtered-copy.txt"),
               atomically: true, encoding: .utf8)
    // 2.99.0 proof: the filtered digest's journal entry - title names
    // the query, the condensed body carries the noted roll with its
    // note, exactly as filed by Digest filtered.
    do {
        let subset = model.rollHistory.matching("bridge").filteredDigestSession(query: "bridge")
        let entry = JournalEntry(sessionDigest: subset, format: .condensed)
        try? (entry.title + "\n\n" + entry.text)
            .write(to: URL(fileURLWithPath: "\(outDir)/filtered-digest.txt"),
                   atomically: true, encoding: .utf8)
    }
    // 3.1.0 proof: the filtered Markdown export file - header names
    // the query, table rows in the starred export's shape, the noted
    // roll's note dash-appended in its cell.
    try? filteredMarkdown(model.rollHistory.matching("bridge"), query: "bridge",
                          ofTotal: model.rollHistory.count)
        .write(to: URL(fileURLWithPath: "\(outDir)/filtered-export.md"),
               atomically: true, encoding: .utf8)
    // 2.97.0 proof: with a filter drafted the bar's Copy reads "Copy
    // filtered" - the button says when the filter narrows what it
    // copies; the action already rides visibleHistory.
    renderPNG(
        DiceRollerView(initialHistoryFilter: "fire")
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: width, name: "dice-copy-filtered", outDir: outDir, minHeight: 420, maxHeight: 1100)
    // 3.0.0 proof: the preset cycle - save two, re-save one with
    // different casing (replaces in place, menu order kept); the list
    // the presets menu would show.
    do {
        _ = model.saveFilterPreset(name: "Fire stuff", query: "fire")
        _ = model.saveFilterPreset(name: "Bridge checks", query: "bridge")
        _ = model.saveFilterPreset(name: "fire stuff", query: "fire damage")
        let lines = model.filterPresets.map { "\($0.name) -> \($0.query)" }
        try? ("Presets after save + case-insensitive re-save:\n" + lines.joined(separator: "\n"))
            .write(to: URL(fileURLWithPath: "\(outDir)/filter-presets.txt"),
                   atomically: true, encoding: .utf8)
    }
    // 3.0.0 render: the bar with the presets bookmark menu and the
    // inline naming form open, the draft pre-filled with the query.
    renderPNG(
        DiceRollerView(initialHistoryFilter: "fire",
                       initialSavingFilterPreset: true,
                       initialFilterPresetNameDraft: "Fire stuff")
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: width, name: "dice-filter-presets", outDir: outDir, minHeight: 420, maxHeight: 1100)
    // 3.6.0 proof: preset rename - "Fire stuff" becomes "Fire damage"
    // in place (its filter stays); the txt records the list before and
    // after. The render opens the rename form on "Bridge checks" with
    // the draft pre-filled with its current name.
    do {
        let before = model.filterPresets.map { "\($0.name) -> \($0.query)" }
        let ok = model.renameFilterPreset(from: "Fire stuff", to: "Fire damage")
        let after = model.filterPresets.map { "\($0.name) -> \($0.query)" }
        try? (["Preset rename (3.6.0)", "succeeded: \(ok)", "",
               "before:"] + before + ["", "after:"] + after)
            .joined(separator: "\n")
            .write(to: URL(fileURLWithPath: "\(outDir)/filter-preset-rename.txt"),
                   atomically: true, encoding: .utf8)
    }
    renderPNG(
        DiceRollerView(initialRenamingPresetOriginal: "Bridge checks",
                       initialRenamePresetDraft: "Bridge checks")
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: width, name: "dice-filter-preset-rename", outDir: outDir, minHeight: 420, maxHeight: 1100)
    // 3.7.0 proof: the preset forms say why they stay open - the txt
    // records the nameIssue for blank, clashing, own-name, and fresh
    // names; the render opens the rename form with a clashing draft,
    // the hint inline and Rename disabled.
    do {
        func issueLine(_ label: String, _ issue: FilterPresetNameIssue?) -> String {
            let desc: String
            if let issue {
                switch issue {
                case .blank:
                    desc = "blank - hint shown, button disabled"
                case .taken(let name):
                    desc = "taken by \"\(name)\" - hint shown, button disabled"
                }
            } else {
                desc = "usable"
            }
            return label + " -> " + desc
        }
        let lines = ["Preset form hints (3.7.0)",
                     issueLine("rename \"Bridge checks\" to blank",
                               model.filterPresets.nameIssue("  ", replacing: "Bridge checks")),
                     issueLine("rename \"Bridge checks\" to \"Fire damage\"",
                               model.filterPresets.nameIssue("Fire damage", replacing: "Bridge checks")),
                     issueLine("rename \"Bridge checks\" to \"BRIDGE CHECKS\"",
                               model.filterPresets.nameIssue("BRIDGE CHECKS", replacing: "Bridge checks")),
                     issueLine("rename \"Bridge checks\" to \"Trail checks\"",
                               model.filterPresets.nameIssue("Trail checks", replacing: "Bridge checks"))]
        // 3.7.1: the save case is not a rejection - an existing name
        // shows the replace note and Save stays enabled, so the line
        // describes that instead of borrowing the rename wording.
        let overwrite = model.filterPresets.preset(named: "Fire damage")
        let saveLine = "save under \"Fire damage\" (existing) -> note 'Replaces \"\(overwrite?.name ?? "Fire damage")\".' shown, Save stays enabled"
        let allLines = lines + [saveLine]
        try? allLines.joined(separator: "\n")
            .write(to: URL(fileURLWithPath: "\(outDir)/filter-preset-hints.txt"),
                   atomically: true, encoding: .utf8)
    }
    renderPNG(
        DiceRollerView(initialRenamingPresetOriginal: "Bridge checks",
                       initialRenamePresetDraft: "Fire damage")
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: width, name: "dice-filter-preset-hint", outDir: outDir, minHeight: 420, maxHeight: 1100)
    // 3.8.0 proof: the active preset - the filter text exactly
    // matching a saved preset's query fills the bookmark and
    // checkmarks the menu entry; the txt records the matches.
    do {
        func activeLine(_ filter: String) -> String {
            let shown = filter.isEmpty ? "(empty)" : "\"\(filter)\""
            if let active = model.filterPresets.preset(matchingQuery: filter) {
                return "filter \(shown) -> active preset: \"\(active.name)\" (bookmark filled)"
            }
            return "filter \(shown) -> no active preset"
        }
        try? (["Active preset marker (3.8.0)",
               activeLine("fire damage"),
               activeLine("  fire damage  "),
               activeLine("fire"),
               activeLine("")])
            .joined(separator: "\n")
            .write(to: URL(fileURLWithPath: "\(outDir)/filter-preset-active.txt"),
                   atomically: true, encoding: .utf8)
    }
    renderPNG(
        DiceRollerView(initialHistoryFilter: "fire damage")
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: width, name: "dice-filter-preset-active", outDir: outDir, minHeight: 420, maxHeight: 1100)
    // 3.9.0 proof: the save form's name draft pre-fills from the
    // active preset - the txt records the prefill rule for a matching
    // and a free filter; the render stages the resulting form (the
    // button wiring is the one-line fallback the txt states).
    do {
        func prefillLine(_ filter: String) -> String {
            let draft = model.filterPresets.preset(matchingQuery: filter)?.name
                ?? filter.trimmingCharacters(in: .whitespaces)
            let active = model.filterPresets.preset(matchingQuery: filter)?.name
            if let active {
                return "filter \"\(filter)\" (active preset \"\(active)\") -> name draft pre-fills \"\(draft)\""
            }
            return "filter \"\(filter)\" (no active preset) -> name draft pre-fills the query text \"\(draft)\""
        }
        try? (["Save-form prefill (3.9.0)",
               prefillLine("fire damage"),
               prefillLine("fire")])
            .joined(separator: "\n")
            .write(to: URL(fileURLWithPath: "\(outDir)/filter-preset-prefill.txt"),
                   atomically: true, encoding: .utf8)
    }
    renderPNG(
        DiceRollerView(initialHistoryFilter: "fire damage",
                       initialSavingFilterPreset: true,
                       initialFilterPresetNameDraft: "Fire damage")
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: width, name: "dice-filter-preset-prefill", outDir: outDir, minHeight: 420, maxHeight: 1100)
    // 3.10.0 proof: the filter clear X - visible with text in the
    // field, hidden when empty. The render shows it next to the
    // active filter; the txt states the rule it renders.
    do {
        try? (["Filter clear X (3.10.0)",
               "filter \"fire damage\" -> clear X visible in the bar",
               "filter empty -> clear X hidden"])
            .joined(separator: "\n")
            .write(to: URL(fileURLWithPath: "\(outDir)/filter-clear.txt"),
                   atomically: true, encoding: .utf8)
    }
    renderPNG(
        DiceRollerView(initialHistoryFilter: "fire damage")
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: width, name: "dice-filter-clear", outDir: outDir, minHeight: 420, maxHeight: 1100)
    // 3.11.0 proof: the filtered count names its noted rolls - with
    // the "fire" filter the subset carries the Fireball's note, so
    // the bar reads "N of M, 1 with notes". The txt records the count.
    do {
        let filtered = model.rollHistory.matching("fire")
        try? (["Filtered count with notes (3.11.0)",
               "filter \"fire\" -> \(filtered.count) rolls, \(filtered.notedCount) noted",
               "the bar shows the same numbers as \"N of M, K noted\""])
            .joined(separator: "\n")
            .write(to: URL(fileURLWithPath: "\(outDir)/filter-count-notes.txt"),
                   atomically: true, encoding: .utf8)
    }
    renderPNG(
        DiceRollerView(initialHistoryFilter: "fire")
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: width, name: "dice-filter-count-notes", outDir: outDir, minHeight: 420, maxHeight: 1100)
    // 3.12.0 proof: the overflow menu - with a filter set, Digest,
    // Export, and Delete collapse into the ellipsis while Copy
    // filtered and Journal stay top-level. The txt states the rule;
    // the 3.3.0 confirm render above now shows the confirm in the
    // overflow's place.
    do {
        try? (["Filter-bar overflow (3.12.0)",
               "filter set -> Digest/Export/Delete collapse into the ellipsis menu",
               "Copy filtered, Journal, star menu, and Clear stay top-level",
               "the Delete item names its count (3.16.0) and still opens the inline confirm (3.3.0)"])
            .joined(separator: "\n")
            .write(to: URL(fileURLWithPath: "\(outDir)/filter-overflow.txt"),
                   atomically: true, encoding: .utf8)
    }
    renderPNG(
        DiceRollerView(initialHistoryFilter: "fire")
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: width, name: "dice-filter-overflow", outDir: outDir, minHeight: 420, maxHeight: 1100)
    // 3.16.0 proof: the overflow Delete item names the count it would
    // remove - the only pre-click signal since the 3.12.0 collapse.
    // The txt records the exact label, built by the same ArchiterCore
    // function the menu calls; the menu itself renders closed.
    do {
        let filtered = model.rollHistory.matching("fire")
        try? (["Delete count preview (3.16.0)",
               "menu item with filter \"fire\": \"\(deleteFilteredMenuLabel(count: filtered.count))\"",
               "the label is the pre-click signal; the confirm still asks \"Delete \(filtered.count) rolls?\""])
            .joined(separator: "\n")
            .write(to: URL(fileURLWithPath: "\(outDir)/filter-delete-label.txt"),
                   atomically: true, encoding: .utf8)
    }
    // 3.3.0 render: the confirm state - the bar asks "Delete 6 rolls?"
    // with Delete/Cancel before anything is removed.
    renderPNG(
        DiceRollerView(initialHistoryFilter: "fire",
                       initialConfirmingFilteredDelete: true)
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: width, name: "dice-filter-delete", outDir: outDir, minHeight: 420, maxHeight: 1100)
    // 3.4.0 render: the Clear-all confirm - "Clear all 13 rolls?" with
    // Clear/Cancel, the Copy/Digest/star clusters collapsed for space.
    renderPNG(
        DiceRollerView(initialConfirmingClearAll: true)
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: width, name: "dice-clear-confirm", outDir: outDir, minHeight: 420, maxHeight: 1100)
    // 3.3.0 proof: the model cycle end to end - delete the filtered
    // subset, then the one undo step restores the full log. Runs last
    // so every earlier proof's counts stay stable.
    do {
        let subset = model.rollHistory.matching("fire")
        let before = model.rollHistory.count
        model.deleteFilteredRolls(subset)
        let afterDelete = model.rollHistory.count
        model.undoDelete()
        let afterUndo = model.rollHistory.count
        try? ("Delete filtered (3.3.0)\n\nsubset: \(subset.count) of \(before)\n"
              + "after delete: \(afterDelete)\nafter undo: \(afterUndo)")
            .write(to: URL(fileURLWithPath: "\(outDir)/filter-delete.txt"),
                   atomically: true, encoding: .utf8)
    }
    // 3.13.0 proof: the filtered count also names its starred rolls.
    // One fire roll's star is toggled off here - LAST, after every
    // earlier proof - so the bar shows a discriminating count
    // ("5 starred" of 6) instead of a trivially-all-starred one.
    // The txt records both sides from the model.
    do {
        let filtered = model.rollHistory.matching("fire")
        let beforeStars = filtered.starredCount
        if let roll = filtered.first {
            model.toggleStar(roll)
        }
        let after = model.rollHistory.matching("fire")
        try? (["Filtered count with stars (3.13.0)",
               "filter \"fire\" -> \(filtered.count) rolls, \(filtered.notedCount) noted, \(beforeStars) starred",
               "one star toggled off -> \(after.starredCount) starred",
               "the bar shows the same numbers as \"N of M, K noted, S starred\""])
            .joined(separator: "\n")
            .write(to: URL(fileURLWithPath: "\(outDir)/filter-count-starred.txt"),
                   atomically: true, encoding: .utf8)
    }
    renderPNG(
        DiceRollerView(initialHistoryFilter: "fire")
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: width, name: "dice-filter-count-starred", outDir: outDir, minHeight: 420, maxHeight: 1100)
    // 3.14.0 proof: the bar chips never wrap. Maximum-pressure case:
    // Latest session ON plus the fire filter plus the full
    // notes+starred count - every chip label sits on one line. Runs
    // last, after the 3.13.0 star toggle.
    do {
        let scoped = model.rollHistory.latestSession().matching("fire")
        try? (["Bar chips never wrap (3.14.0)",
               "Latest session + Crits + Starred labels stay on one line under bar pressure",
               "render has Latest session ON, filter \"fire\": \(scoped.count) rolls",
               "the count keeps its 3.13.1 one-line treatment in the same bar"])
            .joined(separator: "\n")
            .write(to: URL(fileURLWithPath: "\(outDir)/latest-chip.txt"),
                   atomically: true, encoding: .utf8)
    }
    renderPNG(
        DiceRollerView(initialLatestSession: true,
                       initialHistoryFilter: "fire")
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: width, name: "dice-filter-latest-chip", outDir: outDir, minHeight: 420, maxHeight: 1100)
    // 3.15.1 proof: pin a macro - Magic missile jumps above Fireball
    // to the top of the Table group with a filled accent pin; the
    // character group above keeps its order. The second table macro is
    // added here, at the end of the sequence, so every earlier dice
    // render keeps the unpinned two-macro layout.
    do {
        model.saveMacro(name: "Magic missile", expression: "3d4+3", damageType: "force")
        if let missile = model.macros.first(where: { $0.name == "Magic missile" }) {
            model.toggleMacroPin(missile)
        }
        let table = pinnedFirst(model.visibleMacros.filter { $0.characterName == nil })
        try? (["Pinned macros (3.15.1)",
               "pinned macros float to the top of their group; owner sections stay put",
               "Table group order: \(table.map(\.name).joined(separator: ", "))",
               "Magic missile pinned: \(model.macros.first(where: { $0.name == "Magic missile" })?.pinned == true)"])
            .joined(separator: "\n")
            .write(to: URL(fileURLWithPath: "\(outDir)/macro-pin.txt"),
                   atomically: true, encoding: .utf8)
    }
    renderPNG(
        DiceRollerView()
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: width, name: "dice-macro-pin", outDir: outDir, minHeight: 420, maxHeight: 1100)
    // 3.19.0 proof: apply a history roll to HP - the Fireball roll
    // lands on Wren (fire resistance halves, temp HP absorbs), the Edit
    // menu names the step, and one undo restores. Runs last: every
    // sheet render and PDF is already written, so the byte-diffs hold.
    do {
        if let fireball = model.rollHistory.first(where: {
            $0.expression == "8d6" && $0.reroll?.damageType == "fire"
        }), let before = model.selected?.wrappedValue {
            let hpBefore = before.currentHP, tempBefore = before.tempHP
            model.applyRollToHP(fireball, healing: false)
            if let applied = model.selected?.wrappedValue {
                let undoLabel = model.undoMenuLabel
                renderPNG(
                    VitalsBlock(character: .constant(applied))
                        .padding()
                        .background(Theme.surface)
                        .environmentObject(model),
                    width: width, name: "sheet-hp-applied", outDir: outDir, minHeight: 200, maxHeight: 600)
                model.undo()
                let restored = model.selected?.wrappedValue
                try? (["Apply to HP (3.19.0)",
                       "roll: \(fireball.expression) fire, total \(fireball.total)",
                       "before: \(hpBefore) HP + \(tempBefore) temp",
                       "after apply: \(applied.currentHP) HP + \(applied.tempHP) temp (resist halves, temp absorbs)",
                       "Edit menu while applied: \"\(undoLabel)\"",
                       "after undo: \(restored?.currentHP ?? -1) HP + \(restored?.tempHP ?? -1) temp"])
                    .joined(separator: "\n")
                    .write(to: URL(fileURLWithPath: "\(outDir)/apply-hp.txt"),
                           atomically: true, encoding: .utf8)
            }
        }
    }
    // 3.20.0 proof: DC / target checks. Runs last: targeted rolls land
    // after every sheet render and PDF, so the byte-diffs hold, and
    // untargeted sessions keep the exact stats line from before.
    do {
        // A macro carrying its DC: rolled for real, the badge derives.
        model.saveMacro(name: "Fire Bolt attack", expression: "1d20+6",
                        forCharacter: model.selected?.wrappedValue.name,
                        targetDC: 15)
        if let bolt = model.macros.first(where: { $0.name == "Fire Bolt attack" }) {
            model.rollMacro(bolt)
        }
        // The bar's ad-hoc DC path (the view passes barTargetDC here).
        model.rollCheck("Perception check", bonus: 9, targetDC: 14)
        var proofLines = ["DC / target checks (3.20.0)",
                          "the badge is derived from the recorded DC and total, never stored"]
        for roll in model.rollHistory.prefix(2) {
            proofLines.append("roll: \(roll.label ?? roll.expression), total \(roll.total), badge: \(targetBadgeLabel(for: roll) ?? "none")")
        }
        // Crafted edge rolls pin the rules live dice can't be asked
        // for: attack nat 20 auto-meets even short of the DC, attack
        // nat 1 auto-misses even at it, checks stay pure arithmetic.
        let nat20Attack = RollResult(expression: "1d20-2",
                                     dice: [DieResult(sides: 20, value: 20, kept: true)],
                                     modifier: -2, total: 18, alternateTotal: nil,
                                     label: "Longsword attack", targetDC: 21)
        let nat1Attack = RollResult(expression: "1d20+14",
                                    dice: [DieResult(sides: 20, value: 1, kept: true)],
                                    modifier: 14, total: 15, alternateTotal: nil,
                                    label: "Warhammer attack", targetDC: 15)
        let nat20Check = RollResult(expression: "1d20+4",
                                    dice: [DieResult(sides: 20, value: 20, kept: true)],
                                    modifier: 4, total: 24, alternateTotal: nil,
                                    label: "Stealth check", targetDC: 25)
        model.rollHistory.insert(contentsOf: [nat20Check, nat1Attack, nat20Attack], at: 0)
        for roll in [nat20Attack, nat1Attack, nat20Check] {
            proofLines.append("edge: \(roll.label ?? roll.expression), total \(roll.total) vs DC \(roll.targetDC ?? -1), badge: \(targetBadgeLabel(for: roll) ?? "none")")
        }
        let targetedSession = RollSession(number: 1, title: "DC demo", key: nil,
                                          rolls: Array(model.rollHistory.prefix(5)))
        proofLines.append("stats with targets: \(sessionStats(targetedSession).line)")
        let untargeted = model.rollHistory.filter { $0.targetDC == nil }
        proofLines.append("stats without targets (unchanged shape): \(sessionStats(RollSession(number: 1, title: "t", key: nil, rolls: untargeted)).line)")
        renderPNG(
            DiceRollerView()
                .padding()
                .background(Theme.surface)
                .environmentObject(model),
            width: width, name: "dice-dc", outDir: outDir, minHeight: 420, maxHeight: 1100)
        try? proofLines.joined(separator: "\n")
            .write(to: URL(fileURLWithPath: "\(outDir)/dc-check.txt"),
                   atomically: true, encoding: .utf8)
    }
    // 3.21.0 proof: combo macros - one tap rolls each part in order
    // as its own history entry. Runs last, after every sheet render
    // and PDF, so the byte-diffs hold.
    do {
        model.saveMacro(name: "Fire Bolt routine", expression: "",
                        forCharacter: model.selected?.wrappedValue.name,
                        parts: [ComboPart(label: "Fire Bolt attack", expression: "1d20+6"),
                                ComboPart(label: "Fire Bolt damage", expression: "2d10+3",
                                          damageType: "fire")])
        var proofLines = ["Combo macros (3.21.0)",
                          "one tap rolls each part in order as its own history entry"]
        if let routine = model.macros.first(where: { $0.name == "Fire Bolt routine" }) {
            proofLines.append("row summary: \(routine.expression)")
            let countBefore = model.rollHistory.count
            model.rollMacro(routine)
            let recorded = Array(model.rollHistory.prefix(model.rollHistory.count - countBefore))
            // History is newest-first; reverse to the table's tap order.
            for roll in recorded.reversed() {
                proofLines.append("part: \(roll.label ?? roll.expression), total \(roll.total), reroll kind: \(roll.reroll?.kind.rawValue ?? "none")")
            }
        }
        let onePart = DiceMacro(name: "x", expression: "",
                                parts: [ComboPart(label: "a", expression: "1d6")])
        proofLines.append("single-part combo rejected: \(!onePart.isValid)")
        renderPNG(
            DiceRollerView()
                .padding()
                .background(Theme.surface)
                .environmentObject(model),
            width: width, name: "dice-combo", outDir: outDir, minHeight: 420, maxHeight: 1100)
        try? proofLines.joined(separator: "\n")
            .write(to: URL(fileURLWithPath: "\(outDir)/combo-roll.txt"),
                   atomically: true, encoding: .utf8)
    }
    // 3.22.0 proof: initiative tracker. Runs last, after every sheet
    // render and PDF, so the byte-diffs hold.
    do {
        model.clearInitiative()
        model.addInitiativeEntry(name: "Wren Halloway", bonus: 2,
                                 forCharacter: model.selected?.wrappedValue.name)
        model.addInitiativeEntry(name: "Goblin 1", bonus: 2)
        model.addInitiativeEntry(name: "Goblin 2", bonus: 2)
        model.addInitiativeEntry(name: "Ogre", bonus: -1)
        model.addInitiativeEntry(name: "Rogue NPC", bonus: 5)
        model.rollInitiative()
        // Force the proof's values so the tie cases are pinned: Rogue
        // and Wren tie at 17 - the higher bonus goes first.
        func setTotal(_ name: String, _ total: Int) {
            if let e = model.initiative.entries.first(where: { $0.name == name }) {
                model.setInitiativeTotal(e, total: total)
            }
        }
        setTotal("Rogue NPC", 17)
        setTotal("Wren Halloway", 17)
        setTotal("Goblin 1", 15)
        setTotal("Goblin 2", 12)
        setTotal("Ogre", 9)
        // Pin the rotation narrative: Rogue leads, advance hands the
        // turn to Wren (the tied, lower bonus).
        model.initiative.activeID = model.initiative.ordered.first?.id
        model.advanceInitiative()
        var proofLines = ["Initiative tracker (3.22.0)",
                          "order: total desc, ties on bonus then insertion; rolls stay out of History"]
        for e in model.initiative.ordered {
            let activeMark = model.initiative.activeID == e.id ? " <- active" : ""
            proofLines.append("  \(e.name) \(e.total ?? -1) (bonus \(e.bonus))\(activeMark)")
        }
        renderPNG(
            DiceRollerView()
                .padding()
                .background(Theme.surface)
                .environmentObject(model),
            width: width, name: "dice-initiative", outDir: outDir, minHeight: 420, maxHeight: 1100)
        // Advance through the rotation: wrapping increments the round.
        model.advanceInitiative()
        model.advanceInitiative()
        model.advanceInitiative()
        model.advanceInitiative()
        if let active = model.initiative.ordered.first(where: { $0.id == model.initiative.activeID }) {
            proofLines.append("after wrapping the rotation: active \(active.name), round \(model.initiative.round)")
        }
        model.endCombat()
        proofLines.append("after End combat: \(model.initiative.entries.count) entries kept, totals cleared: \(model.initiative.entries.allSatisfy { $0.total == nil }), round \(model.initiative.round)")
        try? proofLines.joined(separator: "\n")
            .write(to: URL(fileURLWithPath: "\(outDir)/initiative.txt"),
                   atomically: true, encoding: .utf8)
    }
    // Sheet-to-dice bridge proof (3.23.0): the sample Fire Bolt becomes a
    // two-part combo macro; re-saving after a damage edit refreshes in place.
    if let fireBolt = character.attacks.first(where: { $0.name == "Fire Bolt" }) {
        var bridgeLines = ["Sheet-to-dice bridge (3.23.0)",
                           "sheet attack -> combo macro snapshot; re-save refreshes (scoped-id upsert)"]
        model.saveMacro(forAttack: fireBolt, of: character)
        if let saved = model.macros.first(where: { $0.name == "Fire Bolt" && $0.characterName == character.name }),
           let parts = saved.parts {
            bridgeLines.append("saved as: \(saved.name) [\(saved.characterName ?? "table-wide")]")
            for p in parts {
                let type = p.damageType.map { " (\($0))" } ?? ""
                bridgeLines.append("  \(p.label): \(p.expression)\(type)")
            }
        }
        var edited = fireBolt
        edited.damageExpression = "3d6"
        model.saveMacro(forAttack: edited, of: character)
        let sameScope = model.macros.filter { $0.name == "Fire Bolt" && $0.characterName == character.name }
        if let refreshed = sameScope.first, let parts = refreshed.parts {
            bridgeLines.append("after editing damage to 3d6 and re-saving: \(parts.map { $0.expression }.joined(separator: ", "))")
            bridgeLines.append("macro count for that name+owner unchanged: \(sameScope.count == 1)")
        }
        try? bridgeLines.joined(separator: "\n")
            .write(to: URL(fileURLWithPath: "\(outDir)/bridge.txt"),
                   atomically: true, encoding: .utf8)
    }
    // Condition advisory proof (3.24.0): the demo character ships clean, so
    // existing renders stay byte-identical; hindrances are set at the END of
    // the run, then the banner renders and enforcement fires on real rolls.
    if var hindered = model.selected?.wrappedValue {
        hindered.conditions = [.prone, .poisoned]
        hindered.exhaustion = 2
        // 2024-style so the exhaustion line mirrors a real penalty (2014
        // carries no numeric penalty and the advisory correctly stays silent).
        hindered.era = .era2024
        model.selected?.wrappedValue = hindered
    }
    var advisoryLines = ["Condition advisory (3.24.0)",
                         "banner mirrors roll-time enforcement; advisory only, hidden when clean"]
    if let sel = model.selected?.wrappedValue {
        for line in ConditionAdvisory.lines(for: sel) { advisoryLines.append("  \(line)") }
    }
    renderPNG(
        DiceRollerView()
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: width, name: "dice-conditions", outDir: outDir, minHeight: 420, maxHeight: 1100)
    model.rollCheck("Warhammer attack", bonus: 14, mode: .normal)
    model.rollCheck("Stealth check", bonus: 4, mode: .advantage)
    for r in model.rollHistory.prefix(2).reversed() {
        advisoryLines.append("rolled: \(r.label ?? "?")")
    }
    try? advisoryLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/conditions.txt"),
               atomically: true, encoding: .utf8)
    // Roll condition markers proof (3.63.0): ONE flag-derived marker
    // producer in Core feeds every d20 display path. A hindersAttacks custom
    // marks the attack roll and nothing else; an immobilizing custom flags
    // the movement readout and no roll; removal removes the marker. State is
    // set explicitly and restored at the end of the block.
    var markerLines = ["Roll condition markers (3.63.0)",
                       "one flag-derived marker producer in Core; four display paths converged; surfacing only, roll math untouched"]
    if var marked = model.selected?.wrappedValue {
        let origConditions = marked.conditions
        let origCustoms = marked.customConditions
        let origExhaustion = marked.exhaustion
        let origEra = marked.era
        // Phase 1: a custom condition that hinders attacks only.
        marked.conditions = []
        marked.exhaustion = 0
        marked.customConditions = [CustomCondition(name: "Grave-chained", hindersAttacks: true)]
        model.selected?.wrappedValue = marked
        if let dagger = marked.attacks.first(where: { $0.name == "Dagger" }) {
            model.rollAttack(dagger, for: marked)
        }
        model.rollCheck("Perception check", bonus: 5, mode: .normal)
        model.rollCheck("Wisdom save", bonus: 3, mode: .normal)
        let attackLabel = model.rollHistory.first(where: { ($0.label ?? "").hasPrefix("Dagger attack") })?.label ?? "?"
        let checkLabel = model.rollHistory.first(where: { ($0.label ?? "").hasPrefix("Perception check") })?.label ?? "?"
        let saveLabel = model.rollHistory.first(where: { ($0.label ?? "").hasPrefix("Wisdom save") })?.label ?? "?"
        markerLines.append("rolled: \(attackLabel ?? "?")")
        markerLines.append("hindersAttacks custom marks the attack roll: \(attackLabel == "Dagger attack (disadvantage: Grave-chained)")")
        markerLines.append("rolled: \(checkLabel ?? "?")")
        markerLines.append("the same flag marks no check roll: \(checkLabel == "Perception check")")
        markerLines.append("rolled: \(saveLabel ?? "?")")
        markerLines.append("the same flag marks no save roll: \(saveLabel == "Wisdom save")")
        let adv = ConditionAdvisory.lines(for: marked)
        markerLines.append("pre-roll advisory: \(adv.joined(separator: " \u{00B7} "))")
        markerLines.append("advisory names the custom flag: \(adv == ["Attacks hindered: Grave-chained"])")
        renderPNG(
            DiceRollerView()
                .padding()
                .background(Theme.surface)
                .environmentObject(model),
            width: width, name: "dice-roll-markers", outDir: outDir, minHeight: 420, maxHeight: 1100)
        // Phase 2: an immobilizing custom - movement readout flagged, every
        // roll kind clean (the pin-3 boundary in both directions).
        marked.customConditions = [CustomCondition(name: "Stone-rooted", immobilizes: true)]
        model.selected?.wrappedValue = marked
        markerLines.append("immobilized movement readout: \(marked.effectiveMovementSummary)")
        markerLines.append("immobilize flags the movement readout: \(marked.effectiveMovementSummary == "0 ft (immobilized)")")
        model.rollCheck("Longbow attack", bonus: 7, mode: .normal)
        model.rollCheck("Investigation check", bonus: 5, mode: .normal)
        model.rollCheck("Dexterity save", bonus: 3, mode: .normal)
        let ia = model.rollHistory.first(where: { ($0.label ?? "").hasPrefix("Longbow attack") })?.label ?? "?"
        let ic = model.rollHistory.first(where: { ($0.label ?? "").hasPrefix("Investigation check") })?.label ?? "?"
        let isv = model.rollHistory.first(where: { ($0.label ?? "").hasPrefix("Dexterity save") })?.label ?? "?"
        markerLines.append("rolled while immobilized: \(ia ?? "?") / \(ic ?? "?") / \(isv ?? "?")")
        markerLines.append("immobilize marks no attack, check, or save: \(ia == "Longbow attack" && ic == "Investigation check" && isv == "Dexterity save")")
        // Phase 3: removal removes the marker.
        marked.customConditions = []
        model.selected?.wrappedValue = marked
        model.rollCheck("Dagger attack", bonus: 10, mode: .normal)
        let ra = model.rollHistory.first?.label ?? "?"
        markerLines.append("after removal: \(ra ?? "?")")
        markerLines.append("removal removes the marker: \((ra ?? "?") == "Dagger attack")")
        // Restore the state the 3.24.0 block left behind.
        marked.conditions = origConditions
        marked.customConditions = origCustoms
        marked.exhaustion = origExhaustion
        marked.era = origEra
        model.selected?.wrappedValue = marked
        let restored = model.selected?.wrappedValue
        markerLines.append("fixture state restored: \(restored?.conditions == origConditions && restored?.customConditions == origCustoms && restored?.exhaustion == origExhaustion && restored?.era == origEra)")
    }
    try? markerLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/roll-markers.txt"),
               atomically: true, encoding: .utf8)
    // Level-up preview proof (3.25.0): render the preview sheet and record
    // the derived delta, then confirm via the average path and record the
    // result. Runs at END so every earlier render stays byte-identical.
    var levelLines = ["Level-up preview (3.25.0)",
                      "delta computed by derivation; Confirm rides the existing levelUp machinery"]
    if let sel = model.selected?.wrappedValue, let preview = LevelUpPreview(character: sel) {
        levelLines.append("level \(preview.fromLevel) -> \(preview.toLevel); hit dice \(preview.hitDiceFrom) -> \(preview.hitDiceTo); proficiency +\(preview.proficiencyFrom) -> +\(preview.proficiencyTo)")
        for d in preview.slotDeltas {
            levelLines.append("  spell level \(d.spellLevel) slots \(d.from) -> \(d.to)")
        }
        let hpBefore = sel.maxHP
        renderPNG(
            LevelUpPreviewView(character: .constant(sel))
                .environmentObject(model),
            width: 420, name: "level-up-preview", outDir: outDir, minHeight: 180, maxHeight: 480)
        model.levelUp(rollHP: false)
        if let after = model.selected?.wrappedValue {
            levelLines.append("after average confirm: level \(after.level), maxHP \(hpBefore) -> \(after.maxHP) (+\(after.maxHP - hpBefore))")
        }
    }
    try? levelLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/levelup.txt"),
               atomically: true, encoding: .utf8)
    // Group check proof (3.26.0): the whole roster rolls one skill; runs at
    // END so every earlier render stays byte-identical. Two clean party
    // members join the demo character (still hindered from the 3.24.0
    // block), so the proof shows per-participant condition tags.
    var groupLines = ["Group check (3.26.0)",
                      "whole roster rolls the same skill; half or more beats the DC"]
    var bram = SampleContent.demoCharacter()
    bram.id = UUID()
    bram.name = "Bram Oakfel"
    bram.conditions = []
    bram.customConditions = []
    bram.exhaustion = 0
    var sera = SampleContent.demoCharacter()
    sera.id = UUID()
    sera.name = "Sera Vint"
    sera.conditions = []
    sera.customConditions = []
    sera.exhaustion = 0
    model.characters.append(contentsOf: [bram, sera])
    model.rollGroupCheck(skillName: "Stealth", targetDC: 12)
    if let outcome = model.lastGroupCheck {
        for line in outcome.lines {
            let tagSuffix = line.tags.isEmpty ? "" : " (\(line.tags.joined(separator: "; ")))"
            let verdict = line.passed.map { $0 ? "met" : "missed" } ?? "-"
            groupLines.append("\(line.name): total \(line.total) \(verdict)\(tagSuffix)")
        }
        if let v = outcome.verdictLine { groupLines.append(v) }
    }
    renderPNG(
        GroupCheckSectionView()
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: 520, name: "group-check", outDir: outDir, minHeight: 200, maxHeight: 480)
    // 3.27.0 reroll proof: Roll Again on Wren's entry with BRAM selected must
    // re-derive WREN's conditions (hindered), not the selection's (clean).
    model.selectedID = bram.id
    if let wrenEntry = model.rollHistory.first(where: {
        $0.label?.hasPrefix("Wren Halloway - Stealth check") == true
    }) {
        model.rollAgain(wrenEntry)
        if let top = model.rollHistory.first {
            groupLines.append("reroll with Bram selected: \(top.label ?? "?")")
        }
    }
    model.selectedID = character.id
    // Concentration-check proof (3.28.0): untyped incoming damage (no
    // defenses, so the harness can derive the same DC) to a concentrating
    // character forces a CON save; the txt states the outcome either way.
    var concLines = ["Concentration checks (3.28.0)",
                     "incoming damage forces a CON save: DC max(10, damage/2); a fail ends the spell"]
    if var sel = model.selected?.wrappedValue {
        sel.beginConcentration(on: "Ember Ward")
        model.selected?.wrappedValue = sel
        model.rollIncomingDamage("8d6", type: nil)
        let save = model.rollHistory.first
        let dmg = model.rollHistory.dropFirst().first
        if let save, let dmg, let after = model.selected?.wrappedValue {
            let dc = concentrationDC(forDamage: dmg.total)
            let outcome = save.total >= dc ? "met" : "missed"
            concLines.append("concentrating on Ember Ward; damage \(dmg.total) -> DC \(dc); CON save \(save.total) \(outcome); concentration after: \(after.concentratingOn ?? "none")")
        }
    }
    try? concLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/concentrating.txt"),
               atomically: true, encoding: .utf8)
    // Party strip proof (3.29.0): the roster is three by now, so the strip
    // renders; base renders earlier in the run had a roster of one and stay
    // byte-identical (the strip hides). party.txt states each card.
    var partyLines = ["Party overview strip (3.29.0)",
                      "read-only roster cards on every tab; hidden at a roster of one"]
    for c in model.characters {
        let card = PartyCardSummary(character: c)
        let selMark = model.selectedID == c.id ? " [selected]" : ""
        let chips = card.chips.isEmpty ? "-" : card.chips.joined(separator: ", ")
        partyLines.append("\(card.name): lvl \(card.level), HP \(card.currentHP)/\(card.maxHP), temp \(card.tempHP), chips: \(chips)\(selMark)")
    }
    renderPNG(
        PartyStripView()
            .padding(.vertical)
            .background(Theme.surface)
            .environmentObject(model),
        width: 720, name: "party-strip", outDir: outDir, minHeight: 90, maxHeight: 200)
    try? partyLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/party.txt"),
               atomically: true, encoding: .utf8)
    // Condition timers proof (3.30.0): Wren Prone for 2 rounds, Sera
    // Poisoned for 1; the initiative wraps once - Sera's ends with a
    // milestone, Wren's drops to 1. Runs at END.
    var durationLines = ["Condition timers (3.30.0)",
                         "rounds tick on the initiative round wrap; a timer at 0 ends the condition"]
    if let wIdx = model.characters.firstIndex(where: { $0.name == "Wren Halloway" }) {
        model.characters[wIdx].conditionDurations[Condition.prone.rawValue] = 2
    }
    if let sIdx = model.characters.firstIndex(where: { $0.name == "Sera Vint" }) {
        model.characters[sIdx].conditions.insert(.poisoned)
        model.characters[sIdx].conditionDurations[Condition.poisoned.rawValue] = 1
    }
    durationLines.append("before wrap: Wren Prone (2), Sera Poisoned (1)")
    model.addInitiativeEntry(name: "Wren Halloway", bonus: 3)
    model.addInitiativeEntry(name: "Bram Oakfel", bonus: 1)
    model.addInitiativeEntry(name: "Sera Vint", bonus: 2)
    model.rollInitiative()
    // A FULL rotation: the 3.22.0 proof's entries survive its End combat,
    // so the rotation is longer than the three entries added here - only a
    // full lap wraps the round and ticks the timers. (3.30.0 fix1)
    for _ in 0..<model.initiative.entries.count { model.advanceInitiative() }
    for c in model.characters {
        let chips = c.conditionChipNames.isEmpty ? "-" : c.conditionChipNames.joined(separator: ", ")
        durationLines.append("after wrap \(model.initiative.round): \(c.name) chips: \(chips)")
        if c.name == "Sera Vint" {
            let milestone = c.notes.contains("Poisoned ended (duration).") ? "present" : "MISSING"
            durationLines.append("Sera notes milestone: \(milestone)")
        }
    }
    if let selBinding = model.selected {
        renderPNG(
            VitalsBlock(character: selBinding)
                .padding()
                .background(Theme.surface)
                .environmentObject(model),
            width: 520, name: "vitals-timers", outDir: outDir, minHeight: 300, maxHeight: 900)
    }
    try? durationLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/durations.txt"),
               atomically: true, encoding: .utf8)
    // Group save proof (3.31.0): Wren is poisoned + exhausted - her save
    // line shows the exhaustion tag and NO disadvantage tag (the save-kind
    // rider made visible). Runs at END.
    var gsaveLines = ["Group saves (3.31.0)",
                      "saves are never condition-hindered; exhaustion still subtracts (2024)"]
    model.rollGroupSave(ability: .wisdom, targetDC: 13)
    if let outcome = model.lastGroupCheck {
        for line in outcome.lines {
            let tagSuffix = line.tags.isEmpty ? "" : " (\(line.tags.joined(separator: "; ")))"
            let verdict = line.passed.map { $0 ? "met" : "missed" } ?? "-"
            gsaveLines.append("\(line.name): total \(line.total) \(verdict)\(tagSuffix)")
        }
        if let v = outcome.verdictLine { gsaveLines.append(v) }
    }
    renderPNG(
        GroupCheckSectionView()
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: 520, name: "group-save", outDir: outDir, minHeight: 200, maxHeight: 480)
    try? gsaveLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/groupsave.txt"),
               atomically: true, encoding: .utf8)
    // Delete confirmation proof (3.32.0): the armed toolbar state. Runs at
    // END; no state is mutated (the confirm is never fired).
    renderPNG(
        DeleteConfirmCluster(confirmingDelete: .constant(true))
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: 520, name: "roster-delete-confirm", outDir: outDir, minHeight: 60, maxHeight: 120)
    // Concentration timer proof (3.33.0): cast a 1-minute spell (10 rounds),
    // wrap once, render the row at 9, then wrap on to the expiry milestone.
    var ctLines = ["Concentration duration timers (3.33.0)",
                   "cast sets the timer from the spell's duration; the wrap ticks it; 0 drops concentration"]
    if let faerie = SpellLibrary.spell(named: "Faerie Fire") {
        model.castSpell(faerie)
        ctLines.append("cast Faerie Fire (1 minute) -> timer \(model.selected?.wrappedValue.concentrationTimer ?? -1), concentrating")
        for _ in 0..<model.initiative.entries.count { model.advanceInitiative() }
        ctLines.append("after wrap 1: timer \(model.selected?.wrappedValue.concentrationTimer ?? -1)")
        if let selBinding = model.selected {
            renderPNG(
                SpellcastingBlock(character: selBinding)
                    .padding()
                    .background(Theme.surface)
                    .environmentObject(model),
                // Tall window: renderPNG clips from the TOP when the fitting
                // height exceeds maxHeight (AppKit lays out bottom-up), and
                // the concentration row sits at the block's top.
                width: 520, name: "concentration-timer", outDir: outDir, minHeight: 200, maxHeight: 1800)
        }
        for _ in 0..<(9 * model.initiative.entries.count) { model.advanceInitiative() }
        let after = model.selected?.wrappedValue
        let milestone = after?.notes.contains("Concentration on Faerie Fire ended (duration).") == true ? "present" : "MISSING"
        ctLines.append("after wrap 10: concentrating \(after?.concentratingOn ?? "ended"), milestone \(milestone)")
    }
    try? ctLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/concentration-timer.txt"),
               atomically: true, encoding: .utf8)
    // Encounter estimate proof (3.34.0): party derived from the roster,
    // two entered enemy rows, verdict with the derivation shown. Runs at
    // END; the rows persist to the scratch store only.
    model.encounterLines = [
        EncounterLine(count: 2, cr: 3),
        EncounterLine(count: 1, cr: 0.5),
    ]
    model.saveEncounterLines()
    var encLines = ["Encounter estimate (3.34.0)",
                    "party thresholds derive from roster levels; enemy rows are entered, never inferred"]
    encLines.append("party: " + model.characters.map { "\($0.name) L\($0.level)" }.joined(separator: ", "))
    if let est = model.encounterEstimate {
        encLines.append("enemies: 2x CR 3 + 1x CR 1/2 -> base \(est.baseXP) XP x\(est.multiplier) = adjusted \(est.adjustedXP)")
        let t = est.thresholds
        encLines.append("thresholds: Easy \(t.easy) - Medium \(t.medium) - Hard \(t.hard) - Deadly \(t.deadly)")
        encLines.append("verdict: \(est.band.displayName)")
    }
    renderPNG(
        EncounterSectionView()
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: 520, name: "encounter", outDir: outDir, minHeight: 140, maxHeight: 800)
    try? encLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/encounter.txt"),
               atomically: true, encoding: .utf8)
    // Party-strip concentration chip proof (3.35.0): a running timer rides
    // the chip. Runs at END; mutates Wren after every earlier render.
    if let idx = model.characters.firstIndex(where: { $0.name == "Wren Halloway" }) {
        model.characters[idx].beginConcentration(on: "Faerie Fire")
        model.characters[idx].concentrationTimer = 9
    }
    renderPNG(
        PartyStripView()
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: 720, name: "party-strip-concentration", outDir: outDir, minHeight: 90, maxHeight: 200)
    let wrenChip = model.characters.first(where: { $0.name == "Wren Halloway" })
        .map { PartyCardSummary(character: $0).chips.last ?? "-" } ?? "-"
    try? (["Party-strip concentration chip (3.35.0)",
           "a running concentration timer rides the chip, matching the condition countdowns",
           "Wren's last chip: \(wrenChip)"]
          .joined(separator: "\n"))
        .write(to: URL(fileURLWithPath: "\(outDir)/party-strip-concentration.txt"),
               atomically: true, encoding: .utf8)
    // Live-fight estimate proof (3.36.0): CRs ride the initiative entries;
    // the estimate derives from the tracker - entered once, never
    // duplicated. Runs at END and resets the tracker, so the earlier dice
    // and encounter renders stay CR-free.
    model.clearInitiative()
    model.addInitiativeEntry(name: "Gnoll 1", bonus: 1, cr: 3)
    model.addInitiativeEntry(name: "Gnoll 2", bonus: 1, cr: 3)
    model.addInitiativeEntry(name: "Snapjaw", bonus: 2, cr: 0.5)
    for c in model.characters {
        model.addInitiativeEntry(name: c.name, bonus: c.initiative, forCharacter: c.name)
    }
    var liveLines = ["Live-fight estimate (3.36.0)",
                     "CRs ride initiative entries; the estimate derives from the tracker - entered once, never duplicated"]
    liveLines.append("from initiative: \(model.initiative.crBreakdown)")
    if let live = model.liveFightEstimate {
        liveLines.append("base \(live.baseXP) XP x\(live.multiplier) = adjusted \(live.adjustedXP)")
        let t = live.thresholds
        liveLines.append("thresholds: Easy \(t.easy) - Medium \(t.medium) - Hard \(t.hard) - Deadly \(t.deadly)")
        liveLines.append("verdict: \(live.band.displayName)")
    } else {
        liveLines.append("verdict: MISSING - no live estimate")
    }
    liveLines.append("excluded from the estimate: \(model.initiative.entriesWithoutCR) entries without CR")
    renderPNG(
        EncounterSectionView()
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: 520, name: "live-fight", outDir: outDir, minHeight: 240, maxHeight: 900)
    try? liveLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/live-fight.txt"),
               atomically: true, encoding: .utf8)
    // Start-fight proof (3.37.0): the planner's rows push into the tracker
    // as individual CR'd entries; the live estimate derives from the push.
    // Runs at END; the planner still holds 2x CR 3 + 1x CR 1/2.
    model.startFightFromPlanner()
    var sfLines = ["Start fight (3.37.0)",
                   "planner rows expand into individual CR'd entries - replace semantics, rolls flat"]
    sfLines.append("pushed: " + model.initiative.entries.map { "\($0.name) (CR \($0.cr.map { EncounterMath.crText($0) } ?? "-"))" }.joined(separator: ", "))
    sfLines.append("tracker entries: \(model.initiative.entries.count), round \(model.initiative.round), totals all nil: \(model.initiative.entries.allSatisfy { $0.total == nil })")
    if let live = model.liveFightEstimate {
        sfLines.append("live verdict after push: \(live.band.displayName) (adjusted \(live.adjustedXP)) - matches the planner")
    } else {
        sfLines.append("live verdict after push: MISSING")
    }
    renderPNG(
        InitiativeSectionView()
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: 560, name: "start-fight", outDir: outDir, minHeight: 200, maxHeight: 600)
    try? sfLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/start-fight.txt"),
               atomically: true, encoding: .utf8)
    // Rename proof (3.38.0): the pencil swaps the row's name for a field;
    // blank keeps the current name. Runs at END on the pushed tracker.
    var rnLines = ["Tracker-entry rename (3.38.0)",
                   "pencil swaps the name for an inline field; blank keeps the current name"]
    if let target = model.initiative.entries.first(where: { $0.name == "CR 3 #2" }) {
        model.renameInitiativeEntry(target, name: "Gnoll archer")
        model.renameInitiativeEntry(target, name: "   ")
        let after = model.initiative.entries.first(where: { $0.id == target.id })
        rnLines.append("renamed: \(target.name) -> \(after?.name ?? "MISSING") (a blank submit kept it)")
        rnLines.append("preserved: CR \(after?.cr.map { EncounterMath.crText($0) } ?? "-"), total nil: \(after?.total == nil)")
    } else {
        rnLines.append("rename target MISSING")
    }
    renderPNG(
        InitiativeSectionView()
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: 560, name: "initiative-rename", outDir: outDir, minHeight: 200, maxHeight: 600)
    try? rnLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/initiative-rename.txt"),
               atomically: true, encoding: .utf8)
    // Add-to-fight proof (3.39.0): the wave appends, numbering continues by
    // CR value through the renamed entry, and the live verdict re-derives
    // over the bigger fight - Hard tips to Deadly. Runs at END.
    model.addToFightFromPlanner()
    var afLines = ["Add to fight (3.39.0)",
                   "the wave appends; numbering continues by CR value through renames; turn state carries"]
    afLines.append("tracker now: " + model.initiative.entries.map { $0.name }.joined(separator: ", "))
    afLines.append("round \(model.initiative.round), entries \(model.initiative.entries.count)")
    if let live = model.liveFightEstimate {
        afLines.append("live verdict after the wave: \(live.band.displayName) (adjusted \(live.adjustedXP)) - was Hard 3000 before")
    } else {
        afLines.append("live verdict after the wave: MISSING")
    }
    renderPNG(
        InitiativeSectionView()
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: 560, name: "add-to-fight", outDir: outDir, minHeight: 260, maxHeight: 700)
    try? afLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/add-to-fight.txt"),
               atomically: true, encoding: .utf8)
    // Bonus-edit + add-party proofs (3.40.0). Runs at END on the wave tracker.
    var bpLines = ["Initiative bonus edit + add party (3.40.0)",
                   "bonus edits in place like CR and total; add party skips names already on the tracker"]
    if let target = model.initiative.entries.first(where: { $0.name == "CR 3 #1" }) {
        model.setInitiativeBonus(target, bonus: 4)
        model.setInitiativeBonus(target, bonus: Int("abc"))
        let after = model.initiative.entries.first(where: { $0.id == target.id })
        bpLines.append("bonus edit: CR 3 #1 bonus 0 -> \(after?.bonus ?? -99) (an invalid submit kept it)")
    } else {
        bpLines.append("bonus edit target MISSING")
    }
    let before = model.initiative.entries.count
    model.addRosterToInitiative()
    let mid = model.initiative.entries.count
    model.addRosterToInitiative()
    bpLines.append("add party: entries \(before) -> \(mid); re-tap: \(model.initiative.entries.count) (dedup held)")
    bpLines.append("party linked: " + model.initiative.entries.filter { $0.characterName != nil }
        .map { $0.name }.joined(separator: ", "))
    renderPNG(
        InitiativeSectionView()
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: 560, name: "initiative-bonus-party", outDir: outDir, minHeight: 320, maxHeight: 900)
    try? bpLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/initiative-bonus-party.txt"),
               atomically: true, encoding: .utf8)
    // Award-XP proofs (3.41.0): the fight pays its base XP back to the
    // roster - pool derivation, even split, live re-split on uncheck,
    // level-up note, undo ride. Runs at END on the party-laden tracker.
    var axLines = ["Award XP from the fight (3.41.0)",
                   "pool derives from tracker CRs (base pays, adjusted budgets); apply rides each character's undo stack"]
    // Park Bram one step below his next threshold so the preview badge shows.
    if let bidx = model.characters.firstIndex(where: { $0.name == "Bram Oakfel" }),
       let next = RulesMath.xpForNextLevel(RulesMath.level(forXP: model.characters[bidx].experience)) {
        model.characters[bidx].experience = next - 100
    }
    renderPNG(
        XPAwardPanelView()
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: 560, name: "award-xp", outDir: outDir, minHeight: 160, maxHeight: 480)
    if let plan = model.xpAwardPlan(mode: .equalSplit, excluded: []) {
        axLines.append("pool: \(plan.baseXP) base (adjusted \(Int(plan.adjustedXP.rounded()))) from \(model.initiative.entries.compactMap(\.cr).count) CR'd entries; \(model.initiative.entriesWithoutCR) without CR pay nothing")
        axLines.append("split: " + plan.shares.map { "\($0.name) \($0.currentXP) + \($0.amount) = \($0.newXP)\($0.levelsUp ? " LEVEL UP -> L\($0.newLevel)" : "")" }.joined(separator: ", "))
    } else {
        axLines.append("plan MISSING")
    }
    if let full = model.xpAwardPlan(mode: .fullPool, excluded: []) {
        axLines.append("full pool each: " + full.shares.map { "\($0.name) +\($0.amount)" }.joined(separator: ", "))
    }
    if let bram = model.characters.first(where: { $0.name == "Bram Oakfel" }),
       let re = model.xpAwardPlan(mode: .equalSplit, excluded: [bram.id]) {
        axLines.append("re-split without Bram: " + re.shares.filter { $0.included }.map { "\($0.name) +\($0.amount)" }.joined(separator: ", "))
    }
    let leveled = model.awardFightXP(mode: .equalSplit, excluded: [])
    axLines.append("applied: level-ups \(leveled.isEmpty ? "none" : leveled.joined(separator: ", "))")
    axLines.append("after: " + model.characters.map { "\($0.name) \($0.experience) XP L\($0.level)" }.joined(separator: ", "))
    let nobody = model.awardFightXP(mode: .equalSplit, excluded: Set(model.characters.map(\.id)))
    axLines.append("award with nobody checked: \(nobody.isEmpty ? "paid nothing" : "PAID - WRONG")")
    if let bram = model.characters.first(where: { $0.name == "Bram Oakfel" }) {
        model.selectedID = bram.id
        model.undo()
        let back = model.characters.first(where: { $0.id == bram.id })
        axLines.append("undo: Bram back to \(back?.experience ?? -1) XP L\(back?.level ?? -1) (one step on his own stack)")
    }
    try? axLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/award-xp.txt"),
               atomically: true, encoding: .utf8)
    // Milestone-safe leveling proofs (3.42.0): a hand-raised level holds
    // through awards until the track passes it. Runs at END.
    var msLines = ["Milestone-safe leveling (3.42.0)",
                   "level is a floor: awards never demote; the track takes over once it passes the milestone"]
    if let sidx = model.characters.firstIndex(where: { $0.name == "Sera Vint" }) {
        model.characters[sidx].level = 8   // hand-raised past the track (8200 XP derives 5)
    }
    if let parked = model.characters.first(where: { $0.name == "Sera Vint" }) {
        msLines.append("parked: Sera Vint L\(parked.level) at \(parked.experience) XP (track derives L\(RulesMath.level(forXP: parked.experience))) - milestone-ahead: \(parked.isMilestoneAhead)")
    }
    renderPNG(
        SheetColumnView(character: .constant(model.characters.first(where: { $0.name == "Sera Vint" }) ?? model.characters[0]))
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: 1180, name: "milestone-leveling", outDir: outDir)
    let others = Set(model.characters.filter { $0.name != "Sera Vint" }.map(\.id))
    if let plan = model.xpAwardPlan(mode: .equalSplit, excluded: others),
       let share = plan.shares.first(where: { $0.name == "Sera Vint" }) {
        msLines.append("preview: Sera \(share.currentXP) + \(share.amount) = \(share.newXP), badge \(share.levelsUp ? "ON" : "off (holds L\(share.newLevel))")")
    }
    let leveled2 = model.awardFightXP(mode: .equalSplit, excluded: others)
    let after1 = model.characters.first(where: { $0.name == "Sera Vint" })
    msLines.append("applied: level-ups \(leveled2.isEmpty ? "none" : leveled2.joined(separator: ", ")); Sera \(after1?.experience ?? -1) XP L\(after1?.level ?? -1) (pre-3.42.0 she would drop to L5)")
    // Park XP just under the next threshold; the next award lets the track
    // pass the milestone.
    if let sidx = model.characters.firstIndex(where: { $0.name == "Sera Vint" }) {
        model.characters[sidx].experience = 47900   // derives L8, level holds at 8
    }
    if let plan = model.xpAwardPlan(mode: .equalSplit, excluded: others),
       let share = plan.shares.first(where: { $0.name == "Sera Vint" }) {
        msLines.append("catch-up preview: Sera \(share.currentXP) + \(share.amount) = \(share.newXP)\(share.levelsUp ? " LEVEL UP -> L\(share.newLevel)" : " (no badge - WRONG)")")
    }
    let leveled3 = model.awardFightXP(mode: .equalSplit, excluded: others)
    let after2 = model.characters.first(where: { $0.name == "Sera Vint" })
    msLines.append("applied: level-ups \(leveled3.isEmpty ? "none" : leveled3.joined(separator: ", ")); Sera \(after2?.experience ?? -1) XP L\(after2?.level ?? -1) (the track took over past the milestone)")
    try? msLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/milestone-leveling.txt"),
               atomically: true, encoding: .utf8)
    // Encounter library + labeled rows proofs (3.43.0). Runs at END.
    var elLines = ["Encounter library + labeled rows (3.43.0)",
                   "save/reload carries labels; overwrite upserts by name; wave numbering keys the label FIELD, never names"]
    // Migration: pre-label rows (no label key in the JSON) decode unchanged.
    let oldJSON = "[{\"id\":\"\(UUID().uuidString)\",\"count\":2,\"cr\":3.0}]"
    let oldLines = (try? JSONDecoder().decode([EncounterLine].self, from: Data(oldJSON.utf8))) ?? []
    elLines.append("migration: old-format row decodes (count \(oldLines.first?.count ?? -1), label '\(oldLines.first?.label ?? "?")') - saved planner rows survive")
    // Label the CR 3 row, save as a named encounter, junk the rows, reload.
    if let idx = model.encounterLines.firstIndex(where: { $0.cr == 3 }) {
        model.encounterLines[idx].label = "Gnolls"
        model.saveEncounterLines()
    }
    model.saveEncounterAs(name: "Bridge ambush")
    let savedSummary = model.savedEncounters.first?.summary ?? "MISSING"
    model.encounterLines = [EncounterLine(count: 5, cr: 10)]
    model.saveEncounterLines()
    if let saved = model.savedEncounters.first {
        model.loadSavedEncounter(saved)
    }
    elLines.append("library: saved 'Bridge ambush' (\(savedSummary)); junked rows, reload restored: \(model.encounterLines.map { "\($0.count)x \($0.label.isEmpty ? "CR \(EncounterMath.crText($0.cr))" : $0.label)" }.joined(separator: ", "))")
    model.saveEncounterAs(name: "Bridge ambush")   // the UI arms an overwrite confirm first
    elLines.append("overwrite: duplicate name upserts in place - library count \(model.savedEncounters.count)")
    renderPNG(
        EncounterLibraryView()
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: 560, name: "encounter-library", outDir: outDir, minHeight: 120, maxHeight: 400)
    if let saved = model.savedEncounters.first { model.deleteSavedEncounter(saved) }
    elLines.append("delete: library count \(model.savedEncounters.count)")
    // Labeled start fight, then a wave after a rename.
    model.startFightFromPlanner()
    elLines.append("labels: start fight -> \(model.initiative.entries.map { $0.name }.joined(separator: ", "))")
    if let first = model.initiative.entries.first(where: { $0.label == "Gnolls" }) {
        model.renameInitiativeEntry(first, name: "Bridge boss")
    }
    model.addToFightFromPlanner()
    let gnolls = model.initiative.entries.filter { $0.label == "Gnolls" }.map { $0.name }
    elLines.append("wave after rename: Gnolls-labeled entries now \(gnolls.joined(separator: ", ")) ('Bridge boss' keeps its label field; numbering never parses names)")
    try? elLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/encounter-library.txt"),
               atomically: true, encoding: .utf8)
    // Pre-fight restore + fight recap proofs (3.44.0). Runs at END.
    var prLines = ["Pre-fight restore + fight recap (3.44.0)",
                   "Start fight snapshots the displaced tracker one level deep; End combat files a derived recap to the selected character's journal"]
    // A live mid-round fight on the tracker, displaced by Start fight.
    model.initiative = InitiativeTracker(entries: [InitiativeEntry(name: "Lone sentry", bonus: 2, total: 14, cr: 1),
                                                   InitiativeEntry(name: "Wren Halloway", bonus: 3, total: 18, characterName: "Wren Halloway")],
                                         activeID: nil, round: 2)
    model.startFightFromPlanner()   // planner still holds 2x Gnolls + 1x CR 1/2
    prLines.append("snapshot: start fight over a mid-round tracker -> \(model.initiative.entries.count) new entries; snapshot holds '\(model.initiative.preFightSnapshot?.entries.map(\.name).joined(separator: ", ") ?? "MISSING")' round \(model.initiative.preFightSnapshot?.round ?? -1)")
    renderPNG(
        InitiativeSectionView()
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: 520, name: "initiative-restore", outDir: outDir, minHeight: 160, maxHeight: 600)
    model.restorePreFight()
    prLines.append("restore: tracker back to \(model.initiative.entries.map(\.name).joined(separator: ", ")) round \(model.initiative.round); snapshot consumed: \(model.initiative.preFightSnapshot == nil)")
    model.restorePreFight()
    prLines.append("second restore is a no-op (one level, no chain): still \(model.initiative.entries.map(\.name).joined(separator: ", "))")
    // Fight recap: run the planner fight three rounds, award, end.
    model.startFightFromPlanner()
    model.rollInitiative()
    for _ in 0..<6 { model.advanceInitiative() }   // two wraps -> round 3
    _ = model.awardFightXP(mode: .equalSplit, excluded: [])
    if let wren = model.characters.first(where: { $0.name == "Wren Halloway" }) { model.selectedID = wren.id }
    model.endCombat()
    let recapEntry = model.characters.first(where: { $0.name == "Wren Halloway" })?.journal.last
    prLines.append("recap: '\(recapEntry?.title ?? "MISSING")' - \(recapEntry?.text ?? "MISSING")")
    prLines.append("after end combat: totals cleared \(model.initiative.entries.allSatisfy { $0.total == nil }), round \(model.initiative.round), award consumed \(model.initiative.fightAward == nil)")
    // Negative: a second End combat on the idle tracker files nothing.
    let journalCountBefore = model.characters.first(where: { $0.name == "Wren Halloway" })?.journal.count ?? -1
    model.endCombat()
    let journalCountAfter = model.characters.first(where: { $0.name == "Wren Halloway" })?.journal.count ?? -1
    prLines.append("idle end combat files nothing: journal \(journalCountBefore) -> \(journalCountAfter)")
    try? prLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/prefight-recap.txt"),
               atomically: true, encoding: .utf8)
    // Table log + party rest proofs (3.45.0). Runs at END.
    var tlLines = ["Table log + party rest (3.45.0)",
                   "the party's shared record: manual entries + the fight recap's second home; party rest rides each member's own undo stack"]
    model.addTableLogEntry(title: "Ember Warrens", text: "The party reaches the bridge over the Ember.")
    tlLines.append("manual entry: log count \(model.tableLog.count), latest '\(model.tableLog.last?.title ?? "MISSING")' - \(model.tableLog.last?.text ?? "MISSING")")
    // Fight recap dual-files: the identical derived line to the journal AND the log.
    model.startFightFromPlanner()
    model.rollInitiative()
    for _ in 0..<6 { model.advanceInitiative() }   // two wraps -> round 3
    _ = model.awardFightXP(mode: .equalSplit, excluded: [])
    if let wren = model.characters.first(where: { $0.name == "Wren Halloway" }) { model.selectedID = wren.id }
    model.endCombat()
    let journalLine = model.characters.first(where: { $0.name == "Wren Halloway" })?.journal.last?.text ?? "MISSING"
    let logLine = model.tableLog.last?.text ?? "MISSING"
    tlLines.append("dual-file: journal and log identical: \(journalLine == logLine) - '\(logLine)'")
    renderPNG(
        TableLogView()
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: 720, name: "table-log", outDir: outDir, minHeight: 120, maxHeight: 400) // 3.66.0: 560 clipped the new filter menu
    if let first = model.tableLog.first { model.deleteTableLogEntry(first) }
    tlLines.append("delete: log count \(model.tableLog.count) (the recap entry survives)")
    // Persistence proof via a scoped store load: reloading the whole model
    // here re-seeds the roster from the scratch store on disk and drops the
    // in-memory-only fixture members, voiding the rest/undo proofs below
    // (3.45.0 first build). A direct store round-trip leaves live state
    // untouched.
    let persistedLog = model.tableLogStore.load()
    tlLines.append("persistence: disk round-trip keeps \(persistedLog.count) of \(model.tableLog.count) entries - latest '\(persistedLog.last?.title ?? "MISSING")'")
    // Negative: an idle End combat files to NEITHER the journal nor the log.
    let jBefore = model.characters.first(where: { $0.name == "Wren Halloway" })?.journal.count ?? -1
    let lBefore = model.tableLog.count
    model.endCombat()
    tlLines.append("idle end combat: journal \(jBefore) -> \(model.characters.first(where: { $0.name == "Wren Halloway" })?.journal.count ?? -1), log \(lBefore) -> \(model.tableLog.count)")
    // Party rest: rough the roster up first so the rest has something to do.
    // The rough-up goes through the tracked `selected` binding so each
    // member's undo stack stays in sync with the live character - a direct
    // array mutation would leave the stack stale and the undo step below
    // would restore a pre-rough-up frame instead of the true pre-rest state
    // (the 3.45.0 fixed build read 'back to 0' for exactly that reason).
    if let w = model.characters.firstIndex(where: { $0.name == "Wren Halloway" }) {
        model.selectedID = model.characters[w].id
        if var sel = model.selected?.wrappedValue {
            sel.currentHP = max(1, sel.currentHP - 7)
            model.selected?.wrappedValue = sel
        }
    }
    if let b = model.characters.firstIndex(where: { $0.name == "Bram Oakfel" }) {
        model.selectedID = model.characters[b].id
        if var sel = model.selected?.wrappedValue {
            sel.exhaustion = 2
            model.selected?.wrappedValue = sel
        }
    }
    tlLines.append("before rest: " + model.characters.map { "\($0.name) HP \($0.currentHP)/\($0.maxHP) ex \($0.exhaustion)" }.joined(separator: ", "))
    let wrenPreRestHP = model.characters.first(where: { $0.name == "Wren Halloway" })?.currentHP ?? -1
    let rested = model.restParty(long: true)
    tlLines.append("party long rest: rested \(rested.count) (\(rested.joined(separator: ", ")))")
    tlLines.append("after rest: " + model.characters.map { "\($0.name) HP \($0.currentHP)/\($0.maxHP) ex \($0.exhaustion)" }.joined(separator: ", "))
    // The undo ride: one member's undo restores just them, to exactly their
    // pre-rest state; the others stay rested. Both checks print as booleans.
    let bramRestedHP = model.characters.first(where: { $0.name == "Bram Oakfel" })?.currentHP ?? -1
    if let wren2 = model.characters.first(where: { $0.name == "Wren Halloway" }) {
        model.selectedID = wren2.id
        model.undo()
        let back = model.characters.first(where: { $0.name == "Wren Halloway" })
        let bramAfter = model.characters.first(where: { $0.name == "Bram Oakfel" })
        tlLines.append("undo: Wren HP back to \(back?.currentHP ?? -1) (pre-rest \(wrenPreRestHP): \(back?.currentHP == wrenPreRestHP)); Bram untouched: \(bramAfter?.currentHP == bramRestedHP)")
    }
    try? tlLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/table-log.txt"),
               atomically: true, encoding: .utf8)
    // 3.44.0 hygiene: hand selection back to Bram so downstream proofs
    // (the delete-confirm caption) match their pre-3.44.0 bytes.
    if let bram = model.characters.first(where: { $0.name == "Bram Oakfel" }) { model.selectedID = bram.id }
    try? (["Delete confirmation (3.32.0)",
           "the toolbar trash arms an inline confirm - Delete fires only from",
           "the armed state; Cancel disarms. The character's undo stack dies",
           "with it, so the armed Delete warns it cannot be undone.",
           "armed caption reads: Delete \(model.selected?.wrappedValue.name ?? "character")?"]
          .joined(separator: "\n"))
        .write(to: URL(fileURLWithPath: "\(outDir)/delete-confirm.txt"),
               atomically: true, encoding: .utf8)
    try? groupLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/groupcheck.txt"),
               atomically: true, encoding: .utf8)
    // Encounter notes + party journal search proofs (3.46.0). Runs at END.
    var enLines = ["Encounter notes (3.46.0)",
                   "a tactics note rides the saved encounter through save/load/overwrite"]
    // Make sure the planner has a row, then save and give it a note.
    if model.encounterLines.isEmpty {
        model.addEncounterLine()
        model.encounterLines[model.encounterLines.count - 1].count = 2
        model.encounterLines[model.encounterLines.count - 1].label = "Gnolls"
        model.saveEncounterLines()
    }
    model.saveEncounterAs(name: "Proof Den")
    guard let den = model.savedEncounters.first(where: { $0.name == "Proof Den" }) else {
        enLines.append("SETUP MISS: Proof Den did not save")
        try? enLines.joined(separator: "\n")
            .write(to: URL(fileURLWithPath: "\(outDir)/encounter-notes.txt"),
                   atomically: true, encoding: .utf8)
        return
    }
    let denID = den.id
    model.setSavedEncounterNotes(id: denID, notes: "focus the casters")
    let persistedNote = model.encounterLibraryStore.load()
        .first(where: { $0.name == "Proof Den" })?.notes ?? "MISSING"
    enLines.append("note set + persistence: library reload keeps '\(persistedNote)'")
    // Same-name overwrite replaces the rows but must keep note and identity.
    model.addEncounterLine()
    model.encounterLines[model.encounterLines.count - 1].count = 1
    model.encounterLines[model.encounterLines.count - 1].label = "Shaman"
    model.saveEncounterLines()
    model.saveEncounterAs(name: "Proof Den")
    let afterOverwrite = model.savedEncounters.first(where: { $0.name == "Proof Den" })
    enLines.append("overwrite: note kept \(afterOverwrite?.notes == "focus the casters"), id stable \(afterOverwrite?.id == denID), summary now '\(afterOverwrite?.summary ?? "MISSING")'")
    // Edit path: the note updates in place.
    model.setSavedEncounterNotes(id: denID, notes: "river is difficult terrain")
    enLines.append("edit: note now '\(model.savedEncounters.first(where: { $0.id == denID })?.notes ?? "MISSING")'")
    renderPNG(
        EncounterLibraryView()
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: 560, name: "encounter-notes", outDir: outDir, minHeight: 120, maxHeight: 400)
    try? enLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/encounter-notes.txt"),
               atomically: true, encoding: .utf8)
    // Party journal search: plant a distinctive entry in Bram's journal,
    // then prove the party lens finds it with attribution while Wren's
    // per-character filter cannot.
    var psLines = ["Party journal search (3.46.0)",
                   "one query across every party member's journal, with attribution"]
    if let bram = model.characters.first(where: { $0.name == "Bram Oakfel" }) {
        model.selectedID = bram.id
        if var sel = model.selected?.wrappedValue {
            sel.journal.append(JournalEntry(date: "Session 9", title: "Moonlight omen",
                                            text: "The Vault sigil flared under moonlight.",
                                            createdAt: Date()))
            model.selected?.wrappedValue = sel
        }
    }
    let hits = model.journalPartySearch("moonlight")
    psLines.append("party search 'moonlight': \(hits.count) hit - \(hits.first.map { "\($0.characterName): '\($0.entry.title)'" } ?? "none")")
    psLines.append("case-insensitive: 'MOONLIGHT' hits \(model.journalPartySearch("MOONLIGHT").count)")
    let wrenOwn = model.characters.first(where: { $0.name == "Wren Halloway" })?
        .journal.filter { $0.matchesFilter("moonlight") }.count ?? -1
    psLines.append("per-character scope: Wren's own filter finds \(wrenOwn) (the entry is Bram's)")
    psLines.append("empty query: \(model.journalPartySearch("   ").count) hits")
    renderPNG(
        JournalBlock(character: .constant(model.characters.first(where: { $0.name == "Wren Halloway" }) ?? character),
                     initialFilter: "moonlight", initialPartyScope: true)
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: 560, name: "journal-party-search", outDir: outDir, minHeight: 120, maxHeight: 400)
    try? psLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/journal-party-search.txt"),
               atomically: true, encoding: .utf8)
    // Party damage/heal + table-log export proofs (3.47.0). Runs at END.
    var phLines = ["Party damage/heal (3.47.0)",
                   "the rest row's exact discipline: own undo stacks, temp-HP absorption, 0-HP floor"]
    // Give Wren temp HP 5 through the tracked selected binding.
    if let wren = model.characters.first(where: { $0.name == "Wren Halloway" }) {
        model.selectedID = wren.id
        if var sel = model.selected?.wrappedValue {
            sel.tempHP = 5
            model.selected?.wrappedValue = sel
        }
    }
    let wrenPre = model.characters.first(where: { $0.name == "Wren Halloway" })
    let bramPre = model.characters.first(where: { $0.name == "Bram Oakfel" })
    let seraPre = model.characters.first(where: { $0.name == "Sera Vint" })
    phLines.append("before: " + model.characters.map { "\($0.name) HP \($0.currentHP)/\($0.maxHP) temp \($0.tempHP)" }.joined(separator: ", "))
    let damaged = model.adjustPartyHP(amount: 10, damage: true)
    let wrenDmg = model.characters.first(where: { $0.name == "Wren Halloway" })
    let bramDmg = model.characters.first(where: { $0.name == "Bram Oakfel" })
    let seraDmg = model.characters.first(where: { $0.name == "Sera Vint" })
    phLines.append("party damage 10: adjusted \(damaged.count) (\(damaged.joined(separator: ", ")))")
    phLines.append("after: " + model.characters.map { "\($0.name) HP \($0.currentHP)/\($0.maxHP) temp \($0.tempHP)" }.joined(separator: ", "))
    phLines.append("temp absorbs then floor: Wren temp \(wrenPre?.tempHP ?? -1)->\(wrenDmg?.tempHP ?? -1), HP \(wrenPre?.currentHP ?? -1)->\(wrenDmg?.currentHP ?? -1) (floored at 0: \(wrenDmg?.currentHP == 0))")
    // 3.47.0 label fix: report the actual pre-damage temp instead of
    // assuming none - the roster fixture carries temp on Bram/Sera.
    phLines.append("Bram temp \(bramPre?.tempHP ?? -1)->\(bramDmg?.tempHP ?? -1), HP \(bramPre?.currentHP ?? -1)->\(bramDmg?.currentHP ?? -1); Sera temp \(seraPre?.tempHP ?? -1)->\(seraDmg?.tempHP ?? -1), HP \(seraPre?.currentHP ?? -1)->\(seraDmg?.currentHP ?? -1)")
    // One member's undo restores just them - own undo stacks.
    if let wren2 = model.characters.first(where: { $0.name == "Wren Halloway" }) {
        model.selectedID = wren2.id
        model.undo()
        let back = model.characters.first(where: { $0.name == "Wren Halloway" })
        let bramStill = model.characters.first(where: { $0.name == "Bram Oakfel" })
        phLines.append("Wren-only undo: HP \(back?.currentHP ?? -1) temp \(back?.tempHP ?? -1) (pre-damage \(wrenPre?.currentHP ?? -1)/\(wrenPre?.tempHP ?? -1): \(back?.currentHP == wrenPre?.currentHP && back?.tempHP == wrenPre?.tempHP)); Bram untouched: \(bramStill?.currentHP == bramDmg?.currentHP)")
    }
    let healed = model.adjustPartyHP(amount: 6, damage: false)
    phLines.append("party heal 6: adjusted \(healed.count)")
    phLines.append("after heal: " + model.characters.map { "\($0.name) HP \($0.currentHP)/\($0.maxHP) temp \($0.tempHP)" }.joined(separator: ", "))
    renderPNG(
        GroupCheckSectionView()
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: 520, name: "party-hp", outDir: outDir, minHeight: 200, maxHeight: 480)
    try? phLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/party-hp.txt"),
               atomically: true, encoding: .utf8)
    // Table-log export: the whole log as one text block, oldest-first.
    let exportText = TableLogExport.text(entries: model.tableLog)
    var teLines = ["Table-log export (3.47.0)",
                   "one text block, oldest-first, day labels"]
    let emberRange = exportText.range(of: "Ember Warrens")
    let fightRange = exportText.range(of: "Fight recap")
    teLines.append("head line: \(exportText.hasPrefix("Table log"))")
    teLines.append("both titles present: \(emberRange != nil && fightRange != nil)")
    if let e = emberRange, let f = fightRange {
        teLines.append("oldest-first: \(e.lowerBound < f.lowerBound)")
    }
    if let first = model.tableLog.sorted(by: { $0.createdAt < $1.createdAt }).first {
        teLines.append("day label: \(exportText.contains(JournalStamp.day(first.createdAt)))")
    }
    teLines.append("")
    teLines.append(exportText)
    try? teLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/table-log-export.txt"),
               atomically: true, encoding: .utf8)
    // 3.47.0 hygiene: hand selection back to Bram.
    if let bram = model.characters.first(where: { $0.name == "Bram Oakfel" }) { model.selectedID = bram.id }
    // Library band + party-search jump proofs (3.48.0). Runs at END.
    var lbLines = ["Difficulty band on library rows (3.48.0)",
                   "a saved encounter's lines vs the CURRENT roster's levels - re-derived, never stored"]
    let rosterLevels = model.characters.map(\.level)
    if let den = model.savedEncounters.first(where: { $0.name == "Proof Den" }) {
        let band = model.savedEncounterBand(den)
        let est = EncounterMath.estimate(levels: rosterLevels, lines: den.lines)
        lbLines.append("Proof Den (\(den.summary)) vs roster levels \(rosterLevels): band \(band?.displayName ?? "nil"), adjusted \(est?.adjustedXP ?? -1) XP")
        let weak = EncounterMath.estimate(levels: [1, 1, 1], lines: den.lines)
        lbLines.append("same lines vs a level-1 party: \(weak?.band.displayName ?? "nil") - the band re-derives from the roster")
        lbLines.append("matches the planner's own math: \(band == est?.band)")
    } else {
        lbLines.append("SETUP MISS: Proof Den not in the library")
    }
    renderPNG(
        EncounterLibraryView()
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: 560, name: "library-band", outDir: outDir, minHeight: 120, maxHeight: 400)
    try? lbLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/library-band.txt"),
               atomically: true, encoding: .utf8)
    var pjLines = ["Party search jump-to-entry (3.48.0)",
                   "a party hit selects its character and filters their journal to the entry"]
    let jumpHits = model.journalPartySearch("moonlight")
    let bramID = model.characters.first(where: { $0.name == "Bram Oakfel" })?.id
    if let hit = jumpHits.first {
        pjLines.append("hit '\(hit.entry.title)' by \(hit.characterName): carries Bram's characterID \(hit.characterID == bramID)")
        model.selectedID = hit.characterID
        let jumpFilter = hit.entry.title.isEmpty
            ? (hit.entry.matchingLines("moonlight").first ?? "moonlight")
            : hit.entry.title
        let shown = model.characters.first(where: { $0.id == hit.characterID })?
            .journal.filter { $0.matchesFilter(jumpFilter) } ?? []
        pjLines.append("after jump: selected '\(model.selected?.wrappedValue.name ?? "none")', filter '\(jumpFilter)' -> \(shown.count) entries, first '\(shown.first?.title ?? "none")'")
        let wrenOwn = model.characters.first(where: { $0.name == "Wren Halloway" })?
            .journal.filter { $0.matchesFilter("moonlight") }.count ?? -1
        pjLines.append("the entry stays Bram's: Wren's own journal has \(wrenOwn) matches")
    } else {
        pjLines.append("SETUP MISS: no moonlight hit")
    }
    if let bram = model.characters.first(where: { $0.name == "Bram Oakfel" }) {
        renderPNG(
            JournalBlock(character: .constant(bram), initialFilter: "Moonlight omen", initialPartyScope: false)
                .padding()
                .background(Theme.surface)
                .environmentObject(model),
            width: 560, name: "party-jump", outDir: outDir, minHeight: 120, maxHeight: 400)
    }
    try? pjLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/party-jump.txt"),
               atomically: true, encoding: .utf8)
    // 3.48.0 hygiene: hand selection back to Bram (the jump already lands there).
    if let bram = model.characters.first(where: { $0.name == "Bram Oakfel" }) { model.selectedID = bram.id }
    // Table-log entry edit + encounter share proofs (3.49.0). Runs at END.
    var editLines = ["Table-log entry edit (3.49.0)",
                   "edit in place keeps id and createdAt - a fix costs the entry nothing"]
    if let ember = model.tableLog.first(where: { $0.title == "Ember Warrens" }) {
        let origTitle = ember.title, origText = ember.text
        editLines.append("before: '\(origTitle)' / '\(origText)' (day \(JournalStamp.day(ember.createdAt)))")
        model.editTableLogEntry(id: ember.id, title: "Ember Warrens (corrected)", text: "The party reaches the bridge over the Ember - west side collapsed.")
        let edited = model.tableLog.first(where: { $0.id == ember.id })
        editLines.append("after edit: '\(edited?.title ?? "MISSING")' / '\(edited?.text ?? "MISSING")'")
        editLines.append("id kept: \(edited?.id == ember.id), createdAt kept: \(edited?.createdAt == ember.createdAt)")
        let persisted = model.tableLogStore.load().first(where: { $0.id == ember.id })
        editLines.append("persistence: store reload shows '\(persisted?.title ?? "MISSING")'")
        model.editTableLogEntry(id: ember.id, title: origTitle, text: origText)
        let restored = model.tableLog.first(where: { $0.id == ember.id })
        editLines.append("edited back: '\(restored?.title ?? "MISSING")' restored \(restored?.title == origTitle && restored?.text == origText)")
        let blank = model.tableLog.count
        model.editTableLogEntry(id: ember.id, title: " ", text: " ")
        editLines.append("blank+blank is a no-op: \(model.tableLog.count == blank && model.tableLog.first(where: { $0.id == ember.id })?.title == origTitle)")
    } else {
        editLines.append("SETUP MISS: Ember Warrens entry not found")
    }
    try? editLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/table-log-edit.txt"),
               atomically: true, encoding: .utf8)
    var esLines = ["Encounter share text (3.49.0)",
                   "one block: name, rows, band vs the current party, tactics note"]
    if let den = model.savedEncounters.first(where: { $0.name == "Proof Den" }) {
        let band = model.savedEncounterBand(den)
        let share = den.shareText(band: band)
        esLines.append("name present: \(share.hasPrefix("Proof Den"))")
        esLines.append("rows present: \(share.contains(den.summary))")
        esLines.append("band line matches the row band: \(share.contains("\(band?.displayName ?? "?") vs the current party"))")
        esLines.append("note present: \(share.contains("note: river is difficult terrain"))")
        esLines.append("")
        esLines.append(share)
    } else {
        esLines.append("SETUP MISS: Proof Den not in the library")
    }
    renderPNG(
        EncounterLibraryView()
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: 560, name: "library-share", outDir: outDir, minHeight: 120, maxHeight: 400)
    try? esLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/encounter-share.txt"),
               atomically: true, encoding: .utf8)
    // Library rename + duplicate proofs (3.50.0). Runs at END.
    var lrLines = ["Library rename (3.50.0)",
                   "rename in place fixes a typo'd save - identity, rows and note kept"]
    if let den = model.savedEncounters.first(where: { $0.name == "Proof Den" }) {
        model.renameSavedEncounter(id: den.id, name: "Proof Den (west)")
        let rn = model.savedEncounters.first(where: { $0.id == den.id })
        lrLines.append("renamed: '\(rn?.name ?? "MISSING")', id kept \(rn?.id == den.id)")
        lrLines.append("rows kept: \(rn?.lines == den.lines), note kept: \(rn?.notes == den.notes)")
        let rnPersist = model.encounterLibraryStore.load().first(where: { $0.id == den.id })
        lrLines.append("persistence: store reload shows '\(rnPersist?.name ?? "MISSING")'")
        model.renameSavedEncounter(id: den.id, name: "   ")
        lrLines.append("blank rename is a no-op: \(model.savedEncounters.first(where: { $0.id == den.id })?.name == "Proof Den (west)")")
        model.renameSavedEncounter(id: den.id, name: "Proof Den")
        lrLines.append("renamed back: '\(model.savedEncounters.first(where: { $0.id == den.id })?.name ?? "MISSING")'")
    } else {
        lrLines.append("SETUP MISS: Proof Den not in the library")
    }
    if let den = model.savedEncounters.first(where: { $0.name == "Proof Den" }) {
        renderPNG(
            EncounterLibraryView(initialRenameID: den.id)
                .padding()
                .background(Theme.surface)
                .environmentObject(model),
            width: 560, name: "library-rename", outDir: outDir, minHeight: 120, maxHeight: 400)
    }
    try? lrLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/library-rename.txt"),
               atomically: true, encoding: .utf8)
    var dupLines = ["Library duplicate (3.50.0)",
                    "the copy carries rows and the tactics note under a fresh identity - the start of a variant"]
    if let den = model.savedEncounters.first(where: { $0.name == "Proof Den" }) {
        let libCount = model.savedEncounters.count
        let dupAID = model.duplicateSavedEncounter(id: den.id)
        let dupA = model.savedEncounters.first(where: { $0.id == dupAID })
        dupLines.append("copy: '\(dupA?.name ?? "MISSING")', new identity \(dupAID != nil && dupAID != den.id)")
        dupLines.append("rows carried: \(dupA?.lines == den.lines), note carried: \(dupA?.notes == den.notes && dupA?.notes.isEmpty == false)")
        dupLines.append("original untouched: \(model.savedEncounters.first(where: { $0.id == den.id })?.name == "Proof Den")")
        let dupPersist = model.encounterLibraryStore.load()
        dupLines.append("persistence: store reload has \(dupPersist.count) encounters (was \(libCount)), copy present \(dupPersist.contains(where: { $0.id == dupAID }))")
        let dupBID = model.duplicateSavedEncounter(id: den.id)
        dupLines.append("second copy dedupes the name: '\(model.savedEncounters.first(where: { $0.id == dupBID })?.name ?? "MISSING")'")
        if let dupBID {
            model.renameSavedEncounter(id: dupBID, name: "Proof Den copy")
            let dupBName = model.savedEncounters.first(where: { $0.id == dupBID })?.name
            dupLines.append("rename onto a taken name is rejected: still '\(dupBName ?? "MISSING")'")
        }
        renderPNG(
            EncounterLibraryView()
                .padding()
                .background(Theme.surface)
                .environmentObject(model),
            width: 560, name: "library-duplicate", outDir: outDir, minHeight: 120, maxHeight: 400)
        model.savedEncounters.removeAll { $0.id == dupAID || $0.id == dupBID }
        model.encounterLibraryStore.save(model.savedEncounters)
        dupLines.append("hygiene: copies removed, library back to \(model.savedEncounters.count) encounter(s)")
    } else {
        dupLines.append("SETUP MISS: Proof Den not in the library")
    }
    try? dupLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/library-duplicate.txt"),
               atomically: true, encoding: .utf8)
    // Party-condition apply proofs (3.51.0). Runs at END.
    var pcLines = ["Party-condition apply (3.51.0)",
                   "one condition to the whole roster - never stacks, rounds refresh, untimed keeps running clocks"]
    var pcOrig: [UUID: (conditions: Set<Condition>, durations: [String: Int])] = [:]
    for c in model.characters { pcOrig[c.id] = (c.conditions, c.conditionDurations) }
    // setup: construct the "already has it" case - Wren Prone with a
    // 2-round clock (earlier blocks' initiative wraps can tick a fixture
    // Prone off, so set the condition explicitly)
    if let wren = model.characters.first(where: { $0.name == "Wren Halloway" }) {
        model.selectedID = wren.id
        var w = wren
        w.conditions.insert(.prone)
        w.conditionDurations[Condition.prone.rawValue] = 2
        model.selected?.wrappedValue = w
    }
    let pcOutcome = model.applyPartyCondition(.prone, rounds: 3)
    pcLines.append("apply Prone (3 rounds) to the roster: new [\(pcOutcome.applied.joined(separator: ", "))], refreshed [\(pcOutcome.refreshed.joined(separator: ", "))]")
    let pcWren = model.characters.first(where: { $0.name == "Wren Halloway" })
    pcLines.append("Wren already had it: in refreshed \(pcOutcome.refreshed.contains("Wren Halloway")), not in new \(!pcOutcome.applied.contains("Wren Halloway")), clock refreshed 2 -> \(pcWren?.conditionDurations[Condition.prone.rawValue] ?? -1)")
    let pcBram = model.characters.first(where: { $0.name == "Bram Oakfel" })
    pcLines.append("Bram gained Prone with 3 rounds: \(pcBram?.conditions.contains(.prone) == true && pcBram?.conditionDurations[Condition.prone.rawValue] == 3)")
    do {
        let pcReload = try model.store.load(id: pcBram?.id ?? UUID())
        pcLines.append("persistence: store reload shows Bram Prone \(pcReload.conditions.contains(.prone))")
    } catch {
        pcLines.append("persistence: store reload threw \(error)")
    }
    let pcLogCount = model.tableLog.filter { $0.title == "Party condition" }.count
    let pcLog = model.tableLog.last(where: { $0.title == "Party condition" })?.text ?? "MISSING"
    pcLines.append("table log entry: '\(pcLog)'")
    // untimed re-apply: nothing changes, no clock dies, no new log entry
    let pcOutcome2 = model.applyPartyCondition(.prone, rounds: nil)
    let pcWren2 = model.characters.first(where: { $0.name == "Wren Halloway" })
    pcLines.append("untimed re-apply: touched \(pcOutcome2.applied.count + pcOutcome2.refreshed.count) characters, Wren's clock still \(pcWren2?.conditionDurations[Condition.prone.rawValue] ?? -1), no new log entry \(model.tableLog.filter { $0.title == "Party condition" }.count == pcLogCount)")
    // undo/redo on one character
    if let bram = model.characters.first(where: { $0.name == "Bram Oakfel" }) {
        model.selectedID = bram.id
        model.undo()
        let pcBramAfter = model.characters.first(where: { $0.id == bram.id })
        pcLines.append("undo on Bram: Prone gone \(pcBramAfter?.conditions.contains(.prone) == false)")
        model.redo()
        pcLines.append("redo: Prone back \(model.characters.first(where: { $0.id == bram.id })?.conditions.contains(.prone) == true)")
    }
    // hygiene: restore every character's original conditions + clocks, drop test log entries
    for idx in model.characters.indices {
        let c = model.characters[idx]
        if let orig = pcOrig[c.id], c.conditions != orig.conditions || c.conditionDurations != orig.durations {
            var restored = c
            restored.conditions = orig.conditions
            restored.conditionDurations = orig.durations
            model.characters[idx] = restored
            try? model.store.save(restored)
        }
    }
    model.tableLog.removeAll { $0.title == "Party condition" }
    model.tableLogStore.save(model.tableLog)
    if let bram = model.characters.first(where: { $0.name == "Bram Oakfel" }) { model.selectedID = bram.id }
    pcLines.append("hygiene: roster conditions, clocks, log and selection restored")
    renderPNG(
        GroupCheckSectionView()
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: 560, name: "party-condition", outDir: outDir, minHeight: 120, maxHeight: 500)
    try? pcLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/party-condition.txt"),
               atomically: true, encoding: .utf8)
    // Party condition-remove proofs (3.52.0). Runs at END.
    var rmLines = ["Party condition-remove (3.52.0)",
                   "remove from the whole roster - clears the condition and its clock; undo restores both"]
    var rmOrig: [UUID: (conditions: Set<Condition>, durations: [String: Int])] = [:]
    for c in model.characters { rmOrig[c.id] = (c.conditions, c.conditionDurations) }
    // setup: everyone Prone with 3-round clocks via the 3.51.0 apply
    _ = model.applyPartyCondition(.prone, rounds: 3)
    let rmSetup = model.characters.allSatisfy { $0.conditions.contains(.prone) && $0.conditionDurations[Condition.prone.rawValue] == 3 }
    rmLines.append("setup: whole roster Prone (3 rounds) \(rmSetup)")
    let rmOutcome = model.removePartyCondition(.prone)
    rmLines.append("remove Prone from the roster: cleared [\(rmOutcome.joined(separator: ", "))]")
    rmLines.append("condition gone from all: \(model.characters.allSatisfy { !$0.conditions.contains(.prone) })")
    rmLines.append("no ghost clocks: \(model.characters.allSatisfy { $0.conditionDurations[Condition.prone.rawValue] == nil })")
    let rmBram = model.characters.first(where: { $0.name == "Bram Oakfel" })
    do {
        let rmReload = try model.store.load(id: rmBram?.id ?? UUID())
        rmLines.append("persistence: store reload shows Bram without Prone \(!rmReload.conditions.contains(.prone))")
    } catch {
        rmLines.append("persistence: store reload threw \(error)")
    }
    let rmLog = model.tableLog.last(where: { $0.title == "Party condition" })?.text ?? "MISSING"
    rmLines.append("table log entry: '\(rmLog)'")
    // undo restores condition AND clock - the stack snapshots the whole character
    if let bram = model.characters.first(where: { $0.name == "Bram Oakfel" }) {
        model.selectedID = bram.id
        model.undo()
        let rmBramAfter = model.characters.first(where: { $0.id == bram.id })
        rmLines.append("undo on Bram: Prone back \(rmBramAfter?.conditions.contains(.prone) == true), clock back at \(rmBramAfter?.conditionDurations[Condition.prone.rawValue] ?? -1)")
        model.redo()
    }
    // removing what nobody has is a silent no-op
    let rmLogCount = model.tableLog.filter { $0.title == "Party condition" }.count
    let rmOutcome2 = model.removePartyCondition(.prone)
    rmLines.append("second remove: touched \(rmOutcome2.count) characters, no new log entry \(model.tableLog.filter { $0.title == "Party condition" }.count == rmLogCount)")
    // hygiene: restore every character's original conditions + clocks, drop test log entries
    for idx in model.characters.indices {
        let c = model.characters[idx]
        if let orig = rmOrig[c.id], c.conditions != orig.conditions || c.conditionDurations != orig.durations {
            var restored = c
            restored.conditions = orig.conditions
            restored.conditionDurations = orig.durations
            model.characters[idx] = restored
            try? model.store.save(restored)
        }
    }
    model.tableLog.removeAll { $0.title == "Party condition" }
    model.tableLogStore.save(model.tableLog)
    if let bram = model.characters.first(where: { $0.name == "Bram Oakfel" }) { model.selectedID = bram.id }
    rmLines.append("hygiene: roster conditions, clocks, log and selection restored")
    renderPNG(
        GroupCheckSectionView()
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: 560, name: "party-condition-remove", outDir: outDir, minHeight: 120, maxHeight: 500)
    try? rmLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/party-condition-remove.txt"),
               atomically: true, encoding: .utf8)
    // Party condition-summary proofs (3.53.0). Runs at END.
    var sumLines = ["Party condition summary (3.53.0)",
                    "who's holding what plus clocks - one read-only glance line"]
    var sumOrig: [UUID: (conditions: Set<Condition>, durations: [String: Int])] = [:]
    for c in model.characters { sumOrig[c.id] = (c.conditions, c.conditionDurations) }
    // fixture control (3.60.0 f3): SampleContent seeds a custom on Wren and
    // customs now render on the summary line - strip every roster custom (and
    // any custom duration/note key) so this block's line assertions keep their
    // pre-3.60.0 contract. Hygiene below restores them.
    var sumCustomOrig: [UUID: (customs: [CustomCondition], durations: [String: Int], notes: [String: String])] = [:]
    let sumBuiltInKeys = Set(Condition.allCases.map(\.rawValue))
    for idx in model.characters.indices {
        let c = model.characters[idx]
        sumCustomOrig[c.id] = (c.customConditions, c.conditionDurations, c.conditionNotes)
        var stripped = c
        stripped.customConditions = []
        stripped.conditionDurations = c.conditionDurations.filter { sumBuiltInKeys.contains($0.key) }
        stripped.conditionNotes = c.conditionNotes.filter { sumBuiltInKeys.contains($0.key) }
        if stripped != c {
            model.characters[idx] = stripped
            try? model.store.save(stripped)
        }
    }
    sumLines.append("fixture control: roster customs stripped (the sample seeds one on Wren) \(model.characters.allSatisfy { $0.customConditions.isEmpty })")
    // setup: Prone 3 on everyone via the 3.51.0 party apply; Wren also
    // holds Poisoned (untimed) so the line shows a clock next to no-clock
    _ = model.applyPartyCondition(.prone, rounds: 3)
    if let idx = model.characters.firstIndex(where: { $0.name == "Wren Halloway" }) {
        var w = model.characters[idx]
        w.conditions.insert(.poisoned)
        model.characters[idx] = w
        try? model.store.save(w)
    }
    let sumExpect = "Wren Halloway: Poisoned, Prone 3r \u{00B7} Bram Oakfel: Prone 3r \u{00B7} Sera Vint: Prone 3r"
    sumLines.append("summary: '\(partyConditionSummary(model.characters))'")
    sumLines.append("matches expected exact string \(partyConditionSummary(model.characters) == sumExpect)")
    // a non-holder is not named: clear Sera, re-read the line
    if let idx = model.characters.firstIndex(where: { $0.name == "Sera Vint" }) {
        var s = model.characters[idx]
        s.conditions.remove(.prone)
        s.conditionDurations.removeValue(forKey: Condition.prone.rawValue)
        model.characters[idx] = s
    }
    sumLines.append("non-holder Sera not named \(!partyConditionSummary(model.characters).contains("Sera"))")
    sumLines.append("holders Wren and Bram still named \(partyConditionSummary(model.characters).contains("Wren") && partyConditionSummary(model.characters).contains("Bram"))")
    _ = model.applyPartyCondition(.prone, rounds: 3) // Sera back in for the render
    renderPNG(
        GroupCheckSectionView()
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: 560, name: "party-condition-summary", outDir: outDir, minHeight: 120, maxHeight: 500)
    // negative: nobody holds anything -> empty line, row hides
    for idx in model.characters.indices {
        var c = model.characters[idx]
        c.conditions = []
        c.conditionDurations = [:]
        model.characters[idx] = c
    }
    sumLines.append("empty when nobody holds anything \(partyConditionSummary(model.characters).isEmpty)")
    // hygiene: restore every character's original conditions + clocks, drop test log entries
    for idx in model.characters.indices {
        let c = model.characters[idx]
        if let orig = sumOrig[c.id], c.conditions != orig.conditions || c.conditionDurations != orig.durations {
            var restored = c
            restored.conditions = orig.conditions
            restored.conditionDurations = orig.durations
            model.characters[idx] = restored
            try? model.store.save(restored)
        }
    }
    model.tableLog.removeAll { $0.title == "Party condition" }
    // restore the stripped roster customs (and any custom duration/note keys)
    for idx in model.characters.indices {
        let c = model.characters[idx]
        if let corig = sumCustomOrig[c.id], c.customConditions != corig.customs || c.conditionDurations != corig.durations || c.conditionNotes != corig.notes {
            var restored = c
            restored.customConditions = corig.customs
            restored.conditionDurations = corig.durations
            restored.conditionNotes = corig.notes
            model.characters[idx] = restored
            try? model.store.save(restored)
        }
    }
    model.tableLogStore.save(model.tableLog)
    if let bram = model.characters.first(where: { $0.name == "Bram Oakfel" }) { model.selectedID = bram.id }
    sumLines.append("hygiene: roster conditions, clocks, notes, customs, log and selection restored")
    try? sumLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/party-condition-summary.txt"),
               atomically: true, encoding: .utf8)
    // Party summary click-through proofs (3.54.0). Runs at END.
    var tapLines = ["Party summary click-through (3.54.0)",
                    "tap a name in the summary line, land on that character's sheet"]
    var tapOrig: [UUID: (conditions: Set<Condition>, durations: [String: Int])] = [:]
    for c in model.characters { tapOrig[c.id] = (c.conditions, c.conditionDurations) }
    // fixture control (3.60.0 f3): SampleContent seeds a custom on Wren and
    // customs now render on the summary line - strip every roster custom (and
    // any custom duration/note key) so this block's line assertions keep their
    // pre-3.60.0 contract. Hygiene below restores them.
    var tapCustomOrig: [UUID: (customs: [CustomCondition], durations: [String: Int], notes: [String: String])] = [:]
    let tapBuiltInKeys = Set(Condition.allCases.map(\.rawValue))
    for idx in model.characters.indices {
        let c = model.characters[idx]
        tapCustomOrig[c.id] = (c.customConditions, c.conditionDurations, c.conditionNotes)
        var stripped = c
        stripped.customConditions = []
        stripped.conditionDurations = c.conditionDurations.filter { tapBuiltInKeys.contains($0.key) }
        stripped.conditionNotes = c.conditionNotes.filter { tapBuiltInKeys.contains($0.key) }
        if stripped != c {
            model.characters[idx] = stripped
            try? model.store.save(stripped)
        }
    }
    tapLines.append("fixture control: roster customs stripped (the sample seeds one on Wren) \(model.characters.allSatisfy { $0.customConditions.isEmpty })")
    // setup: Prone 3 on everyone; Wren also Poisoned (untimed)
    _ = model.applyPartyCondition(.prone, rounds: 3)
    if let idx = model.characters.firstIndex(where: { $0.name == "Wren Halloway" }) {
        var w = model.characters[idx]
        w.conditions.insert(.poisoned)
        model.characters[idx] = w
        try? model.store.save(w)
    }
    let tapItems = partyConditionSummaryItems(model.characters)
    tapLines.append("segments: \(tapItems.count) holders")
    tapLines.append("first segment: '\(tapItems.first?.text ?? "MISSING")'")
    tapLines.append("segment ids match holders \(tapItems.count == 3 && tapItems[0].characterID == model.characters[0].id && tapItems[1].characterID == model.characters[1].id && tapItems[2].characterID == model.characters[2].id)")
    // the 3.53.0 string still derives from the same segments
    tapLines.append("summary string unchanged \(partyConditionSummary(model.characters) == "Wren Halloway: Poisoned, Prone 3r \u{00B7} Bram Oakfel: Prone 3r \u{00B7} Sera Vint: Prone 3r")")
    // the tap: from the Dice tab (2), reveal Sera -> selection moves, tab flips to Sheet (0)
    let tapTab = UserDefaults.standard.integer(forKey: "architer.detailTab")
    UserDefaults.standard.set(2, forKey: "architer.detailTab")
    let tapSera = model.characters.first(where: { $0.name == "Sera Vint" })
    model.revealOnSheet(tapSera?.id ?? UUID())
    tapLines.append("tap Sera: selection landed \(model.selectedID == tapSera?.id), tab flipped to sheet \(UserDefaults.standard.integer(forKey: "architer.detailTab") == 0)")
    // unknown id is a silent no-op
    let tapBefore = model.selectedID
    model.revealOnSheet(UUID())
    tapLines.append("unknown id ignored \(model.selectedID == tapBefore)")
    renderPNG(
        GroupCheckSectionView()
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: 560, name: "party-clickthrough", outDir: outDir, minHeight: 120, maxHeight: 500)
    // hygiene: tab value, conditions + clocks, log entries, selection
    UserDefaults.standard.set(tapTab, forKey: "architer.detailTab")
    for idx in model.characters.indices {
        let c = model.characters[idx]
        if let orig = tapOrig[c.id], c.conditions != orig.conditions || c.conditionDurations != orig.durations {
            var restored = c
            restored.conditions = orig.conditions
            restored.conditionDurations = orig.durations
            model.characters[idx] = restored
            try? model.store.save(restored)
        }
    }
    model.tableLog.removeAll { $0.title == "Party condition" }
    // restore the stripped roster customs (and any custom duration/note keys)
    for idx in model.characters.indices {
        let c = model.characters[idx]
        if let corig = tapCustomOrig[c.id], c.customConditions != corig.customs || c.conditionDurations != corig.durations || c.conditionNotes != corig.notes {
            var restored = c
            restored.customConditions = corig.customs
            restored.conditionDurations = corig.durations
            restored.conditionNotes = corig.notes
            model.characters[idx] = restored
            try? model.store.save(restored)
        }
    }
    model.tableLogStore.save(model.tableLog)
    if let bram = model.characters.first(where: { $0.name == "Bram Oakfel" }) { model.selectedID = bram.id }
    tapLines.append("hygiene: tab, roster, customs, log and selection restored")
    try? tapLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/party-clickthrough.txt"),
               atomically: true, encoding: .utf8)
    // Party condition-remove targeting proofs (3.55.0). Runs at END.
    var subLines = ["Party condition-remove targeting (3.55.0)",
                    "remove a condition from a chosen subset - the rest of the roster keeps it"]
    var subOrig: [UUID: (conditions: Set<Condition>, durations: [String: Int])] = [:]
    for c in model.characters { subOrig[c.id] = (c.conditions, c.conditionDurations) }
    // setup: everyone Prone with 3-round clocks
    _ = model.applyPartyCondition(.prone, rounds: 3)
    let subSetup = model.characters.allSatisfy { $0.conditions.contains(.prone) && $0.conditionDurations[Condition.prone.rawValue] == 3 }
    subLines.append("setup: whole roster Prone (3 rounds) \(subSetup)")
    // remove from Wren + Sera only
    let subWren = model.characters.first(where: { $0.name == "Wren Halloway" })
    let subSera = model.characters.first(where: { $0.name == "Sera Vint" })
    let subBram = model.characters.first(where: { $0.name == "Bram Oakfel" })
    let subOutcome = model.removePartyCondition(.prone, from: Set([subWren?.id, subSera?.id].compactMap { $0 }))
    subLines.append("remove from {Wren, Sera}: cleared [\(subOutcome.joined(separator: ", "))]")
    let subWrenAfter = model.characters.first(where: { $0.name == "Wren Halloway" })
    let subSeraAfter = model.characters.first(where: { $0.name == "Sera Vint" })
    let subBramAfter = model.characters.first(where: { $0.name == "Bram Oakfel" })
    subLines.append("subset cleared incl. clocks \(subWrenAfter?.conditions.contains(.prone) == false && subSeraAfter?.conditions.contains(.prone) == false && subWrenAfter?.conditionDurations[Condition.prone.rawValue] == nil && subSeraAfter?.conditionDurations[Condition.prone.rawValue] == nil)")
    subLines.append("Bram untouched: still Prone with clock at 3 \(subBramAfter?.conditions.contains(.prone) == true && subBramAfter?.conditionDurations[Condition.prone.rawValue] == 3)")
    do {
        let subReload = try model.store.load(id: subBram?.id ?? UUID())
        subLines.append("persistence: store reload shows Bram still Prone \(subReload.conditions.contains(.prone))")
    } catch {
        subLines.append("persistence: store reload threw \(error)")
    }
    let subLog = model.tableLog.last(where: { $0.title == "Party condition" })?.text ?? "MISSING"
    subLines.append("table log entry: '\(subLog)'")
    // undo on Wren restores condition AND clock
    if let wren = model.characters.first(where: { $0.name == "Wren Halloway" }) {
        model.selectedID = wren.id
        model.undo()
        let wrenAfter = model.characters.first(where: { $0.id == wren.id })
        subLines.append("undo on Wren: Prone back \(wrenAfter?.conditions.contains(.prone) == true), clock back at \(wrenAfter?.conditionDurations[Condition.prone.rawValue] ?? -1)")
        model.redo()
    }
    // empty subset is a silent no-op
    let subLogCount = model.tableLog.filter { $0.title == "Party condition" }.count
    let subEmpty = model.removePartyCondition(.prone, from: [])
    subLines.append("empty subset: touched \(subEmpty.count), no new log entry \(model.tableLog.filter { $0.title == "Party condition" }.count == subLogCount)")
    renderPNG(
        GroupCheckSectionView()
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: 560, name: "party-remove-subset", outDir: outDir, minHeight: 120, maxHeight: 500)
    // hygiene: restore every character's original conditions + clocks, drop test log entries
    for idx in model.characters.indices {
        let c = model.characters[idx]
        if let orig = subOrig[c.id], c.conditions != orig.conditions || c.conditionDurations != orig.durations {
            var restored = c
            restored.conditions = orig.conditions
            restored.conditionDurations = orig.durations
            model.characters[idx] = restored
            try? model.store.save(restored)
        }
    }
    model.tableLog.removeAll { $0.title == "Party condition" }
    model.tableLogStore.save(model.tableLog)
    if let bram = model.characters.first(where: { $0.name == "Bram Oakfel" }) { model.selectedID = bram.id }
    subLines.append("hygiene: roster conditions, clocks, log and selection restored")
    try? subLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/party-remove-subset.txt"),
               atomically: true, encoding: .utf8)
    // Party apply-to-subset proofs (3.56.0). Runs at END.
    var apsLines = ["Party condition apply-to-subset (3.56.0)",
                    "grant a condition to a chosen subset - the rest of the roster is untouched"]
    var apsOrig: [UUID: (conditions: Set<Condition>, durations: [String: Int])] = [:]
    for c in model.characters { apsOrig[c.id] = (c.conditions, c.conditionDurations) }
    let apsWren = model.characters.first(where: { $0.name == "Wren Halloway" })
    let apsBram = model.characters.first(where: { $0.name == "Bram Oakfel" })
    let apsSera = model.characters.first(where: { $0.name == "Sera Vint" })
    // apply Frightened 2 to {Wren, Bram} only
    let apsOutcome = model.applyPartyCondition(.frightened, rounds: 2, from: Set([apsWren?.id, apsBram?.id].compactMap { $0 }))
    apsLines.append("apply to {Wren, Bram}: applied [\(apsOutcome.applied.joined(separator: ", "))], refreshed [\(apsOutcome.refreshed.joined(separator: ", "))]")
    let apsWrenAfter = model.characters.first(where: { $0.name == "Wren Halloway" })
    let apsBramAfter = model.characters.first(where: { $0.name == "Bram Oakfel" })
    let apsSeraAfter = model.characters.first(where: { $0.name == "Sera Vint" })
    apsLines.append("both gained Frightened with clocks at 2 \(apsWrenAfter?.conditionDurations[Condition.frightened.rawValue] == 2 && apsBramAfter?.conditionDurations[Condition.frightened.rawValue] == 2)")
    apsLines.append("Sera untouched \(apsSeraAfter?.conditions.contains(.frightened) == false && apsSeraAfter?.conditionDurations[Condition.frightened.rawValue] == nil)")
    do {
        let apsReload = try model.store.load(id: apsSera?.id ?? UUID())
        apsLines.append("persistence: store reload shows Sera without Frightened \(!apsReload.conditions.contains(.frightened))")
    } catch {
        apsLines.append("persistence: store reload threw \(error)")
    }
    let apsLog = model.tableLog.last(where: { $0.title == "Party condition" })?.text ?? "MISSING"
    apsLines.append("table log entry: '\(apsLog)'")
    // blank-rounds re-apply to a holder is a full no-op (never stacks, no refresh without rounds)
    let apsLogCount = model.tableLog.filter { $0.title == "Party condition" }.count
    let apsNoop = model.applyPartyCondition(.frightened, rounds: nil, from: Set([apsWren?.id].compactMap { $0 }))
    let apsWrenNoop = model.characters.first(where: { $0.name == "Wren Halloway" })
    apsLines.append("blank re-apply to Wren: applied \(apsNoop.applied.count) refreshed \(apsNoop.refreshed.count), clock still 2 \(apsWrenNoop?.conditionDurations[Condition.frightened.rawValue] == 2), no new log \(model.tableLog.filter { $0.title == "Party condition" }.count == apsLogCount)")
    // rounds re-apply to a holder refreshes the clock
    let apsRefresh = model.applyPartyCondition(.frightened, rounds: 5, from: Set([apsWren?.id].compactMap { $0 }))
    let apsWrenRef = model.characters.first(where: { $0.name == "Wren Halloway" })
    apsLines.append("5-round re-apply to Wren: refreshed [\(apsRefresh.refreshed.joined(separator: ", "))], clock now \(apsWrenRef?.conditionDurations[Condition.frightened.rawValue] ?? -1)")
    // undo on Bram removes condition AND clock
    if let bram = model.characters.first(where: { $0.name == "Bram Oakfel" }) {
        model.selectedID = bram.id
        model.undo()
        let bramAfter = model.characters.first(where: { $0.id == bram.id })
        apsLines.append("undo on Bram: Frightened gone \(bramAfter?.conditions.contains(.frightened) == false), clock gone \(bramAfter?.conditionDurations[Condition.frightened.rawValue] == nil)")
        model.redo()
    }
    // empty subset is a silent no-op
    let apsLogCount2 = model.tableLog.filter { $0.title == "Party condition" }.count
    let apsEmpty = model.applyPartyCondition(.frightened, rounds: 2, from: [])
    apsLines.append("empty subset: applied \(apsEmpty.applied.count) refreshed \(apsEmpty.refreshed.count), no new log \(model.tableLog.filter { $0.title == "Party condition" }.count == apsLogCount2)")
    renderPNG(
        GroupCheckSectionView()
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: 560, name: "party-apply-subset", outDir: outDir, minHeight: 120, maxHeight: 500)
    // hygiene: restore every character's original conditions + clocks, drop test log entries
    for idx in model.characters.indices {
        let c = model.characters[idx]
        if let orig = apsOrig[c.id], c.conditions != orig.conditions || c.conditionDurations != orig.durations {
            var restored = c
            restored.conditions = orig.conditions
            restored.conditionDurations = orig.durations
            model.characters[idx] = restored
            try? model.store.save(restored)
        }
    }
    model.tableLog.removeAll { $0.title == "Party condition" }
    model.tableLogStore.save(model.tableLog)
    if let bram = model.characters.first(where: { $0.name == "Bram Oakfel" }) { model.selectedID = bram.id }
    apsLines.append("hygiene: roster conditions, clocks, log and selection restored")
    try? apsLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/party-apply-subset.txt"),
               atomically: true, encoding: .utf8)
    // Summary-row expiry highlight proofs (3.57.0). Runs at END.
    var expLines = ["Summary-row expiry highlight (3.57.0)",
                    "a clock at 1 - one tick from removal - reads in accent on the summary line"]
    var expOrig: [UUID: (conditions: Set<Condition>, durations: [String: Int])] = [:]
    for c in model.characters { expOrig[c.id] = (c.conditions, c.conditionDurations) }
    // setup: Wren Prone 1r (ending) + her fixture Poisoned (untimed);
    // Bram Prone 3r (not ending); Sera Prone 2r (boundary - not ending)
    _ = model.applyPartyCondition(.prone, rounds: 1, from: Set([model.characters.first(where: { $0.name == "Wren Halloway" })?.id].compactMap { $0 }))
    _ = model.applyPartyCondition(.prone, rounds: 3, from: Set([model.characters.first(where: { $0.name == "Bram Oakfel" })?.id].compactMap { $0 }))
    _ = model.applyPartyCondition(.prone, rounds: 2, from: Set([model.characters.first(where: { $0.name == "Sera Vint" })?.id].compactMap { $0 }))
    let expItems = partyConditionSummaryItems(model.characters)
    let expWren = expItems.first(where: { $0.name == "Wren Halloway" })
    let expBram = expItems.first(where: { $0.name == "Bram Oakfel" })
    let expSera = expItems.first(where: { $0.name == "Sera Vint" })
    expLines.append("summary: '\(partyConditionSummary(model.characters))'")
    expLines.append("Wren's Prone 1r marked expiring \(expWren?.parts.first(where: { $0.label == "Prone 1r" })?.expiring == true)")
    expLines.append("Wren's untimed Poisoned not expiring \(expWren?.parts.first(where: { $0.label == "Poisoned" })?.expiring == false)")
    expLines.append("Bram's Prone 3r not expiring \(expBram?.parts.first(where: { $0.label == "Prone 3r" })?.expiring == false)")
    expLines.append("boundary: Sera's Prone 2r not expiring \(expSera?.parts.first(where: { $0.label == "Prone 2r" })?.expiring == false)")
    // the 3.53.0 string contract survives: text still derives byte-identical
    let expJoined = expItems.map(\.text).joined(separator: " \u{00B7} ")
    expLines.append("text byte-identical to the 3.53.0 string \(partyConditionSummary(model.characters) == expJoined)")
    renderPNG(
        GroupCheckSectionView()
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: 560, name: "party-expiry-highlight", outDir: outDir, minHeight: 120, maxHeight: 500)
    // hygiene: restore every character's original conditions + clocks, drop test log entries
    for idx in model.characters.indices {
        let c = model.characters[idx]
        if let orig = expOrig[c.id], c.conditions != orig.conditions || c.conditionDurations != orig.durations {
            var restored = c
            restored.conditions = orig.conditions
            restored.conditionDurations = orig.durations
            model.characters[idx] = restored
            try? model.store.save(restored)
        }
    }
    model.tableLog.removeAll { $0.title == "Party condition" }
    model.tableLogStore.save(model.tableLog)
    if let bram = model.characters.first(where: { $0.name == "Bram Oakfel" }) { model.selectedID = bram.id }
    expLines.append("hygiene: roster conditions, clocks, log and selection restored")
    try? expLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/party-expiry-highlight.txt"),
               atomically: true, encoding: .utf8)
    // Condition notes proofs (3.58.0). Runs at END.
    var pcnLines = ["Condition notes on the summary line (3.58.0)",
                    "the 'why they have it' - stored input, the line stays derived, the note dies with the condition"]
    var pcnOrig: [UUID: (conditions: Set<Condition>, durations: [String: Int], notes: [String: String])] = [:]
    for c in model.characters { pcnOrig[c.id] = (c.conditions, c.conditionDurations, c.conditionNotes) }
    // fixture control (3.60.0 f3): SampleContent seeds a custom on Wren and
    // customs now render on the summary line - strip every roster custom (and
    // any custom duration/note key) so this block's line assertions keep their
    // pre-3.60.0 contract. Hygiene below restores them.
    var pcnCustomOrig: [UUID: (customs: [CustomCondition], durations: [String: Int], notes: [String: String])] = [:]
    let pcnBuiltInKeys = Set(Condition.allCases.map(\.rawValue))
    for idx in model.characters.indices {
        let c = model.characters[idx]
        pcnCustomOrig[c.id] = (c.customConditions, c.conditionDurations, c.conditionNotes)
        var stripped = c
        stripped.customConditions = []
        stripped.conditionDurations = c.conditionDurations.filter { pcnBuiltInKeys.contains($0.key) }
        stripped.conditionNotes = c.conditionNotes.filter { pcnBuiltInKeys.contains($0.key) }
        if stripped != c {
            model.characters[idx] = stripped
            try? model.store.save(stripped)
        }
    }
    pcnLines.append("fixture control: roster customs stripped (the sample seeds one on Wren) \(model.characters.allSatisfy { $0.customConditions.isEmpty })")
    // the note-free roster still reads byte-identical to the 3.53.0 string shape
    pcnLines.append("note-free summary: '\(partyConditionSummary(model.characters))'")
    pcnLines.append("note-free roster byte-identical to the 3.53.0 shape \(partyConditionSummary(model.characters) == "Wren Halloway: Poisoned")")
    let pcnWrenID = model.characters.first(where: { $0.name == "Wren Halloway" })?.id
    let pcnBramID = model.characters.first(where: { $0.name == "Bram Oakfel" })?.id
    // setup: Wren Poisoned note "sting" (untimed) + Prone 1r note "shove"; Bram Prone 3r no note
    if let w = pcnWrenID {
        _ = model.applyPartyCondition(.poisoned, rounds: nil, note: "sting", from: [w])
        _ = model.applyPartyCondition(.prone, rounds: 1, note: "shove", from: [w])
    }
    if let b = pcnBramID { _ = model.applyPartyCondition(.prone, rounds: 3, from: [b]) }
    let pcnItems = partyConditionSummaryItems(model.characters)
    let pcnWren = pcnItems.first(where: { $0.name == "Wren Halloway" })
    let pcnBram = pcnItems.first(where: { $0.name == "Bram Oakfel" })
    pcnLines.append("summary: '\(partyConditionSummary(model.characters))'")
    pcnLines.append("summary exact \(partyConditionSummary(model.characters) == "Wren Halloway: Poisoned (sting), Prone 1r (shove) \u{00B7} Bram Oakfel: Prone 3r")")
    let pcnPoison = pcnWren?.parts.first(where: { $0.label == "Poisoned" })
    let pcnProne = pcnWren?.parts.first(where: { $0.label == "Prone 1r" })
    pcnLines.append("Poisoned carries its note \(pcnPoison?.note == "sting"), untimed and not expiring \(pcnPoison?.expiring == false)")
    pcnLines.append("Prone 1r carries its note \(pcnProne?.note == "shove"), expiring still derived \(pcnProne?.expiring == true)")
    pcnLines.append("Bram's note-free Prone 3r: no note \(pcnBram?.parts.first?.note == nil), label unchanged \(pcnBram?.parts.first?.label == "Prone 3r")")
    if let w = pcnWrenID {
        // blank-note re-apply preserves; typed-note re-apply replaces
        let pcnLogCount = model.tableLog.filter { $0.title == "Party condition" }.count
        let pcnNoop = model.applyPartyCondition(.poisoned, rounds: nil, from: [w])
        pcnLines.append("blank-note re-apply: no-op \(pcnNoop.applied.isEmpty && pcnNoop.refreshed.isEmpty), note kept \(model.characters.first(where: { $0.id == w })?.conditionNotes[Condition.poisoned.rawValue] == "sting"), no new log \(model.tableLog.filter { $0.title == "Party condition" }.count == pcnLogCount)")
        _ = model.applyPartyCondition(.poisoned, rounds: nil, note: "bite", from: [w])
        pcnLines.append("typed-note re-apply replaces: note now '\(model.characters.first(where: { $0.id == w })?.conditionNotes[Condition.poisoned.rawValue] ?? "missing")'")
        // cap: a 36-char note stores as 24, trailing trim
        _ = model.applyPartyCondition(.poisoned, rounds: nil, note: "this note is definitely over the cap", from: [w])
        let pcnCapped = model.characters.first(where: { $0.id == w })?.conditionNotes[Condition.poisoned.rawValue]
        pcnLines.append("cap: 36-char note stored as \(pcnCapped?.count ?? -1) chars ('\(pcnCapped ?? "missing")')")
        // persistence: notes round-trip through the store (2 notes on Wren here)
        if let pcnWrenNow = model.characters.first(where: { $0.id == w }), let pcnReload = try? model.store.load(id: w) {
            pcnLines.append("persistence: notes round-trip \(pcnReload.conditionNotes == pcnWrenNow.conditionNotes && pcnReload.conditionNotes.count == 2)")
        }
    }
    renderPNG(
        GroupCheckSectionView()
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: 560, name: "party-condition-notes", outDir: outDir, minHeight: 120, maxHeight: 500)
    if let w = pcnWrenID {
        // removal drops the note with the condition
        _ = model.removePartyCondition(.poisoned, from: [w])
        let pcnWrenAfter = model.characters.first(where: { $0.id == w })
        pcnLines.append("removal: Poisoned gone \(pcnWrenAfter?.conditions.contains(.poisoned) == false), note gone \(pcnWrenAfter?.conditionNotes[Condition.poisoned.rawValue] == nil)")
        // a clock at 0 drops the note too
        if let wIdx = model.characters.firstIndex(where: { $0.id == w }) {
            var pcnTick = model.characters[wIdx]
            _ = pcnTick.tickConditionDurations()
            model.characters[wIdx] = pcnTick
            try? model.store.save(pcnTick)
            pcnLines.append("tick to 0: Prone gone \(pcnTick.conditions.contains(.prone) == false), note gone \(pcnTick.conditionNotes[Condition.prone.rawValue] == nil)")
        }
    }
    // hygiene: restore every character's original conditions + clocks + notes, drop test log entries
    for idx in model.characters.indices {
        let c = model.characters[idx]
        if let orig = pcnOrig[c.id], c.conditions != orig.conditions || c.conditionDurations != orig.durations || c.conditionNotes != orig.notes {
            var restored = c
            restored.conditions = orig.conditions
            restored.conditionDurations = orig.durations
            restored.conditionNotes = orig.notes
            model.characters[idx] = restored
            try? model.store.save(restored)
        }
    }
    model.tableLog.removeAll { $0.title == "Party condition" }
    // restore the stripped roster customs (and any custom duration/note keys)
    for idx in model.characters.indices {
        let c = model.characters[idx]
        if let corig = pcnCustomOrig[c.id], c.customConditions != corig.customs || c.conditionDurations != corig.durations || c.conditionNotes != corig.notes {
            var restored = c
            restored.customConditions = corig.customs
            restored.conditionDurations = corig.durations
            restored.conditionNotes = corig.notes
            model.characters[idx] = restored
            try? model.store.save(restored)
        }
    }
    model.tableLogStore.save(model.tableLog)
    if let bram = model.characters.first(where: { $0.name == "Bram Oakfel" }) { model.selectedID = bram.id }
    pcnLines.append("hygiene: roster conditions, clocks, notes, customs, log and selection restored")
    try? pcnLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/party-condition-notes.txt"),
               atomically: true, encoding: .utf8)
    // Party-note log lines (3.64.0): a note typed in the header apply sheet
    // rides the apply log line, per holder, on subset and Everyone paths.
    // State is set explicitly and restored at the end of the block.
    var pnlLines = ["Party-note log lines (3.64.0)",
                    "the apply log gains the typed note: 'Condition -> A, B (note: ...)'; blank-note applies log no suffix"]
    var pnlOrig: [UUID: (conditions: Set<Condition>, durations: [String: Int], notes: [String: String])] = [:]
    for c in model.characters { pnlOrig[c.id] = (c.conditions, c.conditionDurations, c.conditionNotes) }
    if let w = model.characters.first(where: { $0.name == "Wren Halloway" })?.id {
        // Subset apply with note: the note lands per holder and rides the log.
        _ = model.applyPartyCondition(.blinded, rounds: 2, note: "the trap's flash", from: [w])
        let pnlLast = model.tableLog.last(where: { $0.title == "Party condition" })?.text ?? "<missing>"
        pnlLines.append("subset apply with note: '\(pnlLast)'")
        pnlLines.append("subset log string exact \(pnlLast == "Blinded (2 rounds) -> Wren Halloway (note: the trap's flash)")")
        pnlLines.append("note stored per holder \(model.characters.first(where: { $0.id == w })?.conditionNotes[Condition.blinded.rawValue] == "the trap's flash")")
        // Blank-note re-apply (different rounds so it logs): no note suffix,
        // the stored note is kept (3.58.0's blank-keeps rule per holder).
        _ = model.applyPartyCondition(.blinded, rounds: 3, from: [w])
        let pnlBlank = model.tableLog.last(where: { $0.title == "Party condition" })?.text ?? "<missing>"
        pnlLines.append("blank-note re-apply: '\(pnlBlank)'")
        pnlLines.append("blank apply logs no note suffix \(pnlBlank == "Blinded (3 rounds) -> Wren Halloway"), note kept \(model.characters.first(where: { $0.id == w })?.conditionNotes[Condition.blinded.rawValue] == "the trap's flash")")
        // Typed-note re-apply replaces the stored note AND the log names the new one.
        _ = model.applyPartyCondition(.blinded, rounds: 3, note: "smoke", from: [w])
        let pnlReplaced = model.tableLog.last(where: { $0.title == "Party condition" })?.text ?? "<missing>"
        pnlLines.append("typed re-apply replaces: '\(pnlReplaced)', stored now '\(model.characters.first(where: { $0.id == w })?.conditionNotes[Condition.blinded.rawValue] ?? "<missing>")'")
        pnlLines.append("typed replace exact \(pnlReplaced == "Blinded (3 rounds) -> Wren Halloway (note: smoke)" && model.characters.first(where: { $0.id == w })?.conditionNotes[Condition.blinded.rawValue] == "smoke")")
    }
    // Everyone-apply with note: one line names the whole roster.
    _ = model.applyPartyCondition(.frightened, rounds: nil, note: "the howl")
    let pnlAll = model.tableLog.last(where: { $0.title == "Party condition" })?.text ?? "<missing>"
    pnlLines.append("party apply with note: '\(pnlAll)'")
    pnlLines.append("party log exact \(pnlAll == "Frightened -> Wren Halloway, Bram Oakfel, Sera Vint (note: the howl)")")
    pnlLines.append("note landed on every holder \(model.characters.allSatisfy { $0.conditionNotes[Condition.frightened.rawValue] == "the howl" })")
    // PNG: the summary line carrying party-applied notes.
    renderPNG(
        GroupCheckSectionView()
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: width, name: "party-note-log", outDir: outDir, minHeight: 200, maxHeight: 700)
    // Persistence: the party-applied notes round-trip through the store.
    let pnlPersist = model.characters.allSatisfy { c in
        (try? model.store.load(id: c.id))?.conditionNotes == c.conditionNotes
    }
    pnlLines.append("persistence: party notes round-trip \(pnlPersist)")
    // Removal takes the note with the condition (3.58.0 discipline, party path).
    _ = model.removePartyCondition(.frightened)
    pnlLines.append("party removal drops the notes \(model.characters.allSatisfy { $0.conditionNotes[Condition.frightened.rawValue] == nil })")
    // Hygiene: restore conditions/clocks/notes, drop this block's log entries.
    for idx in model.characters.indices {
        let c = model.characters[idx]
        if let orig = pnlOrig[c.id], c.conditions != orig.conditions || c.conditionDurations != orig.durations || c.conditionNotes != orig.notes {
            var restored = c
            restored.conditions = orig.conditions
            restored.conditionDurations = orig.durations
            restored.conditionNotes = orig.notes
            model.characters[idx] = restored
            try? model.store.save(restored)
        }
    }
    model.tableLog.removeAll { $0.title == "Party condition" }
    model.tableLogStore.save(model.tableLog)
    pnlLines.append("hygiene: conditions, clocks, notes and the log restored")
    try? pnlLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/party-note-log.txt"),
               atomically: true, encoding: .utf8)
    // Party-remove note log lines (3.65.0): the removal log line carries
    // each cleared holder's dropped note (captured before it dies with the
    // condition), per holder, on built-in and custom paths. Returned names
    // stay bare; only the log line gains the suffix. State is set
    // explicitly and restored at the end of the block.
    var prnLines = ["Party-remove note log lines (3.65.0)",
                    "the removal log gains each holder's dropped note: 'X removed: A (note: ...), B'; unnoted holders stay bare; returned names stay bare"]
    var prnOrig: [UUID: (conditions: Set<Condition>, durations: [String: Int], notes: [String: String], customs: [CustomCondition])] = [:]
    for c in model.characters { prnOrig[c.id] = (c.conditions, c.conditionDurations, c.conditionNotes, c.customConditions) }
    if let w = model.characters.first(where: { $0.name == "Wren Halloway" })?.id,
       let b = model.characters.first(where: { $0.name == "Bram Oakfel" })?.id,
       let sr = model.characters.first(where: { $0.name == "Sera Vint" })?.id {
        // Mixed noted/unnoted holders: Wren noted, Bram bare.
        _ = model.applyPartyCondition(.blinded, rounds: 3, note: "smoke", from: [w])
        _ = model.applyPartyCondition(.blinded, rounds: 5, from: [b])
        let prnRemoved = model.removePartyCondition(.blinded, from: [w, b])
        let prnLast = model.tableLog.last(where: { $0.title == "Party condition" })?.text ?? "<missing>"
        prnLines.append("mixed removal: '\(prnLast)'")
        prnLines.append("mixed removal exact \(prnLast == "Blinded removed: Wren Halloway (note: smoke), Bram Oakfel")")
        prnLines.append("returned names stay bare \(prnRemoved == ["Wren Halloway", "Bram Oakfel"])")
        prnLines.append("notes died with the condition \(model.characters.allSatisfy { $0.conditionNotes[Condition.blinded.rawValue] == nil })")
        // Persistence: a store reload shows the notes gone post-removal.
        let prnPersist = (try? model.store.load(id: w))?.conditionNotes[Condition.blinded.rawValue] == nil
            && (try? model.store.load(id: b))?.conditionNotes[Condition.blinded.rawValue] == nil
        prnLines.append("persistence: store reload shows dropped notes gone \(prnPersist)")
        // Unnoted-only removal: no suffix at all.
        _ = model.applyPartyCondition(.prone, rounds: nil, from: [w, b])
        _ = model.removePartyCondition(.prone, from: [w, b])
        let prnBare = model.tableLog.last(where: { $0.title == "Party condition" })?.text ?? "<missing>"
        prnLines.append("unnoted removal: '\(prnBare)'")
        prnLines.append("unnoted removal logs no note suffix \(prnBare == "Prone removed: Wren Halloway, Bram Oakfel")")
        // Custom path: note captured per instance before removal.
        _ = model.applyPartyCustomCondition(name: "Hexed", rounds: nil, note: "the brand", from: [sr])
        _ = model.removePartyCustomCondition(name: "Hexed", from: [sr])
        let prnCustom = model.tableLog.last(where: { $0.title == "Party condition" })?.text ?? "<missing>"
        prnLines.append("custom removal with note: '\(prnCustom)'")
        prnLines.append("custom removal exact \(prnCustom == "Hexed removed: Sera Vint (note: the brand)")")
        prnLines.append("custom note died with the condition \(model.characters.first(where: { $0.id == sr })?.conditionNotes.values.contains("the brand") == false)")
    }
    // PNG: the table log showing removal lines carrying (and omitting) notes.
    renderPNG(
        TableLogView()
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: 720, name: "party-remove-note-log", outDir: outDir, minHeight: 120, maxHeight: 400) // 3.66.0: 560 clipped the new filter menu
    // Hygiene: restore conditions/clocks/notes/customs, drop this block's log entries.
    for idx in model.characters.indices {
        let c = model.characters[idx]
        if let orig = prnOrig[c.id], c.conditions != orig.conditions || c.conditionDurations != orig.durations || c.conditionNotes != orig.notes || c.customConditions != orig.customs {
            var restored = c
            restored.conditions = orig.conditions
            restored.conditionDurations = orig.durations
            restored.conditionNotes = orig.notes
            restored.customConditions = orig.customs
            model.characters[idx] = restored
            try? model.store.save(restored)
        }
    }
    model.tableLog.removeAll { $0.title == "Party condition" }
    model.tableLogStore.save(model.tableLog)
    prnLines.append("hygiene: conditions, clocks, notes, customs and the log restored")
    try? prnLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/party-remove-note-log.txt"),
               atomically: true, encoding: .utf8)
    // Custom conditions on the summary line proofs (3.60.0). Runs at END.
    var pccLines = ["Custom conditions on the summary line (3.60.0)",
                    "name is the party identity - customs are per-character instances, born in the per-character editor, party-appliable after"]
    var pccOrig: [UUID: (conditions: Set<Condition>, durations: [String: Int], notes: [String: String], customs: [CustomCondition])] = [:]
    for c in model.characters { pccOrig[c.id] = (c.conditions, c.conditionDurations, c.conditionNotes, c.customConditions) }
    // fixture control (3.60.0 f2): SampleContent seeds a "Vault-marked" custom
    // on Wren - strip every roster custom (and any non-built-in duration/note
    // key) so the block's starting state is explicit. Hygiene below restores.
    let pccBuiltInKeys = Set(Condition.allCases.map(\.rawValue))
    for idx in model.characters.indices {
        var stripped = model.characters[idx]
        stripped.customConditions = []
        stripped.conditionDurations = stripped.conditionDurations.filter { pccBuiltInKeys.contains($0.key) }
        stripped.conditionNotes = stripped.conditionNotes.filter { pccBuiltInKeys.contains($0.key) }
        if stripped != model.characters[idx] {
            model.characters[idx] = stripped
            try? model.store.save(stripped)
        }
    }
    pccLines.append("fixture control: roster customs stripped (the sample seeds one on Wren) \(model.characters.allSatisfy { $0.customConditions.isEmpty })")
    // a customs-free roster keeps the 3.53.0 string contract
    pccLines.append("customs-free summary: '\(partyConditionSummary(model.characters))'")
    pccLines.append("customs-free roster byte-identical to the 3.53.0 shape \(partyConditionSummary(model.characters) == "Wren Halloway: Poisoned")")
    let pccWrenID = model.characters.first(where: { $0.name == "Wren Halloway" })?.id
    let pccBramID = model.characters.first(where: { $0.name == "Bram Oakfel" })?.id
    let pccSeraID = model.characters.first(where: { $0.name == "Sera Vint" })?.id
    // setup: Wren pre-holds "Vault-marked" with a 2r clock, built through the
    // per-character path (explicit fixture construction, flags set here)
    if let w = pccWrenID, let wIdx = model.characters.firstIndex(where: { $0.id == w }) {
        var pccSetup = model.characters[wIdx]
        let pccSeed = CustomCondition(name: "Vault-marked", hindersChecks: true)
        pccSetup.customConditions.append(pccSeed)
        pccSetup.conditionDurations[pccSeed.id.uuidString] = 2
        model.characters[wIdx] = pccSetup
        try? model.store.save(pccSetup)
    }
    pccLines.append("menu names derive from the roster \(model.partyCustomConditionNames == ["Vault-marked"])")
    // party apply, blank rounds + a note: Wren refreshes (clock kept, note
    // attached); Bram and Sera are new, flag set copied from Wren
    let pccLogCount = model.tableLog.filter { $0.title == "Party condition" }.count
    let pccApply = model.applyPartyCustomCondition(name: "Vault-marked", rounds: nil, note: "vault")
    pccLines.append("apply: new [\(pccApply.applied.joined(separator: ", "))], refreshed [\(pccApply.refreshed.joined(separator: ", "))]")
    let pccWrenNow = model.characters.first(where: { $0.id == pccWrenID })
    let pccBramNow = model.characters.first(where: { $0.id == pccBramID })
    let pccSeraNow = model.characters.first(where: { $0.id == pccSeraID })
    let pccWrenCC = pccWrenNow?.customConditions.first(where: { $0.name == "Vault-marked" })
    let pccBramCC = pccBramNow?.customConditions.first(where: { $0.name == "Vault-marked" })
    pccLines.append("Wren refreshed not stacked \(pccApply.refreshed == ["Wren Halloway"] && (pccWrenNow?.customConditions.count ?? -1) == 1), clock kept \(pccWrenCC.flatMap { pccWrenNow?.conditionDurations[$0.id.uuidString] } == 2), note attached \(pccWrenCC.flatMap { pccWrenNow?.conditionNotes[$0.id.uuidString] } == "vault")")
    pccLines.append("flags copied from the first holder \(pccBramCC?.hindersChecks == true), fresh per-character UUID \(pccBramCC != nil && pccWrenCC != nil && pccBramCC!.id != pccWrenCC!.id)")
    // the summary line: built-ins first, customs after, per character; a
    // custom-only holder (Sera) appears
    pccLines.append("summary: '\(partyConditionSummary(model.characters))'")
    pccLines.append("summary exact \(partyConditionSummary(model.characters) == "Wren Halloway: Poisoned, Vault-marked 2r (vault) \u{00B7} Bram Oakfel: Vault-marked (vault) \u{00B7} Sera Vint: Vault-marked (vault)")")
    let pccItems = partyConditionSummaryItems(model.characters)
    pccLines.append("custom-only Sera appears on the line \(pccItems.first(where: { $0.name == "Sera Vint" })?.text == "Sera Vint: Vault-marked (vault)")")
    pccLines.append("Wren's custom part: expiring derived false at 2r \(pccItems.first(where: { $0.name == "Wren Halloway" })?.parts.first(where: { $0.label == "Vault-marked 2r" })?.expiring == false)")
    // never stacks: a blank re-apply to Bram is a no-op, no new log
    if let b = pccBramID {
        let pccNoop = model.applyPartyCustomCondition(name: "Vault-marked", rounds: nil, from: [b])
        pccLines.append("blank re-apply: no-op \(pccNoop.applied.isEmpty && pccNoop.refreshed.isEmpty), no new log \(model.tableLog.filter { $0.title == "Party condition" }.count == pccLogCount + 1)")
    }
    pccLines.append("apply log: '\(model.tableLog.last(where: { $0.title == "Party condition" })?.text ?? "missing")'")
    renderPNG(
        GroupCheckSectionView()
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: 560, name: "party-custom-conditions", outDir: outDir, minHeight: 120, maxHeight: 500)
    // persistence: Bram's instance, clock-less state and note round-trip
    if let b = pccBramID, let pccBramReload = try? model.store.load(id: b) {
        pccLines.append("persistence: custom + note round-trip \(pccBramReload.customConditions == pccBramNow?.customConditions && pccBramReload.conditionNotes == pccBramNow?.conditionNotes)")
    }
    // scoped removal: Sera only - condition, note and any clock clear together
    if let s = pccSeraID {
        let pccRemoved = model.removePartyCustomCondition(name: "Vault-marked", from: [s])
        let pccSeraAfter = model.characters.first(where: { $0.id == s })
        pccLines.append("scoped removal: named [\(pccRemoved.joined(separator: ", "))], Sera clean \(pccSeraAfter?.customConditions.isEmpty == true && pccSeraAfter?.conditionNotes.isEmpty == true), others keep theirs \(model.characters.first(where: { $0.id == pccBramID })?.customConditions.isEmpty == false)")
    }
    // tick to 0 ends Wren's custom and its note (2r -> 1r -> gone)
    if let w = pccWrenID, let wIdx = model.characters.firstIndex(where: { $0.id == w }) {
        var pccTick = model.characters[wIdx]
        _ = pccTick.tickConditionDurations()
        let pccAtOne = pccTick.customConditions.first(where: { $0.name == "Vault-marked" })
        let pccOneLeft = pccAtOne.flatMap { pccTick.conditionDurations[$0.id.uuidString] } == 1
        _ = pccTick.tickConditionDurations()
        model.characters[wIdx] = pccTick
        try? model.store.save(pccTick)
        pccLines.append("tick: 2r->1r \(pccOneLeft), at 0 custom gone \(pccTick.customConditions.isEmpty), note gone \(pccTick.conditionNotes.isEmpty)")
    }
    // hygiene: restore conditions + clocks + notes + customs, drop test log entries
    for idx in model.characters.indices {
        let c = model.characters[idx]
        if let orig = pccOrig[c.id], c.conditions != orig.conditions || c.conditionDurations != orig.durations || c.conditionNotes != orig.notes || c.customConditions != orig.customs {
            var restored = c
            restored.conditions = orig.conditions
            restored.conditionDurations = orig.durations
            restored.conditionNotes = orig.notes
            restored.customConditions = orig.customs
            model.characters[idx] = restored
            try? model.store.save(restored)
        }
    }
    model.tableLog.removeAll { $0.title == "Party condition" }
    model.tableLogStore.save(model.tableLog)
    if let bram = model.characters.first(where: { $0.name == "Bram Oakfel" }) { model.selectedID = bram.id }
    pccLines.append("hygiene: roster conditions, clocks, notes, customs, log and selection restored")
    try? pccLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/party-custom-conditions.txt"),
               atomically: true, encoding: .utf8)

    // Rests run out timed conditions proofs (3.61.0). Runs at END.
    var restLines = ["Rests run out timed conditions (3.61.0)",
                     "short or long, every timed clock dies with its notes; untimed stays - the table's reset"]
    // fixture control (the standing 3.60.0 drill): strip the sample-seeded
    // roster custom so the fixture is explicit; hygiene restores everything.
    var restOrig: [UUID: (conditions: Set<Condition>, durations: [String: Int], notes: [String: String], customs: [CustomCondition])] = [:]
    let restBuiltInKeys = Set(Condition.allCases.map(\.rawValue))
    for idx in model.characters.indices {
        let c = model.characters[idx]
        restOrig[c.id] = (c.conditions, c.conditionDurations, c.conditionNotes, c.customConditions)
        var stripped = c
        stripped.customConditions = []
        stripped.conditionDurations = c.conditionDurations.filter { restBuiltInKeys.contains($0.key) }
        stripped.conditionNotes = c.conditionNotes.filter { restBuiltInKeys.contains($0.key) }
        if stripped != c {
            model.characters[idx] = stripped
            try? model.store.save(stripped)
        }
    }
    restLines.append("fixture control: roster customs stripped (the sample seeds one on Wren) \(model.characters.allSatisfy { $0.customConditions.isEmpty })")
    let restWrenID = model.characters.first(where: { $0.name == "Wren Halloway" })?.id
    let restBramID = model.characters.first(where: { $0.name == "Bram Oakfel" })?.id
    let restSeraID = model.characters.first(where: { $0.name == "Sera Vint" })?.id
    // fixture: Wren Prone 3r (Poisoned untimed rides the sample fixture);
    // Bram a TIMED custom with a note; Sera the SAME custom untimed - the
    // partial-holder case name-scoped removal must not touch
    if let w = restWrenID { _ = model.applyPartyCondition(.prone, rounds: 3, from: [w]) }
    if let b = restBramID { _ = model.applyPartyCustomCondition(name: "Vault-marked", rounds: 2, note: "vault", from: [b]) }
    if let s = restSeraID { _ = model.applyPartyCustomCondition(name: "Vault-marked", rounds: nil, from: [s]) }
    restLines.append("before short rest: '\(partyConditionSummary(model.characters))'")
    restLines.append("before short exact \(partyConditionSummary(model.characters) == "Wren Halloway: Poisoned, Prone 3r \u{00B7} Bram Oakfel: Vault-marked 2r (vault) \u{00B7} Sera Vint: Vault-marked")")
    // SHORT REST: an hour passes - every round-scale clock runs out
    let restShortRested = model.restParty(long: false)
    restLines.append("short rest vitals moved \(restShortRested.count) member(s)")
    restLines.append("after short rest: '\(partyConditionSummary(model.characters))'")
    restLines.append("after short exact \(partyConditionSummary(model.characters) == "Wren Halloway: Poisoned \u{00B7} Sera Vint: Vault-marked")")
    restLines.append("untimed Poisoned stays \(model.characters.first(where: { $0.id == restWrenID })?.conditions.contains(.poisoned) == true)")
    restLines.append("partial-holder custom survives on Sera \(model.characters.first(where: { $0.id == restSeraID })?.customConditions.count == 1)")
    if let b = restBramID, let reloaded = try? model.store.load(id: b) {
        restLines.append("persistence: Bram's custom, clock and note gone \(reloaded.customConditions.isEmpty && reloaded.conditionDurations.isEmpty && reloaded.conditionNotes.isEmpty)")
    }
    let restShortLog = model.tableLog.last(where: { $0.title == "Party rest" })?.text ?? "MISSING"
    restLines.append("short rest log: '\(restShortLog)'")
    restLines.append("short rest log exact \(restShortLog == "Short rest cleared Bram Oakfel: Vault-marked \u{00B7} Wren Halloway: Prone")")
    restLines.append("removal-path lines used \(model.tableLog.contains { $0.title == "Party condition" && $0.text == "Prone removed: Wren Halloway" } && model.tableLog.contains { $0.title == "Party condition" && $0.text == "Vault-marked removed: Bram Oakfel (note: vault)" })")
    // LONG REST fixture: Prone 2r on everyone, Bram's custom timed again
    _ = model.applyPartyCondition(.prone, rounds: 2)
    if let b = restBramID { _ = model.applyPartyCustomCondition(name: "Vault-marked", rounds: 5, note: "mark", from: [b]) }
    restLines.append("before long rest: '\(partyConditionSummary(model.characters))'")
    restLines.append("before long exact \(partyConditionSummary(model.characters) == "Wren Halloway: Poisoned, Prone 2r \u{00B7} Bram Oakfel: Prone 2r, Vault-marked 5r (mark) \u{00B7} Sera Vint: Prone 2r, Vault-marked")")
    let restLongRested = model.restParty(long: true)
    restLines.append("long rest vitals moved \(restLongRested.count) member(s)")
    restLines.append("after long rest: '\(partyConditionSummary(model.characters))'")
    restLines.append("after long exact \(partyConditionSummary(model.characters) == "Wren Halloway: Poisoned \u{00B7} Sera Vint: Vault-marked")")
    let restLongLog = model.tableLog.last(where: { $0.title == "Party rest" })?.text ?? "MISSING"
    restLines.append("long rest log: '\(restLongLog)'")
    restLines.append("long rest log exact \(restLongLog == "Long rest cleared Bram Oakfel: Vault-marked, Prone \u{00B7} Sera Vint: Prone \u{00B7} Wren Halloway: Prone")")
    restLines.append("untimed still untouched: Poisoned \(model.characters.first(where: { $0.id == restWrenID })?.conditions.contains(.poisoned) == true), Sera's custom \(model.characters.first(where: { $0.id == restSeraID })?.customConditions.count == 1)")
    renderPNG(
        GroupCheckSectionView()
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: 1024, name: "party-rest-conditions", outDir: outDir, minHeight: 768, maxHeight: 768)
    // hygiene: restore every character's original conditions, clocks, notes
    // and customs; drop the block's log entries; hand selection back
    for idx in model.characters.indices {
        let c = model.characters[idx]
        if let orig = restOrig[c.id], c.conditions != orig.conditions || c.conditionDurations != orig.durations || c.conditionNotes != orig.notes || c.customConditions != orig.customs {
            var restored = c
            restored.conditions = orig.conditions
            restored.conditionDurations = orig.durations
            restored.conditionNotes = orig.notes
            restored.customConditions = orig.customs
            model.characters[idx] = restored
            try? model.store.save(restored)
        }
    }
    model.tableLog.removeAll { $0.title == "Party condition" || $0.title == "Party rest" }
    model.tableLogStore.save(model.tableLog)
    if let bram = model.characters.first(where: { $0.name == "Bram Oakfel" }) { model.selectedID = bram.id }
    restLines.append("hygiene: roster conditions, clocks, notes, customs, log and selection restored")
    try? restLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/party-rest-conditions.txt"),
               atomically: true, encoding: .utf8)

    // Per-character rest clearing parity proofs (3.62.0). Runs at END.
    var pcrLines = ["Per-character rests run out timed conditions (3.62.0)",
                    "the same rule one level down - the sheet-level rest buttons clear what the party buttons clear"]
    // fixture control (the standing drill): strip the sample-seeded roster
    // custom; hygiene restores everything.
    var pcrOrig: [UUID: (conditions: Set<Condition>, durations: [String: Int], notes: [String: String], customs: [CustomCondition])] = [:]
    let pcrBuiltInKeys = Set(Condition.allCases.map(\.rawValue))
    for idx in model.characters.indices {
        let c = model.characters[idx]
        pcrOrig[c.id] = (c.conditions, c.conditionDurations, c.conditionNotes, c.customConditions)
        var stripped = c
        stripped.customConditions = []
        stripped.conditionDurations = c.conditionDurations.filter { pcrBuiltInKeys.contains($0.key) }
        stripped.conditionNotes = c.conditionNotes.filter { pcrBuiltInKeys.contains($0.key) }
        if stripped != c {
            model.characters[idx] = stripped
            try? model.store.save(stripped)
        }
    }
    pcrLines.append("fixture control: roster customs stripped (the sample seeds one on Wren) \(model.characters.allSatisfy { $0.customConditions.isEmpty })")
    let pcrWrenID = model.characters.first(where: { $0.name == "Wren Halloway" })?.id
    // fixture on Wren alone: Prone 3r + a timed custom with a note; Poisoned
    // (untimed) rides the sample fixture and must survive both rests
    if let w = pcrWrenID {
        _ = model.applyPartyCondition(.prone, rounds: 3, from: [w])
        _ = model.applyPartyCustomCondition(name: "Vault-marked", rounds: 2, note: "vault", from: [w])
        model.selectedID = w
    }
    pcrLines.append("before short rest: '\(partyConditionSummary(model.characters))'")
    pcrLines.append("before short exact \(partyConditionSummary(model.characters) == "Wren Halloway: Poisoned, Prone 3r, Vault-marked 2r (vault)")")
    model.shortRest()
    pcrLines.append("after short rest: '\(partyConditionSummary(model.characters))'")
    pcrLines.append("after short exact \(partyConditionSummary(model.characters) == "Wren Halloway: Poisoned")")
    pcrLines.append("untimed Poisoned stays \(model.characters.first(where: { $0.id == pcrWrenID })?.conditions.contains(.poisoned) == true)")
    if let w = pcrWrenID, let reloaded = try? model.store.load(id: w) {
        pcrLines.append("persistence: custom, clock and note gone \(reloaded.customConditions.isEmpty && reloaded.conditionDurations.isEmpty && reloaded.conditionNotes.isEmpty)")
    }
    let pcrShortLog = model.tableLog.last(where: { $0.title == "Rest" })?.text ?? "MISSING"
    pcrLines.append("short rest log: '\(pcrShortLog)'")
    pcrLines.append("short rest log exact \(pcrShortLog == "Short rest cleared Wren Halloway: Vault-marked, Prone")")
    pcrLines.append("removal-path lines used \(model.tableLog.contains { $0.title == "Party condition" && $0.text == "Prone removed: Wren Halloway" } && model.tableLog.contains { $0.title == "Party condition" && $0.text == "Vault-marked removed: Wren Halloway (note: vault)" })")
    // LONG fixture on Wren: Prone 1r + the custom timed again
    if let w = pcrWrenID {
        _ = model.applyPartyCondition(.prone, rounds: 1, from: [w])
        _ = model.applyPartyCustomCondition(name: "Vault-marked", rounds: 4, note: "mark", from: [w])
    }
    pcrLines.append("before long rest: '\(partyConditionSummary(model.characters))'")
    pcrLines.append("before long exact \(partyConditionSummary(model.characters) == "Wren Halloway: Poisoned, Prone 1r, Vault-marked 4r (mark)")")
    model.longRest()
    pcrLines.append("after long rest: '\(partyConditionSummary(model.characters))'")
    pcrLines.append("after long exact \(partyConditionSummary(model.characters) == "Wren Halloway: Poisoned")")
    let pcrLongLog = model.tableLog.last(where: { $0.title == "Rest" })?.text ?? "MISSING"
    pcrLines.append("long rest log: '\(pcrLongLog)'")
    pcrLines.append("long rest log exact \(pcrLongLog == "Long rest cleared Wren Halloway: Vault-marked, Prone")")
    renderPNG(
        GroupCheckSectionView()
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: 1024, name: "perchar-rest-conditions", outDir: outDir, minHeight: 768, maxHeight: 768)
    // hygiene: restore roster state, drop the block's log entries, selection back
    for idx in model.characters.indices {
        let c = model.characters[idx]
        if let orig = pcrOrig[c.id], c.conditions != orig.conditions || c.conditionDurations != orig.durations || c.conditionNotes != orig.notes || c.customConditions != orig.customs {
            var restored = c
            restored.conditions = orig.conditions
            restored.conditionDurations = orig.durations
            restored.conditionNotes = orig.notes
            restored.customConditions = orig.customs
            model.characters[idx] = restored
            try? model.store.save(restored)
        }
    }
    model.tableLog.removeAll { $0.title == "Party condition" || $0.title == "Rest" }
    model.tableLogStore.save(model.tableLog)
    if let bram = model.characters.first(where: { $0.name == "Bram Oakfel" }) { model.selectedID = bram.id }
    pcrLines.append("hygiene: roster conditions, clocks, notes, customs, log and selection restored")
    try? pcrLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/perchar-rest-conditions.txt"),
               atomically: true, encoding: .utf8)
    // Undo-restore log lines (3.66.0): the undo of a removal logs what
    // returned - 'restored Frightened on Ila Thorn (note: the howl)' -
    // through the same note rule the removal line uses (3.65.0); the undo
    // of an APPLY stays silent (one-direction audit). A throwaway probe
    // character keeps the fixture roster and its undo stacks untouched;
    // deleteSelected retires the probe's stack. Runs at END.
    var rlnLines = ["Undo-restore log lines (3.66.0)",
                    "the undo of a removal logs the restoration, note and all; the undo of an apply logs nothing"]
    let rlnLogStart = model.tableLog.count
    model.addCharacter(Character(name: "Ila Thorn"))
    let rlnProbeID = model.selectedID! // addCharacter selects the probe
    _ = model.applyPartyCondition(.frightened, rounds: 3, note: "the howl", from: [rlnProbeID])
    _ = model.removePartyCondition(.frightened, from: [rlnProbeID])
    let rlnRemoval = model.tableLog.last(where: { $0.title == "Party condition" })?.text ?? "<missing>"
    rlnLines.append("noted removal: '\(rlnRemoval)'")
    rlnLines.append("noted removal exact \(rlnRemoval == "Frightened removed: Ila Thorn (note: the howl)")")
    model.undo()
    let rlnRestore = model.tableLog.last(where: { $0.title == "Party condition" })?.text ?? "<missing>"
    rlnLines.append("undo of the removal: '\(rlnRestore)'")
    rlnLines.append("restore exact \(rlnRestore == "restored Frightened on Ila Thorn (note: the howl)")")
    let rlnHolds = model.characters.first(where: { $0.id == rlnProbeID })
    rlnLines.append("probe holds Frightened again \(rlnHolds?.conditions.contains(.frightened) == true)")
    rlnLines.append("note restored with it \(rlnHolds?.conditionNotes[Condition.frightened.rawValue] == "the howl")")
    rlnLines.append("clock restored with it \(rlnHolds?.conditionDurations[Condition.frightened.rawValue] == 3)")
    if let rlnReloaded = try? model.store.load(id: rlnProbeID) {
        rlnLines.append("persistence: store reload shows condition and note \(rlnReloaded.conditions.contains(.frightened) && rlnReloaded.conditionNotes[Condition.frightened.rawValue] == "the howl")")
    }
    // One-direction: the undo of an APPLY drops the condition, logs nothing.
    _ = model.applyPartyCondition(.prone, rounds: nil, from: [rlnProbeID])
    let rlnCountBeforeSilentUndo = model.tableLog.count
    model.undo()
    rlnLines.append("undo of an apply appends no entry \(model.tableLog.count == rlnCountBeforeSilentUndo)")
    rlnLines.append("the applied condition is gone \(model.characters.first(where: { $0.id == rlnProbeID })?.conditions.contains(.prone) == false)")
    // Unnoted built-in restore stays bare.
    _ = model.applyPartyCondition(.prone, rounds: nil, from: [rlnProbeID])
    _ = model.removePartyCondition(.prone, from: [rlnProbeID])
    model.undo()
    let rlnBare = model.tableLog.last(where: { $0.title == "Party condition" })?.text ?? "<missing>"
    rlnLines.append("unnoted restore: '\(rlnBare)'")
    rlnLines.append("unnoted restore exact \(rlnBare == "restored Prone on Ila Thorn")")
    // Custom path: the instance note rides the restore.
    _ = model.applyPartyCustomCondition(name: "Hexed", rounds: nil, note: "the brand", from: [rlnProbeID])
    _ = model.removePartyCustomCondition(name: "Hexed", from: [rlnProbeID])
    model.undo()
    let rlnCustom = model.tableLog.last(where: { $0.title == "Party condition" })?.text ?? "<missing>"
    rlnLines.append("custom restore: '\(rlnCustom)'")
    rlnLines.append("custom restore exact \(rlnCustom == "restored Hexed on Ila Thorn (note: the brand)")")
    rlnLines.append("probe holds the custom again \(model.characters.first(where: { $0.id == rlnProbeID })?.customConditions.contains(where: { $0.name == "Hexed" }) == true)")
    // PNG: removal and restore lines side by side in the log.
    renderPNG(
        TableLogView()
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: 720, name: "party-restore-note-log", outDir: outDir, minHeight: 120, maxHeight: 400)
    // Hygiene: retire the probe (its undo stack dies with it), drop the
    // block's log entries, selection back to Bram.
    model.selectedID = rlnProbeID
    model.deleteSelected()
    model.tableLog.removeLast(model.tableLog.count - rlnLogStart)
    model.tableLogStore.save(model.tableLog)
    if let bram = model.characters.first(where: { $0.name == "Bram Oakfel" }) { model.selectedID = bram.id }
    rlnLines.append("hygiene: probe retired, block log entries dropped, selection restored")
    try? rlnLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/party-restore-note-log.txt"),
               atomically: true, encoding: .utf8)
    // Table log condition filter (3.66.0): the header menu narrows the log
    // to one condition's lines - apply, removal and restore entries all
    // name their condition; case-insensitive over title and text; blank
    // shows all; Copy stays whole-log. Runs at END.
    var tlfLines = ["Table log condition filter (3.66.0)",
                    "one menu picks a condition name; the log narrows to the entries naming it"]
    let tlfLogStart = model.tableLog.count
    model.addTableLogEntry(title: "Party condition", text: "restored Frightened on Ila Thorn (note: the howl)")
    // "Zephyr Hollow", not an Ember title: the sample log seeds an Ember
    // Warrens entry (3.49.0 block), which would break a unique-hit count.
    model.addTableLogEntry(title: "Zephyr Hollow", text: "The party reaches the rope bridge.")
    model.addTableLogEntry(title: "Party condition", text: "Prone removed: Bram Oakfel")
    tlfLines.append("blank query shows everything \(TableLogConditionFilter.filter(model.tableLog, query: "").count == model.tableLog.count)")
    let tlfFrightened = TableLogConditionFilter.filter(model.tableLog, query: "frightened")
    tlfLines.append("case-insensitive text match \(tlfFrightened.count == 1 && tlfFrightened.first?.text == "restored Frightened on Ila Thorn (note: the howl)")")
    let tlfProne = TableLogConditionFilter.filter(model.tableLog, query: "Prone")
    tlfLines.append("name match finds the removal line \(tlfProne.count == 1 && tlfProne.first?.text == "Prone removed: Bram Oakfel")")
    let tlfTitle = TableLogConditionFilter.filter(model.tableLog, query: "Zephyr")
    tlfLines.append("titles match too \(tlfTitle.count == 1 && tlfTitle.first?.title == "Zephyr Hollow")")
    tlfLines.append("no match filters to empty \(TableLogConditionFilter.filter(model.tableLog, query: "Petrified").isEmpty)")
    // PNG: the filtered view - only the Frightened line, menu reads the
    // filter. 3.67.0: the filter lives on the model (persisted across
    // launches); seed it there, restore blank after.
    model.tableLogConditionFilter = "Frightened"
    renderPNG(
        TableLogView()
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: 720, name: "table-log-condition-filter", outDir: outDir, minHeight: 120, maxHeight: 400)
    model.tableLogConditionFilter = ""
    tlfLines.append("filter seeded through the persisted model property \(model.tableLogConditionFilter.isEmpty)")
    model.tableLog.removeLast(model.tableLog.count - tlfLogStart)
    model.tableLogStore.save(model.tableLog)
    tlfLines.append("hygiene: filter-fixture entries dropped")
    try? tlfLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/table-log-condition-filter.txt"),
               atomically: true, encoding: .utf8)
    // Redo-of-removal log lines (3.67.0): the redo of a removal logs the
    // re-removal in the removal line's own shape (3.65.0), closing the
    // audit loop apply -> removed -> restored -> removed; the redo of an
    // APPLY stays silent (one-direction, mirroring the undo side). A
    // throwaway probe character keeps the fixture roster and its undo
    // stacks untouched; deleteSelected retires the probe's stack. Runs at
    // END.
    var rdlLines = ["Redo-of-removal log lines (3.67.0)",
                    "the redo of a removal logs the re-removal, note and all; the redo of an apply logs nothing"]
    let rdlLogStart = model.tableLog.count
    model.addCharacter(Character(name: "Nyx Alder"))
    let rdlProbeID = model.selectedID! // addCharacter selects the probe
    _ = model.applyPartyCondition(.frightened, rounds: 3, note: "the howl", from: [rdlProbeID])
    _ = model.removePartyCondition(.frightened, from: [rdlProbeID])
    model.undo()
    model.redo()
    let rdlRedo = model.tableLog.last(where: { $0.title == "Party condition" })?.text ?? "<missing>"
    rdlLines.append("redo of the removal: '\(rdlRedo)'")
    rdlLines.append("redo removal exact \(rdlRedo == "Frightened removed: Nyx Alder (note: the howl)")")
    rdlLines.append("the condition is gone again \(model.characters.first(where: { $0.id == rdlProbeID })?.conditions.contains(.frightened) == false)")
    rdlLines.append("the note dies with it again \(model.characters.first(where: { $0.id == rdlProbeID })?.conditionNotes[Condition.frightened.rawValue] == nil)")
    // One-direction: the redo of an APPLY re-applies silently.
    _ = model.applyPartyCondition(.prone, rounds: nil, from: [rdlProbeID])
    model.undo()
    let rdlCountBeforeSilentRedo = model.tableLog.count
    model.redo()
    rdlLines.append("redo of an apply appends no entry \(model.tableLog.count == rdlCountBeforeSilentRedo)")
    rdlLines.append("the applied condition is back \(model.characters.first(where: { $0.id == rdlProbeID })?.conditions.contains(.prone) == true)")
    // Unnoted built-in redo stays bare.
    _ = model.removePartyCondition(.prone, from: [rdlProbeID])
    model.undo()
    model.redo()
    let rdlBare = model.tableLog.last(where: { $0.title == "Party condition" })?.text ?? "<missing>"
    rdlLines.append("unnoted redo: '\(rdlBare)'")
    rdlLines.append("unnoted redo exact \(rdlBare == "Prone removed: Nyx Alder")")
    // Custom path: the instance note rides the re-removal.
    _ = model.applyPartyCustomCondition(name: "Hexed", rounds: nil, note: "the brand", from: [rdlProbeID])
    _ = model.removePartyCustomCondition(name: "Hexed", from: [rdlProbeID])
    model.undo()
    model.redo()
    let rdlCustom = model.tableLog.last(where: { $0.title == "Party condition" })?.text ?? "<missing>"
    rdlLines.append("custom redo: '\(rdlCustom)'")
    rdlLines.append("custom redo exact \(rdlCustom == "Hexed removed: Nyx Alder (note: the brand)")")
    // PNG: the audit loop visible end to end - apply, removal, restore,
    // re-removal side by side in the log.
    renderPNG(
        TableLogView()
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: 720, name: "party-redo-removal-log", outDir: outDir, minHeight: 120, maxHeight: 400)
    // Hygiene: retire the probe (its undo stack dies with it), drop the
    // block's log entries, selection back to Bram.
    model.selectedID = rdlProbeID
    model.deleteSelected()
    model.tableLog.removeLast(model.tableLog.count - rdlLogStart)
    model.tableLogStore.save(model.tableLog)
    if let bram = model.characters.first(where: { $0.name == "Bram Oakfel" }) { model.selectedID = bram.id }
    rdlLines.append("hygiene: probe retired, block log entries dropped, selection restored")
    try? rdlLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/party-redo-removal-log.txt"),
               atomically: true, encoding: .utf8)
    // Table log filter persistence (3.67.0): the pick writes UserDefaults
    // on change; a fresh model - the relaunch - reads it back and the
    // view binds to it, so the filter survives quitting.
    var tfpLines = ["Table log filter persistence (3.67.0)",
                    "the condition filter persists across launches; a relaunched model restores the pick"]
    let tfpLogStart = model.tableLog.count
    model.addTableLogEntry(title: "Party condition", text: "Hexed removed: Nyx Alder (note: the brand)")
    model.addTableLogEntry(title: "Table note", text: "The torches gutter.")
    model.tableLogConditionFilter = "Hexed"
    // Key literal mirrored from AppModel (private there):
    // architer.tableLogConditionFilter.
    tfpLines.append("the pick writes defaults \(UserDefaults.standard.string(forKey: "architer.tableLogConditionFilter") == "Hexed")")
    let tfpRelaunch = AppModel()
    tfpLines.append("a relaunched model restores the pick \(tfpRelaunch.tableLogConditionFilter == "Hexed")")
    let tfpFiltered = TableLogConditionFilter.filter(tfpRelaunch.tableLog, query: tfpRelaunch.tableLogConditionFilter)
    tfpLines.append("the relaunch narrows to the one Hexed entry \(tfpFiltered.count == 1 && tfpFiltered.first?.text == "Hexed removed: Nyx Alder (note: the brand)")")
    // PNG: the relaunched model's own view - the menu reads Hexed, one
    // entry listed. Rendered off the relaunch, not the seeding model.
    renderPNG(
        TableLogView()
            .padding()
            .background(Theme.surface)
            .environmentObject(tfpRelaunch),
        width: 720, name: "table-log-filter-persistence", outDir: outDir, minHeight: 120, maxHeight: 400)
    model.tableLogConditionFilter = ""
    tfpLines.append("clearing persists blank \(UserDefaults.standard.string(forKey: "architer.tableLogConditionFilter") == "")")
    let tfpRelaunchCleared = AppModel()
    tfpLines.append("a relaunch after clearing shows the whole log \(tfpRelaunchCleared.tableLogConditionFilter == "")")
    // Hygiene: drop the fixture entries; the render model's filter was
    // cleared above.
    model.tableLog.removeLast(model.tableLog.count - tfpLogStart)
    model.tableLogStore.save(model.tableLog)
    tfpLines.append("hygiene: fixture entries dropped, filter cleared")
    try? tfpLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/table-log-filter-persistence.txt"),
               atomically: true, encoding: .utf8)
    // Party detail panel (3.68.0): the wide surface where chips carry
    // the whole note and remaining clock. Proves the summary-grammar
    // chip texts, all-chips-no-cap, the expiring mark, the compact empty
    // row, 720 + 1024 renders, and the collapsed pick's persistence on a
    // relaunched model. Direct state edits (the pcr block's pattern)
    // keep the log untouched - the panel is read-only, so the block also
    // asserts no log entries appear. Hygiene restores the roster and the
    // collapsed default. Runs at END.
    var pdpLines = ["Party detail panel (3.68.0)",
                    "every chip with its whole note and clock, one row per member; read-only; collapsed by default and the pick persists"]
    let pdpLogStart = model.tableLog.count
    let pdpOrig: [UUID: (Set<Condition>, [String: Int], [String: String], [CustomCondition], String?, Int?)] =
        Dictionary(uniqueKeysWithValues: model.characters.map {
            ($0.id, ($0.conditions, $0.conditionDurations, $0.conditionNotes, $0.customConditions, $0.concentratingOn, $0.concentrationTimer))
        })
    // Deterministic fixture: each member's full condition state is set
    // explicitly, so the exact strings never depend on block order.
    if let idx = model.characters.firstIndex(where: { $0.name == "Wren Halloway" }) {
        var c = model.characters[idx]
        c.conditions = [.frightened]
        c.conditionDurations = [Condition.frightened.rawValue: 2]
        c.conditionNotes = [Condition.frightened.rawValue: "the howl"]
        c.customConditions = [CustomCondition(name: "Vault-marked")]
        c.concentratingOn = "Misty step"
        c.concentrationTimer = 3
        model.characters[idx] = c
    }
    if let idx = model.characters.firstIndex(where: { $0.name == "Bram Oakfel" }) {
        var c = model.characters[idx]
        c.conditions = [.prone]
        c.conditionDurations = [:]
        c.conditionNotes = [:]
        let hexed = CustomCondition(name: "Hexed")
        c.customConditions = [hexed]
        c.conditionDurations = [hexed.id.uuidString: 1]
        c.conditionNotes = [hexed.id.uuidString: "the brand"]
        c.concentratingOn = nil
        c.concentrationTimer = nil
        model.characters[idx] = c
    }
    if let idx = model.characters.firstIndex(where: { $0.name == "Sera Vint" }) {
        var c = model.characters[idx]
        c.conditions = []
        c.conditionDurations = [:]
        c.conditionNotes = [:]
        c.customConditions = []
        c.concentratingOn = nil
        c.concentrationTimer = nil
        model.characters[idx] = c
    }
    let pdpRows = partyDetailRows(model.characters)
    let pdpWren = pdpRows.first(where: { $0.name == "Wren Halloway" })
    pdpLines.append("wren chips: \(pdpWren?.chips.map(\.text) ?? [])")
    pdpLines.append("wren chips exact \(pdpWren?.chips.map(\.text) == ["Frightened 2r (the howl)", "Vault-marked", "Concentrating: Misty step (3)"])")
    pdpLines.append("wren flags none expiring \(pdpWren?.chips.map(\.expiring) == [false, false, false])")
    let pdpBram = pdpRows.first(where: { $0.name == "Bram Oakfel" })
    pdpLines.append("bram chips: \(pdpBram?.chips.map(\.text) ?? [])")
    pdpLines.append("bram chips exact \(pdpBram?.chips.map(\.text) == ["Prone", "Hexed 1r (the brand)"])")
    pdpLines.append("bram flags the 1r clock expiring \(pdpBram?.chips.map(\.expiring) == [false, true])")
    let pdpSera = pdpRows.first(where: { $0.name == "Sera Vint" })
    pdpLines.append("sera holds nothing, still one row \(pdpSera != nil && pdpSera?.chips.isEmpty == true)")
    pdpLines.append("all three members list \(pdpRows.count == 3)")
    pdpLines.append("hp rides the row \(pdpWren != nil && pdpWren!.currentHP == model.characters.first(where: { $0.id == pdpWren!.characterID })!.currentHP && pdpWren!.maxHP == model.characters.first(where: { $0.id == pdpWren!.characterID })!.maxHP)")
    pdpLines.append("no cap inside the panel \(pdpWren?.chips.count == 3)")
    pdpLines.append("read-only: the log gains no entries \(model.tableLog.count == pdpLogStart)")
    // PNGs: the expanded panel at 720 and 1024 - wrap behavior at both.
    model.partyDetailPanelOpen = true
    renderPNG(
        PartyDetailPanelView()
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: 720, name: "party-detail-panel-720", outDir: outDir, minHeight: 120, maxHeight: 400)
    renderPNG(
        PartyDetailPanelView()
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: 1024, name: "party-detail-panel-1024", outDir: outDir, minHeight: 120, maxHeight: 400)
    // Persistence: the open pick writes defaults; a relaunched model
    // restores it; collapsed persists too (the default).
    // Key literal mirrored from AppModel (private there):
    // architer.partyDetailPanelOpen.
    pdpLines.append("the open pick writes defaults \(UserDefaults.standard.bool(forKey: "architer.partyDetailPanelOpen") == true)")
    let pdpRelaunch = AppModel()
    pdpLines.append("a relaunched model restores open \(pdpRelaunch.partyDetailPanelOpen == true)")
    model.partyDetailPanelOpen = false
    pdpLines.append("collapsing persists \(UserDefaults.standard.bool(forKey: "architer.partyDetailPanelOpen") == false)")
    let pdpRelaunchClosed = AppModel()
    pdpLines.append("a relaunch restores collapsed \(pdpRelaunchClosed.partyDetailPanelOpen == false)")
    // Hygiene: roster condition state back, pick back to the default.
    for idx in model.characters.indices {
        let c = model.characters[idx]
        if let orig = pdpOrig[c.id], c.conditions != orig.0 || c.conditionDurations != orig.1 || c.conditionNotes != orig.2 || c.customConditions != orig.3 || c.concentratingOn != orig.4 || c.concentrationTimer != orig.5 {
            var restored = c
            restored.conditions = orig.0
            restored.conditionDurations = orig.1
            restored.conditionNotes = orig.2
            restored.customConditions = orig.3
            restored.concentratingOn = orig.4
            restored.concentrationTimer = orig.5
            model.characters[idx] = restored
            try? model.store.save(restored)
        }
    }
    pdpLines.append("hygiene: roster conditions, clocks, notes, customs and concentration restored; pick collapsed")
    try? pdpLines.joined(separator: "\n")
        .write(to: URL(fileURLWithPath: "\(outDir)/party-detail-panel.txt"),
               atomically: true, encoding: .utf8)
    // 3.69.0: force the panel's wrap branch at 720 with six full-note
    // chips on a single member. Restore the roster without storing this
    // visual-only fixture. Pixels, not the chip count, prove the wrap.
    let pwrOriginalRoster = model.characters
    let pwrOriginalOpen = model.partyDetailPanelOpen
    var pwrProbe = Character(name: "Wrap proof")
    pwrProbe.conditions = [.blinded, .frightened, .poisoned, .prone, .stunned, .restrained]
    for condition in pwrProbe.conditions {
        pwrProbe.conditionNotes[condition.rawValue] = "abcdefghijklmnopqrstuvwx"
        pwrProbe.conditionDurations[condition.rawValue] = 2
    }
    model.characters = [pwrProbe]
    model.partyDetailPanelOpen = true
    let pwrChips = partyDetailRows(model.characters).first?.chips ?? []
    renderPNG(PartyDetailPanelView().padding().background(Theme.surface).environmentObject(model),
              width: 720, name: "party-detail-panel-wrap-720", outDir: outDir, minHeight: 120, maxHeight: 600)
    let pwrLines = ["Panel multi-row wrap fixture (3.69.0)",
                    "six noted clocked chips \(pwrChips.count == 6)",
                    "whole 24-character notes on every chip \(pwrChips.allSatisfy { $0.text.contains("abcdefghijklmnopqrstuvwx") })",
                    "pixel proof: party-detail-panel-wrap-720.png must show multiple chip rows without clipping"]
    try? pwrLines.joined(separator: "\n").write(to: URL(fileURLWithPath: "\(outDir)/party-detail-panel-wrap.txt"), atomically: true, encoding: .utf8)
    model.characters = pwrOriginalRoster
    model.partyDetailPanelOpen = pwrOriginalOpen
    // 3.69.0: production history query survives a fresh model. Explicit
    // older render seeds stay local overrides and leave defaults alone.
    let hqpOriginalHistory = model.rollHistory
    let hqpOriginalQuery = model.rollHistoryQuery
    model.rollHistory = [
        RollResult(expression: "1d6", dice: [], modifier: 0, total: 4,
                   alternateTotal: nil, label: "Zephyr beacon", rolledAt: Date()),
        RollResult(expression: "1d8", dice: [], modifier: 0, total: 6,
                   alternateTotal: nil, label: "Bridge watch", rolledAt: Date())
    ]
    model.rollHistoryStore.save(model.rollHistory)
    model.rollHistoryQuery = "Zephyr beacon"
    var hqpLines = ["History-query persistence (3.69.0)"]
    hqpLines.append("query writes defaults \(UserDefaults.standard.string(forKey: "architer.rollHistoryQuery") == "Zephyr beacon")")
    let hqpRelaunch = AppModel()
    hqpLines.append("fresh model restores query \(hqpRelaunch.rollHistoryQuery == "Zephyr beacon")")
    let hqpMatches = hqpRelaunch.rollHistory.matching(hqpRelaunch.rollHistoryQuery)
    hqpLines.append("fresh model filters to one exact roll \(hqpMatches.count == 1 && hqpMatches.first?.label == "Zephyr beacon")")
    renderPNG(DiceRollerView().padding().background(Theme.surface).environmentObject(hqpRelaunch),
              width: 1024, name: "history-query-persistence", outDir: outDir, minHeight: 420, maxHeight: 1100)
    renderPNG(DiceRollerView(initialHistoryFilter: "Bridge watch").padding().background(Theme.surface).environmentObject(model),
              width: 1024, name: "history-query-local-override", outDir: outDir, minHeight: 420, maxHeight: 1100)
    hqpLines.append("explicit render override leaves stored query untouched \(model.rollHistoryQuery == "Zephyr beacon" && UserDefaults.standard.string(forKey: "architer.rollHistoryQuery") == "Zephyr beacon")")
    model.rollHistoryQuery = ""
    let hqpCleared = AppModel()
    hqpLines.append("clear survives fresh model \(hqpCleared.rollHistoryQuery.isEmpty)")
    hqpLines.append("clear shows both rolls \(hqpCleared.rollHistory.matching(hqpCleared.rollHistoryQuery).count == 2)")
    model.rollHistory = hqpOriginalHistory
    model.rollHistoryStore.save(model.rollHistory)
    model.rollHistoryQuery = hqpOriginalQuery
    try? hqpLines.joined(separator: "\n").write(to: URL(fileURLWithPath: "\(outDir)/history-query-persistence.txt"), atomically: true, encoding: .utf8)
    // 3.70.0: the Edit menu names condition steps while their snapshot
    // tops the selected character's undo stack - apply, remove (built-in
    // and custom), and the round-wrap tick - and falls back to plain
    // "Undo" after a newer unlabeled edit or the undo itself. Runs at
    // the end like every AppModel proof; the roster and the initiative
    // tracker are restored afterwards.
    do {
        let culOriginalInitiative = model.initiative
        let culIdx = model.characters.firstIndex(where: { $0.id == model.selectedID }) ?? 0
        let culOriginal = model.characters[culIdx]
        let culName = culOriginal.name
        var culLines = ["Condition undo-menu labels (3.70.0)",
                        "the Edit menu names a condition step only while its snapshot tops the selected character's undo stack"]
        // Apply names the step.
        model.applyPartyCondition(.frightened, rounds: 2, from: [culOriginal.id])
        culLines.append("apply names the step \(model.undoMenuLabel == "Undo Apply Frightened to \(culName)")")
        // The undo itself moves the depth: plain "Undo".
        model.undo()
        culLines.append("after undo the menu falls back \(model.undoMenuLabel == "Undo")")
        // Re-apply, then the removal names its own step.
        model.applyPartyCondition(.frightened, rounds: 2, from: [culOriginal.id])
        model.removePartyCondition(.frightened, from: [culOriginal.id])
        culLines.append("removal names the step \(model.undoMenuLabel == "Undo Remove Frightened from \(culName)")")
        // Customs ride the same pair under their trimmed name.
        model.applyPartyCustomCondition(name: "Hexed", rounds: 3, from: [culOriginal.id])
        culLines.append("custom apply names the step \(model.undoMenuLabel == "Undo Apply Hexed to \(culName)")")
        model.removePartyCustomCondition(name: "Hexed", from: [culOriginal.id])
        culLines.append("custom removal names the step \(model.undoMenuLabel == "Undo Remove Hexed from \(culName)")")
        // A newer unlabeled edit moves the depth: plain "Undo".
        if var c = model.selected?.wrappedValue {
            c.experience += 1
            model.selected?.wrappedValue = c
        }
        culLines.append("newer unlabeled edit falls back \(model.undoMenuLabel == "Undo")")
        // The round-wrap tick names its step and actually ends the
        // 1-round condition. Two rolled entries make the wrap real.
        model.applyPartyCondition(.poisoned, rounds: 1, from: [culOriginal.id])
        model.clearInitiative()
        model.addInitiativeEntry(name: "Tick proof A", bonus: 0)
        model.addInitiativeEntry(name: "Tick proof B", bonus: 0)
        model.rollInitiative()
        model.initiative.activeID = model.initiative.rolledOrder.last?.id
        model.advanceInitiative()
        culLines.append("wrap tick names the step \(model.undoMenuLabel == "Undo Tick condition timers on \(culName)")")
        culLines.append("tick ended the 1-round condition \(model.selected?.wrappedValue.conditions.contains(.poisoned) == false)")
        model.undo()
        culLines.append("after tick undo the menu falls back \(model.undoMenuLabel == "Undo")")
        // Hygiene: roster and tracker back to their fixture state.
        model.characters[culIdx] = culOriginal
        try? model.store.save(culOriginal)
        model.initiative = culOriginalInitiative
        model.initiativeStore.save(culOriginalInitiative)
        culLines.append("hygiene: roster and initiative restored")
        try? culLines.joined(separator: "\n")
            .write(to: URL(fileURLWithPath: "\(outDir)/condition-undo-label.txt"),
                   atomically: true, encoding: .utf8)
    }
    // 3.71.0: a NEW incapacitating condition ends concentration on
    // landing through the shared party-apply walk, with the damage
    // path's notes milestone; undo restores both; refresh does not
    // re-fire; removal never restores a lost concentration. Runs at
    // the end like every AppModel proof; the roster is restored after.
    do {
        let icIdx = model.characters.firstIndex(where: { $0.id == model.selectedID }) ?? 0
        let icOriginal = model.characters[icIdx]
        var icLines = ["Incapacitation breaks concentration (3.71.0)",
                       "a new incapacitating state ends concentration on landing; refresh and removal never touch it"]
        func icConcentrate(_ spell: String) {
            if var c = model.selected?.wrappedValue {
                c.beginConcentration(on: spell)
                model.selected?.wrappedValue = c
            }
        }
        // New apply of a breaking state: concentration ends, milestone lands.
        icConcentrate("Ember Shield")
        model.applyPartyCondition(.stunned, rounds: nil, from: [icOriginal.id])
        let icAfterStun = model.selected?.wrappedValue
        icLines.append("stunned apply ends concentration \(icAfterStun?.concentratingOn == nil && (icAfterStun?.notes.contains("Lost concentration on Ember Shield.") ?? false))")
        // Undo restores the condition and the concentration together.
        model.undo()
        let icAfterUndo = model.selected?.wrappedValue
        icLines.append("undo restores condition and concentration together \(icAfterUndo?.conditions.contains(.stunned) == false && icAfterUndo?.concentratingOn == "Ember Shield")")
        // A non-breaking state leaves concentration alone.
        model.applyPartyCondition(.prone, rounds: nil, from: [icOriginal.id])
        let icAfterProne = model.selected?.wrappedValue
        icLines.append("prone leaves concentration \(icAfterProne?.concentratingOn == "Ember Shield" && icAfterProne?.conditions.contains(.prone) == true)")
        model.removePartyCondition(.prone, from: [icOriginal.id])
        // Customs never break concentration.
        model.applyPartyCustomCondition(name: "Dazed", rounds: nil, from: [icOriginal.id])
        let icAfterCustom = model.selected?.wrappedValue
        icLines.append("custom condition leaves concentration \(icAfterCustom?.concentratingOn == "Ember Shield" && (icAfterCustom?.customConditions.contains { $0.name == "Dazed" } ?? false))")
        model.removePartyCustomCondition(name: "Dazed", from: [icOriginal.id])
        // Refresh of a held state does not re-fire the break. The held
        // state is planted by direct mutation (the raw editing path),
        // which deliberately bypasses the play-time break.
        if var c = model.selected?.wrappedValue {
            c.conditions.insert(.paralyzed)
            c.beginConcentration(on: "Ward of Stone")
            model.selected?.wrappedValue = c
        }
        model.applyPartyCondition(.paralyzed, rounds: 3, from: [icOriginal.id])
        let icAfterRefresh = model.selected?.wrappedValue
        icLines.append("timer refresh does not re-fire the break \(icAfterRefresh?.concentratingOn == "Ward of Stone" && !(icAfterRefresh?.notes.contains("Lost concentration on Ward of Stone.") ?? true))")
        if var c = model.selected?.wrappedValue {
            c.conditions.remove(.paralyzed)
            c.conditionDurations.removeValue(forKey: Condition.paralyzed.rawValue)
            c.dropConcentration()
            model.selected?.wrappedValue = c
        }
        // Removal never restores a lost concentration.
        icConcentrate("Last Light")
        model.applyPartyCondition(.unconscious, rounds: nil, from: [icOriginal.id])
        model.removePartyCondition(.unconscious, from: [icOriginal.id])
        let icAfterRemoval = model.selected?.wrappedValue
        icLines.append("removal never restores a lost concentration \(icAfterRemoval?.concentratingOn == nil && icAfterRemoval?.conditions.contains(.unconscious) == false && (icAfterRemoval?.notes.contains("Lost concentration on Last Light.") ?? false))")
        // The party-wide path shares the same walk: one proof through it.
        icConcentrate("Full Chorus")
        model.applyPartyCondition(.paralyzed, rounds: nil)
        let icAfterParty = model.selected?.wrappedValue
        icLines.append("party-path apply breaks the same way \(icAfterParty?.concentratingOn == nil && icAfterParty?.conditions.contains(.paralyzed) == true && (icAfterParty?.notes.contains("Lost concentration on Full Chorus.") ?? false))")
        model.removePartyCondition(.paralyzed)
        // Hygiene: roster back to its fixture state.
        model.characters[icIdx] = icOriginal
        try? model.store.save(icOriginal)
        icLines.append("hygiene: roster restored")
        try? icLines.joined(separator: "\n")
            .write(to: URL(fileURLWithPath: "\(outDir)/incapacitate-concentration.txt"),
                   atomically: true, encoding: .utf8)
    }
    // 3.72.0: end-of-turn save-ends conditions. The outgoing active
    // entry's saves roll on ANY turn handoff (a mid-round handoff is
    // proven, not only wraps); a success ends the condition with both
    // milestone lines, a failure persists; undo restores the pre-save
    // state in one snapshot. Runs at the end like every AppModel proof;
    // the roster, the tracker, and the roll history are restored after.
    seProof: do {
        let seOriginalInitiative = model.initiative
        let seOriginalHistory = model.rollHistory
        let seIdx = model.characters.firstIndex(where: { $0.id == model.selectedID }) ?? 0
        let seOriginal = model.characters[seIdx]
        let seName = seOriginal.name
        guard let seB = model.characters.first(where: { $0.id != seOriginal.id }) else { break seProof }
        let seFKey = Condition.frightened.rawValue
        let sePKey = Condition.poisoned.rawValue
        let seSKey = Condition.stunned.rawValue
        var seLines = ["Save-ends conditions (3.72.0)",
                       "a marked condition offers a save when the holder's turn ends; a success ends it",
                       "deterministic by construction: WIS save +5 (16 WIS + proficiency at L1) -",
                       "  success forced: worst d20 1 + 5 = 6 >= DC 1; failure forced: best d20 20 + 5 = 25 < DC 99",
                       "  (DC 99 beats even the best possible save bonus: 20 + 11 = 31 < 99)"]
        // Pin: the sheet Save-ends editor rides the normal edit/undo
        // path - set, undo, redo, clear - each leaving durations and
        // notes untouched. Driven through the same selected-binding
        // write the UI rows use.
        if var c = model.selected?.wrappedValue {
            c.conditions.insert(.frightened)
            c.conditionDurations[seFKey] = 5
            c.conditionNotes[seFKey] = "wraith shriek"
            model.selected?.wrappedValue = c
        }
        if var c = model.selected?.wrappedValue {
            c.conditionSaveEnds[seFKey] = ConditionSaveEnd(dc: 12, ability: .wisdom)
            model.selected?.wrappedValue = c
        }
        seLines.append("editor set marks the save \(model.selected?.wrappedValue.conditionSaveEnds[seFKey]?.dc == 12)")
        model.undo()
        seLines.append("editor undo unmarks it \(model.selected?.wrappedValue.conditionSaveEnds[seFKey] == nil)")
        model.redo()
        seLines.append("editor redo remarks it \(model.selected?.wrappedValue.conditionSaveEnds[seFKey]?.dc == 12)")
        if var c = model.selected?.wrappedValue {
            c.conditionSaveEnds.removeValue(forKey: seFKey)
            model.selected?.wrappedValue = c
        }
        let seAfterClear = model.selected?.wrappedValue
        seLines.append("editor clear removes the mark \(seAfterClear?.conditionSaveEnds[seFKey] == nil)")
        seLines.append("editor steps leave duration and note untouched \(seAfterClear?.conditionDurations[seFKey] == 5 && seAfterClear?.conditionNotes[seFKey] == "wraith shriek")")
        // Walk fixture: Frightened (DC 1 WIS - ends), a custom Hexed
        // (DC 1 WIS - ends through the custom branch), Poisoned (DC 99
        // WIS - persists), and a stale Stunned key (absent - rolls
        // nothing). One binding write plants the lot.
        let seHexed = CustomCondition(name: "Hexed")
        if var c = model.selected?.wrappedValue {
            c.scores = AbilityScores(Dictionary(uniqueKeysWithValues: Ability.allCases.map { ($0, $0 == .wisdom ? 16 : 10) }))
            c.savingThrowProficiencies.insert(.wisdom)
            c.conditions.insert(.poisoned)
            c.conditionDurations[sePKey] = 2
            c.customConditions.append(seHexed)
            c.conditionSaveEnds[seFKey] = ConditionSaveEnd(dc: 1, ability: .wisdom)
            c.conditionSaveEnds[seHexed.id.uuidString] = ConditionSaveEnd(dc: 1, ability: .wisdom)
            c.conditionSaveEnds[sePKey] = ConditionSaveEnd(dc: 99, ability: .wisdom)
            c.conditionSaveEnds[seSKey] = ConditionSaveEnd(dc: 1, ability: .wisdom)
            model.selected?.wrappedValue = c
        }
        // Deterministic tracker: A 20, an unlinked scout 15, B 10; A is
        // active, so the first advance is a MID-ROUND handoff off A.
        model.clearInitiative()
        model.addInitiativeEntry(name: seName, bonus: 0, forCharacter: seName)
        model.addInitiativeEntry(name: "Scout (unlinked)", bonus: 0)
        model.addInitiativeEntry(name: seB.name, bonus: 0, forCharacter: seB.name)
        for i in model.initiative.entries.indices {
            let n = model.initiative.entries[i].name
            model.initiative.entries[i].total = n == seName ? 20 : (n == seB.name ? 10 : 15)
        }
        model.initiative.activeID = model.initiative.entries.first(where: { $0.name == seName })?.id
        let seRoundBefore = model.initiative.round
        model.advanceInitiative()
        let seA1 = model.selected?.wrappedValue
        seLines.append("mid-round handoff triggers the walk \(model.initiative.round == seRoundBefore && (seA1?.notes.contains("Save vs Frightened (DC 1):") ?? false))")
        seLines.append("frightened ends on success with both milestones \(seA1?.conditions.contains(.frightened) == false && (seA1?.notes.contains("Save vs Frightened (DC 1):") ?? false) && (seA1?.notes.contains(" - success.") ?? false) && (seA1?.notes.contains("Frightened ended (save).") ?? false))")
        seLines.append("success clears the duration, note, and save keys \(seA1?.conditionDurations[seFKey] == nil && seA1?.conditionNotes[seFKey] == nil && seA1?.conditionSaveEnds[seFKey] == nil)")
        seLines.append("custom hexed ends through the same walk \(seA1?.customConditions.contains { $0.name == "Hexed" } == false && (seA1?.notes.contains("Hexed ended (save).") ?? false) && seA1?.conditionSaveEnds[seHexed.id.uuidString] == nil)")
        seLines.append("poisoned fails and persists with its own milestone \(seA1?.conditions.contains(.poisoned) == true && (seA1?.notes.contains("Save vs Poisoned (DC 99):") ?? false) && (seA1?.notes.contains(" - failure.") ?? false))")
        seLines.append("failure leaves the timer and the save mark in place \(seA1?.conditionDurations[sePKey] == 2 && seA1?.conditionSaveEnds[sePKey]?.dc == 99)")
        seLines.append("independent resolves in one advance: one ended, one persists \(seA1?.conditions.contains(.frightened) == false && seA1?.conditions.contains(.poisoned) == true)")
        seLines.append("stale key rolls nothing and stays \(seA1?.notes.contains("Save vs Stunned") == false && seA1?.conditionSaveEnds[seSKey]?.dc == 1)")
        seLines.append("saves land in dice history \(model.rollHistory.contains { $0.label?.hasPrefix("Save vs Frightened") == true } && model.rollHistory.contains { $0.label?.hasPrefix("Save vs Poisoned") == true })")
        seLines.append("edit menu names the walk \(model.undoMenuLabel == "Undo Roll end-of-turn saves on \(seName)")")
        // Undo restores the pre-save state in one snapshot check.
        model.undo()
        let seAU = model.selected?.wrappedValue
        let seUndoOK = seAU?.conditions.contains(.frightened) == true
            && seAU?.conditions.contains(.poisoned) == true
            && (seAU?.customConditions.contains { $0.name == "Hexed" } ?? false)
            && seAU?.conditionSaveEnds.count == 4
            && seAU?.conditionDurations[seFKey] == 5
            && seAU?.conditionNotes[seFKey] == "wraith shriek"
            && !(seAU?.notes.contains("Save vs") ?? true)
        seLines.append("undo restores the pre-save state in one snapshot \(seUndoOK)")
        model.redo()
        let seAR = model.selected?.wrappedValue
        seLines.append("redo re-applies the walk outcome \(seAR?.conditions.contains(.frightened) == false && seAR?.conditions.contains(.poisoned) == true)")
        // Outgoing is the unlinked scout next: nothing rolls.
        let seHistCount = model.rollHistory.count
        model.advanceInitiative()
        seLines.append("unlinked entry rolls nothing \(model.rollHistory.count == seHistCount && model.initiative.round == seRoundBefore)")
        // Outgoing is B (no save-ends): the advance wraps, the timer
        // ticks, and no extra save fires for A.
        model.advanceInitiative()
        let seAW = model.selected?.wrappedValue
        seLines.append("wrap coexists: timer ticks, no extra save \(model.initiative.round == seRoundBefore + 1 && seAW?.conditionDurations[sePKey] == 1 && (seAW?.notes.components(separatedBy: "Save vs Poisoned").count ?? 0) == 2)")
        // Hygiene: roster, tracker, and history back to fixture state.
        model.characters[seIdx] = seOriginal
        try? model.store.save(seOriginal)
        model.initiative = seOriginalInitiative
        model.initiativeStore.save(seOriginalInitiative)
        model.rollHistory = seOriginalHistory
        model.rollHistoryStore.save(seOriginalHistory)
        seLines.append("hygiene: roster, initiative, and history restored")
        try? seLines.joined(separator: "\n")
            .write(to: URL(fileURLWithPath: "\(outDir)/saveends.txt"),
                   atomically: true, encoding: .utf8)
    }
    // 3.73.0 condition immunity by lineage: derived lineage grants and
    // the stored set both stop a NEW apply on every party path; a holder
    // who already has the condition still refreshes; nothing is stored
    // for the derived grant. Roster and log restored after.
    ciProof: do {
        let ciOrigChars = model.characters
        let ciOrigLog = model.tableLog
        guard model.characters.count >= 2 else { break ciProof }
        let ciAIdx = model.characters.firstIndex(where: { $0.id == model.selectedID }) ?? 0
        let ciBIdx = model.characters.firstIndex(where: { $0.id != model.selectedID }) ?? 1
        let ciAId = model.characters[ciAIdx].id
        let ciBId = model.characters[ciBIdx].id
        let ciAName = model.characters[ciAIdx].name
        let ciBName = model.characters[ciBIdx].name
        model.characters[ciAIdx].lineage = "High Elf"
        model.characters[ciAIdx].conditions = []
        model.characters[ciAIdx].conditionImmunities = [.charmed]
        model.characters[ciBIdx].lineage = "Warforged Scout"
        model.characters[ciBIdx].conditions = []
        model.characters[ciBIdx].conditionImmunities = []
        var ciLines = ["Condition immunity by lineage (3.73.0)",
                       "lineage text grants derived immunities (Warforged -> poisoned); a stored set adds more; a new apply on an immune holder does nothing",
                       "deterministic by construction: fixture lineages are forced (A: High Elf + stored charmed; B: Warforged Scout)"]
        ciLines.append("derived grant reads from lineage text \(ConditionImmunity.lineageGrants("Warforged Scout") == [.poisoned] && ConditionImmunity.lineageGrants("Warforged Scout") == model.characters[ciBIdx].allConditionImmunities)")
        ciLines.append("keyword match is case-insensitive and substring \(ConditionImmunity.lineageGrants("the UNDEAD knight") == [.poisoned])")
        ciLines.append("no grant for an unrelated lineage \(ConditionImmunity.lineageGrants("High Elf").isEmpty && model.characters[ciAIdx].conditionImmunitySource(.poisoned) == nil)")
        ciLines.append("source labels: lineage vs set \(model.characters[ciBIdx].conditionImmunitySource(.poisoned) == "lineage" && model.characters[ciAIdx].conditionImmunitySource(.charmed) == "set")")
        // Party-wide poisoned: A takes it, B (derived immune) is blocked.
        let ciMenuBefore = model.undoMenuLabel
        let ciBBefore = model.characters[ciBIdx]
        let ciR1 = model.applyPartyCondition(.poisoned, rounds: 3, note: "bad stew")
        let ciA1 = model.characters[ciAIdx]
        let ciB1 = model.characters[ciBIdx]
        ciLines.append("party apply: non-immune takes it \(ciA1.conditions.contains(.poisoned) && ciR1.applied.contains(ciAName))")
        ciLines.append("party apply: lineage-immune blocked, reported \(!ciB1.conditions.contains(.poisoned) && ciR1.immune == [ciBName] && !ciR1.applied.contains(ciBName))")
        ciLines.append("blocked holder is left byte-identical: no condition, timer, or note \(ciB1 == ciBBefore && ciB1.conditionDurations[Condition.poisoned.rawValue] == nil && ciB1.conditionNotes[Condition.poisoned.rawValue] == nil)")
        ciLines.append("log names the immune holder \(model.tableLog.last?.text.contains("(immune: \(ciBName))") == true)")
        _ = ciMenuBefore
        // Stored-set path, targeted to A alone: fully blocked -> blocked log.
        let ciLogCount = model.tableLog.count
        let ciR2 = model.applyPartyCondition(.charmed, rounds: 2, from: [ciAId])
        ciLines.append("targeted apply: stored-set immune blocked \(ciR2.immune == [ciAName] && ciR2.applied.isEmpty && !(model.characters[ciAIdx].conditions.contains(.charmed)))")
        ciLines.append("all-immune apply writes one blocked log line \(model.tableLog.count == ciLogCount + 1 && model.tableLog.last?.text == "Charmed blocked (immune): \(ciAName)")")
        // The same condition lands on the non-immune holder.
        let ciR3 = model.applyPartyCondition(.charmed, rounds: 2, from: [ciBId])
        ciLines.append("same condition lands on a non-immune holder \(ciR3.applied == [ciBName] && model.characters[ciBIdx].conditions.contains(.charmed) && ciR3.immune.isEmpty)")
        // Already-held override refreshes despite immunity.
        model.characters[ciBIdx].conditions.insert(.poisoned)
        model.characters[ciBIdx].conditionDurations[Condition.poisoned.rawValue] = 1
        let ciR4 = model.applyPartyCondition(.poisoned, rounds: 4, from: [ciBId])
        ciLines.append("held-by-override still refreshes \(ciR4.refreshed == [ciBName] && ciR4.immune.isEmpty && model.characters[ciBIdx].conditionDurations[Condition.poisoned.rawValue] == 4)")
        // Derived, never stored: clear the lineage and the grant goes away.
        model.characters[ciBIdx].conditions.remove(.poisoned)
        model.characters[ciBIdx].conditionDurations.removeValue(forKey: Condition.poisoned.rawValue)
        ciLines.append("grant is not stored \(model.characters[ciBIdx].conditionImmunities.isEmpty)")
        model.characters[ciBIdx].lineage = "Human"
        let ciR5 = model.applyPartyCondition(.poisoned, rounds: 2, from: [ciBId])
        ciLines.append("editing the lineage drops the grant at once \(ciR5.applied == [ciBName] && ciR5.immune.isEmpty && model.characters[ciBIdx].conditions.contains(.poisoned))")
        // Codable: stored set round-trips, legacy blob decodes empty.
        let ciData = (try? JSONEncoder().encode(model.characters[ciAIdx])) ?? Data()
        let ciBack = try? JSONDecoder().decode(Character.self, from: ciData)
        ciLines.append("stored set round-trips through Codable \(ciBack?.conditionImmunities == [.charmed])")
        var ciObj = (try? JSONSerialization.jsonObject(with: ciData) as? [String: Any]) ?? [:]
        ciObj.removeValue(forKey: "conditionImmunities")
        let ciLegacy = (try? JSONSerialization.data(withJSONObject: ciObj)).flatMap { try? JSONDecoder().decode(Character.self, from: $0) }
        ciLines.append("legacy blob without the key decodes empty \(ciLegacy?.conditionImmunities.isEmpty == true)")
        // Hygiene.
        model.characters = ciOrigChars
        for c in ciOrigChars { try? model.store.save(c) }
        model.tableLog = ciOrigLog
        model.tableLogStore.save(ciOrigLog)
        ciLines.append("hygiene: roster and table log restored \(model.characters == ciOrigChars && model.tableLog.count == ciOrigLog.count)")
        try? ciLines.joined(separator: "\n")
            .write(to: URL(fileURLWithPath: "\(outDir)/condimmune.txt"),
                   atomically: true, encoding: .utf8)
    }
    // 3.74.0 max-HP reduction: a stored drain lowers the derived effective
    // max until a long rest; healing caps there; current HP is pulled under
    // the new ceiling. Sheet editing rides the normal edit/undo path.
    hpProof: do {
        let hpOrigChars = model.characters
        let hpIdx = model.characters.firstIndex(where: { $0.id == model.selectedID }) ?? 0
        var hpBase = model.characters[hpIdx]
        hpBase.maxHP = 32
        hpBase.currentHP = 24
        hpBase.tempHP = 5
        hpBase.maxHPReduction = 0
        // Seed through the selected binding so the undo stack's baseline is
        // the fixture (a direct roster write would leave it stale).
        model.selected?.wrappedValue = hpBase
        var hpLines = ["Max-HP reduction (3.74.0)",
                       "a drain lowers the effective max HP until a long rest; healing caps at it; long rest lifts it",
                       "deterministic by construction: fixture is max 32, current 24, temp 5; every step is integer arithmetic"]
        var c = hpBase
        hpLines.append("no drain: effective max equals stored max \(c.effectiveMaxHP == 32 && c.maxHPReduction == 0)")
        c.setMaxHPReduction(10)
        hpLines.append("drain 10 lowers the effective max to 22 \(c.effectiveMaxHP == 22 && c.maxHP == 32)")
        hpLines.append("current HP pulled under the new ceiling (24 -> 22) \(c.currentHP == 22)")
        hpLines.append("temp HP untouched by the drain \(c.tempHP == 5)")
        c.currentHP = 10
        c.applyHealing(100)
        hpLines.append("healing caps at the drained max, not the stored max \(c.currentHP == 22)")
        c.setMaxHPReduction(4)
        hpLines.append("lowering the drain raises the ceiling (28) but not current HP (22) \(c.effectiveMaxHP == 28 && c.currentHP == 22)")
        c.applyHealing(100)
        hpLines.append("healing then fills the restored room \(c.currentHP == 28)")
        c.setMaxHPReduction(999)
        hpLines.append("drain clamps at max-1 so the ceiling floors at 1 \(c.maxHPReduction == 31 && c.effectiveMaxHP == 1 && c.currentHP == 1)")
        c.setMaxHPReduction(-5)
        hpLines.append("negative drain clamps to 0 \(c.maxHPReduction == 0 && c.effectiveMaxHP == 32)")
        c.setMaxHPReduction(8)
        c.shortRest()
        hpLines.append("short rest leaves the drain in place \(c.maxHPReduction == 8 && c.effectiveMaxHP == 24)")
        var hpDrained = c
        c.longRest()
        hpLines.append("long rest lifts the drain and restores full HP \(c.maxHPReduction == 0 && c.currentHP == 32 && c.effectiveMaxHP == 32)")
        hpDrained.maxHP = 5
        hpDrained.normalizeHP()
        hpLines.append("lowering the stored max re-clamps drain and current HP (drain 4, max 1) \(hpDrained.maxHPReduction == 4 && hpDrained.effectiveMaxHP == 1 && hpDrained.currentHP == 1)")
        // Surfaces read the derived ceiling.
        var hpSurface = hpBase
        hpSurface.setMaxHPReduction(10)
        hpLines.append("party strip shows the drained max \(PartyCardSummary(character: hpSurface).maxHP == 22)")
        hpLines.append("markdown export shows the drained max \(SheetExporter.exportMarkdown(hpSurface).contains("HP **22/22**"))")
        hpLines.append("html export shows the drained max \(SheetExporter.exportHTML(hpSurface).contains("HP <b>22/22</b>"))")
        hpLines.append("undrained export is unchanged \(SheetExporter.exportMarkdown(hpBase).contains("HP **24/32**"))")
        // Codable.
        let hpData = (try? JSONEncoder().encode(hpSurface)) ?? Data()
        hpLines.append("drain round-trips through Codable \((try? JSONDecoder().decode(Character.self, from: hpData))?.maxHPReduction == 10)")
        var hpObj = (try? JSONSerialization.jsonObject(with: hpData) as? [String: Any]) ?? [:]
        hpObj["maxHPReduction"] = 999
        let hpClamped = (try? JSONSerialization.data(withJSONObject: hpObj)).flatMap { try? JSONDecoder().decode(Character.self, from: $0) }
        hpLines.append("an absurd stored drain decodes clamped to max-1 \(hpClamped?.maxHPReduction == 31)")
        hpObj.removeValue(forKey: "maxHPReduction")
        let hpLegacy = (try? JSONSerialization.data(withJSONObject: hpObj)).flatMap { try? JSONDecoder().decode(Character.self, from: $0) }
        hpLines.append("legacy blob without the key decodes undrained \(hpLegacy?.maxHPReduction == 0)")
        // Editor rides the normal edit/undo path, set / undo / redo / clear.
        if var e = model.selected?.wrappedValue { e.setMaxHPReduction(10); model.selected?.wrappedValue = e }
        hpLines.append("editor set drains \(model.selected?.wrappedValue.effectiveMaxHP == 22 && model.selected?.wrappedValue.currentHP == 22)")
        model.undo()
        hpLines.append("editor undo restores max and current in one snapshot \(model.selected?.wrappedValue.effectiveMaxHP == 32 && model.selected?.wrappedValue.currentHP == 24 && model.selected?.wrappedValue.maxHPReduction == 0)")
        model.redo()
        hpLines.append("editor redo re-drains \(model.selected?.wrappedValue.maxHPReduction == 10 && model.selected?.wrappedValue.currentHP == 22)")
        if var e = model.selected?.wrappedValue { e.setMaxHPReduction(0); model.selected?.wrappedValue = e }
        hpLines.append("editor clear lifts the drain, current HP stays \(model.selected?.wrappedValue.maxHPReduction == 0 && model.selected?.wrappedValue.currentHP == 22)")
        model.characters = hpOrigChars
        for ch in hpOrigChars { try? model.store.save(ch) }
        hpLines.append("hygiene: roster restored \(model.characters == hpOrigChars)")
        try? hpLines.joined(separator: "\n")
            .write(to: URL(fileURLWithPath: "\(outDir)/maxhpdrain.txt"),
                   atomically: true, encoding: .utf8)
    }
    // 3.75.0 drain-on-damage: a drain-tagged type lowers the max HP by the
    // HP the hit actually took (after defenses and temp HP, never past 0)
    // through the same apply path as any damage roll.
    ddProof: do {
        let ddOrigChars = model.characters
        let ddOrigLog = model.tableLog
        let ddIdx = model.characters.firstIndex(where: { $0.id == model.selectedID }) ?? 0
        let ddName = model.characters[ddIdx].name
        func ddSeed(cur: Int = 24, temp: Int = 0, resist: Set<DamageType> = [], immune: Set<DamageType> = [], tags: Set<DamageType> = [.necrotic]) {
            var c = model.characters[ddIdx]
            c.maxHP = 32; c.currentHP = cur; c.tempHP = temp; c.maxHPReduction = 0
            c.resistances = resist; c.immunities = immune; c.vulnerabilities = []
            c.drainDamageTypes = tags
            model.selected?.wrappedValue = c
        }
        func ddRoll(_ total: Int, _ type: String?) -> RollResult {
            RollResult(expression: "1d1+\(total - 1)", dice: [DieResult(sides: 1, value: 1, kept: true)], modifier: total - 1, total: total,
                       alternateTotal: nil, label: "drain proof",
                       reroll: type.map { RerollSpec(kind: .outgoingDamage, damageType: $0) })
        }
        var ddLines = ["Drain on damage (3.75.0)",
                       "a drain-tagged damage type also lowers max HP by the HP the hit actually took",
                       "deterministic by construction: crafted rolls with fixed totals; fixture max 32, current 24, no temp HP, defenses cleared unless a step sets them"]
        // Untagged type: no drain.
        ddSeed()
        model.applyRollToHP(ddRoll(4, "fire"), healing: false)
        var dd = model.characters[ddIdx]
        ddLines.append("an untagged type never drains \(dd.currentHP == 20 && dd.maxHPReduction == 0)")
        // Tagged: drains by damage dealt, one log line.
        ddSeed()
        let ddLogBefore = model.tableLog.count
        model.applyRollToHP(ddRoll(8, "necrotic"), healing: false)
        dd = model.characters[ddIdx]
        ddLines.append("tagged hit drains by the damage dealt (8) \(dd.currentHP == 16 && dd.maxHPReduction == 8 && dd.effectiveMaxHP == 24)")
        ddLines.append("one log line names the drain \(model.tableLog.count == ddLogBefore + 1 && model.tableLog.last?.title == "Max HP drain" && model.tableLog.last?.text == "\(ddName) -8 max HP (necrotic, max now 24)")")
        ddLines.append("edit menu still names the HP apply \(model.undoMenuLabel.hasPrefix("Undo"))")
        model.undo()
        dd = model.characters[ddIdx]
        ddLines.append("undo restores HP and drain in one snapshot \(dd.currentHP == 24 && dd.maxHPReduction == 0)")
        model.redo()
        dd = model.characters[ddIdx]
        ddLines.append("redo re-applies damage and drain \(dd.currentHP == 16 && dd.maxHPReduction == 8)")
        // Hits accumulate.
        model.applyRollToHP(ddRoll(5, "necrotic"), healing: false)
        dd = model.characters[ddIdx]
        ddLines.append("a second hit accumulates the drain (8+5) \(dd.maxHPReduction == 13 && dd.effectiveMaxHP == 19 && dd.currentHP == 11)")
        // Derived from what was dealt: resistance halves it.
        ddSeed(resist: [.necrotic])
        model.applyRollToHP(ddRoll(8, "necrotic"), healing: false)
        dd = model.characters[ddIdx]
        ddLines.append("resistance halves the hit and the drain (8 -> 4) \(dd.maxHPReduction == 4 && dd.currentHP == 20)")
        // Temp HP absorbs first, only real HP drains.
        ddSeed(temp: 5)
        model.applyRollToHP(ddRoll(8, "necrotic"), healing: false)
        dd = model.characters[ddIdx]
        ddLines.append("temp HP absorbs first, drain is only the 3 that reached HP \(dd.tempHP == 0 && dd.maxHPReduction == 3 && dd.currentHP == 21)")
        // Overkill: damage past 0 does not drain.
        ddSeed(cur: 2)
        model.applyRollToHP(ddRoll(10, "necrotic"), healing: false)
        dd = model.characters[ddIdx]
        ddLines.append("damage past 0 does not drain (2 taken, not 10) \(dd.currentHP == 0 && dd.maxHPReduction == 2)")
        // Immunity: nothing dealt, nothing drained, no log, no snapshot.
        ddSeed(immune: [.necrotic])
        let ddImmuneLog = model.tableLog.count
        let ddImmuneBefore = model.characters[ddIdx]
        model.applyRollToHP(ddRoll(9, "necrotic"), healing: false)
        ddLines.append("immune: no damage, no drain, no log \(model.characters[ddIdx] == ddImmuneBefore && model.tableLog.count == ddImmuneLog)")
        // Untyped roll with the tag set: nothing.
        ddSeed()
        model.applyRollToHP(ddRoll(6, nil), healing: false)
        dd = model.characters[ddIdx]
        ddLines.append("an untyped hit never drains \(dd.currentHP == 18 && dd.maxHPReduction == 0)")
        // Healing never drains or logs.
        ddSeed(cur: 10)
        let ddHealLog = model.tableLog.count
        model.applyRollToHP(ddRoll(6, "necrotic"), healing: true)
        dd = model.characters[ddIdx]
        ddLines.append("healing is not a drain \(dd.currentHP == 16 && dd.maxHPReduction == 0 && model.tableLog.count == ddHealLog)")
        // Clamp: the drain floors the ceiling at 1.
        ddSeed(cur: 32)
        model.applyRollToHP(ddRoll(32, "necrotic"), healing: false)
        dd = model.characters[ddIdx]
        ddLines.append("a full-HP wipe drains 32 but clamps at max-1 (31, ceiling 1) \(dd.maxHPReduction == 31 && dd.effectiveMaxHP == 1 && dd.currentHP == 0)")
        // Long rest lifts.
        dd.longRest()
        ddLines.append("long rest lifts a damage drain too \(dd.maxHPReduction == 0 && dd.currentHP == 32)")
        // Codable.
        ddSeed()
        let ddData = (try? JSONEncoder().encode(model.characters[ddIdx])) ?? Data()
        ddLines.append("tag set round-trips through Codable \((try? JSONDecoder().decode(Character.self, from: ddData))?.drainDamageTypes == [.necrotic])")
        var ddObj = (try? JSONSerialization.jsonObject(with: ddData) as? [String: Any]) ?? [:]
        ddObj.removeValue(forKey: "drainDamageTypes")
        let ddLegacy = (try? JSONSerialization.data(withJSONObject: ddObj)).flatMap { try? JSONDecoder().decode(Character.self, from: $0) }
        ddLines.append("legacy blob without the key decodes empty \(ddLegacy?.drainDamageTypes.isEmpty == true)")
        // Hygiene.
        model.characters = ddOrigChars
        for ch in ddOrigChars { try? model.store.save(ch) }
        model.tableLog = ddOrigLog
        model.tableLogStore.save(ddOrigLog)
        ddLines.append("hygiene: roster and table log restored \(model.characters == ddOrigChars && model.tableLog.count == ddOrigLog.count)")
        try? ddLines.joined(separator: "\n")
            .write(to: URL(fileURLWithPath: "\(outDir)/drainondamage.txt"),
                   atomically: true, encoding: .utf8)
    }
    // 3.76.0 typed party damage: the party damage path takes an optional
    // type and routes each character through the typed applyDamage.
    ptProof: do {
        let ptOrigChars = model.characters
        let ptOrigLog = model.tableLog
        guard model.characters.count >= 2 else { break ptProof }
        // The party path hits the WHOLE roster, so the proof narrows the roster
        // to exactly two (selected first, then one other); restored after.
        guard let ptA = model.characters.first(where: { $0.id == model.selectedID }),
              let ptB = model.characters.first(where: { $0.id != model.selectedID }) else { break ptProof }
        model.characters = [ptA, ptB]
        let ptAIdx = 0
        let ptBIdx = 1
        let ptAName = model.characters[ptAIdx].name
        let ptBName = model.characters[ptBIdx].name
        func ptSeed(aResist: Set<DamageType> = [], bImmune: Set<DamageType> = [], aDrain: Set<DamageType> = []) {
            for i in [ptAIdx, ptBIdx] {
                model.characters[i].maxHP = 32; model.characters[i].currentHP = 30; model.characters[i].tempHP = 0
                model.characters[i].maxHPReduction = 0
                model.characters[i].resistances = []; model.characters[i].immunities = []; model.characters[i].vulnerabilities = []
                model.characters[i].drainDamageTypes = []
            }
            model.characters[ptAIdx].resistances = aResist
            model.characters[ptAIdx].drainDamageTypes = aDrain
            model.characters[ptBIdx].immunities = bImmune
        }
        var ptLines = ["Typed party damage (3.76.0)",
                       "the party damage button takes an optional type: resist / immune / vuln and drain tags apply per character; a typed hit writes one log line",
                       "deterministic by construction: two roster characters forced to max 32, current 30, no temp HP; defenses set per step"]
        ptSeed(aResist: [.fire])
        var ptLogN = model.tableLog.count
        let ptNamed = model.adjustPartyHP(amount: 10, damage: true, type: .fire)
        ptLines.append("resistance halves for the resistant character only \(model.characters[ptAIdx].currentHP == 25 && model.characters[ptBIdx].currentHP == 20)")
        ptLines.append("both changed characters are returned \(Set(ptNamed) == Set([ptAName, ptBName]))")
        ptLines.append("one log line names who took what \(model.tableLog.count == ptLogN + 1 && model.tableLog.last?.title == "Party damage" && model.tableLog.last?.text == "10 fire: \(ptAName) -5, \(ptBName) -10")")
        // Immunity.
        ptSeed(bImmune: [.poison])
        ptLogN = model.tableLog.count
        let ptImmuneNamed = model.adjustPartyHP(amount: 10, damage: true, type: .poison)
        ptLines.append("an immune character takes nothing and is named immune \(model.characters[ptBIdx].currentHP == 30 && model.tableLog.last?.text == "10 poison: \(ptAName) -10, \(ptBName) immune")")
        ptLines.append("an immune character is not returned as adjusted \(ptImmuneNamed == [ptAName])")
        // Drain tag rides the typed path.
        ptSeed(aDrain: [.necrotic])
        model.adjustPartyHP(amount: 8, damage: true, type: .necrotic)
        ptLines.append("a drain-tagged character also loses max HP \(model.characters[ptAIdx].maxHPReduction == 8 && model.characters[ptBIdx].maxHPReduction == 0)")
        ptLines.append("the log line carries the drain \(model.tableLog.last?.text == "8 necrotic: \(ptAName) -8 (max -8), \(ptBName) -8")")
        // Untyped: legacy behavior, silent.
        ptSeed(aResist: [.fire], aDrain: [.necrotic])
        ptLogN = model.tableLog.count
        model.adjustPartyHP(amount: 10, damage: true)
        ptLines.append("untyped party damage ignores defenses and drain tags \(model.characters[ptAIdx].currentHP == 20 && model.characters[ptBIdx].currentHP == 20 && model.characters[ptAIdx].maxHPReduction == 0)")
        ptLines.append("untyped party damage writes no log line, as before \(model.tableLog.count == ptLogN)")
        // Healing ignores the type and logs nothing.
        ptLogN = model.tableLog.count
        model.adjustPartyHP(amount: 5, damage: false, type: .fire)
        ptLines.append("healing ignores the type and writes no log line \(model.characters[ptAIdx].currentHP == 25 && model.tableLog.count == ptLogN)")
        // Everyone immune: no log at all? (immune parts still log) - documented.
        ptSeed(bImmune: [.cold])
        model.characters[ptAIdx].immunities = [.cold]
        ptLogN = model.tableLog.count
        let ptAllImmune = model.adjustPartyHP(amount: 9, damage: true, type: .cold)
        ptLines.append("all-immune hit changes nobody yet still logs who was immune \(ptAllImmune.isEmpty && model.tableLog.count == ptLogN + 1 && model.tableLog.last?.text == "9 cold: \(ptAName) immune, \(ptBName) immune")")
        model.characters = ptOrigChars
        for ch in ptOrigChars { try? model.store.save(ch) }
        model.tableLog = ptOrigLog
        model.tableLogStore.save(ptOrigLog)
        ptLines.append("hygiene: roster and table log restored \(model.characters == ptOrigChars && model.tableLog.count == ptOrigLog.count)")
        try? ptLines.joined(separator: "\n")
            .write(to: URL(fileURLWithPath: "\(outDir)/partytyped.txt"),
                   atomically: true, encoding: .utf8)
    }
    // 3.77.0 drain chip: drained characters show "Max -N" on the party
    // strip card and the party detail row, derived from the stored drain.
    dcProof: do {
        guard var dcBase = model.characters.first else { break dcProof }
        dcBase.maxHP = 32; dcBase.currentHP = 30; dcBase.tempHP = 0
        dcBase.conditions = []; dcBase.customConditions = []; dcBase.concentratingOn = nil
        dcBase.conditionDurations = [:]; dcBase.conditionNotes = [:]
        dcBase.maxHPReduction = 0
        var dcLines = ["Drain chip (3.77.0)",
                       "a drained character carries a last chip \"Max -N\" on the party strip and detail row; undrained characters are unchanged",
                       "deterministic by construction: one fixture character, no conditions, forced max 32 / current 30"]
        dcLines.append("undrained strip has no drain chip \(PartyCardSummary(character: dcBase).drainChip == nil && !PartyCardSummary(character: dcBase).chips.contains { $0.hasPrefix("Max -") })")
        dcLines.append("undrained detail row has no drain chip \(!(partyDetailRows([dcBase]).first?.chips.contains { $0.text.hasPrefix("Max -") } ?? true))")
        var dcDrained = dcBase
        dcDrained.setMaxHPReduction(8)
        let dcStrip = PartyCardSummary(character: dcDrained)
        dcLines.append("drained strip card pins the chip outside the chip list \(dcStrip.drainChip == "Max -8" && dcStrip.chips.isEmpty && dcStrip.maxHP == 24 && dcStrip.currentHP == 24)")
        let dcRow = partyDetailRows([dcDrained]).first
        dcLines.append("drained detail row shows the chip \(dcRow?.chips.map(\.text) == ["Max -8"] && dcRow?.maxHP == 24)")
        var dcBusy = dcDrained
        dcBusy.conditions.insert(.prone)
        dcBusy.concentratingOn = "Hold Person"
        dcLines.append("the detail chip rides last; the strip chip never enters the overflow \(PartyCardSummary(character: dcBusy).drainChip == "Max -8" && !PartyCardSummary(character: dcBusy).chips.contains { $0.hasPrefix("Max -") } && partyDetailRows([dcBusy]).first?.chips.last?.text == "Max -8")")
        dcBusy.setMaxHPReduction(15)
        dcLines.append("the chip follows the stored drain \(PartyCardSummary(character: dcBusy).drainChip == "Max -15")")
        dcBusy.longRest()
        dcLines.append("long rest clears the chip \(PartyCardSummary(character: dcBusy).drainChip == nil)")
        try? dcLines.joined(separator: "\n")
            .write(to: URL(fileURLWithPath: "\(outDir)/drainchip.txt"),
                   atomically: true, encoding: .utf8)
    }
    // 3.78.0 partial restore: lift drain by N on the roster or a subset.
    rmProof: do {
        let rmOrig = model.characters
        let rmOrigLog = model.tableLog
        guard let rmA = model.characters.first(where: { $0.id == model.selectedID }),
              let rmB = model.characters.first(where: { $0.id != model.selectedID }) else { break rmProof }
        model.characters = [rmA, rmB]
        func rmSeed(aDrain: Int, bDrain: Int) {
            for i in 0..<2 {
                model.characters[i].maxHP = 32; model.characters[i].currentHP = 10; model.characters[i].tempHP = 0
            }
            model.characters[0].maxHPReduction = 0; model.characters[1].maxHPReduction = 0
            model.characters[0].setMaxHPReduction(aDrain); model.characters[1].setMaxHPReduction(bDrain)
            model.characters[0].currentHP = 10; model.characters[1].currentHP = 10
        }
        let rmAName = model.characters[0].name, rmBName = model.characters[1].name
        var rmLines = ["Partial restore (3.78.0)",
                       "Restore max lifts the drain by N without a rest: clamped at 0, current HP never rises, one log line, undrained skipped",
                       "deterministic by construction: two roster characters forced to max 32, current 10; drains set per step"]
        // Core rule.
        var c = Character(name: "T", maxHP: 32, currentHP: 10)
        c.setMaxHPReduction(8)
        rmLines.append("core lifts by the amount and reports it \(c.restoreMaxHP(5) == 5 && c.maxHPReduction == 3 && c.effectiveMaxHP == 29)")
        rmLines.append("core clamps at the drain (restore 99 lifts only 3) \(c.restoreMaxHP(99) == 3 && c.maxHPReduction == 0)")
        rmLines.append("core restore on an undrained character is 0 \(c.restoreMaxHP(5) == 0 && c.restoreMaxHP(-4) == 0)")
        // Party path.
        rmSeed(aDrain: 8, bDrain: 2)
        var rmLogN = model.tableLog.count
        let rmNames = model.restorePartyMaxHP(amount: 5)
        rmLines.append("party restore lifts each by what it can (8->3, 2->0) \(model.characters[0].maxHPReduction == 3 && model.characters[1].maxHPReduction == 0)")
        rmLines.append("changed characters are returned \(rmNames == [rmAName, rmBName])")
        rmLines.append("current HP never rises \(model.characters[0].currentHP == 10 && model.characters[1].currentHP == 10)")
        rmLines.append("one log line names who got what \(model.tableLog.count == rmLogN + 1 && model.tableLog.last?.title == "Max HP restored" && model.tableLog.last?.text == "\(rmAName) +5 (max now 29), \(rmBName) +2 (max now 32)")")
        // Skip undrained silently.
        rmSeed(aDrain: 0, bDrain: 4)
        rmLogN = model.tableLog.count
        let rmSkip = model.restorePartyMaxHP(amount: 3)
        rmLines.append("undrained characters are skipped silently \(rmSkip == [rmBName] && model.characters[0].maxHPReduction == 0 && model.characters[1].maxHPReduction == 1)")
        // Nobody drained: no log.
        rmSeed(aDrain: 0, bDrain: 0)
        rmLogN = model.tableLog.count
        rmLines.append("nobody drained: no-op and no log \(model.restorePartyMaxHP(amount: 5).isEmpty && model.tableLog.count == rmLogN)")
        rmLines.append("non-positive amount is a no-op \(model.restorePartyMaxHP(amount: 0).isEmpty)")
        // Targeted subset.
        rmSeed(aDrain: 6, bDrain: 6)
        let rmTarget = model.restorePartyMaxHP(amount: 4, from: [model.characters[1].id])
        rmLines.append("targeted restore touches only the subset \(rmTarget == [rmBName] && model.characters[0].maxHPReduction == 6 && model.characters[1].maxHPReduction == 2)")
        // Undo restores the drain in one snapshot (selected character A).
        rmSeed(aDrain: 6, bDrain: 0)
        // Baseline the undo stack through two REAL binding writes (a write of an
        // equal value is ignored, which would leave the stack baseline stale).
        if var t = model.selected?.wrappedValue { t.currentHP = 9; model.selected?.wrappedValue = t; t.currentHP = 10; model.selected?.wrappedValue = t }
        model.restorePartyMaxHP(amount: 4)
        rmLines.append("restore applied to the selected character \(model.characters[0].maxHPReduction == 2)")
        model.undo()
        rmLines.append("undo restores the drain in one snapshot \(model.characters[0].maxHPReduction == 6 && model.characters[0].currentHP == 10)")
        model.redo()
        rmLines.append("redo re-lifts it \(model.characters[0].maxHPReduction == 2)")
        model.characters = rmOrig
        for ch in rmOrig { try? model.store.save(ch) }
        model.tableLog = rmOrigLog
        model.tableLogStore.save(rmOrigLog)
        rmLines.append("hygiene: roster and table log restored \(model.characters == rmOrig && model.tableLog.count == rmOrigLog.count)")
        try? rmLines.joined(separator: "\n")
            .write(to: URL(fileURLWithPath: "\(outDir)/restoremax.txt"),
                   atomically: true, encoding: .utf8)
    }
    // 3.79.0 visual proof pass for the drain surfaces (3.75.0-3.78.0).
    // Real views, real fixture roster, two pane widths (480 narrow, 720
    // normal) plus the crowded-chips case. Pixels are inspected by eye by
    // the lane; this block only produces the captures and a manifest.
    vzProof: do {
        let vzOrigChars = model.characters
        let vzOrigSel = model.selectedID
        let vzOrigOpen = model.partyDetailPanelOpen
        var vzDax = Character(name: "Drained Dax", maxHP: 32, currentHP: 30)
        vzDax.level = 5
        vzDax.setMaxHPReduction(8)
        var vzCora = Character(name: "Crowded Cora", maxHP: 40, currentHP: 36)
        vzCora.level = 7
        vzCora.tempHP = 5
        vzCora.conditions = [.prone, .poisoned, .blinded, .frightened]
        vzCora.concentratingOn = "Hold Person"
        vzCora.setMaxHPReduction(12)
        var vzPip = Character(name: "Plain Pip", maxHP: 24, currentHP: 24)
        vzPip.level = 3
        var vzWard = Character(name: "Warforged Ward", lineage: "Warforged Scout", maxHP: 30, currentHP: 30)
        vzWard.level = 4
        vzWard.resistances = [.fire]; vzWard.immunities = [.poison]; vzWard.vulnerabilities = [.thunder]
        vzWard.drainDamageTypes = [.necrotic, .radiant]
        vzWard.conditionImmunities = [.charmed]
        model.characters = [vzDax, vzCora, vzPip, vzWard]
        model.selectedID = vzCora.id
        model.partyDetailPanelOpen = true
        var vzManifest = ["Visual proof pass (3.79.0): drain surfaces", "widths: 480 narrow pane, 720 normal pane (harness convention: group-check renders at 520)"]
        for w in [480, 720] as [CGFloat] {
            let n = Int(w)
            renderPNG(PartyStripView().padding(.vertical).background(Theme.surface).environmentObject(model),
                      width: w, name: "viz-party-strip-\(n)", outDir: outDir, minHeight: 100, maxHeight: 260)
            renderPNG(PartyDetailPanelView().padding().background(Theme.surface).environmentObject(model),
                      width: w, name: "viz-party-detail-\(n)", outDir: outDir, minHeight: 120, maxHeight: 700)
            renderPNG(GroupCheckSectionView().padding().background(Theme.surface).environmentObject(model),
                      width: w, name: "viz-party-controls-\(n)", outDir: outDir, minHeight: 200, maxHeight: 900)
            renderPNG(VitalsBlock(character: .constant(vzWard)).padding().background(Theme.surface).environmentObject(model),
                      width: w, name: "viz-vitals-defense-\(n)", outDir: outDir, minHeight: 200, maxHeight: 900)
            renderPNG(VitalsBlock(character: .constant(vzCora)).padding().background(Theme.surface).environmentObject(model),
                      width: w, name: "viz-vitals-drained-\(n)", outDir: outDir, minHeight: 200, maxHeight: 900)
            vzManifest.append("rendered viz-vitals-drained-\(n) (drained Cora: Drain stepper label with max shown)")
            vzManifest.append("rendered viz-party-strip-\(n), viz-party-detail-\(n), viz-party-controls-\(n), viz-vitals-defense-\(n)")
        }
        let vzCard = PartyCardSummary(character: vzCora)
        vzManifest.append("crowded card: chips \(vzCard.chips) visible \(vzCard.visibleChips) extra \(vzCard.extraChipCount) drainChip \(vzCard.drainChip ?? "nil")")
        vzManifest.append("crowded card keeps the drain out of the overflow \(vzCard.drainChip == "Max -12" && !vzCard.chips.contains { $0.hasPrefix("Max -") } && vzCard.extraChipCount >= 1)")
        vzManifest.append("detail row for the crowded card carries every chip incl. the drain last \(partyDetailRows([vzCora]).first?.chips.last?.text == "Max -12")")
        vzManifest.append("pixel proof: the PNGs above are inspected for clipping, truncation and overlap")
        try? vzManifest.joined(separator: "\n")
            .write(to: URL(fileURLWithPath: "\(outDir)/viz-drain-manifest.txt"), atomically: true, encoding: .utf8)
        // 3.80.0: drain recovery on rest - proof lines plus a 480/720 render of the control.
        var drLines = ["Drain recovery on rest (3.80.0)",
                       "nil keeps the full lift; a number lifts that much per long rest and current HP rises to the new ceiling"]
        var drFull = vzCora; drFull.longRestDrainRecovery = nil
        let drStart = drFull.maxHPReduction
        drFull.longRest()
        drLines.append("default long rest lifts the whole drain (was \(drStart)) \(drStart > 0 && drFull.maxHPReduction == 0 && drFull.currentHP == drFull.maxHP)")
        var drPart = vzCora; drPart.longRestDrainRecovery = 5
        let drBefore = drPart.maxHPReduction
        drPart.longRest()
        drLines.append("configured 5 lifts only 5 (\(drBefore) -> \(drPart.maxHPReduction)) \(drPart.maxHPReduction == drBefore - 5 && drPart.currentHP == drPart.effectiveMaxHP)")
        var drZero = vzCora; drZero.longRestDrainRecovery = 0
        drZero.longRest()
        drLines.append("configured 0 keeps the drain \(drZero.maxHPReduction == drBefore)")
        // 3.81.0: the rest log names the lift; nothing logged when no drain moved.
        let dlSaveChars = model.characters, dlSaveLog = model.tableLog
        var dlCora = vzCora; dlCora.longRestDrainRecovery = 5
        model.characters = [dlCora]
        let dlN = model.tableLog.count
        _ = model.restParty(long: true)
        let dlText = model.tableLog.last?.text ?? "nil"
        drLines.append("party long rest logs the lift: \(dlText) \(model.tableLog.count == dlN + 1 && dlText == "Long rest lifted drain: \(dlCora.name) -12 to -7")")
        let dlN2 = model.tableLog.count
        _ = model.restParty(long: false)
        drLines.append("short rest logs no drain line \(model.tableLog.count == dlN2)")
        // per-character sheet-level Long rest: same line, one character
        var dlSolo = vzCora; dlSolo.longRestDrainRecovery = 5
        let dlSelSave = model.selectedID
        model.characters = [dlSolo]; model.selectedID = dlSolo.id
        let dlN3 = model.tableLog.count
        model.longRest()
        let dlSoloText = model.tableLog.last?.text ?? "nil"
        drLines.append("sheet Long rest logs the lift: \(dlSoloText) \(model.tableLog.count == dlN3 + 1 && model.tableLog.last?.title == "Rest" && dlSoloText == "Long rest lifted drain: \(dlSolo.name) -12 to -7")")
        drLines.append("sheet Long rest left drain 7 and healed to the new ceiling \(model.characters[0].maxHPReduction == 7 && model.characters[0].currentHP == model.characters[0].effectiveMaxHP)")
        let dlN4 = model.tableLog.count
        model.longRest(); model.longRest()
        drLines.append("two more rests: -7 to -2 then -2 to none, 2 lines \(model.tableLog.count == dlN4 + 2 && model.tableLog.last?.text == "Long rest lifted drain: \(dlSolo.name) -2 to none" && model.characters[0].maxHPReduction == 0)")
        let dlN5 = model.tableLog.count
        model.longRest()
        drLines.append("undrained long rest logs no drain line \(model.tableLog.count == dlN5)")
        model.selectedID = dlSelSave
        model.characters = dlSaveChars; model.tableLog = dlSaveLog; model.tableLogStore.save(dlSaveLog)
        // 3.83.0: split gold across the roster.
        let lsSaveChars = model.characters, lsSaveLog = model.tableLog
        var lsLines = ["Split gold (3.83.0)",
                       "Amount is gp; the pot is exact copper, each share the whole-copper floor as fewest coins added to each purse, leftover stays in the pot"]
        var lsRoster = Array(lsSaveChars.prefix(3))
        for i in lsRoster.indices { lsRoster[i].currency = Currency(copper: 3, silver: 0, gold: 10 * (i + 1)) }
        model.characters = lsRoster
        let lsBefore = model.characters.map(\.currency)
        let lsN = model.tableLog.count
        let lsNames = model.splitPartyGold(amount: 100)
        let lsText = model.tableLog.last?.text ?? "nil"
        lsLines.append("100 gp over 3 members: 3 pp, 3 gp, 3 sp, 3 cp each (3333 cp), 1 cp left; log: \(lsText) \(lsNames.count == 3 && lsText == "100 gp split 3 ways: 3 pp, 3 gp, 3 sp, 3 cp each (1 cp left in the pot)" && model.tableLog.count == lsN + 1 && model.tableLog.last?.title == "Loot split")")
        lsLines.append("existing coins kept, share added per denomination \(model.characters[0].currency == Currency(copper: 6, silver: 3, gold: 13, platinum: 3) && model.characters[2].currency == Currency(copper: 6, silver: 3, gold: 33, platinum: 3))")
        lsLines.append("exact copper conserved: shares + leftover = pot \(model.characters.indices.map { model.characters[$0].currency.totalCopper - lsBefore[$0].totalCopper }.reduce(0, +) + 1 == 10000)")
        let lsPersisted = (try? model.store.load(id: model.characters[1].id))?.currency == model.characters[1].currency
        lsLines.append("persisted through the store \(lsPersisted)")
        let lsN2 = model.tableLog.count
        lsLines.append("zero amount splits nothing \(model.splitPartyGold(amount: 0).isEmpty && model.tableLog.count == lsN2)")
        lsLines.append("even pot logs no leftover: 90 gp over 3 \(model.splitPartyGold(amount: 90).count == 3 && model.tableLog.last?.text == "90 gp split 3 ways: 3 pp each")")
        lsLines.append("core: nobody or nothing yields no split \(LootSplit(totalCopper: 100, members: 0) == nil && LootSplit(totalCopper: 0, members: 3) == nil)")
        model.characters = lsSaveChars; model.tableLog = lsSaveLog; model.tableLogStore.save(lsSaveLog)
        for ch in lsSaveChars { try? model.store.save(ch) }
        lsLines.append("hygiene: roster and table log restored \(model.characters == lsSaveChars && model.tableLog.count == lsSaveLog.count)")
        try? lsLines.joined(separator: "\n")
            .write(to: URL(fileURLWithPath: "\(outDir)/splitgold.txt"), atomically: true, encoding: .utf8)
        // 3.84.0: per-member include/exclude on Split gold.
        let sxSaveChars = model.characters, sxSaveLog = model.tableLog
        var sxLines = ["Split gold with members left out (3.84.0)",
                       "unticked members get nothing; the preview line is derived; the log names who was left out"]
        var sxRoster = Array(sxSaveChars.prefix(3))
        for i in sxRoster.indices { sxRoster[i].currency = Currency() }
        model.characters = sxRoster
        let sxAbsent = sxRoster[2]
        let sxPrev = model.partyGoldSplitPreview(amount: 100, excluded: [sxAbsent.id]) ?? "nil"
        sxLines.append("preview with the third member left out: \(sxPrev) \(sxPrev == "5 pp each to \(sxRoster[0].name), \(sxRoster[1].name)")")
        sxLines.append("preview is nil for no amount or nobody ticked \(model.partyGoldSplitPreview(amount: 0, excluded: []) == nil && model.partyGoldSplitPreview(amount: 100, excluded: Set(sxRoster.map(\.id))) == nil)")
        let sxIDs = Set(sxRoster.map(\.id)).subtracting([sxAbsent.id])
        let sxN = model.tableLog.count
        let sxNames = model.splitPartyGold(amount: 100, among: sxIDs)
        let sxLog = model.tableLog.last?.text ?? "nil"
        sxLines.append("split two ways: \(sxLog) \(sxNames.count == 2 && model.tableLog.count == sxN + 1 && sxLog == "100 gp split 2 ways: 5 pp each - left out: \(sxAbsent.name)")")
        sxLines.append("members got 5 pp each, absent got nothing \(model.characters[0].currency == Currency(platinum: 5) && model.characters[1].currency == Currency(platinum: 5) && model.characters[2].currency == Currency())")
        sxLines.append("nobody ticked splits nothing \(model.splitPartyGold(amount: 100, among: []).isEmpty && model.tableLog.count == sxN + 1)")
        model.tableLog = sxSaveLog
        for w in [480, 720] as [CGFloat] {
            renderPNG(GroupCheckSectionView(previewAmount: "250", previewExcluded: [sxAbsent.id]).padding().background(Theme.surface).environmentObject(model),
                      width: w, name: "viz-party-split-\(Int(w))", outDir: outDir, minHeight: 200, maxHeight: 900)
        }
        sxLines.append("rendered viz-party-split-480, viz-party-split-720 (Amount 250, third member unticked, preview line shown)")
        model.characters = sxSaveChars; model.tableLog = sxSaveLog; model.tableLogStore.save(sxSaveLog)
        for ch in sxSaveChars { try? model.store.save(ch) }
        sxLines.append("hygiene: roster and table log restored \(model.characters == sxSaveChars && model.tableLog.count == sxSaveLog.count)")
        try? sxLines.joined(separator: "\n")
            .write(to: URL(fileURLWithPath: "\(outDir)/splitgold-members.txt"), atomically: true, encoding: .utf8)
        var drShown = vzCora; drShown.longRestDrainRecovery = 5
        for w in [480, 720] as [CGFloat] {
            renderPNG(VitalsBlock(character: .constant(drShown)).padding().background(Theme.surface).environmentObject(model),
                      width: w, name: "viz-vitals-recovery-\(Int(w))", outDir: outDir, minHeight: 200, maxHeight: 900)
        }
        drLines.append("rendered viz-vitals-recovery-480, viz-vitals-recovery-720")
        try? drLines.joined(separator: "\n")
            .write(to: URL(fileURLWithPath: "\(outDir)/drainrecovery.txt"), atomically: true, encoding: .utf8)
        model.characters = vzOrigChars
        model.selectedID = vzOrigSel
        model.partyDetailPanelOpen = vzOrigOpen
    }
    print("exports written (pdf \(pdf.count) bytes)")
    print("RENDER DONE")
}

/// A synthesized demo portrait (initials on a warm disc) so renders exercise
/// the portrait UI without bundling any artwork.
func demoPortraitPNG(initials: String) -> Data? {
    let side = 256
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor(calibratedRed: 0.54, green: 0.35, blue: 0.17, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: side, height: side)).fill()
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.boldSystemFont(ofSize: 120),
        .foregroundColor: NSColor(calibratedRed: 0.95, green: 0.9, blue: 0.8, alpha: 1),
    ]
    let text = NSAttributedString(string: initials, attributes: attrs)
    let bounds = text.boundingRect(with: NSSize(width: side, height: side))
    text.draw(at: NSPoint(x: (CGFloat(side) - bounds.width) / 2,
                          y: (CGFloat(side) - bounds.height) / 2))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

@main
struct RenderMain {
    @MainActor
    static func main() {
        let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "render-out"
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.appearance = NSAppearance(named: .darkAqua)
        let model = AppModel()
        var character = SampleContent.demoCharacter()
        character.portrait = demoPortraitPNG(initials: "WH")
        // Select the demo character so character-scoped UI (per-character
        // roll history filter) exercises its populated state in renders.
        model.characters = [character]
        model.selectedID = character.id
        run(model: model, character: character, outDir: outDir)
        exit(0)
    }
}
#else
@main
struct RenderStub {
    static func main() { print("architer-render is macOS-only.") }
}
#endif
