import Foundation

/// Party condition summary (3.53.0): "who's holding what, plus clocks" as
/// one glanceable line for the Party section. Pure derivation from stored
/// conditions and duration keys - never stored, always recomputed; empty
/// when the roster holds nothing (the row hides).
public func partyConditionSummary(_ characters: [Character]) -> String {
    partyConditionSummaryItems(characters).map(\.text).joined(separator: " · ")
}

/// One segment of the party condition summary (3.54.0): the holder's
/// id for click-through plus their rendered text. Derived, never stored.
public struct PartyConditionSummaryItem: Equatable, Sendable, Identifiable {
    public var id: UUID { characterID }
    public let characterID: UUID
    public let name: String
    public let text: String
    /// The held conditions split for styling (3.57.0): expiring marks a
    /// clock at 1 - one tick from removal, "ending this round".
    public let parts: [PartyConditionSummaryPart]
    public init(characterID: UUID, name: String, text: String, parts: [PartyConditionSummaryPart]) {
        self.characterID = characterID
        self.name = name
        self.text = text
        self.parts = parts
    }
}

public struct PartyConditionSummaryPart: Equatable, Sendable {
    public let label: String
    public let expiring: Bool
    /// The DM's "why they have it" (3.58.0), rendered in parens after the
    /// label in faint - never accent, which stays reserved for expiring.
    public let note: String?
    public init(label: String, expiring: Bool, note: String? = nil) {
        self.label = label
        self.expiring = expiring
        self.note = note
    }
}

public func partyConditionSummaryItems(_ characters: [Character]) -> [PartyConditionSummaryItem] {
    characters.compactMap { c in
        guard !c.conditions.isEmpty else { return nil }
        var parts: [PartyConditionSummaryPart] = []
        let held = c.conditions.sorted { $0.displayName < $1.displayName }.map { cond -> String in
            // 3.58.0: the note rides the label in the derived string too -
            // the line stays exactly what's stored, nothing computed in.
            let note = c.conditionNotes[cond.rawValue]
            let suffix = note.map { " (\($0))" } ?? ""
            if let rounds = c.conditionDurations[cond.rawValue] {
                let label = "\(cond.displayName) \(rounds)r"
                parts.append(PartyConditionSummaryPart(label: label, expiring: rounds == 1, note: note))
                return label + suffix
            }
            parts.append(PartyConditionSummaryPart(label: cond.displayName, expiring: false, note: note))
            return cond.displayName + suffix
        }
        return PartyConditionSummaryItem(characterID: c.id, name: c.name,
                                         text: "\(c.name): \(held.joined(separator: ", "))",
                                         parts: parts)
    }
}
