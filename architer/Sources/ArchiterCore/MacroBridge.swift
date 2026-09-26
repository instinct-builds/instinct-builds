import Foundation

/// Sheet-to-dice bridge (3.23.0): builds a combo macro from a sheet attack
/// so a weapon becomes a reusable, editable dice-pane entry instead of only
/// one-shot rolls. The macro is a snapshot resolved from the character's
/// current scores and level - the same contract every macro already carries.
public enum MacroBridge {
    /// Two-part combo: "<name> attack" (1d20 + resolved bonus) and
    /// "<name> damage" (current grip, damage type carried), scoped to the
    /// character so it files with their per-character macros. Re-saving
    /// after a weapon edit refreshes in place: DiceMacro's scoped id is
    /// stable for the same name + owner, and the store upserts by that id.
    public static func combo(for attack: Attack, characterName: String,
                             scores: AbilityScores, level: Int) -> DiceMacro {
        let bonus = attack.attackBonus(scores: scores, level: level)
        let attackExpression = bonus == 0 ? "1d20" : "1d20\(bonus > 0 ? "+\(bonus)" : "\(bonus)")"
        let attackPart = ComboPart(label: "\(attack.name) attack", expression: attackExpression)
        let damageType = attack.damageType.trimmingCharacters(in: .whitespaces).lowercased()
        let damagePart = ComboPart(label: "\(attack.name) damage",
                                   expression: attack.damageString(scores: scores),
                                   damageType: damageType.isEmpty ? nil : damageType)
        let parts = [attackPart, damagePart]
        return DiceMacro(name: attack.name,
                         expression: comboSummary(parts),
                         characterName: characterName,
                         parts: parts)
    }
}
