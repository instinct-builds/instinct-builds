import Foundation

/// Condition immunity by lineage (3.73.0). A lineage grants immunity to
/// some conditions by keyword over its free-text name ("Warforged
/// Scout" counts), original table, genre-standard shape: built or
/// deathless bodies do not sicken. The grant is DERIVED from the stored
/// lineage text and never stored itself, so editing the lineage changes
/// it instantly; a stored per-character set (`conditionImmunities`)
/// adds table-specific immunities on top.
public enum ConditionImmunity {
    /// Lowercased keyword -> conditions granted.
    static let table: [(keyword: String, grants: Set<Condition>)] = [
        ("warforged", [.poisoned]),
        ("construct", [.poisoned]),
        ("undead", [.poisoned]),
        ("revenant", [.poisoned]),
        ("stoneborn", [.petrified]),
        ("wraithkin", [.charmed, .poisoned])
    ]

    /// Every condition the lineage text grants immunity to.
    public static func lineageGrants(_ lineage: String) -> Set<Condition> {
        let lowered = lineage.lowercased()
        var out: Set<Condition> = []
        for entry in table where lowered.contains(entry.keyword) {
            out.formUnion(entry.grants)
        }
        return out
    }
}

extension Character {
    /// Stored (manual) union derived (lineage) immunities.
    public var allConditionImmunities: Set<Condition> {
        conditionImmunities.union(ConditionImmunity.lineageGrants(lineage))
    }

    public func isImmune(to condition: Condition) -> Bool {
        allConditionImmunities.contains(condition)
    }

    /// "lineage" when only the lineage grants it, "set" when the stored
    /// set does (manual wins the label when both apply).
    public func conditionImmunitySource(_ condition: Condition) -> String? {
        if conditionImmunities.contains(condition) { return "set" }
        if ConditionImmunity.lineageGrants(lineage).contains(condition) { return "lineage" }
        return nil
    }
}
