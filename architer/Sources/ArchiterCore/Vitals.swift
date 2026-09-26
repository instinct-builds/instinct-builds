import Foundation

/// Genre-standard conditions that can affect a character. Original naming for
/// a simplified sheet; these are functional game states.
public enum Condition: String, Codable, CaseIterable, Sendable {
    case blinded, charmed, deafened, frightened, grappled, incapacitated,
         invisible, paralyzed, petrified, poisoned, prone, restrained,
         stunned, unconscious

    public var displayName: String { rawValue.capitalized }

    /// Genre-standard d20 side effects we model automatically. Attack
    /// disadvantage: the attacker is hindered on attack rolls.
    public var hindersAttacks: Bool {
        switch self {
        case .blinded, .poisoned, .prone, .restrained, .frightened: return true
        default: return false
        }
    }

    /// Ability-check disadvantage.
    public var hindersChecks: Bool {
        switch self {
        case .poisoned, .frightened: return true
        default: return false
        }
    }
}

/// A user-defined condition: a name plus which d20 side effects it carries.
/// Complements the built-in list for homebrew states ("Dazed", "Marked").
public struct CustomCondition: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID = UUID()
    public var name: String
    /// Attack disadvantage, mirroring the built-in flag.
    public var hindersAttacks: Bool
    /// Ability-check disadvantage.
    public var hindersChecks: Bool
    /// Speed drops to 0, like the built-in grappled/restrained states.
    public var immobilizes: Bool

    public init(name: String, hindersAttacks: Bool = false, hindersChecks: Bool = false,
                immobilizes: Bool = false) {
        self.name = name
        self.hindersAttacks = hindersAttacks
        self.hindersChecks = hindersChecks
        self.immobilizes = immobilizes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        hindersAttacks = try c.decodeIfPresent(Bool.self, forKey: .hindersAttacks) ?? false
        hindersChecks = try c.decodeIfPresent(Bool.self, forKey: .hindersChecks) ?? false
        immobilizes = try c.decodeIfPresent(Bool.self, forKey: .immobilizes) ?? false
    }
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

    /// Consolidates loose change into the fewest coins, keeping the total
    /// value: platinum and gold first, silver and copper for the remainder.
    /// Electrum is folded away (tables rarely trade in it).
    public func normalized() -> Currency {
        var rest = totalCopper
        let pp = rest / 1000; rest -= pp * 1000
        let gp = rest / 100;  rest -= gp * 100
        let sp = rest / 10;   rest -= sp * 10
        return Currency(copper: rest, silver: sp, gold: gp, platinum: pp)
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

/// Concentration checks (3.28.0): the DC of the CON save damage forces,
/// derived from the damage that actually landed (defenses already folded
/// in). Genre-standard floor: never below 10, half the damage above that.
public func concentrationDC(forDamage damage: Int) -> Int {
    max(10, damage / 2)
}
