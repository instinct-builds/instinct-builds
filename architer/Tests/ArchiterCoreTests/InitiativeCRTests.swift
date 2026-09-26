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

@Suite("Add to fight (3.39.0)")
struct AddToFightTests {
    @Test func appendPreservesTurnState() {
        let wren = InitiativeEntry(name: "Wren", bonus: 2, total: 17)
        let tracker = InitiativeTracker(entries: [
            InitiativeEntry(name: "CR 3 #1", bonus: 0, total: 14, cr: 3),
            wren,
        ], activeID: wren.id, round: 2)
        let updated = tracker.appendingFight(from: [EncounterLine(count: 1, cr: 3)])
        #expect(updated.round == 2)
        #expect(updated.activeID == wren.id)
        #expect(updated.entries[0].total == 14)
        #expect(updated.entries.count == 3)
    }

    @Test func numberingContinuesByCRValueThroughRenames() {
        let tracker = InitiativeTracker(entries: [
            InitiativeEntry(name: "CR 3 #1", bonus: 0, cr: 3),
            InitiativeEntry(name: "Gnoll archer", bonus: 0, cr: 3),
            InitiativeEntry(name: "CR 1/2 #1", bonus: 0, cr: 0.5),
        ])
        let updated = tracker.appendingFight(from: [
            EncounterLine(count: 2, cr: 3),
            EncounterLine(count: 1, cr: 0.5),
        ])
        #expect(updated.entries.suffix(3).map(\.name) == ["CR 3 #3", "CR 3 #4", "CR 1/2 #2"])
    }

    @Test func invalidRowsAppendNothing() {
        let tracker = InitiativeTracker(entries: [InitiativeEntry(name: "CR 3 #1", bonus: 0, cr: 3)])
        let updated = tracker.appendingFight(from: [EncounterLine(count: 1, cr: 1.7),
                                                    EncounterLine(count: 0, cr: 2)])
        #expect(updated == tracker)
    }

    @Test func arrivalsSinkBelowRolledEntries() {
        let tracker = InitiativeTracker(entries: [
            InitiativeEntry(name: "Wren", bonus: 2, total: 17),
            InitiativeEntry(name: "CR 3 #1", bonus: 0, total: 12, cr: 3),
        ])
        let updated = tracker.appendingFight(from: [EncounterLine(count: 1, cr: 3)])
        #expect(updated.ordered.first?.name == "Wren")
        #expect(updated.ordered.last?.total == nil)
    }
}


@Suite struct XPAwardPlanTests {
    private func members() -> [(id: UUID, name: String, xp: Int, level: Int, included: Bool)] {
        [(UUID(), "A", 0, 1, true), (UUID(), "B", 7200, 5, true), (UUID(), "C", 200, 1, true)]
    }

    @Test func equalSplitFloorsEvenly() {
        let p = XPAwardPlan(crs: [3, 3, 0.5], members: members(), mode: .equalSplit)
        #expect(p?.baseXP == 1500)
        #expect(p?.adjustedXP == 3000)
        #expect(p?.shares.map(\.amount) == [500, 500, 500])
    }

    @Test func remainderDropsNothingInvented() {
        let p = XPAwardPlan(crs: [3], members: members(), mode: .equalSplit)
        #expect(p?.baseXP == 700)
        #expect(p?.shares.map(\.amount) == [233, 233, 233])
    }

    @Test func fullPoolPaysEachTheWhole() {
        let p = XPAwardPlan(crs: [3, 3, 0.5], members: members(), mode: .fullPool)
        #expect(p?.shares.map(\.amount) == [1500, 1500, 1500])
    }

    @Test func excludedMemberKeepsZeroShareAndReSplits() {
        var m = members()
        m[0].included = false
        let p = XPAwardPlan(crs: [3, 3, 0.5], members: m, mode: .equalSplit)
        #expect(p?.shares.map(\.amount) == [0, 750, 750])
        #expect(p?.shares.first?.included == false)
    }

    @Test func nilWhenNoCRorNoneChecked() {
        #expect(XPAwardPlan(crs: [], members: members(), mode: .equalSplit) == nil)
        #expect(XPAwardPlan(crs: [3], members: members().map { ($0.id, $0.name, $0.xp, $0.level, false) }, mode: .equalSplit) == nil)
    }

    @Test func levelUpBadgeReadsTheXPTrack() {
        var m = members()
        m[0].included = false
        let p = XPAwardPlan(crs: [3, 3, 0.5], members: m, mode: .equalSplit)
        let b = p?.shares.first { $0.name == "B" }
        let c = p?.shares.first { $0.name == "C" }
        #expect(b?.levelsUp == false)   // 7200 + 750 = 7950 stays level 5
        #expect(c?.levelsUp == true)    // 200 + 750 = 950 reaches level 3
        #expect(c?.newLevel == 3)
    }

    @Test func milestoneAheadMemberKeepsLevelAndBadgeStaysOff() {
        // 3.42.0: the preview reads the stored level as a floor, so it
        // agrees with the apply by construction.
        var m = members()
        m[0].included = false
        m[1] = (m[1].id, "B", 7200, 8, true)   // hand-raised: L8 at 7200 XP
        let p = XPAwardPlan(crs: [3, 3, 0.5], members: m, mode: .equalSplit)
        let b = p?.shares.first { $0.name == "B" }
        #expect(b?.levelsUp == false)   // the track derives 5, under stored 8
        #expect(b?.newLevel == 8)       // preview matches the apply
        #expect(b?.amount == 750)       // the XP still pays
    }
}


