import Foundation

/// Party detail panel (3.68.0): the wide surface the 3.66.0 ruling
/// deferred condition-chip notes to. One row per roster member, every
/// chip shown - the "+N more" cap is the strip's answer to its own 220pt
/// budget; the panel exists so nothing is elided. Name, the whole
/// 24-char note and the remaining clock ride each chip in the party
/// condition summary's exact grammar (3.53.0-3.60.0), so the strip, the
/// summary line, the log and this panel never disagree. Pure derivation
/// from stored state - conditions, notes, durations, concentration, HP -
/// never stored, always recomputed. Read-only: no mutation paths.
public struct PartyDetailChip: Equatable, Sendable {
    /// The chip's full text: "Frightened 2r (the howl)", "Prone",
    /// "Concentrating: Misty step (3)".
    public let text: String
    /// A clock at 1 - one tick from removal (3.57.0's expiring mark).
    public let expiring: Bool
    public init(text: String, expiring: Bool) {
        self.text = text
        self.expiring = expiring
    }
}

public struct PartyDetailRow: Equatable, Sendable, Identifiable {
    public var id: UUID { characterID }
    public let characterID: UUID
    public let name: String
    public let currentHP: Int
    public let maxHP: Int
    public let tempHP: Int
    /// Every held condition, chip order (built-ins by display name, then
    /// customs by name), then a concentration chip when holding one.
    /// Empty when the member holds nothing - the row still lists as one
    /// compact line, doubling as the party HP glance.
    public let chips: [PartyDetailChip]
    public init(characterID: UUID, name: String, currentHP: Int, maxHP: Int, tempHP: Int, chips: [PartyDetailChip]) {
        self.characterID = characterID
        self.name = name
        self.currentHP = currentHP
        self.maxHP = maxHP
        self.tempHP = tempHP
        self.chips = chips
    }
}

public func partyDetailRows(_ characters: [Character]) -> [PartyDetailRow] {
    let items = partyConditionSummaryItems(characters)
    return characters.map { c in
        var chips: [PartyDetailChip] = items.first(where: { $0.characterID == c.id })?.parts.map {
            PartyDetailChip(text: $0.label + ($0.note.map { " (\($0))" } ?? ""), expiring: $0.expiring)
        } ?? []
        // Concentration rides last, the strip's chip grammar verbatim
        // (PartyCardSummary) - one vocabulary across every surface.
        if let spell = c.concentratingOn {
            let chip = c.concentrationTimer.map { "\(spell) (\($0))" } ?? spell
            chips.append(PartyDetailChip(text: "Concentrating: \(chip)", expiring: false))
        }
        return PartyDetailRow(characterID: c.id, name: c.name,
                              currentHP: c.currentHP, maxHP: c.maxHP, tempHP: c.tempHP, chips: chips)
    }
}
