import Foundation

/// Edit-menu descriptions for condition mutations (3.70.0), the same
/// shape as the 3.19.0 HP-apply label: AppModel stores the description
/// with the undo depth the mutation left behind on the selected
/// character's stack, and the Edit menu shows "Undo <label>" while that
/// step is on top - any newer edit or the undo itself moves the depth
/// and the menu falls back to plain "Undo". Pure strings derived from
/// the mutation, never stored.

/// "Apply Frightened to Wren Halloway" - built-ins pass their display
/// name, customs their trimmed name (the party functions' identity).
public func conditionApplyMenuLabel(conditionName: String, characterName: String) -> String {
    "Apply \(conditionName) to \(characterName)"
}

/// "Remove Frightened from Wren Halloway".
public func conditionRemoveMenuLabel(conditionName: String, characterName: String) -> String {
    "Remove \(conditionName) from \(characterName)"
}

/// The initiative round-wrap tick: every timer on the character stepped
/// down, ending whatever hit 0. "Tick condition timers on Wren Halloway".
public func conditionTickMenuLabel(characterName: String) -> String {
    "Tick condition timers on \(characterName)"
}
