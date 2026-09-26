import Foundation
import Testing
@testable import ArchiterCore

@Suite("Condition timers (3.30.0)")
struct ConditionTimerTests {
    private func character(name: String = "Wren") -> Character {
        Character(name: name)
    }

    @Test func tickDecrementsAndKeepsCondition() {
        var c = character()
        c.conditions.insert(.prone)
        c.conditionDurations[Condition.prone.rawValue] = 2
        let ended = c.tickConditionDurations()
        #expect(ended.isEmpty)
        #expect(c.conditions.contains(.prone))
        #expect(c.conditionDurations[Condition.prone.rawValue] == 1)
    }

    @Test func tickAtOneEndsConditionAndReportsName() {
        var c = character()
        c.conditions.insert(.prone)
        c.conditionDurations[Condition.prone.rawValue] = 1
        let ended = c.tickConditionDurations()
        #expect(ended == ["Prone"])
        #expect(!c.conditions.contains(.prone))
        #expect(c.conditionDurations[Condition.prone.rawValue] == nil)
    }

    @Test func untimedConditionsSurviveTicks() {
        var c = character()
        c.conditions.insert(.poisoned)
        c.conditions.insert(.prone)
        c.conditionDurations[Condition.prone.rawValue] = 1
        let ended = c.tickConditionDurations()
        #expect(ended == ["Prone"])
        #expect(c.conditions.contains(.poisoned))
    }

    @Test func customConditionTimerEndsTheCustom() {
        var c = character()
        let cc = CustomCondition(name: "Vault-marked", hindersChecks: true)
        c.customConditions = [cc]
        c.conditionDurations[cc.id.uuidString] = 1
        let ended = c.tickConditionDurations()
        #expect(ended == ["Vault-marked"])
        #expect(c.customConditions.isEmpty)
        #expect(c.conditionDurations.isEmpty)
    }

    @Test func chipLabelsCarryRounds() {
        var c = character()
        c.conditions.insert(.prone)
        c.conditionDurations[Condition.prone.rawValue] = 3
        c.customConditions = [CustomCondition(name: "Vault-marked", hindersChecks: true)]
        #expect(c.conditionChipNames == ["Prone (3)", "Vault-marked"])
    }

    @Test func durationsRoundTripThroughCodable() throws {
        var c = character()
        c.conditions.insert(.prone)
        c.conditionDurations[Condition.prone.rawValue] = 4
        let data = try JSONEncoder().encode(c)
        let back = try JSONDecoder().decode(Character.self, from: data)
        #expect(back.conditionDurations[Condition.prone.rawValue] == 4)
    }
}
