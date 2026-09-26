import Foundation

/// Party XP award from a fight (3.41.0). The pool derives from stored
/// inputs - the initiative tracker's challenge ratings - and is never
/// itself stored. Raw base XP is the payout; the count multiplier stays a
/// budgeting yardstick. The preview names both, so a number is never
/// silently one or the other.
public struct XPAwardPlan: Equatable, Sendable {
    /// One roster member's line in the preview.
    public struct Share: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let name: String
        /// Unchecked members stay listed with a zero share, so the preview
        /// shows the whole roster and re-checking is one tap.
        public let included: Bool
        public let currentXP: Int
        public let amount: Int

        public init(id: UUID, name: String, included: Bool, currentXP: Int, amount: Int) {
            self.id = id
            self.name = name
            self.included = included
            self.currentXP = max(0, currentXP)
            self.amount = max(0, amount)
        }

        public var newXP: Int { currentXP + amount }
        public var newLevel: Int { RulesMath.level(forXP: newXP) }
        public var levelsUp: Bool { newLevel > RulesMath.level(forXP: currentXP) }
    }

    /// How the pool reaches the checked members: an even floor split with
    /// the remainder dropped, or the whole pool to each (the party-XP
    /// house rule).
    public enum Mode: String, Equatable, Sendable, CaseIterable {
        case equalSplit
        case fullPool
    }

    public let baseXP: Int
    public let adjustedXP: Double
    public let mode: Mode
    public let shares: [Share]

    /// Nil when no challenge rating pays or no member is checked - there
    /// is nothing to award in either case.
    public init?(crs: [Double], members: [(id: UUID, name: String, xp: Int, included: Bool)], mode: Mode) {
        let known = crs.compactMap { EncounterMath.xp(forCR: $0) }
        let checked = members.filter { $0.included }
        guard !known.isEmpty, !checked.isEmpty else { return nil }
        let base = known.reduce(0, +)
        baseXP = base
        adjustedXP = Double(base) * EncounterMath.multiplier(forEnemyCount: known.count)
        self.mode = mode
        let split = base / checked.count
        shares = members.map { m in
            Share(id: m.id, name: m.name, included: m.included, currentXP: m.xp,
                  amount: m.included ? (mode == .equalSplit ? split : base) : 0)
        }
    }
}
