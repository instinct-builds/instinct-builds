import Foundation
import Testing
@testable import ArchiterCore

@Suite("Encounter estimate (3.34.0)")
struct EncounterTests {
    @Test func thresholdsSumOverLevels() {
        let t = EncounterMath.thresholds(forLevels: [6, 5, 5])
        #expect(t.easy == 300 + 250 + 250)
        #expect(t.medium == 600 + 500 + 500)
        #expect(t.hard == 900 + 750 + 750)
        #expect(t.deadly == 1400 + 1100 + 1100)
    }

    @Test func levelClamp() {
        let low = EncounterMath.thresholds(forLevels: [0])
        let one = EncounterMath.thresholds(forLevels: [1])
        #expect(low == one)
        let high = EncounterMath.thresholds(forLevels: [99])
        let twenty = EncounterMath.thresholds(forLevels: [20])
        #expect(high == twenty)
    }

    @Test func crMapIncludingFractions() {
        #expect(EncounterMath.xp(forCR: 0.125) == 25)
        #expect(EncounterMath.xp(forCR: 0.25) == 50)
        #expect(EncounterMath.xp(forCR: 0.5) == 100)
        #expect(EncounterMath.xp(forCR: 1) == 200)
        #expect(EncounterMath.xp(forCR: 3) == 700)
        #expect(EncounterMath.xp(forCR: 30) == 155000)
        #expect(EncounterMath.xp(forCR: 1.7) == nil)
    }

    @Test func multiplierBrackets() {
        #expect(EncounterMath.multiplier(forEnemyCount: 1) == 1)
        #expect(EncounterMath.multiplier(forEnemyCount: 2) == 1.5)
        #expect(EncounterMath.multiplier(forEnemyCount: 3) == 2)
        #expect(EncounterMath.multiplier(forEnemyCount: 6) == 2)
        #expect(EncounterMath.multiplier(forEnemyCount: 7) == 2.5)
        #expect(EncounterMath.multiplier(forEnemyCount: 11) == 3)
        #expect(EncounterMath.multiplier(forEnemyCount: 15) == 4)
    }

    @Test func bandsAtBoundaries() {
        // Party of one L1: thresholds 25/50/75/100. One CR 1/8 enemy = 25 XP.
        let easy = EncounterMath.estimate(levels: [1], lines: [EncounterLine(count: 1, cr: 0.125)])
        #expect(easy?.band == .easy)
        // Two CR 1/8: base 50 x1.5 = 75 -> hard (75 is not < 75).
        let hard = EncounterMath.estimate(levels: [1], lines: [EncounterLine(count: 2, cr: 0.125)])
        #expect(hard?.adjustedXP == 75)
        #expect(hard?.band == .hard)
        // Ten CR 0: base 100 x2.5 = 250 -> deadly for one L1.
        let deadly = EncounterMath.estimate(levels: [1], lines: [EncounterLine(count: 10, cr: 0)])
        #expect(deadly?.band == .deadly)
        // Zero-count rows contribute nothing.
        let none = EncounterMath.estimate(levels: [1], lines: [EncounterLine(count: 0, cr: 30)])
        #expect(none == nil)
    }

    @Test func nilCases() {
        #expect(EncounterMath.estimate(levels: [], lines: [EncounterLine(count: 1, cr: 1)]) == nil)
        #expect(EncounterMath.estimate(levels: [5], lines: []) == nil)
        #expect(EncounterMath.estimate(levels: [5], lines: [EncounterLine(count: 1, cr: 1.7)]) == nil)
    }

    @Test func crTextRoundTrip() {
        #expect(EncounterMath.crText(0.125) == "1/8")
        #expect(EncounterMath.crText(0.25) == "1/4")
        #expect(EncounterMath.crText(0.5) == "1/2")
        #expect(EncounterMath.crText(3) == "3")
        #expect(EncounterMath.parseCR("1/8") == 0.125)
        #expect(EncounterMath.parseCR(" 12 ") == 12)
        #expect(EncounterMath.parseCR("lots") == nil)
    }
}
