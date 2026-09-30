import Foundation
import Testing
@testable import ArchiterCore

@Suite("Concentration break classification (3.71.0)")
struct ConcentrationBreakTests {
    @Test func incapacitatingStatesBreakConcentration() {
        for condition: Condition in [.incapacitated, .paralyzed, .petrified, .stunned, .unconscious] {
            #expect(condition.breaksConcentration, "\(condition.displayName) must break concentration")
        }
    }

    @Test func otherBuiltInsNeverBreakConcentration() {
        for condition: Condition in [.blinded, .charmed, .deafened, .frightened, .grappled,
                                     .invisible, .poisoned, .prone, .restrained] {
            #expect(!condition.breaksConcentration, "\(condition.displayName) must not break concentration")
        }
    }

    @Test func allCasesClassifiedExactly() {
        let breaking = Condition.allCases.filter(\.breaksConcentration)
        #expect(breaking.count == 5)
        #expect(Condition.allCases.count == 14)
    }

    @Test func customConditionsHaveNoBreakFlag() {
        // Customs are mechanical-only homebrew states; the break is a
        // built-in-only classification, so there is nothing to set and
        // nothing to store. Pin that the type carries no such concept by
        // exercising the flags it does have.
        let custom = CustomCondition(name: "Dazed", hindersAttacks: true, hindersChecks: true, immobilizes: true)
        #expect(custom.hindersAttacks && custom.hindersChecks && custom.immobilizes)
    }
}
