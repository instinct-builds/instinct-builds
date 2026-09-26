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

    public init(id: UUID = UUID(), name: String, bonus: Int, total: Int? = nil,
                characterName: String? = nil) {
        self.id = id
        self.name = name
        self.bonus = bonus
        self.total = total
        self.characterName = characterName
    }
}

/// The initiative tracker (3.22.0): ordered entries, the active turn,
/// and the round. Deliberately order-only - no HP, no conditions, no
/// per-entry notes; this tracks whose turn it is, not the fight.
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
