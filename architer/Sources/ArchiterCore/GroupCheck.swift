import Foundation

/// Group checks (3.26.0): the whole party attempts the same skill check and
/// the group succeeds when half or more of the participants beat the DC -
/// genre-standard resolution, original wording. Everything here is derived:
/// the plan comes from each character's own sheet, the verdict from the
/// rolls. Nothing is stored, so the summary can never drift from history.
public struct GroupCheckPlan: Equatable, Sendable {
    /// One participant's roll terms, derived from their own sheet.
    public struct Participant: Equatable, Sendable {
        public let characterID: UUID
        public let name: String
        /// Sheet bonus for the skill (before the exhaustion penalty).
        public let bonus: Int
        /// Effective d20 mode after the participant's own conditions.
        public let mode: RollMode
        /// Exhaustion penalty subtracted from the bonus at roll time.
        public let penalty: Int
        /// The same tags rollCheck would put on the history entry.
        public let tags: [String]

        public init(characterID: UUID, name: String, bonus: Int, mode: RollMode,
                    penalty: Int, tags: [String]) {
            self.characterID = characterID
            self.name = name
            self.bonus = bonus
            self.mode = mode
            self.penalty = penalty
            self.tags = tags
        }
    }

    public let skillName: String
    public let participants: [Participant]

    /// nil for an empty roster - there is no group to roll.
    public init?(characters: [Character], skillName: String) {
        guard !characters.isEmpty else { return nil }
        self.skillName = skillName
        // A plain loop, not map: a closure would capture self before
        // participants is initialized (Participant's init is a member).
        var built: [Participant] = []
        for c in characters {
            // Custom rulesets can drop a default skill: fall back to the
            // default list's ability as an untrained check.
            let skill = c.skills.first(where: { $0.name == skillName })
                ?? Skill.defaultList.first(where: { $0.name == skillName })
            let bonus = skill.map { $0.bonus(scores: c.scores, level: c.level) } ?? 0
            let mode = c.effectiveRollMode(.normal, for: .check)
            let penalty = c.exhaustionRollPenalty
            // Mirrors rollCheck's labeling for a normal-mode check.
            var tags: [String] = []
            if penalty > 0 { tags.append("exhaustion -\(penalty)") }
            if mode == .disadvantage {
                let names = c.disadvantageSourceNames(for: .check).joined(separator: ", ")
                tags.append("disadvantage: \(names)")
            }
            built.append(Participant(characterID: c.id, name: c.name, bonus: bonus,
                                     mode: mode, penalty: penalty, tags: tags))
        }
        participants = built
    }
}

/// The outcome of one group check: per-participant results plus the derived
/// verdict. Ephemeral by design - history carries the auditable rolls.
public struct GroupCheckOutcome: Equatable, Sendable {
    public struct Line: Equatable, Sendable {
        public let name: String
        public let total: Int
        /// nil when no DC was set - totals only, no verdict.
        public let passed: Bool?
        public let tags: [String]

        public init(name: String, total: Int, passed: Bool?, tags: [String]) {
            self.name = name
            self.total = total
            self.passed = passed
            self.tags = tags
        }
    }

    public let skillName: String
    public let targetDC: Int?
    public let lines: [Line]

    public init(skillName: String, targetDC: Int?, lines: [Line]) {
        self.skillName = skillName
        self.targetDC = targetDC
        self.lines = lines
    }

    public var passCount: Int { lines.filter { $0.passed == true }.count }

    /// Half or more of the participants beat the DC; nil without a DC.
    public var groupSucceeded: Bool? {
        guard targetDC != nil, !lines.isEmpty else { return nil }
        return passCount * 2 >= lines.count
    }

    /// The one-line verdict, e.g. "Group succeeds: 3 of 4 met DC 12."
    public var verdictLine: String? {
        guard let dc = targetDC, let succeeded = groupSucceeded else { return nil }
        return "Group \(succeeded ? "succeeds" : "fails"): \(passCount) of \(lines.count) met DC \(dc)."
    }
}

/// Group saves (3.31.0): the whole party attempts the same saving throw.
/// Same participant shape as group checks; the terms differ - bonus from
/// the character's own save proficiency, mode always normal (saves are
/// never condition-hindered), exhaustion the only tag. The verdict reuses
/// GroupCheckOutcome unchanged.
public struct GroupSavePlan: Equatable, Sendable {
    public let ability: Ability
    public let participants: [GroupCheckPlan.Participant]

    /// nil for an empty roster - there is no group to roll.
    public init?(characters: [Character], ability: Ability) {
        guard !characters.isEmpty else { return nil }
        self.ability = ability
        // A plain loop, not map: Participant's init is a member of
        // GroupCheckPlan, so a closure would capture self too early.
        var built: [GroupCheckPlan.Participant] = []
        for c in characters {
            let bonus = c.savingThrow(ability)
            let mode = c.effectiveRollMode(.normal, for: .save)
            let penalty = c.exhaustionRollPenalty
            var tags: [String] = []
            if penalty > 0 { tags.append("exhaustion -\(penalty)") }
            built.append(GroupCheckPlan.Participant(characterID: c.id, name: c.name,
                                                    bonus: bonus, mode: mode,
                                                    penalty: penalty, tags: tags))
        }
        participants = built
    }
}
