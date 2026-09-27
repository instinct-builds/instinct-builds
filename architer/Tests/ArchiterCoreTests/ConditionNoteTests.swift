import Foundation
import Testing
@testable import ArchiterCore

@Suite("Condition notes (3.58.0)")
struct ConditionNoteTests {
    private func character(name: String = "Wren") -> Character {
        Character(name: name)
    }

    @Test func blankNormalizesToNil() {
        #expect(Character.normalizedConditionNote("") == nil)
        #expect(Character.normalizedConditionNote("   ") == nil)
        #expect(Character.normalizedConditionNote("\n") == nil)
    }

    @Test func trimsAndFlattensToOneLine() {
        #expect(Character.normalizedConditionNote("  sting\nsave each turn  ") == "sting save each turn")
    }

    @Test func capsAt24Characters() {
        let normalized = Character.normalizedConditionNote("this note is definitely over the cap")
        #expect(normalized == "this note is definitely")
        #expect((normalized?.count ?? 99) <= 24)
    }

    @Test func summaryCarriesTheNoteInParens() {
        var c = character()
        c.conditions.insert(.poisoned)
        c.conditionNotes[Condition.poisoned.rawValue] = "sting"
        c.conditions.insert(.prone)
        c.conditionDurations[Condition.prone.rawValue] = 1
        c.conditionNotes[Condition.prone.rawValue] = "shove"
        let items = partyConditionSummaryItems([c])
        #expect(items.first?.text == "Wren: Poisoned (sting), Prone 1r (shove)")
        #expect(items.first?.parts.first(where: { $0.label == "Poisoned" })?.note == "sting")
        #expect(items.first?.parts.first(where: { $0.label == "Prone 1r" })?.expiring == true)
    }

    @Test func noteFreeRosterKeepsTheByteIdenticalString() {
        var c = character()
        c.conditions.insert(.poisoned)
        c.conditions.insert(.prone)
        c.conditionDurations[Condition.prone.rawValue] = 2
        #expect(partyConditionSummary([c]) == "Wren: Poisoned, Prone 2r")
    }

    @Test func tickDropsTheNoteWithTheCondition() {
        var c = character()
        c.conditions.insert(.prone)
        c.conditionDurations[Condition.prone.rawValue] = 1
        c.conditionNotes[Condition.prone.rawValue] = "shove"
        let ended = c.tickConditionDurations()
        #expect(ended == ["Prone"])
        #expect(c.conditionNotes[Condition.prone.rawValue] == nil)
    }

    @Test func notesRoundTripThroughCodable() throws {
        var c = character()
        c.conditions.insert(.poisoned)
        c.conditionNotes[Condition.poisoned.rawValue] = "sting"
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        let data = try enc.encode(c)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let back = try dec.decode(Character.self, from: data)
        #expect(back.conditionNotes == c.conditionNotes)
    }

    @Test func pre358SavesDecodeWithNotesEmpty() throws {
        var c = character()
        c.conditions.insert(.poisoned)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        let data = try enc.encode(c)
        var obj = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        obj.removeValue(forKey: "conditionNotes")
        let stripped = try JSONSerialization.data(withJSONObject: obj)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let back = try dec.decode(Character.self, from: stripped)
        #expect(back.conditions.contains(.poisoned))
        #expect(back.conditionNotes.isEmpty)
    }
}
