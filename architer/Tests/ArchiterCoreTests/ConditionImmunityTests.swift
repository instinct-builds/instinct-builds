import Foundation
import Testing
@testable import ArchiterCore

@Suite("Condition immunity by lineage (3.73.0)")
struct ConditionImmunityTests {
    @Test func lineageKeywordGrantsAreCaseInsensitiveSubstrings() {
        #expect(ConditionImmunity.lineageGrants("Warforged Scout") == [.poisoned])
        #expect(ConditionImmunity.lineageGrants("the UNDEAD knight") == [.poisoned])
        #expect(ConditionImmunity.lineageGrants("Wraithkin") == [.charmed, .poisoned])
        #expect(ConditionImmunity.lineageGrants("High Elf").isEmpty)
        #expect(ConditionImmunity.lineageGrants("").isEmpty)
    }

    @Test func derivedAndStoredUnionWithSourceLabels() {
        var c = Character(name: "Bram", lineage: "Stoneborn")
        c.conditionImmunities = [.charmed]
        #expect(c.allConditionImmunities == [.petrified, .charmed])
        #expect(c.conditionImmunitySource(.petrified) == "lineage")
        #expect(c.conditionImmunitySource(.charmed) == "set")
        #expect(c.isImmune(to: .petrified))
        #expect(!c.isImmune(to: .poisoned))
    }

    @Test func derivedGrantFollowsLineageEdit() {
        var c = Character(name: "Bram", lineage: "Warforged")
        #expect(c.isImmune(to: .poisoned))
        c.lineage = "Human"
        #expect(!c.isImmune(to: .poisoned))
        #expect(c.conditionImmunities.isEmpty)
    }

    @Test func storedSetRoundTripsAndLegacyDecodesEmpty() throws {
        var c = Character(name: "Bram")
        c.conditionImmunities = [.charmed, .frightened]
        let data = try JSONEncoder().encode(c)
        #expect(try JSONDecoder().decode(Character.self, from: data).conditionImmunities == [.charmed, .frightened])
        var obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        obj.removeValue(forKey: "conditionImmunities")
        let legacy = try JSONSerialization.data(withJSONObject: obj)
        #expect(try JSONDecoder().decode(Character.self, from: legacy).conditionImmunities.isEmpty)
    }
}
