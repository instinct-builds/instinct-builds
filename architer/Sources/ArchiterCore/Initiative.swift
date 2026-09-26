import Foundation

/// One combatant in the initiative tracker (3.22.0). The total is nil
/// until rolled (or set by hand - some tables roll physically); the
/// optional characterName links the entry to a sheet, name-keyed like
/// macros, so "Add Wren" pulls the sheet's live initiative bonus.
public struct InitiativeEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var bonus: Int
    public var total: Int?
    public var characterName: String?
    /// Challenge rating (3.36.0): set on enemy entries; the live-fight
    /// estimate derives from these. Optional so older saves decode
    /// unchanged; nil excludes the entry, never guesses it.
    public var cr: Double?
    /// Planner label (3.43.0): set on entries from labeled planner rows.
    /// Append-wave numbering counts this FIELD, never the name, so waves
    /// stay rename-proof exactly like CR numbering. Optional so older
    /// saves decode unchanged.
    public var label: String?

    public init(id: UUID = UUID(), name: String, bonus: Int, total: Int? = nil,
                characterName: String? = nil, cr: Double? = nil, label: String? = nil) {
        self.id = id
        self.name = name
        self.bonus = bonus
        self.total = total
        self.characterName = characterName
        self.cr = cr
        self.label = label
    }
}

/// XP paid from a fight (3.44.0): the recorded event End combat's recap
/// derives from. Awards are deliberately not idempotent (3.41.0), so
/// repeat taps accumulate the total; recipients list once each in
/// first-payment order.
public struct FightAward: Codable, Equatable, Sendable {
    public var total: Int
    public var recipients: [String]

    public init(total: Int, recipients: [String]) {
        self.total = total
        self.recipients = recipients
    }
}

/// A flattened one-level snapshot of the tracker Start fight displaced
/// (3.44.0). Flattened on purpose: a tracker cannot hold a tracker
/// (value-type recursion), and one level is the whole contract - the
/// restore never chains.
public struct PreFightSnapshot: Codable, Equatable, Sendable {
    public var entries: [InitiativeEntry]
    public var activeID: UUID?
    public var round: Int
    /// Any award the displaced fight had recorded rides back with it.
    public var fightAward: FightAward?

    public init(entries: [InitiativeEntry], activeID: UUID?, round: Int,
                fightAward: FightAward? = nil) {
        self.entries = entries
        self.activeID = activeID
        self.round = round
        self.fightAward = fightAward
    }
}

/// The initiative tracker (3.22.0): ordered entries, the active turn,
/// and the round. Deliberately order-only - no HP, no conditions, no
/// per-entry notes; this tracks whose turn it is, not the fight.
/// (3.36.0: entries may carry a challenge rating for the live-fight
/// estimate - enemy strength entered on the entry, never inferred.)
public struct InitiativeTracker: Codable, Equatable, Sendable {
    public var entries: [InitiativeEntry]
    public var activeID: UUID?
    public var round: Int
    /// XP paid from this fight (3.44.0): recorded when an award pays so
    /// End combat's recap can name it. Optional so pre-3.44.0 saves
    /// decode unchanged (synthesized decodeIfPresent).
    public var fightAward: FightAward?
    /// The tracker Start fight displaced (3.44.0), restorable one level
    /// deep. Consumed on restore, replaced by the next displacing Start
    /// fight, dies with the tracker. Optional so older saves decode
    /// unchanged.
    public var preFightSnapshot: PreFightSnapshot?

    public init(entries: [InitiativeEntry] = [], activeID: UUID? = nil, round: Int = 1,
                fightAward: FightAward? = nil, preFightSnapshot: PreFightSnapshot? = nil) {
        self.entries = entries
        self.activeID = activeID
        self.round = round
        self.fightAward = fightAward
        self.preFightSnapshot = preFightSnapshot
    }

    /// Display order: rolled entries by total descending, ties on the
    /// higher bonus (genre-standard) then insertion order; unrolled
    /// entries sink to the bottom in insertion order.
    public var ordered: [InitiativeEntry] {
        entries.enumerated().sorted { a, b in
            switch (a.element.total, b.element.total) {
            case let (at?, bt?):
                if at != bt { return at > bt }
                if a.element.bonus != b.element.bonus { return a.element.bonus > b.element.bonus }
                return a.offset < b.offset
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return a.offset < b.offset
            }
        }.map(\.element)
    }

    /// The rolled entries in display order - the turn rotation.
    public var rolledOrder: [InitiativeEntry] {
        ordered.filter { $0.total != nil }
    }

    /// Live-fight estimate input (3.36.0): each entry carrying a CR is one
    /// creature. Entries without a CR never contribute - enemy strength is
    /// entered on the entry, never inferred.
    public var encounterLinesFromCRs: [EncounterLine] {
        entries.compactMap { $0.cr.map { EncounterLine(count: 1, cr: $0) } }
    }

    /// Entries the live-fight estimate excludes for lack of a CR - the UI
    /// captions the count so the exclusion is visible, not silent.
    public var entriesWithoutCR: Int {
        entries.filter { $0.cr == nil }.count
    }

    /// "2x CR 3 + 1x CR 1/2" over the CR'd entries, highest first - the
    /// derivation line under the live-fight verdict.
    public var crBreakdown: String {
        let grouped = Dictionary(grouping: entries.compactMap(\.cr), by: { $0 })
        return grouped.keys.sorted(by: >)
            .map { "\(grouped[$0]?.count ?? 0)x CR \(EncounterMath.crText($0))" }
            .joined(separator: " + ")
    }

