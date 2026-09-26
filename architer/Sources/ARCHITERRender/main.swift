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
               "Delete filtered... from the menu still opens the inline confirm (3.3.0)"])
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
    // 3.15.0 proof: pin a macro - Fireball jumps to the top of the
    // Table group with a filled accent pin; the character group above
    // keeps its order. Runs last so every earlier dice render keeps
    // the unpinned layout.
    do {
        if let fireball = model.macros.first(where: { $0.name == "Fireball" }) {
            model.toggleMacroPin(fireball)
        }
        let table = pinnedFirst(model.visibleMacros.filter { $0.characterName == nil })
        try? (["Pinned macros (3.15.0)",
               "pinned macros float to the top of their group; owner sections stay put",
               "Table group order: \(table.map(\.name).joined(separator: ", "))",
               "Fireball pinned: \(model.macros.first(where: { $0.name == "Fireball" })?.pinned == true)"])
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
