import Foundation
import Testing
@testable import ArchiterCore

@Suite("Drain on damage (3.75.0)")
struct DrainOnDamageTests {
    private func drainer() -> Character {
        var c = Character(name: "T", maxHP: 32, currentHP: 24)
        c.drainDamageTypes = [.necrotic]
        return c
    }

    @Test func taggedTypeDrainsByHPTaken() {
        var c = drainer()
        c.applyDamage(8, type: .necrotic)
        #expect(c.currentHP == 16)
        #expect(c.maxHPReduction == 8)
    }

    @Test func untaggedAndUntypedNeverDrain() {
        var c = drainer()
        c.applyDamage(4, type: .fire)
        c.applyDamage(4)
        #expect(c.maxHPReduction == 0)
        #expect(c.currentHP == 16)
    }

    @Test func defensesAndTempHPFoldIntoTheDrain() {
        var c = drainer()
        c.resistances = [.necrotic]
        c.tempHP = 2
        c.applyDamage(10, type: .necrotic)   // halved to 5, temp eats 2, 3 reaches HP
        #expect(c.maxHPReduction == 3)
        #expect(c.tempHP == 0)
    }

    @Test func overkillDrainsOnlyWhatWasTaken() {
        var c = drainer()
        c.currentHP = 2
        c.applyDamage(50, type: .necrotic)
        #expect(c.maxHPReduction == 2)
        #expect(c.currentHP == 0)
    }

    @Test func tagSetRoundTripsAndLegacyDecodesEmpty() throws {
        let c = drainer()
        let data = try JSONEncoder().encode(c)
        #expect(try JSONDecoder().decode(Character.self, from: data).drainDamageTypes == [.necrotic])
        var obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        obj.removeValue(forKey: "drainDamageTypes")
        let legacy = try JSONSerialization.data(withJSONObject: obj)
        #expect(try JSONDecoder().decode(Character.self, from: legacy).drainDamageTypes.isEmpty)
    }
}
