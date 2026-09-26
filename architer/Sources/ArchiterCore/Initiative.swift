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

    public init(id: UUID = UUID(), name: String, bonus: Int, total: Int? = nil,
                characterName: String? = nil, cr: Double? = nil) {
        self.id = id
        self.name = name
        self.bonus = bonus
        self.total = total
        self.characterName = characterName
        self.cr = cr
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

    public init(entries: [InitiativeEntry] = [], activeID: UUID? = nil, round: Int = 1) {
        self.entries = entries
        self.activeID = activeID
        self.round = round
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
            guard let cr = entry.cr else { continue }
            seed[EncounterMath.crText(cr), default: 0] += 1
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
            let label = EncounterMath.crText(line.cr)
            for _ in 0..<line.count {
                let n = (numbers[label] ?? 0) + 1
                numbers[label] = n
                entries.append(InitiativeEntry(name: "CR \(label) #\(n)", bonus: 0, cr: line.cr))
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
    /// the entries stay, so a rerun fight just re-rolls.
    public mutating func endCombat() {
        for i in entries.indices { entries[i].total = nil }
        activeID = nil
        round = 1
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
