import Foundation
import Testing
@testable import ArchiterCore

@Suite("Group checks (3.26.0)")
struct GroupCheckTests {
    private func rogue(name: String, dex: Int = 16, level: Int = 5,
                       tier: ProficiencyTier = .proficient) -> Character {
        var c = Character(name: name)
        c.level = level
        c.scores = AbilityScores([.dexterity: dex])
        c.skills = [Skill(name: "Stealth", ability: .dexterity, tier: tier)]
        return c
    }

    @Test func planDerivesPerParticipantTerms() throws {
        var hindered = rogue(name: "Wren")
        hindered.era = .era2024
        hindered.exhaustion = 2
        hindered.customConditions = [CustomCondition(name: "Vault-marked", hindersChecks: true)]
        let plan = try #require(GroupCheckPlan(characters: [hindered, rogue(name: "Bram")],
                                               skillName: "Stealth"))
        #expect(plan.participants.count == 2)
        let wren = plan.participants[0]
        // DEX 16 (+3), proficient at level 5 (+3) = +6; 2024 exhaustion step 2 = -2.
        #expect(wren.bonus == 6)
        #expect(wren.penalty == 2)
        #expect(wren.mode == .disadvantage)
        #expect(wren.tags == ["exhaustion -2", "disadvantage: Vault-marked"])
        let bram = plan.participants[1]
        #expect(bram.mode == .normal && bram.penalty == 0 && bram.tags.isEmpty)
    }

    @Test func missingSkillFallsBackToUntrainedAbility() throws {
        var c = rogue(name: "Wren")
        c.skills = [] // a custom ruleset dropped the default list
        let plan = try #require(GroupCheckPlan(characters: [c], skillName: "Stealth"))
        // The default list maps Stealth to dexterity; untrained = raw modifier.
        #expect(plan.participants[0].bonus == 3)
    }

    @Test func unknownSkillScoresZero() throws {
        // A skill name no list knows: bonus 0 rather than a crash.
        let plan = try #require(GroupCheckPlan(characters: [rogue(name: "Wren")],
                                               skillName: "Birdwhistling"))
        #expect(plan.participants[0].bonus == 0)
    }

    @Test func emptyRosterHasNoPlan() {
        #expect(GroupCheckPlan(characters: [], skillName: "Stealth") == nil)
    }

    @Test func verdictIsHalfOrMore() {
        func line(_ passed: Bool?) -> GroupCheckOutcome.Line {
            GroupCheckOutcome.Line(name: "P", total: 10, passed: passed, tags: [])
        }
        let twoOfFour = GroupCheckOutcome(skillName: "Stealth", targetDC: 12,
                                          lines: [line(true), line(true), line(false), line(false)])
        #expect(twoOfFour.passCount == 2)
        #expect(twoOfFour.groupSucceeded == true)
        #expect(twoOfFour.verdictLine == "Group succeeds: 2 of 4 met DC 12.")
        let twoOfFive = GroupCheckOutcome(skillName: "Stealth", targetDC: 12,
                                          lines: [line(true), line(true), line(false),
                                                  line(false), line(false)])
        #expect(twoOfFive.groupSucceeded == false)
        #expect(twoOfFive.verdictLine == "Group fails: 2 of 5 met DC 12.")
        let oneOfTwo = GroupCheckOutcome(skillName: "Stealth", targetDC: 12,
                                         lines: [line(true), line(false)])
        #expect(oneOfTwo.groupSucceeded == true)
    }

    @Test func noDCMeansNoVerdict() {
        let outcome = GroupCheckOutcome(skillName: "Stealth", targetDC: nil,
                                        lines: [GroupCheckOutcome.Line(name: "P", total: 14,
                                                                       passed: nil, tags: [])])
        #expect(outcome.groupSucceeded == nil)
        #expect(outcome.verdictLine == nil)
        #expect(outcome.passCount == 0)
    }
}
