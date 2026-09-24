#if os(macOS)
import SwiftUI

import AppKit
import ARCHITERUI
import ArchiterCore

// Renders the app's key views with a rich sample character to PNGs, plus the
// PDF/HTML/Markdown exports, so CI can attach visual proof to each build.
// Usage: architer-render <output-directory>

func renderPNG<V: View>(_ view: V, width: CGFloat, name: String, outDir: String, minHeight: CGFloat = 120) {
    let hosting = NSHostingView(rootView: view)
    hosting.frame = NSRect(x: 0, y: 0, width: width, height: 100)
    hosting.layoutSubtreeIfNeeded()
    let fitting = hosting.fittingSize
    let size = NSSize(width: width, height: max(fitting.height, minHeight))
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
    // outgoing-defense note, and that entry quick-added to the journal so
    // the sheet render shows it in the journal block.
    if let fireBolt = character.attacks.first(where: { $0.name == "Fire Bolt" }) {
        model.rollAttack(fireBolt, for: character)
        if let rolled = model.rollHistory.first { model.addRollToJournal(rolled) }
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
    renderPNG(
        DiceRollerView()
            .padding()
            .background(Theme.surface)
            .environmentObject(model),
        width: width, name: "dice", outDir: outDir, minHeight: 420)
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
    let compactPdf = SheetPDFExporter.export(character, style: .compact)
    try? compactPdf.write(to: URL(fileURLWithPath: "\(outDir)/sample-sheet-compact.pdf"))
    let compactLandscapePdf = SheetPDFExporter.export(character, style: .compact, orientation: .landscape)
    try? compactLandscapePdf.write(to: URL(fileURLWithPath: "\(outDir)/sample-sheet-compact-landscape.pdf"))
    // 2.34.0 proof: compact export with zero-quantity rows collapsed.
    var depleted = character
    depleted.inventory.append(InventoryItem(name: "Arrows", quantity: 0, weight: 1, category: "Ammunition"))
    depleted.inventory.append(InventoryItem(name: "Chalk", quantity: 0, category: "Gear"))
    let collapsedPdf = SheetPDFExporter.export(depleted, style: .compact, collapseEmptyInventory: true)
    try? collapsedPdf.write(to: URL(fileURLWithPath: "\(outDir)/sample-sheet-compact-collapsed.pdf"))
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
