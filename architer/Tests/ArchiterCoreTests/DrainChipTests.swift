import Foundation
import Testing
@testable import ArchiterCore

@Suite("Drain chip (3.77.0)")
struct DrainChipTests {
    @Test func drainedCharacterGetsALastChipOnBothSurfaces() {
        var c = Character(name: "T", maxHP: 32, currentHP: 30)
        #expect(PartyCardSummary(character: c).chips.isEmpty)
        #expect(PartyCardSummary(character: c).drainChip == nil)
        c.setMaxHPReduction(8)
        #expect(PartyCardSummary(character: c).drainChip == "Max -8")
        #expect(PartyCardSummary(character: c).chips.isEmpty)
        #expect(partyDetailRows([c]).first?.chips.map(\.text) == ["Max -8"])
    }

    @Test func chipRidesLastAndClearsOnLongRest() {
        var c = Character(name: "T", maxHP: 32, currentHP: 30)
        c.conditions.insert(.prone)
        c.setMaxHPReduction(3)
        #expect(PartyCardSummary(character: c).drainChip == "Max -3")
        #expect(PartyCardSummary(character: c).chips == ["Prone"])
        c.longRest()
        #expect(PartyCardSummary(character: c).drainChip == nil)
    }
}
