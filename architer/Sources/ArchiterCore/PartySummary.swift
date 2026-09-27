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
    public init(characterID: UUID, name: String, text: String) {
        self.characterID = characterID
        self.name = name
        self.text = text
    }
}

public func partyConditionSummaryItems(_ characters: [Character]) -> [PartyConditionSummaryItem] {
    characters.compactMap { c in
        guard !c.conditions.isEmpty else { return nil }
        let held = c.conditions.sorted { $0.displayName < $1.displayName }.map { cond -> String in
            if let rounds = c.conditionDurations[cond.rawValue] {
                return "\(cond.displayName) \(rounds)r"
            }
            return cond.displayName
        }
        return PartyConditionSummaryItem(characterID: c.id, name: c.name,
                                         text: "\(c.name): \(held.joined(separator: ", "))")
    }
}
