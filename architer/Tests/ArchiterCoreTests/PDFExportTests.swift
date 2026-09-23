import Testing
import Foundation
@testable import ArchiterCore

private func aria() -> Character {
    var scores = AbilityScores()
    scores[.strength] = 12
    scores[.dexterity] = 17
    scores[.constitution] = 13
    scores[.intelligence] = 14
    scores[.wisdom] = 15
    scores[.charisma] = 10
    var skills = Skill.defaultList
    if let i = skills.firstIndex(where: { $0.name == "Stealth" }) { skills[i].tier = .expert }
    if let i = skills.firstIndex(where: { $0.name == "Perception" }) { skills[i].tier = .proficient }
    if let i = skills.firstIndex(where: { $0.name == "Acrobatics" }) { skills[i].tier = .proficient }
    return Character(
        name: "Aria Thorne",
        lineage: "Shade-Touched",
        calling: "Ranger",
        background: "Road Warden",
        level: 5,
        experience: 6500,
        scores: scores,
        skills: skills,
        savingThrowProficiencies: [.dexterity, .wisdom],
        maxHP: 38,
        armorClass: 15,
        speed: 30,
        attacks: [
            Attack(name: "Longbow", attackBonus: 6, damageExpression: "1d8+3", notes: "150/600 ft"),
            Attack(name: "Shortsword", attackBonus: 5, damageExpression: "1d6+3"),
        ],
        inventory: [
            InventoryItem(name: "Arrows", quantity: 40),
            InventoryItem(name: "Rope, hempen", quantity: 1, notes: "50 ft"),
        ],
        notes: "Keeps a marked map of the northern passes."
    )
}

@Suite("PDF export")
struct PDFExportTests {

    @Test func compactLayoutIsInkLightAndComplete() throws {
        var c = aria()
        c.proficienciesText = "Armor: light - Weapons: simple, martial"
        c.toolProficiencies = [ToolProficiency(name: "Thieves' tools", tier: .expert)]
        let full = SheetPDFExporter.export(c)
        let compact = SheetPDFExporter.export(c, style: .compact)
        let fullText = String(data: full, encoding: .utf8) ?? ""
        let compactText = String(data: compact, encoding: .utf8) ?? ""
        // Proficiencies and tools lines ship in BOTH layouts.
        #expect(fullText.contains("Proficiencies: Armor: light"))
        #expect(compactText.contains("Proficiencies: Armor: light"))
        #expect(compactText.contains("Tools: Thieves' tools \\(expertise\\)")) // parens are escaped in PDF literal strings
        // Compact uses no color operators and no filled rects (ink-light).
        #expect(!compactText.contains(" rg"))
        #expect(!compactText.contains(" RG"))
        #expect(!compactText.contains(" re f"))
        // The content still makes it in.
        #expect(compactText.contains("Aria Thorne"))
        #expect(compactText.contains("Longbow"))
        // And it is genuinely smaller than the styled layout.
        #expect(compact.count < full.count)
    }

    @Test func compactLayoutFlowsInTwoColumns() throws {
        let demo = SampleContent.demoCharacter()
        let compact = SheetPDFExporter.export(demo, style: .compact)
        let text = String(data: compact, encoding: .utf8) ?? ""
        // Sections still labeled.
        #expect(text.contains("(SKILLS"))
        #expect(text.contains("(ATTACKS"))
        #expect(text.contains("(FEATURES"))
        // Two-column flow: content lands in the right-hand column.
        // Column x origin = margin 40 + column width 254 + gutter 24 = 318.
        #expect(text.contains("Tf 318 "))
        // The attacks table suspends the columns and spans the full width:
        // its "Bonus" column sits at x = margin 40 + 4 + 170 = 214.
        #expect(text.contains("Tf 214 "))
        // Ink-light stays true under the column machinery.
        #expect(!text.contains(" rg"))
        #expect(!text.contains(" re f"))
    }

    @Test func compactEntriesKeepTogether() throws {
        let demo = SampleContent.demoCharacter()
        let text = String(data: SheetPDFExporter.export(demo, style: .compact), encoding: .utf8) ?? ""
        // Page content streams end with "endstream"; an entry's head and
        // body must land in the same stream, never split across pages.
        let chunks = text.components(separatedBy: "endstream")
        // Feature name + first detail line (parens are escaped in PDF literals).
        let pairs: [(String, String)] = [
            ("Keen Senses \\(High Elf\\)", "Proficiency in Perception"),
            ("Arcane Recovery \\(Wizard 1\\)", "Once per day"),
            ("Session 2 - Lantern Street", "Bressa says the"),
        ]
        for (head, body) in pairs {
            let headChunk = chunks.firstIndex(where: { $0.contains(head) })
            let bodyChunk = chunks.firstIndex(where: { $0.contains(body) })
            #expect(headChunk != nil)
            #expect(headChunk == bodyChunk)
        }
    }

