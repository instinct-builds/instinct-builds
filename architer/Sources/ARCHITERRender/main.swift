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
    // 2.39.0/2.41.0 proof: the compact export carries the character's
    // session-log appendix, ranged to Today - the Yesterday group is
    // filtered out, the rerolled 4d6kh3 stays.
    let compactPdf = SheetPDFExporter.export(character, style: .compact,
                                             sessionRolls: model.rollHistory.forCharacter(character.name).within(.today))
    try? compactPdf.write(to: URL(fileURLWithPath: "\(outDir)/sample-sheet-compact.pdf"))
    // 2.42.0 proof: the same rolls as a plain-text session log, honoring
    // the same range - Today only, day-grouped, no PDF.
    let logRolls = model.rollHistory.forCharacter(character.name).within(.today)
    let logText = sessionLogText(character: character.name, range: .today,
                                 rows: sessionLogRows(logRolls))
    try? logText.write(to: URL(fileURLWithPath: "\(outDir)/session-log.txt"),
                       atomically: true, encoding: .utf8)
    // 2.44.0 proof: the same Today rolls as a Markdown table.
    let logMd = sessionLogMarkdown(character: character.name, range: .today,
                                   groups: groupRollsByDay(Array(logRolls.reversed())))
    try? logMd.write(to: URL(fileURLWithPath: "\(outDir)/session-log.md"),
                     atomically: true, encoding: .utf8)
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
    }
    // 2.46.0 proof: today's journal entries and rolls as one shareable
    // recap block - the same text the sheet's Copy today button copies.
    let recap = sessionRecap(character: model.selected?.wrappedValue ?? character,
                             rolls: model.rollHistory)
    try? recap.write(to: URL(fileURLWithPath: "\(outDir)/session-recap.txt"),
                     atomically: true, encoding: .utf8)
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
