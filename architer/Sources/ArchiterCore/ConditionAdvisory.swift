import Foundation

/// Condition advisory (3.24.0): pre-roll visibility for side effects the
/// roller already enforces. Derived live from the character - never stored,
/// so there is no drift surface. Advisory only: the roll-time downgrade in
/// `effectiveRollMode` plus the history tag stays the single source of
/// enforcement.
public enum ConditionAdvisory {
    /// One segment per roll-relevant fact: attack hindrances, check
    /// hindrances, and the exhaustion penalty. Empty when nothing applies,
    /// so the dice pane stays chrome-free for unaffected characters.
    /// Saves are omitted (the era preset covers them by note), as is
    /// immobilize (movement, not dice).
    public static func lines(for c: Character) -> [String] {
        var lines: [String] = []
        let attacks = c.disadvantageSourceNames(for: .attack)
        if !attacks.isEmpty {
            lines.append("Attacks hindered: \(attacks.joined(separator: ", "))")
        }
        let checks = c.disadvantageSourceNames(for: .check)
        if !checks.isEmpty {
            lines.append("Checks hindered: \(checks.joined(separator: ", "))")
        }
        if c.exhaustionRollPenalty > 0 {
            lines.append("Exhaustion \(c.exhaustion): -\(c.exhaustionRollPenalty) on d20 rolls")
        }
        return lines
    }
}
