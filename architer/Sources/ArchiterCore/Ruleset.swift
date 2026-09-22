import Foundation

/// A ruleset preset that switches the sheet's *mechanical behavior* between
/// the two most common modern d20 eras. Everything here is original
/// expression: the presets encode rules behavior only (how rests recover
/// resources, what exhaustion does, how weapons and spell preparation are
/// handled), never published text.
public enum RulesetVariant: String, Codable, CaseIterable, Sendable {
    /// The 2014-era baseline: six-step exhaustion with named side effects,
    /// half of spent hit dice return on a long rest, prepared casters ready
    /// level + casting-modifier spells, no weapon traits.
    case era2014 = "2014-style"
    /// The 2024-era update: ten-step exhaustion as a flat roll penalty, all
    /// spent hit dice return on a long rest, prepared casters use a fixed
    /// count by level, weapons can carry one mastery trait.
    case era2024 = "2024-style"

    public var displayName: String { rawValue }

    /// One-line original summary shown next to the picker.
    public var summary: String {
        switch self {
        case .era2014:
            return "Half hit-dice recovery, six-step exhaustion, level + modifier prepared spells, no weapon traits."
        case .era2024:
            return "Full hit-dice recovery, exhaustion as a flat roll penalty, fixed prepared counts, weapon mastery traits."
        }
    }

    // MARK: Rest behavior

    /// How many spent hit dice a long rest returns (minimum 1).
    /// 2014 era: half the pool. 2024 era: the whole pool.
    public func longRestDiceRecovered(total: Int) -> Int {
        switch self {
        case .era2014: return max(1, total / 2)
        case .era2024: return max(1, total)
        }
    }

    // MARK: Exhaustion

    /// Steps of exhaustion a character can take before dropping.
    public var exhaustionCap: Int {
        switch self {
        case .era2014: return 6
        case .era2024: return 10
        }
    }

    /// Flat penalty subtracted from every d20 roll. The 2014 era models
    /// exhaustion through named side effects instead (see
    /// `exhaustionStepNote`), so it applies no numeric penalty here.
    public func exhaustionRollPenalty(level: Int) -> Int {
        guard level > 0 else { return 0 }
        switch self {
        case .era2014: return 0
        case .era2024: return level
        }
    }

    /// Short original description of what a given exhaustion step means
    /// under this era, shown beside the tracker.
    public func exhaustionStepNote(level: Int) -> String {
        guard level > 0 else { return "No exhaustion." }
        switch self {
        case .era2014:
            switch level {
            case 1: return "Ability checks are disadvantaged."
            case 2: return "Speed is halved."
            case 3: return "Attacks and saves are disadvantaged."
            case 4: return "Hit point maximum is halved."
            case 5: return "Speed is reduced to 0."
            default: return "Down and out."
            }
        case .era2024:
            return "-\(level) to every d20 roll; speed reduced by \(level * 5) ft."
        }
    }

    // MARK: Weapon handling

    /// The 2024 era lets each weapon carry one mastery trait; the 2014 era
    /// has no weapon traits.
    public var usesWeaponMastery: Bool { self == .era2024 }

    // MARK: Spell preparation

    /// How many spells a prepared caster may have ready at once.
    /// 2014 era: level + casting modifier (scales with the ability score).
    /// 2024 era: a fixed count per caster level (scores don't add to it).
    public func preparedLimit(casterLevel: Int, castingModifier: Int) -> Int {
        switch self {
        case .era2014:
            return max(1, casterLevel + castingModifier)
        case .era2024:
            // Fixed by-level curve (mechanics only).
            let curve = [4, 5, 6, 7, 9, 10, 11, 12, 14, 15, 16, 16, 17, 17, 18, 18, 19, 20, 21, 22]
            let lvl = max(1, min(20, casterLevel))
            return curve[lvl - 1]
        }
    }
}

/// A weapon mastery trait (2024-era mechanic). Names are genre-standard
/// single-word mechanical labels; the effects are written in our own words.
public enum WeaponMastery: String, Codable, CaseIterable, Sendable {
    case cleave = "Cleave"
    case graze = "Graze"
    case nick = "Nick"
    case push = "Push"
    case sap = "Sap"
    case slow = "Slow"
    case topple = "Topple"
    case vex = "Vex"

    /// Original one-line description of the trait's behavior.
    public var effect: String {
        switch self {
        case .cleave: return "On a hit, swing once at a second target within reach."
        case .graze: return "A miss still deals damage equal to the ability modifier used."
        case .nick: return "The extra light-weapon swing costs no bonus action."
        case .push: return "On a hit, shove the target up to 10 ft. away."
        case .sap: return "On a hit, the target's next attack roll is disadvantaged."
        case .slow: return "On a hit, cut the target's speed by 10 ft. until your next turn."
        case .topple: return "On a hit, force a save or the target falls prone."
        case .vex: return "On a hit, your next attack against it is advantaged."
        }
    }
}
