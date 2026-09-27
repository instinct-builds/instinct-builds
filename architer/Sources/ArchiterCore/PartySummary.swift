import Foundation

/// Party condition summary (3.53.0): "who's holding what, plus clocks" as
/// one glanceable line for the Party section. Pure derivation from stored
/// conditions and duration keys - never stored, always recomputed; empty
/// when the roster holds nothing (the row hides).
public func partyConditionSummary(_ characters: [Character]) -> String {
    let parts: [String] = characters.compactMap { c in
        guard !c.conditions.isEmpty else { return nil }
        let held = c.conditions.sorted { $0.displayName < $1.displayName }.map { cond -> String in
            if let rounds = c.conditionDurations[cond.rawValue] {
                return "\(cond.displayName) \(rounds)r"
            }
            return cond.displayName
        }
        return "\(c.name): \(held.joined(separator: ", "))"
    }
    return parts.joined(separator: " · ")
}
