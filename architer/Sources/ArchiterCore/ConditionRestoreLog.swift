import Foundation

/// Undo-restore log lines (3.66.0): when an undo step brings a condition
/// back - the undo of a removal - the table log names what returned, with
/// the restored note riding in the same "(note: ...)" shape the removal
/// line carries (3.65.0). Pure diff of the two character states the step
/// moves between: present after, absent before. Only restorations log -
/// an undo that DROPS a condition (the undo of an apply) stays silent,
/// matching the removal log's one-direction audit. Built-ins sort by
/// display name, then customs by name - the chip order
/// (Character.conditionChipNames), so the log and the strip never
/// disagree about order.
public enum ConditionRestoreLog {
    /// One line per condition the step restored, "restored X on Name"
    /// plus " (note: ...)" when the restored state carries a note.
    /// Empty when the step changed no condition membership.
    public static func lines(before: Character, after: Character) -> [String] {
        var lines: [String] = []
        let restoredBuiltIns = after.conditions.subtracting(before.conditions)
            .sorted { $0.displayName < $1.displayName }
        for condition in restoredBuiltIns {
            let note = Character.normalizedConditionNote(after.conditionNotes[condition.rawValue] ?? "")
            lines.append("restored \(condition.displayName) on \(after.name)"
                         + (note.map { " (note: \($0))" } ?? ""))
        }
        // Customs share the removal path's name identity (3.60.0): a
        // same-named instance surviving the step is not a restoration.
        let beforeCustomNames = Set(before.customConditions.map(\.name))
        let restoredCustoms = after.customConditions
            .filter { !beforeCustomNames.contains($0.name) }
            .sorted { $0.name < $1.name }
        for custom in restoredCustoms {
            let note = Character.normalizedConditionNote(after.conditionNotes[custom.id.uuidString] ?? "")
            lines.append("restored \(custom.name) on \(after.name)"
                         + (note.map { " (note: \($0))" } ?? ""))
        }
        return lines
    }
}
