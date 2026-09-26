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

    public init(character c: Character) {
        characterID = c.id
        name = c.name
        level = c.level
        currentHP = c.currentHP
        maxHP = c.maxHP
        tempHP = c.tempHP
        var chips = c.activeConditionNames
        if let spell = c.concentratingOn {
            chips.append("Concentrating: \(spell)")
        }
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
