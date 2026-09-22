import Foundation

/// Genre-standard conditions that can affect a character. Original naming for
/// a simplified sheet; these are functional game states.
public enum Condition: String, Codable, CaseIterable, Sendable {
    case blinded, charmed, deafened, frightened, grappled, incapacitated,
         invisible, paralyzed, petrified, poisoned, prone, restrained,
         stunned, unconscious

    public var displayName: String { rawValue.capitalized }
}

/// Coin purse with genre-standard denominations: 10 cp = 1 sp, 5 sp = 1 ep,
/// 10 sp (or 2 ep) = 1 gp, 10 gp = 1 pp. Totals convert to copper.
public struct Currency: Codable, Equatable, Sendable {
    public var copper: Int
    public var silver: Int
    public var electrum: Int
    public var gold: Int
    public var platinum: Int

    public init(copper: Int = 0, silver: Int = 0, electrum: Int = 0, gold: Int = 0, platinum: Int = 0) {
        self.copper = max(0, copper)
        self.silver = max(0, silver)
        self.electrum = max(0, electrum)
        self.gold = max(0, gold)
        self.platinum = max(0, platinum)
    }

    public var totalCopper: Int {
        copper + silver * 10 + electrum * 50 + gold * 100 + platinum * 1000
    }

    /// A compact readout of nonzero denominations, e.g. "12 gp, 4 sp".
    public var displayString: String {
        var parts: [String] = []
        if platinum > 0 { parts.append("\(platinum) pp") }
        if gold > 0 { parts.append("\(gold) gp") }
        if electrum > 0 { parts.append("\(electrum) ep") }
        if silver > 0 { parts.append("\(silver) sp") }
        if copper > 0 { parts.append("\(copper) cp") }
        return parts.isEmpty ? "0 cp" : parts.joined(separator: ", ")
    }
}

/// How much of the character's carry limit is in use.
public enum Encumbrance: String, Sendable {
    case normal, encumbered, heavilyEncumbered, overCapacity
}
