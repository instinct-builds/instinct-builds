import Foundation

/// Party overview strip (3.29.0): one read-only summary card per roster
/// character, derived entirely from the sheet - the strip shows, the sheet
/// edits. Nothing here is stored.
public struct PartyCardSummary: Equatable, Sendable {
    /// Chips shown before truncation; a "+N more" marker covers the rest.
    public static let visibleChipLimit = 2

    public let characterID: UUID
    public let name: String
    public let level: Int
    public let currentHP: Int
    public let maxHP: Int
    public let tempHP: Int
    /// Every chip: active conditions (built-ins first, then custom, each
    /// sorted), then a concentration chip when the character is holding one.
    public let chips: [String]
    /// 3.79.0: "Max -N" for a drained character; nil otherwise. Not part of
    /// `chips`, so it never falls into the "+N more" overflow.
    public let drainChip: String?

    public init(character c: Character) {
        characterID = c.id
        name = c.name
        level = c.level
        currentHP = c.currentHP
        maxHP = c.effectiveMaxHP
        tempHP = c.tempHP
        var chips = c.conditionChipNames
        if let spell = c.concentratingOn {
            // 3.35.0: a running timer rides the chip, matching the
            // condition countdowns ("Prone (1)").
            let chip = c.concentrationTimer.map { "\(spell) (\($0))" } ?? spell
            chips.append("Concentrating: \(chip)")
        }
        // 3.77.0: a drained character shows it last, derived from the
        // stored drain (nothing extra stored).
        // 3.79.0: pinned OUT of the chip overflow - a crowded card would
        // otherwise hide the drain in "+N more"; the strip renders it in
        // the HP row instead.
        drainChip = c.maxHPReduction > 0 ? "Max -\(c.maxHPReduction)" : nil
        self.chips = chips
    }

    /// The chips the card renders directly.
    public var visibleChips: [String] {
        Array(chips.prefix(PartyCardSummary.visibleChipLimit))
    }

    /// How many chips the "+N more" marker stands for; 0 means no marker.
    public var extraChipCount: Int {
        max(0, chips.count - PartyCardSummary.visibleChipLimit)
    }
}
