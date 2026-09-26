import Foundation
import Testing
@testable import ArchiterCore

@Suite("Group saves (3.31.0)")
struct GroupSaveTests {
    private func character(name: String, wis: Int = 14, proficient: Bool = false) -> Character {
        var c = Character(name: name)
        c.level = 5
        c.scores = AbilityScores([.wisdom: wis])
        if proficient { c.savingThrowProficiencies = [.wisdom] }
        return c
    }

    @Test func labelKindDetection() {
        #expect(Character.d20RollKind(forLabel: "Warhammer attack") == .attack)
        #expect(Character.d20RollKind(forLabel: "WIS save") == .save)
        #expect(Character.d20RollKind(forLabel: "CON save (concentration)") == .save)
        #expect(Character.d20RollKind(forLabel: "Wren - WIS save") == .save)
        #expect(Character.d20RollKind(forLabel: "Stealth check") == .check)
        #expect(Character.d20RollKind(forLabel: "Calligrapher's supplies check (INT)") == .check)
    }

    @Test func planDerivesSaveTerms() throws {
        var hindered = character(name: "Wren", proficient: true)
        hindered.era = .era2024
        hindered.exhaustion = 2
        hindered.conditions = [.poisoned]
        let plan = try #require(GroupSavePlan(characters: [hindered, character(name: "Bram")],
                                              ability: .wisdom))
        let wren = plan.participants[0]
        // WIS 14 (+2), save-proficient at level 5 (+3) = +5; poisoned does
        // NOT hinder a save, exhaustion still subtracts.
        #expect(wren.bonus == 5)
        #expect(wren.penalty == 2)
        #expect(wren.mode == .normal)
        #expect(wren.tags == ["exhaustion -2"])
        let bram = plan.participants[1]
        #expect(bram.bonus == 2 && bram.penalty == 0 && bram.tags.isEmpty)
    }

    @Test func emptyRosterHasNoPlan() {
        #expect(GroupSavePlan(characters: [], ability: .wisdom) == nil)
    }

    @Test func verdictReusesGroupCheckOutcome() {
        let outcome = GroupCheckOutcome(skillName: "WIS save", targetDC: 13, lines: [
            GroupCheckOutcome.Line(name: "A", total: 15, passed: true, tags: []),
            GroupCheckOutcome.Line(name: "B", total: 9, passed: false, tags: []),
            GroupCheckOutcome.Line(name: "C", total: 13, passed: true, tags: []),
        ])
        #expect(outcome.groupSucceeded == true)
        #expect(outcome.verdictLine == "Group succeeds: 2 of 3 met DC 13.")
    }
}
