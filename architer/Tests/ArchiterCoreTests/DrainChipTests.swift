import Foundation
import Testing
@testable import ArchiterCore

@Suite("Drain chip (3.77.0)")
struct DrainChipTests {
    @Test func drainedCharacterGetsALastChipOnBothSurfaces() {
        var c = Character(name: "T", maxHP: 32, currentHP: 30)
        #expect(PartyCardSummary(character: c).chips.isEmpty)
        c.setMaxHPReduction(8)
        #expect(PartyCardSummary(character: c).chips == ["Max -8"])
        #expect(partyDetailRows([c]).first?.chips.map(\.text) == ["Max -8"])
    }

    @Test func chipRidesLastAndClearsOnLongRest() {
        var c = Character(name: "T", maxHP: 32, currentHP: 30)
        c.conditions.insert(.prone)
        c.setMaxHPReduction(3)
        #expect(PartyCardSummary(character: c).chips.last == "Max -3")
        c.longRest()
        #expect(!PartyCardSummary(character: c).chips.contains { $0.hasPrefix("Max -") })
    }
}
