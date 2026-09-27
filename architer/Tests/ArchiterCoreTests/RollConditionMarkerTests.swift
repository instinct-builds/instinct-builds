import Foundation
import Testing
@testable import ArchiterCore

@Suite("Roll condition markers (3.63.0)")
struct RollConditionMarkerTests {
    private func character(conditions: Set<Condition> = [], custom: [CustomCondition] = [],
                           exhaustion: Int = 0, era: RulesetVariant = .era2024) -> Character {
        var c = Character(name: "Test")
        c.conditions = conditions
        c.customConditions = custom
        c.exhaustion = exhaustion
        c.era = era
        return c
    }

    @Test func builtInAndCustomReadIdenticallyThroughOnePath() {
        // Same flag, two sources, one producer: identical marker shape, and a
        // character with both lists built-ins first (the source order
        // disadvantageSourceNames has always used).
        let builtIn = character(conditions: [.poisoned])
            .rollConditionMarkers(requestedMode: .normal, for: .check)
        let custom = character(custom: [CustomCondition(name: "Hexed", hindersChecks: true)])
            .rollConditionMarkers(requestedMode: .normal, for: .check)
        #expect(builtIn == ["disadvantage: Poisoned"])
        #expect(custom == ["disadvantage: Hexed"])
        let both = character(conditions: [.poisoned],
                             custom: [CustomCondition(name: "Hexed", hindersChecks: true)])
            .rollConditionMarkers(requestedMode: .normal, for: .check)
        #expect(both == ["disadvantage: Poisoned, Hexed"])
    }

    @Test func unaffectedKindsCarryNoMarker() {
        // An attacks-only flag marks attacks and nothing else.
        let c = character(custom: [CustomCondition(name: "Hexed", hindersAttacks: true)])
        #expect(c.rollConditionMarkers(requestedMode: .normal, for: .attack) == ["disadvantage: Hexed"])
        #expect(c.rollConditionMarkers(requestedMode: .normal, for: .check).isEmpty)
        #expect(c.rollConditionMarkers(requestedMode: .normal, for: .save).isEmpty)
        // A checks-only flag marks checks and nothing else.
        let d = character(custom: [CustomCondition(name: "Rattled", hindersChecks: true)])
        #expect(d.rollConditionMarkers(requestedMode: .normal, for: .check) == ["disadvantage: Rattled"])
        #expect(d.rollConditionMarkers(requestedMode: .normal, for: .attack).isEmpty)
        #expect(d.rollConditionMarkers(requestedMode: .normal, for: .save).isEmpty)
    }

    @Test func savesNeverCarryConditionMarkers() {
        let c = character(conditions: [.poisoned, .prone],
                          custom: [CustomCondition(name: "Hexed", hindersAttacks: true, hindersChecks: true)])
        #expect(c.rollConditionMarkers(requestedMode: .normal, for: .save).isEmpty)
        #expect(c.effectiveRollMode(.normal, for: .save) == .normal)
    }

    @Test func exhaustionMarkerRidesEveryKind() {
        // 2024-style: the penalty equals the exhaustion level.
        let c = character(exhaustion: 2)
        #expect(c.rollConditionMarkers(requestedMode: .normal, for: .attack) == ["exhaustion -2"])
        #expect(c.rollConditionMarkers(requestedMode: .normal, for: .check) == ["exhaustion -2"])
        #expect(c.rollConditionMarkers(requestedMode: .normal, for: .save) == ["exhaustion -2"])
        // 2014-style carries no numeric roll penalty, so there is no marker.
        #expect(character(exhaustion: 2, era: .era2014)
            .rollConditionMarkers(requestedMode: .normal, for: .check).isEmpty)
    }

    @Test func advantageCancelDerivesSourceNames() {
        let c = character(conditions: [.prone],
                          custom: [CustomCondition(name: "Hexed", hindersAttacks: true)])
        #expect(c.rollConditionMarkers(requestedMode: .advantage, for: .attack)
            == ["advantage canceled: Prone, Hexed"])
        #expect(c.effectiveRollMode(.advantage, for: .attack) == .normal)
    }

    @Test func immobilizeMarksMovementNeverRolls() {
        // Custom Speed-0 flag: the movement readout is flagged, every d20
        // roll kind stays marker-free (the pin-3 boundary, both directions).
        let c = character(custom: [CustomCondition(name: "Stone-rooted", immobilizes: true)])
        #expect(c.immobilized)
        #expect(c.effectiveMovementSummary == "0 ft (immobilized)")
        #expect(c.rollConditionMarkers(requestedMode: .normal, for: .attack).isEmpty)
        #expect(c.rollConditionMarkers(requestedMode: .normal, for: .check).isEmpty)
        #expect(c.rollConditionMarkers(requestedMode: .normal, for: .save).isEmpty)
        // Built-in immobilization behaves the same way.
        let g = character(conditions: [.grappled])
        #expect(g.effectiveMovementSummary == "0 ft (immobilized)")
        #expect(g.rollConditionMarkers(requestedMode: .normal, for: .attack).isEmpty)
    }
}
