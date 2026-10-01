import Foundation
import Testing
@testable import ArchiterCore

@Suite("Party table facts (3.86.0)")
struct PartyTableFactsTests {
    private func member(_ name: String, ac: Int, wisdom: Int, inspired: Bool = false) -> Character {
        var c = Character(name: name, maxHP: 20, currentHP: 20)
        c.armorClass = ac
        var dict = Dictionary(uniqueKeysWithValues: Ability.allCases.map { ($0, 10) })
        dict[.wisdom] = wisdom
        c.scores = AbilityScores(dict)
        c.inspiration = inspired
        return c
    }

    @Test func rowsCarryDerivedFacts() {
        let c = member("Ayla", ac: 16, wisdom: 14, inspired: true)
        let row = partyDetailRows([c]).first
        #expect(row?.armorClass == c.computedAC)
        #expect(row?.passivePerception == c.passivePerception)
        #expect(row?.inspired == true)
    }

    @Test func lineNamesBestPerceptionLowestACAndInspired() {
        let rows = partyDetailRows([
            member("Ayla", ac: 12, wisdom: 10),
            member("Bram", ac: 17, wisdom: 16),
            member("Cora", ac: 15, wisdom: 16, inspired: true),
        ])
        #expect(partyTableFactsLine(rows) ==
                "Best passive Perception 13 (Bram) \u{00B7} Lowest AC 12 (Ayla) \u{00B7} Inspired: Cora")
    }

    @Test func tiesGoToRosterOrderAndNoInspirationOmitsThatPart() {
        let rows = partyDetailRows([
            member("Ayla", ac: 14, wisdom: 12),
            member("Bram", ac: 14, wisdom: 12),
        ])
        #expect(partyTableFactsLine(rows) == "Best passive Perception 11 (Ayla) \u{00B7} Lowest AC 14 (Ayla)")
    }

    @Test func emptyRosterHasNoLine() {
        #expect(partyTableFactsLine([]) == nil)
    }
}
