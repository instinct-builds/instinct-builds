import Foundation
import Testing
@testable import ArchiterCore

@Suite("Party strip cards (3.29.0)")
struct PartyCardTests {
    private func character(name: String) -> Character {
        var c = Character(name: name)
        c.level = 5
        c.maxHP = 38
        c.currentHP = 21
        c.tempHP = 4
        return c
    }

    @Test func cardDerivesFromTheSheet() {
        var c = character(name: "Wren")
        c.conditions = [.prone]
        c.customConditions = [CustomCondition(name: "Vault-marked", hindersChecks: true)]
        c.beginConcentration(on: "Ember Ward")
        let card = PartyCardSummary(character: c)
        #expect(card.name == "Wren")
        #expect(card.currentHP == 21 && card.maxHP == 38 && card.tempHP == 4)
        // Built-ins sorted first, then custom, then the concentration chip.
        #expect(card.chips == ["Prone", "Vault-marked", "Concentrating: Ember Ward"])
    }

    @Test func truncationKeepsTwoPlusCount() {
        var c = character(name: "Wren")
        c.conditions = [.prone, .poisoned]
        c.customConditions = [CustomCondition(name: "Vault-marked", hindersChecks: true)]
        let card = PartyCardSummary(character: c)
        #expect(card.visibleChips == ["Poisoned", "Prone"])
        #expect(card.extraChipCount == 1)
    }

    @Test func cleanCharacterHasNoChipsAndNoMarker() {
        let card = PartyCardSummary(character: character(name: "Bram"))
        #expect(card.chips.isEmpty)
        #expect(card.visibleChips.isEmpty)
        #expect(card.extraChipCount == 0)
    }

    @Test func exactlyTwoChipsShowsNoMarker() {
        var c = character(name: "Wren")
        c.conditions = [.prone]
        c.beginConcentration(on: "Ember Ward")
        let card = PartyCardSummary(character: c)
        #expect(card.visibleChips == ["Prone", "Concentrating: Ember Ward"])
        #expect(card.extraChipCount == 0)
    }
}
