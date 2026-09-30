import Foundation
import Testing
@testable import ArchiterCore

/// Undo-restore log lines (3.66.0): the diff names exactly the conditions
/// the step brought back, notes riding in the removal line's shape.
@Suite("Condition restore log lines (3.66.0)")
struct ConditionRestoreLogTests {
    private func character(name: String = "Wren") -> Character {
        Character(name: name)
    }

    @Test func restoredBuiltInCarriesTheNote() {
        var after = character()
        after.conditions.insert(.frightened)
        after.conditionNotes[Condition.frightened.rawValue] = "the howl"
        #expect(ConditionRestoreLog.lines(before: character(), after: after)
            == ["restored Frightened on Wren (note: the howl)"])
    }

    @Test func unnotedRestoreStaysBare() {
        var after = character()
        after.conditions.insert(.prone)
        #expect(ConditionRestoreLog.lines(before: character(), after: after)
            == ["restored Prone on Wren"])
    }

    @Test func restoredCustomCarriesItsInstanceNote() {
        var after = character()
        let hexed = CustomCondition(name: "Hexed")
        after.customConditions = [hexed]
        after.conditionNotes[hexed.id.uuidString] = "the brand"
        #expect(ConditionRestoreLog.lines(before: character(), after: after)
            == ["restored Hexed on Wren (note: the brand)"])
    }

    @Test func mixedRestoresSortBuiltInsFirstThenCustoms() {
        var after = character()
        after.conditions.insert(.stunned)
        after.conditions.insert(.blinded)
        after.customConditions = [CustomCondition(name: "Hexed"), CustomCondition(name: "Aflame")]
        #expect(ConditionRestoreLog.lines(before: character(), after: after)
            == ["restored Blinded on Wren", "restored Stunned on Wren",
                "restored Aflame on Wren", "restored Hexed on Wren"])
    }

    @Test func conditionsAlreadyHeldAreNotRestorations() {
        var before = character()
        before.conditions.insert(.frightened)
        var after = before
        after.conditions.insert(.prone)
        // Only Prone is new; Frightened survives the step untouched.
        #expect(ConditionRestoreLog.lines(before: before, after: after)
            == ["restored Prone on Wren"])
    }

    @Test func sameNamedCustomSurvivingIsNotARestoration() {
        var before = character()
        before.customConditions = [CustomCondition(name: "Hexed")]
        var after = before
        after.conditions.insert(.prone)
        #expect(ConditionRestoreLog.lines(before: before, after: after)
            == ["restored Prone on Wren"])
    }

    @Test func aStepDroppingAConditionLogsNothing() {
        var before = character()
        before.conditions.insert(.frightened)
        // The undo of an apply: membership shrinks - the audit stays silent.
        #expect(ConditionRestoreLog.lines(before: before, after: character()).isEmpty)
    }

    @Test func aStepTouchingNoConditionsLogsNothing() {
        var before = character()
        before.currentHP = 12
        var after = before
        after.currentHP = 7
        #expect(ConditionRestoreLog.lines(before: before, after: after).isEmpty)
    }

    // 3.67.0: the mirror direction - a redo step that drops conditions
    // logs the re-removal in the removal line's own shape (3.65.0); the
    // note rides from the before-state because removal kills it (3.58.0).

    @Test func droppedBuiltInCarriesTheNoteFromTheBeforeState() {
        var before = character()
        before.conditions.insert(.frightened)
        before.conditionNotes[Condition.frightened.rawValue] = "the howl"
        #expect(ConditionRestoreLog.removalLines(before: before, after: character())
            == ["Frightened removed: Wren (note: the howl)"])
    }

    @Test func unnotedRemovalStaysBare() {
        var before = character()
        before.conditions.insert(.prone)
        #expect(ConditionRestoreLog.removalLines(before: before, after: character())
            == ["Prone removed: Wren"])
    }

    @Test func droppedCustomCarriesItsInstanceNote() {
        var before = character()
        let hexed = CustomCondition(name: "Hexed")
        before.customConditions = [hexed]
        before.conditionNotes[hexed.id.uuidString] = "the brand"
        #expect(ConditionRestoreLog.removalLines(before: before, after: character())
            == ["Hexed removed: Wren (note: the brand)"])
    }

    @Test func sameNamedCustomSurvivingIsNotADrop() {
        var before = character()
        before.customConditions = [CustomCondition(name: "Hexed")]
        var after = character()
        after.customConditions = [CustomCondition(name: "Hexed")]
        #expect(ConditionRestoreLog.removalLines(before: before, after: after).isEmpty)
    }

    @Test func aPureAddDropsNothing() {
        var after = character()
        after.conditions.insert(.stunned)
        #expect(ConditionRestoreLog.removalLines(before: character(), after: after).isEmpty)
    }

    @Test func mixedDropsSortBuiltInsFirstThenCustoms() {
        var before = character()
        before.conditions.insert(.stunned)
        before.conditions.insert(.blinded)
        before.customConditions = [CustomCondition(name: "Hexed")]
        #expect(ConditionRestoreLog.removalLines(before: before, after: character())
            == ["Blinded removed: Wren", "Stunned removed: Wren", "Hexed removed: Wren"])
    }
}
