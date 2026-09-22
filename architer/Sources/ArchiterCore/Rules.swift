import Foundation

/// Genre-standard progression tables: XP-by-level, spell slots, carrying
/// capacity. Game mechanics are functional rules, not copyrighted expression.
extension RulesMath {

    /// Cumulative XP required to be each level (index 0 = level 1).
    public static let xpThresholds: [Int] = [
        0, 300, 900, 2700, 6500, 14000, 23000, 34000, 48000, 64000,
        85000, 100000, 120000, 140000, 165000, 195000, 225000, 265000, 305000, 355000,
    ]

    public static func level(forXP xp: Int) -> Int {
        var level = 1
        for (i, threshold) in xpThresholds.enumerated() where xp >= threshold {
            level = i + 1
        }
        return min(20, level)
    }

    /// XP at which the next level is reached, nil at level 20.
    public static func xpForNextLevel(_ level: Int) -> Int? {
        guard level >= 1, level < 20 else { return nil }
        return xpThresholds[level]
    }

    /// Full-caster spell slots: fullCasterSlots[characterLevel-1][spellLevel-1].
    public static let fullCasterSlots: [[Int]] = [
        [2, 0, 0, 0, 0, 0, 0, 0, 0],
        [3, 0, 0, 0, 0, 0, 0, 0, 0],
        [4, 2, 0, 0, 0, 0, 0, 0, 0],
        [4, 3, 0, 0, 0, 0, 0, 0, 0],
        [4, 3, 2, 0, 0, 0, 0, 0, 0],
        [4, 3, 3, 0, 0, 0, 0, 0, 0],
        [4, 3, 3, 1, 0, 0, 0, 0, 0],
        [4, 3, 3, 2, 0, 0, 0, 0, 0],
        [4, 3, 3, 3, 1, 0, 0, 0, 0],
        [4, 3, 3, 3, 2, 0, 0, 0, 0],
        [4, 3, 3, 3, 2, 1, 0, 0, 0],
        [4, 3, 3, 3, 2, 1, 0, 0, 0],
        [4, 3, 3, 3, 2, 1, 1, 0, 0],
        [4, 3, 3, 3, 2, 1, 1, 0, 0],
        [4, 3, 3, 3, 2, 1, 1, 1, 0],
        [4, 3, 3, 3, 2, 1, 1, 1, 0],
        [4, 3, 3, 3, 2, 1, 1, 1, 1],
        [4, 3, 3, 3, 3, 1, 1, 1, 1],
        [4, 3, 3, 3, 3, 2, 1, 1, 1],
        [4, 3, 3, 3, 3, 2, 2, 1, 1],
    ]

    public static func spellSlots(casterLevel: Int, spellLevel: Int) -> Int {
        guard (1...20).contains(casterLevel), (1...9).contains(spellLevel) else { return 0 }
        return fullCasterSlots[casterLevel - 1][spellLevel - 1]
    }

    /// Pact-magic style casting (short-rest slots of a single level):
    /// returns (slotCount, slotLevel) for a character level.
    public static func pactSlots(casterLevel level: Int) -> (count: Int, slotLevel: Int) {
        switch max(1, min(20, level)) {
        case 1: return (1, 1)
        case 2: return (2, 1)
        case 3...4: return (2, 2)
        case 5...6: return (2, 3)
        case 7...8: return (2, 4)
        case 9...10: return (2, 5)
        case 11...16: return (3, 5)
        default: return (4, 5)
        }
    }

    /// Carrying capacity in pounds (15x Strength), and push/drag/lift (2x).
    public static func carryingCapacity(strength: Int) -> Int { max(0, strength) * 15 }
    public static func pushDragLift(strength: Int) -> Int { carryingCapacity(strength: strength) * 2 }
}
