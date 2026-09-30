import Foundation
import Testing
@testable import ArchiterCore

/// Party detail panel (3.68.0): the wide surface's rows derive in the
/// summary line's exact grammar, show every chip, and list every member.
@Suite("Party detail panel rows (3.68.0)")
struct PartyDetailPanelTests {
    private func character(name: String = "Wren") -> Character {
        Character(name: name)
    }

    @Test func notedClockedBuiltInUsesTheSummaryGrammar() {
        var c = character()
        c.conditions.insert(.frightened)
        c.conditionDurations[Condition.frightened.rawValue] = 2
        c.conditionNotes[Condition.frightened.rawValue] = "the howl"
        #expect(partyDetailRows([c]).first?.chips.map(\.text)
            == ["Frightened 2r (the howl)"])
    }

    @Test func bareBuiltInStaysBare() {
        var c = character()
        c.conditions.insert(.prone)
        #expect(partyDetailRows([c]).first?.chips.map(\.text) == ["Prone"])
    }

    @Test func oneRoundClockMarksExpiring() {
        var c = character()
        let hexed = CustomCondition(name: "Hexed")
        c.customConditions = [hexed]
        c.conditionDurations[hexed.id.uuidString] = 1
        c.conditionNotes[hexed.id.uuidString] = "the brand"
        let chips = partyDetailRows([c]).first?.chips
        #expect(chips?.map(\.text) == ["Hexed 1r (the brand)"])
        #expect(chips?.map(\.expiring) == [true])
    }

    @Test func builtInsSortBeforeCustomsChipOrder() {
        var c = character()
        c.conditions.insert(.stunned)
        c.conditions.insert(.blinded)
        c.customConditions = [CustomCondition(name: "Vault-marked")]
        #expect(partyDetailRows([c]).first?.chips.map(\.text)
            == ["Blinded", "Stunned", "Vault-marked"])
    }

    @Test func concentrationRidesLastWithAndWithoutTimer() {
        var timed = character()
        timed.concentratingOn = "Misty step"
        timed.concentrationTimer = 3
        #expect(partyDetailRows([timed]).first?.chips.map(\.text)
            == ["Concentrating: Misty step (3)"])
        var untimed = character()
        untimed.concentratingOn = "Bless"
        #expect(partyDetailRows([untimed]).first?.chips.map(\.text)
            == ["Concentrating: Bless"])
    }

    @Test func emptyMemberStillListsWithHP() {
        var c = character(name: "Sera")
        c.currentHP = 14
        c.maxHP = 20
        c.tempHP = 3
        let row = partyDetailRows([c]).first
        #expect(row?.chips.isEmpty == true)
        #expect(row?.name == "Sera")
        #expect(row?.currentHP == 14 && row?.maxHP == 20 && row?.tempHP == 3)
    }

    @Test func everyChipShowsNoCap() {
        var c = character()
        c.conditions.insert(.blinded)
        c.conditions.insert(.prone)
        c.conditions.insert(.stunned)
        c.customConditions = [CustomCondition(name: "Hexed")]
        c.concentratingOn = "Bless"
        #expect(partyDetailRows([c]).first?.chips.count == 5)
    }
}
