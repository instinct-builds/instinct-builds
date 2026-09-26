import Foundation
import Testing
@testable import ArchiterCore

@Suite("Level-up preview (3.25.0)")
struct LevelUpPreviewTests {
    private func caster(level: Int, con: Int = 14) -> Character {
        var c = Character(name: "Test")
        c.level = level
        c.hitDiceType = 8
        c.scores = AbilityScores([.constitution: con])
        c.spellcasting = Spellcasting(ability: .intelligence, progression: .full)
        return c
    }

    @Test func proficiencyTierCrossingShows() throws {
        let p = try #require(LevelUpPreview(character: caster(level: 4)))
        #expect(p.fromLevel == 4 && p.toLevel == 5)
        #expect(p.proficiencyFrom == 2 && p.proficiencyTo == 3)
    }

    @Test func withinATierProficiencyStays() throws {
        let p = try #require(LevelUpPreview(character: caster(level: 5)))
        #expect(p.proficiencyFrom == 3 && p.proficiencyTo == 3)
    }

    @Test func fullCasterSlotDeltas() throws {
        let p = try #require(LevelUpPreview(character: caster(level: 2)))
        // Full caster 2 -> 3: 1st-level slots 3 -> 4, 2nd-level slots open at 2.
        #expect(p.slotDeltas == [
            LevelUpPreview.SlotDelta(spellLevel: 1, from: 3, to: 4),
            LevelUpPreview.SlotDelta(spellLevel: 2, from: 0, to: 2),
        ])
    }

    @Test func hitDiceAndAverageHPGain() throws {
        let p = try #require(LevelUpPreview(character: caster(level: 4)))
        #expect(p.hitDiceFrom == "4d8" && p.hitDiceTo == "5d8")
        // d8 average 4 + 1 + CON 14 (+2) = 7, matching levelUp's floor.
        #expect(p.averageHPGain == 7)
        #expect(p.rollExpression == "1d8+2")
        #expect(p.notesLine(hpGain: p.averageHPGain) == "Reached level 5 (+7 HP).")
    }

    @Test func averageGainFloorsAtOne() throws {
        var c = caster(level: 3, con: 8)
        c.hitDiceType = 4
        let p = try #require(LevelUpPreview(character: c))
        // d4 average 2 + 1 + CON 8 (-1) = 2; floor keeps it at >= 1 regardless.
        #expect(p.averageHPGain >= 1)
    }

    @Test func nonCasterHasNoSlotDeltas() throws {
        var c = caster(level: 4)
        c.spellcasting = nil
        let p = try #require(LevelUpPreview(character: c))
        #expect(p.slotDeltas.isEmpty)
    }

    @Test func levelCapHasNoPreview() {
        #expect(LevelUpPreview(character: caster(level: 20)) == nil)
    }
}