    /// Fight-recap line (3.44.0): derived at End combat from stored
    /// inputs - the CR breakdown, the round, the recorded award. Nil
    /// when the tracker holds no CR'd enemies or the fight never ran
    /// (nothing rolled, round 1, no award): End combat on an idle
    /// tracker files nothing, so a double End combat never recaps twice.
    public var fightRecapLine: String? {
        let breakdown = crBreakdown
        guard !breakdown.isEmpty else { return nil }
        let ran = fightAward != nil || round > 1 || entries.contains { $0.total != nil }
        guard ran else { return nil }
        var line = "Fight over: \(breakdown) - \(round) round\(round == 1 ? "" : "s")"
        if let award = fightAward, award.total > 0 {
            line += " - \(award.total) XP to \(award.recipients.joined(separator: ", "))"
        }
        return line
    }

    /// Start fight (3.37.0): expand planner rows into individual entries -
    /// "x2 CR 3" becomes "CR 3 #1", "CR 3 #2", each carrying its CR for the
    /// live-fight estimate. Numbering runs globally per CR text, so same-CR
    /// rows never collide. Bonuses are 0 (flat): CR says nothing about
    /// dexterity, and inventing one would be fake precision. Unknown-CR and
    /// zero-count rows are skipped - the planner already flags them.
    public static func startingFight(from lines: [EncounterLine]) -> InitiativeTracker {
        InitiativeTracker(entries: expand(lines, seeding: [:]))
    }

    /// Add to fight (3.39.0): append planner rows as new entries - the wave
    /// case, deliberately not idempotent. Existing entries, totals, the
    /// active turn, and the round carry over; arrivals roll flat and sink
    /// to the bottom of the order until rolled. Numbering continues per CR
    /// VALUE from the current entries, never parsed from names - renames
    /// and removals cannot break it.
    public func appendingFight(from lines: [EncounterLine]) -> InitiativeTracker {
        var seed: [String: Int] = [:]
        for entry in entries {
            // 3.43.0: labeled entries seed by their label FIELD, never by
            // parsing names - waves stay rename-proof.
            if let label = entry.label {
                seed[label, default: 0] += 1
            } else if let cr = entry.cr {
                seed[EncounterMath.crText(cr), default: 0] += 1
            }
        }
        var copy = self
        copy.entries.append(contentsOf: InitiativeTracker.expand(lines, seeding: seed))
        return copy
    }

    /// Shared expansion for start/append so the two paths cannot drift:
    /// valid rows become one flat entry per creature, numbered per CR text
    /// from the seed counts. Unknown-CR and zero-count rows are skipped.
    private static func expand(_ lines: [EncounterLine], seeding seed: [String: Int]) -> [InitiativeEntry] {
        var entries: [InitiativeEntry] = []
        var numbers = seed
        for line in lines where line.count > 0 {
            guard EncounterMath.xp(forCR: line.cr) != nil else { continue }
            // Labeled rows (3.43.0) name and number by their label;
            // unlabeled rows keep CR-text naming - two domains, one map.
            let custom = line.label.trimmingCharacters(in: .whitespaces)
            let key = custom.isEmpty ? EncounterMath.crText(line.cr) : custom
            for _ in 0..<line.count {
                let n = (numbers[key] ?? 0) + 1
                numbers[key] = n
                let name = custom.isEmpty ? "CR \(key) #\(n)" : "\(key) #\(n)"
                entries.append(InitiativeEntry(name: name, bonus: 0, cr: line.cr,
                                               label: custom.isEmpty ? nil : key))
            }
        }
        return entries
    }

    /// Advance the turn: the next rolled entry becomes active; wrapping
    /// the rotation increments the round. With no active entry the first
    /// rolled entry takes the turn. No-op under two rolled entries.
    public mutating func advance() {
        let rolled = rolledOrder
        guard rolled.count >= 2 else { return }
        guard let activeID, let index = rolled.firstIndex(where: { $0.id == activeID }) else {
            self.activeID = rolled.first?.id
            return
        }
        let next = index + 1
        if next < rolled.count {
            self.activeID = rolled[next].id
        } else {
            self.activeID = rolled[0].id
            round += 1
        }
    }

    /// End combat: totals, the active pointer, and the round reset -
    /// the entries stay, so a rerun fight just re-rolls. 3.44.0: the
    /// recorded award is consumed (the recap reads it first); the
    /// pre-fight snapshot survives - restoring a displaced fight is
    /// still meaningful after this fight ends.
    public mutating func endCombat() {
        for i in entries.indices { entries[i].total = nil }
        activeID = nil
        round = 1
        fightAward = nil
    }
}

/// JSON persistence for the tracker, alongside the character files -
/// a fight survives quitting mid-combat.
public struct InitiativeStore: Sendable {
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    private var fileURL: URL { directory.appendingPathComponent("initiative.json") }

    public func load() -> InitiativeTracker {
        guard let data = try? Data(contentsOf: fileURL),
              let tracker = try? JSONDecoder().decode(InitiativeTracker.self, from: data) else {
            return InitiativeTracker()
        }
        return tracker
    }

    public func save(_ tracker: InitiativeTracker) {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(tracker) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
