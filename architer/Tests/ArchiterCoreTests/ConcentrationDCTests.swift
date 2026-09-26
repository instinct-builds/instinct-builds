import Foundation
import Testing
@testable import ArchiterCore

@Suite("Concentration DC (3.28.0)")
struct ConcentrationDCTests {
    @Test func floorAndHalving() {
        #expect(concentrationDC(forDamage: 1) == 10)
        #expect(concentrationDC(forDamage: 8) == 10)
        #expect(concentrationDC(forDamage: 20) == 10)
        #expect(concentrationDC(forDamage: 21) == 10)
        #expect(concentrationDC(forDamage: 22) == 11)
        #expect(concentrationDC(forDamage: 23) == 11)
        #expect(concentrationDC(forDamage: 40) == 20)
    }
}
