import Foundation
import Testing
@testable import ArchiterCore

@Suite("Initiative CR + live-fight estimate (3.36.0)")
struct InitiativeCRTests {
    @Test func crRoundTripsThroughCodable() throws {
        let entry = InitiativeEntry(name: "Gnoll 1", bonus: 1, cr: 3)
        let data = try JSONEncoder().encode(entry)
        let back = try JSONDecoder().decode(InitiativeEntry.self, from: data)
        #expect(back.cr == 3)
        #expect(back.name == "Gnoll 1")
    }

    @Test func oldSaveWithoutCRDecodes() throws {
        let json = #"{"id":"00000000-0000-0000-0000-000000000001","name":"Gnoll","bonus":1,"total":14}"#
        let back = try JSONDecoder().decode(InitiativeEntry.self, from: Data(json.utf8))
        #expect(back.cr == nil)
        #expect(back.name == "Gnoll")
        #expect(back.total == 14)
    }

    @Test func linesFromCRsAreOneCreaturePerEntry() {
        let tracker = InitiativeTracker(entries: [
            InitiativeEntry(name: "Gnoll 1", bonus: 1, cr: 3),
            InitiativeEntry(name: "Gnoll 2", bonus: 1, cr: 3),
            InitiativeEntry(name: "Snapjaw", bonus: 2, cr: 0.5),
            InitiativeEntry(name: "Wren", bonus: 2),
        ])
        let lines = tracker.encounterLinesFromCRs
        #expect(lines.count == 3)
        #expect(lines.allSatisfy { $0.count == 1 })
        #expect(lines.map(\.cr).sorted(by: >) == [3, 3, 0.5])
        #expect(tracker.entriesWithoutCR == 1)
    }

    @Test func liveEstimateDerivesFromTrackerOnly() {
        let tracker = InitiativeTracker(entries: [
            InitiativeEntry(name: "Gnoll 1", bonus: 1, cr: 3),
            InitiativeEntry(name: "Gnoll 2", bonus: 1, cr: 3),
            InitiativeEntry(name: "Snapjaw", bonus: 2, cr: 0.5),
            InitiativeEntry(name: "Wren", bonus: 2),
            InitiativeEntry(name: "Bram", bonus: 1),
            InitiativeEntry(name: "Sera", bonus: 2),
        ])
        let est = EncounterMath.estimate(levels: [6, 5, 5], lines: tracker.encounterLinesFromCRs)
        #expect(est?.baseXP == 1500)
        #expect(est?.enemyCount == 3)
        #expect(est?.multiplier == 2)
        #expect(est?.adjustedXP == 3000)
        #expect(est?.band == .hard)
        #expect(tracker.entriesWithoutCR == 3)
    }

    @Test func noCRsMeansNoEstimate() {
        let tracker = InitiativeTracker(entries: [InitiativeEntry(name: "Wren", bonus: 2)])
        #expect(tracker.encounterLinesFromCRs.isEmpty)
        #expect(EncounterMath.estimate(levels: [6], lines: tracker.encounterLinesFromCRs) == nil)
    }

    @Test func breakdownNamesHighestFirst() {
        let tracker = InitiativeTracker(entries: [
            InitiativeEntry(name: "A", bonus: 0, cr: 0.5),
            InitiativeEntry(name: "B", bonus: 0, cr: 3),
            InitiativeEntry(name: "C", bonus: 0, cr: 3),
        ])
        #expect(tracker.crBreakdown == "2x CR 3 + 1x CR 1/2")
    }

    @Test func endCombatKeepsCRs() {
        var tracker = InitiativeTracker(entries: [InitiativeEntry(name: "Gnoll", bonus: 1, total: 12, cr: 3)])
        tracker.endCombat()
        #expect(tracker.entries[0].cr == 3)
        #expect(tracker.entries[0].total == nil)
    }
}

@Suite("Start fight (3.37.0)")
struct StartFightTests {
    @Test func expandsRowsIntoIndividualEntries() {
        let tracker = InitiativeTracker.startingFight(from: [
            EncounterLine(count: 2, cr: 3),
            EncounterLine(count: 1, cr: 0.5),
        ])
        #expect(tracker.entries.map(\.name) == ["CR 3 #1", "CR 3 #2", "CR 1/2 #1"])
        #expect(tracker.entries.map(\.cr) == [3, 3, 0.5])
        #expect(tracker.entries.allSatisfy { $0.bonus == 0 && $0.total == nil })
        #expect(tracker.round == 1)
        #expect(tracker.activeID == nil)
    }

    @Test func numberingIsGlobalAcrossSameCRRows() {
        let tracker = InitiativeTracker.startingFight(from: [
            EncounterLine(count: 2, cr: 3),
            EncounterLine(count: 1, cr: 3),
        ])
        #expect(tracker.entries.map(\.name) == ["CR 3 #1", "CR 3 #2", "CR 3 #3"])
    }

    @Test func unknownCRAndZeroCountAreSkipped() {
        let tracker = InitiativeTracker.startingFight(from: [
            EncounterLine(count: 1, cr: 1.7),
            EncounterLine(count: 0, cr: 3),
            EncounterLine(count: 1, cr: 2),
        ])
        #expect(tracker.entries.map(\.name) == ["CR 2 #1"])
    }

    @Test func emptyInputYieldsEmptyTracker() {
        #expect(InitiativeTracker.startingFight(from: []).entries.isEmpty)
        #expect(InitiativeTracker.startingFight(from: [EncounterLine(count: 1, cr: 1.7)]).entries.isEmpty)
    }

    @Test func pushedTrackerDrivesTheLiveEstimate() {
        let tracker = InitiativeTracker.startingFight(from: [
            EncounterLine(count: 2, cr: 3),
            EncounterLine(count: 1, cr: 0.5),
        ])
        let est = EncounterMath.estimate(levels: [6, 5, 5], lines: tracker.encounterLinesFromCRs)
        #expect(est?.adjustedXP == 3000)
        #expect(est?.band == .hard)
    }
}
