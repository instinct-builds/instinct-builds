import Foundation
import Testing
@testable import ArchiterCore

@Suite("Condition advisory (3.24.0)")
struct ConditionAdvisoryTests {
    private func character(conditions: Set<Condition> = [], custom: [CustomCondition] = [],
                           exhaustion: Int = 0, era: RulesetVariant = .era2014) -> Character {
        var c = Character(name: "Test")
        c.conditions = conditions
        c.customConditions = custom
        c.exhaustion = exhaustion
        c.era = era
        return c
    }

    @Test func proneHindersAttacksOnly() {
        let lines = ConditionAdvisory.lines(for: character(conditions: [.prone]))
        #expect(lines == ["Attacks hindered: Prone"])
    }

    @Test func poisonedHindersAttacksAndChecks() {
        let lines = ConditionAdvisory.lines(for: character(conditions: [.poisoned]))
        #expect(lines == ["Attacks hindered: Poisoned", "Checks hindered: Poisoned"])
    }

    @Test func customConditionNamesAppear() {
        let custom = CustomCondition(name: "Hexed", hindersAttacks: true)
        let lines = ConditionAdvisory.lines(for: character(custom: [custom]))
        #expect(lines == ["Attacks hindered: Hexed"])
    }

    @Test func exhaustionAddsPenaltyLine() {
        // 2024-style: the penalty equals the exhaustion level.
        let lines = ConditionAdvisory.lines(for: character(exhaustion: 2, era: .era2024))
        #expect(lines == ["Exhaustion 2: -2 on d20 rolls"])
    }

    @Test func exhaustionIsSilentUnder2014() {
        // 2014-style carries no numeric roll penalty, so there is nothing to
        // mirror - the gate matches what rollCheck would actually subtract.
        let lines = ConditionAdvisory.lines(for: character(exhaustion: 2, era: .era2014))
        #expect(lines.isEmpty)
    }

    @Test func cleanCharacterHasNoLines() {
        #expect(ConditionAdvisory.lines(for: character()).isEmpty)
    }

    @Test func builtInsSortBeforeCustomsByName() {
        let custom = CustomCondition(name: "Ablaze", hindersAttacks: true)
        let lines = ConditionAdvisory.lines(for: character(conditions: [.restrained, .blinded], custom: [custom]))
        #expect(lines == ["Attacks hindered: Blinded, Restrained, Ablaze"])
    }

    @Test func immobilizeOnlyConditionStaysOutOfTheAdvisory() {
        let rooted = CustomCondition(name: "Rooted", immobilizes: true)
        #expect(ConditionAdvisory.lines(for: character(custom: [rooted])).isEmpty)
    }
}
