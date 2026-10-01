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
    /// 3.86.0: table facts a DM asks for out loud, derived from the sheet.
    public let armorClass: Int
    public let passivePerception: Int
    public let inspired: Bool
    public init(characterID: UUID, name: String, currentHP: Int, maxHP: Int, tempHP: Int, chips: [PartyDetailChip],
                armorClass: Int = 0, passivePerception: Int = 0, inspired: Bool = false) {
        self.armorClass = armorClass
        self.passivePerception = passivePerception
        self.inspired = inspired
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
        if c.maxHPReduction > 0 {
            chips.append(PartyDetailChip(text: "Max -\(c.maxHPReduction)", expiring: false))
        }
        return PartyDetailRow(characterID: c.id, name: c.name,
                              currentHP: c.currentHP, maxHP: c.effectiveMaxHP, tempHP: c.tempHP, chips: chips,
                              armorClass: c.computedAC, passivePerception: c.passivePerception, inspired: c.inspiration)
    }
}

/// 3.86.0: the one-line table glance above the rows - best passive
/// Perception (who spots the ambush), lowest AC (who gets hit first),
/// and who holds inspiration. Ties go to roster order; nil for an empty
/// roster. Derived, never stored.
public func partyTableFactsLine(_ rows: [PartyDetailRow]) -> String? {
    guard let best = rows.max(by: { $0.passivePerception < $1.passivePerception }),
          let soft = rows.min(by: { $0.armorClass < $1.armorClass }) else { return nil }
    // max/min(by:) keep the LAST of equals for max and the first for min;
    // pin both to the first in roster order for a stable readout.
    let bestFirst = rows.first(where: { $0.passivePerception == best.passivePerception }) ?? best
    var parts = ["Best passive Perception \(bestFirst.passivePerception) (\(bestFirst.name))",
                 "Lowest AC \(soft.armorClass) (\(soft.name))"]
    let inspired = rows.filter(\.inspired).map(\.name)
    if !inspired.isEmpty { parts.append("Inspired: \(inspired.joined(separator: ", "))") }
    return parts.joined(separator: " \u{00B7} ")
}
