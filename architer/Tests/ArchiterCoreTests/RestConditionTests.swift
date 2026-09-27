import Foundation
import Testing
@testable import ArchiterCore

@Suite("Rest condition clearing (3.61.0)")
struct RestConditionTests {
    @Test func timedBuiltInAndCustomKeysAreListedSorted() {
        var c = Character(name: "Wren")
        c.conditions.insert(.prone)
        c.conditionDurations[Condition.prone.rawValue] = 3
        let cc = CustomCondition(name: "Vault-marked", hindersChecks: true)
        c.customConditions.append(cc)
        c.conditionDurations[cc.id.uuidString] = 2
        #expect(c.restClearedConditionKeys == [cc.id.uuidString, Condition.prone.rawValue].sorted())
        #expect(c.restClearedConditionKeys.count == 2)
    }

    @Test func untimedConditionsStay() {
        var c = Character(name: "Wren")
        c.conditions.insert(.poisoned)
        c.customConditions.append(CustomCondition(name: "Vault-marked"))
        #expect(c.restClearedConditionKeys.isEmpty)
        #expect(!c.conditions.isEmpty && !c.customConditions.isEmpty)
    }

    @Test func clearedKeysMatchTheNaturalTickOutSet() {
        var c = Character(name: "Wren")
        c.conditions.insert(.prone)
        c.conditionDurations[Condition.prone.rawValue] = 1
        c.conditionNotes[Condition.prone.rawValue] = "shove"
        #expect(c.restClearedConditionKeys == [Condition.prone.rawValue])
        // the natural tick-out ends exactly that set, notes included
        let ended = c.tickConditionDurations()
        #expect(ended == ["Prone"])
        #expect(c.conditions.isEmpty && c.conditionDurations.isEmpty && c.conditionNotes.isEmpty)
    }
}
