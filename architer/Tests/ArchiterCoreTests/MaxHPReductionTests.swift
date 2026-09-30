import Foundation
import Testing
@testable import ArchiterCore

@Suite("Max-HP reduction (3.74.0)")
struct MaxHPReductionTests {
    @Test func drainLowersEffectiveMaxAndPullsCurrentDown() {
        var c = Character(name: "T", maxHP: 32, currentHP: 24)
        c.setMaxHPReduction(10)
        #expect(c.effectiveMaxHP == 22)
        #expect(c.currentHP == 22)
        #expect(c.maxHP == 32)
    }

    @Test func healingCapsAtTheDrainedMax() {
        var c = Character(name: "T", maxHP: 20, currentHP: 5)
        c.setMaxHPReduction(8)
        c.applyHealing(100)
        #expect(c.currentHP == 12)
    }

    @Test func drainClampsAndFloorsTheCeilingAtOne() {
        var c = Character(name: "T", maxHP: 10)
        c.setMaxHPReduction(999)
        #expect(c.maxHPReduction == 9)
        #expect(c.effectiveMaxHP == 1)
        c.setMaxHPReduction(-3)
        #expect(c.maxHPReduction == 0)
    }

    @Test func longRestLiftsTheDrainShortRestDoesNot() {
        var c = Character(name: "T", maxHP: 20)
        c.setMaxHPReduction(6)
        c.shortRest()
        #expect(c.maxHPReduction == 6)
        c.longRest()
        #expect(c.maxHPReduction == 0)
        #expect(c.currentHP == 20)
    }

    @Test func roundTripClampAndLegacy() throws {
        var c = Character(name: "T", maxHP: 20)
        c.setMaxHPReduction(7)
        let data = try JSONEncoder().encode(c)
        #expect(try JSONDecoder().decode(Character.self, from: data).maxHPReduction == 7)
        var obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        obj["maxHPReduction"] = 999
        let big = try JSONSerialization.data(withJSONObject: obj)
        #expect(try JSONDecoder().decode(Character.self, from: big).maxHPReduction == 19)
        obj.removeValue(forKey: "maxHPReduction")
        let legacy = try JSONSerialization.data(withJSONObject: obj)
        #expect(try JSONDecoder().decode(Character.self, from: legacy).maxHPReduction == 0)
    }
}
