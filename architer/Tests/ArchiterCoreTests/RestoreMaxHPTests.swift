import Foundation
import Testing
@testable import ArchiterCore

@Suite("Partial restore (3.78.0)")
struct RestoreMaxHPTests {
    @Test func liftsByAmountAndClampsAtTheDrain() {
        var c = Character(name: "T", maxHP: 32, currentHP: 10)
        c.setMaxHPReduction(8)
        #expect(c.restoreMaxHP(5) == 5)
        #expect(c.maxHPReduction == 3)
        #expect(c.restoreMaxHP(99) == 3)
        #expect(c.maxHPReduction == 0)
    }

    @Test func undrainedAndNonPositiveAreNoOps() {
        var c = Character(name: "T", maxHP: 32, currentHP: 10)
        #expect(c.restoreMaxHP(5) == 0)
        c.setMaxHPReduction(4)
        #expect(c.restoreMaxHP(0) == 0)
        #expect(c.restoreMaxHP(-3) == 0)
        #expect(c.maxHPReduction == 4)
    }

    @Test func currentHPNeverRises() {
        var c = Character(name: "T", maxHP: 32, currentHP: 30)
        c.setMaxHPReduction(10)
        #expect(c.currentHP == 22)
        c.restoreMaxHP(10)
        #expect(c.currentHP == 22)
        #expect(c.effectiveMaxHP == 32)
    }
}
