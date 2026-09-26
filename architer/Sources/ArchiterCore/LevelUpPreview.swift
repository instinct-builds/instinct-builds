import Foundation

/// Level-up preview (3.25.0): the level N -> N+1 delta, computed entirely by
/// derivation from the character - never stored, so it can never drift from
/// what `levelUp(hpGain:)` will actually do. The average HP path previews
/// exactly; the roll path carries only its expression (the die lands at
/// Confirm, never in the preview).
public struct LevelUpPreview: Equatable, Sendable {
    /// A per-spell-level slot count change; only levels that change are listed.
    public struct SlotDelta: Equatable, Sendable {
        public let spellLevel: Int
        public let from: Int
        public let to: Int
        public init(spellLevel: Int, from: Int, to: Int) {
            self.spellLevel = spellLevel
            self.from = from
            self.to = to
        }
    }
    public let fromLevel: Int
    public let toLevel: Int
    public let proficiencyFrom: Int
    public let proficiencyTo: Int
    public let hitDiceFrom: String
    public let hitDiceTo: String
    /// Exact gain on the average path (matches levelUp's max(1, ...) floor).
    public let averageHPGain: Int
    /// Expression rolled on the roll path, e.g. "1d8+2".
    public let rollExpression: String
    public let slotDeltas: [SlotDelta]

    /// nil at the level cap - there is no next level to preview.
    public init?(character c: Character) {
        guard c.level < 20 else { return nil }
        fromLevel = c.level
        toLevel = c.level + 1
        proficiencyFrom = RulesMath.proficiencyBonus(level: c.level)
        proficiencyTo = RulesMath.proficiencyBonus(level: toLevel)
        hitDiceFrom = "\(c.hitDiceTotal)d\(c.hitDiceType)"
        hitDiceTo = "\(toLevel)d\(c.hitDiceType)"
        averageHPGain = c.averageLevelUpHP
        rollExpression = c.levelUpRollExpression
        if let sc = c.spellcasting {
            slotDeltas = (1...9).compactMap { sl in
                let from = sc.slotsMax(spellLevel: sl, casterLevel: c.level)
                let to = sc.slotsMax(spellLevel: sl, casterLevel: toLevel)
                return (from > 0 || to > 0) && from != to
                    ? SlotDelta(spellLevel: sl, from: from, to: to) : nil
            }
        } else {
            slotDeltas = []
        }
    }

    /// The milestone line `levelUp(hpGain:)` appends to notes, shown verbatim.
    public func notesLine(hpGain: Int) -> String {
        "Reached level \(toLevel) (+\(max(1, hpGain)) HP)."
    }
}