@Suite struct EncounterLibraryTests {
    @Test func labeledRowsNameAndNumberByLabel() {
        let t = InitiativeTracker.startingFight(from: [
            EncounterLine(count: 2, cr: 3, label: "Gnolls"),
            EncounterLine(count: 1, cr: 0.5),
        ])
        #expect(t.entries.map(\.name) == ["Gnolls #1", "Gnolls #2", "CR 1/2 #1"])
        #expect(t.entries[0].label == "Gnolls")
        #expect(t.entries[2].label == nil)
    }

    @Test func waveNumberingKeysTheLabelFieldNotNames() {
        var t = InitiativeTracker.startingFight(from: [EncounterLine(count: 2, cr: 3, label: "Gnolls")])
        t.entries[0].name = "Bridge boss"   // a rename, as at the table
        let t2 = t.appendingFight(from: [EncounterLine(count: 2, cr: 3, label: "Gnolls")])
        #expect(t2.entries.map(\.name) == ["Bridge boss", "Gnolls #2", "Gnolls #3", "Gnolls #4"])
    }

    @Test func unlabeledNumberingUnchanged() {
        let t = InitiativeTracker.startingFight(from: [EncounterLine(count: 2, cr: 3)])
        #expect(t.entries.map(\.name) == ["CR 3 #1", "CR 3 #2"])
        #expect(t.entries.allSatisfy { $0.label == nil })
    }

    @Test func preLabelRowsDecodeUnchanged() throws {
        let json = "[{\"id\":\"\(UUID().uuidString)\",\"count\":2,\"cr\":3.0}]"
        let lines = try JSONDecoder().decode([EncounterLine].self, from: Data(json.utf8))
        #expect(lines.count == 1)
        #expect(lines[0].label == "")
        #expect(lines[0].count == 2)
        #expect(lines[0].cr == 3)
    }

    @Test func summaryDerivesFromLines() {
        let s = SavedEncounter(name: "T", lines: [
            EncounterLine(count: 2, cr: 3, label: "Gnolls"),
            EncounterLine(count: 1, cr: 0.5),
        ])
        #expect(s.summary == "2x Gnolls · 1x CR 1/2")
    }
}
/// Pre-fight restore + fight recap (3.44.0): the snapshot is one level
/// deep and survives persistence; the recap derives from stored inputs
/// and stays silent on an idle tracker.
@Suite struct PreFightRecapTests {
    @Test func pre344TrackerDecodesWithoutNewKeys() throws {
        // Pre-3.44.0 tracker JSON lacks fightAward / preFightSnapshot.
        let json = #"{"entries":[],"round":2}"#
        let t = try JSONDecoder().decode(InitiativeTracker.self, from: Data(json.utf8))
        #expect(t.round == 2)
        #expect(t.fightAward == nil)
        #expect(t.preFightSnapshot == nil)
    }

    @Test func recapNilUntilTheFightRan() {
        var t = InitiativeTracker.startingFight(from: [EncounterLine(count: 2, cr: 3),
                                                       EncounterLine(count: 1, cr: 0.5)])
        #expect(t.fightRecapLine == nil)   // never rolled, round 1, no award
        t.entries[0].total = 15
        #expect(t.fightRecapLine == "Fight over: 2x CR 3 + 1x CR 1/2 - 1 round")
    }

    @Test func recapNamesRoundsAndAward() {
        var t = InitiativeTracker.startingFight(from: [EncounterLine(count: 2, cr: 3),
                                                       EncounterLine(count: 1, cr: 0.5)])
        t.entries[0].total = 15
        t.round = 3
        t.fightAward = FightAward(total: 1500, recipients: ["Wren", "Bram", "Sera"])
        #expect(t.fightRecapLine == "Fight over: 2x CR 3 + 1x CR 1/2 - 3 rounds - 1500 XP to Wren, Bram, Sera")
    }

    @Test func endCombatConsumesTheAward() {
        var t = InitiativeTracker.startingFight(from: [EncounterLine(count: 1, cr: 3)])
        t.entries[0].total = 12
        t.fightAward = FightAward(total: 700, recipients: ["Wren"])
        #expect(t.fightRecapLine != nil)
        t.endCombat()
        #expect(t.fightAward == nil)
        #expect(t.fightRecapLine == nil)   // totals cleared, round reset
    }

    @Test func snapshotSurvivesPersistence() throws {
        var t = InitiativeTracker.startingFight(from: [EncounterLine(count: 1, cr: 2)])
        t.preFightSnapshot = PreFightSnapshot(
            entries: [InitiativeEntry(name: "Lone sentry", bonus: 2, total: 14, cr: 1)],
            activeID: nil, round: 2,
            fightAward: FightAward(total: 450, recipients: ["Wren"]))
        let data = try JSONEncoder().encode(t)
        let back = try JSONDecoder().decode(InitiativeTracker.self, from: data)
        #expect(back.preFightSnapshot?.entries.map(\.name) == ["Lone sentry"])
        #expect(back.preFightSnapshot?.round == 2)
        #expect(back.preFightSnapshot?.fightAward?.total == 450)
    }
}
