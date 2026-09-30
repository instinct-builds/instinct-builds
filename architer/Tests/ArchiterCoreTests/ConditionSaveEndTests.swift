import Foundation
import Testing
@testable import ArchiterCore

@Suite("Save-ends conditions (3.72.0)")
struct ConditionSaveEndTests {
    private func character(name: String = "Wren") -> Character {
        Character(name: name)
    }

    @Test func saveEndsRoundTripThroughCodable() throws {
        var c = character()
        c.conditions.insert(.frightened)
        c.conditionSaveEnds[Condition.frightened.rawValue] = ConditionSaveEnd(dc: 15, ability: .wisdom)
        let data = try JSONEncoder().encode(c)
        let back = try JSONDecoder().decode(Character.self, from: data)
        #expect(back.conditionSaveEnds[Condition.frightened.rawValue] == ConditionSaveEnd(dc: 15, ability: .wisdom))
    }

    @Test func legacyBlobWithoutSaveEndsDecodesEmpty() throws {
        var c = character()
        c.conditions.insert(.prone)
        let data = try JSONEncoder().encode(c)
        var obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        obj.removeValue(forKey: "conditionSaveEnds")
        let legacy = try JSONSerialization.data(withJSONObject: obj)
        let back = try JSONDecoder().decode(Character.self, from: legacy)
        #expect(back.conditionSaveEnds.isEmpty)
    }

    @Test func timerEndClearsTheSaveEndKey() {
        var c = character()
        c.conditions.insert(.frightened)
        c.conditionDurations[Condition.frightened.rawValue] = 1
        c.conditionSaveEnds[Condition.frightened.rawValue] = ConditionSaveEnd(dc: 12, ability: .wisdom)
        let ended = c.tickConditionDurations()
        #expect(ended == ["Frightened"])
        #expect(c.conditionSaveEnds.isEmpty)
    }

    @Test func customTimerEndClearsTheSaveEndKey() {
        var c = character()
        let cc = CustomCondition(name: "Vault-marked")
        c.customConditions = [cc]
        c.conditionDurations[cc.id.uuidString] = 1
        c.conditionSaveEnds[cc.id.uuidString] = ConditionSaveEnd(dc: 12, ability: .charisma)
        let ended = c.tickConditionDurations()
        #expect(ended == ["Vault-marked"])
        #expect(c.conditionSaveEnds.isEmpty)
    }

    @Test func saveEndSpecIsValueSemantics() {
        let a = ConditionSaveEnd(dc: 10, ability: .constitution)
        var b = a
        b.dc = 20
        #expect(a.dc == 10)
        #expect(a != b)
    }
}