    @Test func validPDFStructure() throws {
        let data = SheetPDFExporter.export(aria())
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.hasPrefix("%PDF-1.4"))
        #expect(text.hasSuffix("%%EOF"))
        #expect(text.contains("/Type /Catalog"))
        #expect(text.contains("/Type /Pages"))
        #expect(text.contains("trailer"))
        // startxref must point at the literal "xref" keyword (byte offset).
        guard let sx = text.range(of: "startxref\n"),
              let nl = text[sx.upperBound...].firstIndex(of: "\n"),
              let pos = Int(text[sx.upperBound..<nl]) else {
            Issue.record("missing startxref")
            return
        }
        let bytes = [UInt8](data)
        #expect(pos + 4 <= bytes.count)
        #expect(Array(bytes[pos..<(pos + 4)]) == Array("xref".utf8))
    }

    @Test func containsSheetContent() {
        let text = String(decoding: SheetPDFExporter.export(aria()), as: UTF8.self)
        #expect(text.contains("(Aria Thorne)"))
        #expect(text.contains("Level 5 Shade-Touched Ranger"))
        #expect(text.contains("(ABILITIES)"))
        #expect(text.contains("Stealth +9"))
        #expect(text.contains("(Longbow)"))
        #expect(text.contains("1d8+3"))
        #expect(text.contains("Keeps a marked map"))
        #expect(text.contains("Made with ARCHITER"))
        #expect(text.contains("Page 1 of 1"))
    }

    @Test func escapesSpecialCharacters() {
        var c = aria()
        c.name = "Rogue (The Fox) \\ Alpha"
        let text = String(decoding: SheetPDFExporter.export(c), as: UTF8.self)
        #expect(text.contains("Rogue \\(The Fox\\) \\\\ Alpha"))
    }

    @Test func longNotesFlowToSecondPage() {
        var c = aria()
        c.notes = (1...80).map { "Session \($0): the party pressed on through the high passes despite the cold." }
            .joined(separator: "\n")
        let data = SheetPDFExporter.export(c)
        let text = String(decoding: data, as: UTF8.self)
        let pageCount = text.components(separatedBy: "/Type /Page ").count - 1
        #expect(pageCount >= 2)
        #expect(text.contains("Page 2 of \(pageCount)"))
    }

    @Test func hiddenBlocksAreNotPrinted() {
        var c = aria()
        c.layout.setVisible(.skills, false)
        c.layout.setVisible(.notes, false)
        let text = String(decoding: SheetPDFExporter.export(c), as: UTF8.self)
        #expect(!text.contains("Stealth +9"))
        #expect(!text.contains("Keeps a marked map"))
        #expect(text.contains("(ABILITIES)")) // visible blocks stay
    }
}

@Suite("Undo stack")
struct UndoStackTests {

    @Test func undoRestoresPriorStates() {
        var c = aria()
        var stack = UndoStack(c)
        c.name = "Aria the Bold"
        stack.push(c)
        c.level = 6
        stack.push(c)
        #expect(stack.current.level == 6)
        let u1 = stack.undo()
        #expect(u1)
        #expect(stack.current.name == "Aria the Bold" && stack.current.level == 5)
        let u2 = stack.undo()
        #expect(u2)
        #expect(stack.current.name == "Aria Thorne")
        let u3 = stack.undo()
        #expect(!u3) // bottom of history
    }

    @Test func redoWalksForwardAndNewEditClearsIt() {
        var c = aria()
        var stack = UndoStack(c)
        c.name = "V1"; stack.push(c)
        c.name = "V2"; stack.push(c)
        _ = stack.undo(); _ = stack.undo()
        #expect(stack.current.name == "Aria Thorne")
        let r = stack.redo()
        #expect(r)
        #expect(stack.current.name == "V1")
        c.name = "V3"; stack.push(c) // branch away
        #expect(!stack.canRedo)
        let r2 = stack.redo()
        #expect(!r2)
    }

    @Test func noOpPushDoesNotGrowHistory() {
        let c = aria()
        var stack = UndoStack(c)
        stack.push(c) // identical state
        #expect(!stack.canUndo)
    }

    @Test func historyIsBounded() {
        var c = aria()
        var stack = UndoStack(c, limit: 5)
        for i in 1...20 {
            c.experience = i
            stack.push(c)
        }
        #expect(stack.depth == 5)
        var undos = 0
        while true { if stack.undo() { undos += 1 } else { break } }
        #expect(undos == 5)
        #expect(stack.current.experience == 15) // oldest retained state
    }
}
