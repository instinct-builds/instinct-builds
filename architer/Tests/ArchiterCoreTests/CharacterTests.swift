import Testing
import Foundation
@testable import ArchiterCore

@Suite("Rules math")
struct RulesMathTests {
    @Test(arguments: [
        (1, -5), (8, -1), (9, -1), (10, 0), (11, 0), (12, 1), (15, 2), (18, 4), (20, 5),
    ])
    func abilityModifier(score: Int, expected: Int) {
        #expect(RulesMath.modifier(for: score) == expected)
    }

    @Test(arguments: [
        (1, 2), (4, 2), (5, 3), (8, 3), (9, 4), (13, 5), (17, 6), (20, 6),
    ])
    func proficiencyByLevel(level: Int, expected: Int) {
        #expect(RulesMath.proficiencyBonus(level: level) == expected)
    }

    @Test func pointBuyBudget() {
        var s = AbilityScores()
        for a in Ability.allCases { s[a] = 15 } // 9 pts each = 54 > 27
        #expect(s.totalPointBuyCost == 54)
        var legal = AbilityScores()
        let spread = [15, 14, 13, 12, 10, 8] // 9+7+5+4+2+0 = 27
        for (a, v) in zip(Ability.allCases, spread) { legal[a] = v }
        #expect(legal.totalPointBuyCost == 27)
    }

    @Test func outOfRangeScoresFailPointBuy() {
        var s = AbilityScores()
        s[.strength] = 20
        #expect(s.totalPointBuyCost == nil)
    }
}

@Suite("Character model")
struct CharacterTests {
    @Test func derivedStats() {
        var scores = AbilityScores()
        scores[.dexterity] = 16 // +3
        scores[.wisdom] = 14    // +2
        var skills = Skill.defaultList
        if let i = skills.firstIndex(where: { $0.name == "Perception" }) {
            skills[i].tier = .proficient
        }
        let c = Character(name: "Test", level: 5, scores: scores, skills: skills)
        #expect(c.initiative == 3)
        #expect(c.proficiencyBonus == 3)
        #expect(c.passivePerception == 10 + 2 + 3)
    }

    @Test func savingThrowsUseProficiency() {
        var scores = AbilityScores()
        scores[.strength] = 14 // +2
        let c = Character(level: 1, scores: scores, savingThrowProficiencies: [.strength])
        #expect(c.savingThrow(.strength) == 4)  // +2 mod +2 prof
        #expect(c.savingThrow(.wisdom) == 0)
    }

    @Test func damageHealingAndRest() {
        var c = Character(maxHP: 20)
        #expect(c.currentHP == 20)
        c.applyDamage(7)
        #expect(c.currentHP == 13)
        c.applyDamage(999)
        #expect(c.currentHP == 0)
        c.applyHealing(5)
        #expect(c.currentHP == 5)
        c.applyHealing(999)
        #expect(c.currentHP == 20)
        c.applyDamage(3)
        c.longRest()
        #expect(c.currentHP == 20)
    }

    @Test func levelIsClamped() {
        #expect(Character(level: 0).level == 1)
        #expect(Character(level: 99).level == 20)
    }
}

@Suite("Persistence round-trip")
struct PersistenceTests {
    @Test func saveLoadRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("architer-tests-\(UUID().uuidString)")
        let store = CharacterStore(directory: dir)
        var c = Character(name: "Roundtrip", level: 3)
        c.attacks.append(Attack(name: "Blade", attackBonus: 5, damageExpression: "1d8+3"))
        c.layout.setVisible(.inventory, false)
        try store.save(c)
        let loaded = try store.load(id: c.id)
        #expect(loaded == c)
        let all = try store.loadAll()
        #expect(all.count == 1)
        try store.delete(c)
        #expect((try store.loadAll()).isEmpty)
    }
}

@Suite("Export")
struct ExportTests {
    @Test func markdownContainsSections() {
        var c = Character(name: "Aria <the Bold>", level: 2)
        c.inventory.append(InventoryItem(name: "Rope", quantity: 2))
        let md = SheetExporter.exportMarkdown(c)
        #expect(md.contains("# Aria <the Bold>"))
        #expect(md.contains("## Abilities"))
        #expect(md.contains("Rope ×2"))
    }

    @Test func htmlEscapesUserText() {
        let c = Character(name: "<script>alert(1)</script>")
        let html = SheetExporter.exportHTML(c)
        #expect(!html.contains("<script>"))
        #expect(html.contains("&lt;script&gt;"))
    }

    @Test func hiddenBlocksAreOmitted() {
        var c = Character(name: "Minimal")
        c.layout.setVisible(.skills, false)
        c.layout.setVisible(.notes, false)
        let md = SheetExporter.exportMarkdown(c)
        #expect(!md.contains("## Skills"))
        #expect(md.contains("## Abilities"))
    }

    @Test func blockReorderIsRespected() {
        var c = Character(name: "Reorder")
        // Move notes to the front.
        if let idx = c.layout.blocks.firstIndex(where: { $0.kind == .notes }) {
            c.layout.move(fromOffsets: IndexSet(integer: idx), toOffset: 0)
        }
        c.notes = "first!"
        let md = SheetExporter.exportMarkdown(c)
        #expect(md.hasPrefix("## Notes"))
    }
}
