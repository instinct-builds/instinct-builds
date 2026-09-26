import Foundation
import Testing
@testable import ArchiterCore

@Suite("Sheet-to-dice bridge (3.23.0)")
struct MacroBridgeTests {
    private var scores: AbilityScores {
        AbilityScores([.strength: 10, .dexterity: 16, .constitution: 12,
                       .intelligence: 18, .wisdom: 14, .charisma: 8])
    }

    @Test func resolvesAbilityBonusAndCarriesDamageType() throws {
        let fireBolt = Attack(name: "Fire Bolt", ability: .intelligence, proficient: true,
                              damageExpression: "2d10", damageType: "fire", range: "120 ft")
        let macro = MacroBridge.combo(for: fireBolt, characterName: "Wren Halloway",
                                      scores: scores, level: 5)
        #expect(macro.name == "Fire Bolt")
        #expect(macro.characterName == "Wren Halloway")
        let parts = try #require(macro.parts)
        #expect(parts.count == 2)
        // INT 18 (+4), proficiency +3 at level 5.
        #expect(parts[0].label == "Fire Bolt attack")
        #expect(parts[0].expression == "1d20+7")
        #expect(parts[1].label == "Fire Bolt damage")
        #expect(parts[1].expression == "2d10+4")
        #expect(parts[1].damageType == "fire")
        #expect(macro.isValid)
    }

    @Test func finessePicksTheBetterOfStrAndDex() throws {
        let dagger = Attack(name: "Dagger", ability: nil, proficient: true,
                            damageExpression: "1d4", damageType: "piercing")
        let macro = MacroBridge.combo(for: dagger, characterName: "Wren Halloway",
                                      scores: scores, level: 5)
        let parts = try #require(macro.parts)
        // DEX 16 (+3) beats STR 10 (+0); proficiency +3.
        #expect(parts[0].expression == "1d20+6")
        #expect(parts[1].expression == "1d4+3")
    }

    @Test func bonusOverridePinsTheSnapshot() throws {
        let pinned = Attack(name: "Oathbow", ability: .strength, proficient: false,
                            bonusOverride: 9, damageExpression: "1d8", damageType: "piercing")
        let macro = MacroBridge.combo(for: pinned, characterName: "Wren Halloway",
                                      scores: scores, level: 5)
        let parts = try #require(macro.parts)
        #expect(parts[0].expression == "1d20+9")
        // Pinned attacks roll the literal damage expression (sheet behavior).
        #expect(parts[1].expression == "1d8")
    }

    @Test func twoHandedGripCapturesTheVersatileExpression() throws {
        let staff = Attack(name: "Quarterstaff", ability: .strength, proficient: true,
                           damageExpression: "1d6", damageType: "bludgeoning",
                           versatileExpression: "1d8", twoHanded: true)
        let macro = MacroBridge.combo(for: staff, characterName: "Wren Halloway",
                                      scores: scores, level: 5)
        let parts = try #require(macro.parts)
        // STR 10 (+0): proficiency-only attack bonus, and the 2H dice.
        #expect(parts[0].expression == "1d20+3")
        #expect(parts[1].expression == "1d8")
    }

    @Test func zeroBonusAttackRollsBareD20() throws {
        let rock = Attack(name: "Rock", ability: .strength, proficient: false,
                          damageExpression: "1d4", damageType: "")
        let macro = MacroBridge.combo(for: rock, characterName: "Wren Halloway",
                                      scores: scores, level: 5)
        let parts = try #require(macro.parts)
        #expect(parts[0].expression == "1d20")
        #expect(parts[1].damageType == nil)
    }

    @Test func reSavingRefreshesTheSameScopedSlot() throws {
        let original = Attack(name: "Fire Bolt", ability: .intelligence, proficient: true,
                              damageExpression: "2d10", damageType: "fire")
        var edited = original
        edited.damageExpression = "3d6"
        let first = MacroBridge.combo(for: original, characterName: "Wren Halloway",
                                      scores: scores, level: 5)
        let second = MacroBridge.combo(for: edited, characterName: "Wren Halloway",
                                       scores: scores, level: 5)
        // The stable scoped id is what makes saveMacro's upsert a refresh.
        #expect(first.id == second.id)
        #expect(first.id == "wren halloway:fire bolt")
        #expect(first.expression != second.expression)
    }
}
