import Foundation
import Testing
@testable import ArchiterCore

@Suite("Drain recovery on rest (3.80.0)")
struct DrainRecoveryTests {
    @Test func defaultLongRestLiftsTheWholeDrain() {
        var c = Character(name: "T", maxHP: 32, currentHP: 10)
        c.setMaxHPReduction(12)
        c.longRest()
        #expect(c.maxHPReduction == 0)
        #expect(c.currentHP == 32)
    }

    @Test func configuredRestLiftsOnlyThatMuchAndHealsToTheNewCeiling() {
        var c = Character(name: "T", maxHP: 32, currentHP: 10)
        c.setMaxHPReduction(12)
        c.longRestDrainRecovery = 5
        c.longRest()
        #expect(c.maxHPReduction == 7)
        #expect(c.effectiveMaxHP == 25)
        #expect(c.currentHP == 25)
        c.longRest()
        #expect(c.maxHPReduction == 2)
        c.longRest()
        #expect(c.maxHPReduction == 0)
        #expect(c.currentHP == 32)
    }

    @Test func zeroRecoveryKeepsTheDrain() {
        var c = Character(name: "T", maxHP: 32, currentHP: 10)
        c.setMaxHPReduction(12)
        c.longRestDrainRecovery = 0
        c.longRest()
        #expect(c.maxHPReduction == 12)
        #expect(c.currentHP == 20)
    }

    @Test func oldSavesDecodeAsFullLiftAndSettingRoundTrips() throws {
        var c = Character(name: "T", maxHP: 32, currentHP: 10)
        let old = try JSONDecoder().decode(Character.self, from: JSONEncoder().encode(c))
        #expect(old.longRestDrainRecovery == nil)
        c.longRestDrainRecovery = 4
        let back = try JSONDecoder().decode(Character.self, from: JSONEncoder().encode(c))
        #expect(back.longRestDrainRecovery == 4)
    }
}
