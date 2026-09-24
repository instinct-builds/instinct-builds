import Foundation

// MARK: - Client rounds on boards and board versions (1.20)

/// One reviewer's feedback on a gallery shared from a board, keyed to the assets they reacted to.
public struct BoardReview: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var gallery: String
    public var reviewer: String
    /// yyyy-MM-dd, when the feedback was imported.
    public var imported: String
    public var picks: [UUID]
    public var notes: [UUID: String]
    public init(id: UUID = UUID(), gallery: String, reviewer: String, imported: String, picks: [UUID] = [], notes: [UUID: String] = [:]) {
        self.id = id; self.gallery = gallery; self.reviewer = reviewer; self.imported = imported; self.picks = picks; self.notes = notes
    }
}

/// What a client said about one card, across every round on the board.
public struct BoardPin: Equatable, Sendable {
    public struct Comment: Equatable, Sendable {
        public var reviewer: String
        public var text: String
        public var imported: String
    }
    public var item: UUID
    /// Reviewers who picked it, latest round first.
    public var pickedBy: [String]
    public var comments: [Comment]
    public var picked: Bool { !pickedBy.isEmpty }
}

/// A saved state of a board's cards and arrows.
public struct BoardVersion: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// ISO-8601 time it was saved.
    public var saved: String
    public var items: [BoardItem]
    public var connectors: [BoardConnector]
    public init(id: UUID = UUID(), name: String, saved: String, items: [BoardItem], connectors: [BoardConnector]) {
        self.id = id; self.name = name; self.saved = saved; self.items = items; self.connectors = connectors
    }
}

extension Moodboard {
    public static let maxVersions = 30

    /// Asset ids the board shows, for matching feedback.
    public var assetIDs: Set<UUID> { Set(items.compactMap { $0.kind == .asset ? $0.assetID : nil }) }

    /// Records (or replaces) one reviewer's round. Only assets on the board count; returns false when nothing matched.
    @discardableResult
    public mutating func recordReview(_ f: ReviewGallery.Feedback, imported: String) -> Bool {
        let reviewer = f.reviewer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Client" : f.reviewer.trimmingCharacters(in: .whitespacesAndNewlines)
        let here = assetIDs
        var picks: [UUID] = [], notes: [UUID: String] = [:]
        for e in f.items {
            guard let id = UUID(uuidString: e.id), here.contains(id) else { continue }
            if e.favorite && !picks.contains(id) { picks.append(id) }
            let t = e.note.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { notes[id] = String(t.prefix(4000)) }
        }
        guard !picks.isEmpty || !notes.isEmpty else { return false }
        reviews.removeAll { $0.gallery == f.gallery && $0.reviewer == reviewer }
        reviews.append(BoardReview(gallery: f.gallery, reviewer: reviewer, imported: imported, picks: picks, notes: notes))
        return true
    }

    /// Pins for asset cards that got a pick or a comment, latest round first. `reviewer` narrows to one person.
    public func pins(reviewer: String? = nil) -> [UUID: BoardPin] {
        var out: [UUID: BoardPin] = [:]
        let rounds = reviews.enumerated().sorted { $0.element.imported == $1.element.imported ? $0.offset > $1.offset : $0.element.imported > $1.element.imported }.map(\.element)
        for it in items where it.kind == .asset {
            guard let a = it.assetID else { continue }
            var pin = BoardPin(item: it.id, pickedBy: [], comments: [])
            for r in rounds where reviewer == nil || r.reviewer == reviewer {
                if r.picks.contains(a) && !pin.pickedBy.contains(r.reviewer) { pin.pickedBy.append(r.reviewer) }
                if let t = r.notes[a] { pin.comments.append(.init(reviewer: r.reviewer, text: t, imported: r.imported)) }
            }
            if pin.picked || !pin.comments.isEmpty { out[it.id] = pin }
        }
        return out
    }

    public var reviewers: [String] {
        var seen: [String] = []
        for r in reviews where !seen.contains(r.reviewer) { seen.append(r.reviewer) }
        return seen
    }

    /// Saves the cards and arrows as they are now. The oldest version drops off past the limit.
    @discardableResult
    public mutating func saveVersion(named name: String? = nil, saved: String) -> UUID {
        let t = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let v = BoardVersion(name: t.isEmpty ? "Version \(versions.count + 1)" : String(t.prefix(80)), saved: saved, items: items, connectors: connectors)
        versions.append(v)
        if versions.count > Self.maxVersions { versions.removeFirst(versions.count - Self.maxVersions) }
        return v.id
    }

    /// Puts a version's cards and arrows back. What was there is saved first as "Before restoring …" unless it already matches a version.
    @discardableResult
    public mutating func restoreVersion(_ id: UUID, saved: String) -> Bool {
        guard let v = versions.first(where: { $0.id == id }) else { return false }
        if !versions.contains(where: { $0.items == items && $0.connectors == connectors }) {
            saveVersion(named: "Before restoring \(v.name)", saved: saved)
        }
        items = v.items; connectors = v.connectors
        return true
    }

    public mutating func deleteVersion(_ id: UUID) { versions.removeAll { $0.id == id } }

    public mutating func renameVersion(_ id: UUID, to name: String) {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let i = versions.firstIndex(where: { $0.id == id }) else { return }
        versions[i].name = String(t.prefix(80))
    }

    /// How a version differs from the board now: cards added, removed and moved or resized.
    public func changes(since id: UUID) -> (added: Int, removed: Int, changed: Int)? {
        guard let v = versions.first(where: { $0.id == id }) else { return nil }
        let old = Dictionary(v.items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let now = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let added = now.keys.filter { old[$0] == nil }.count
        let removed = old.keys.filter { now[$0] == nil }.count
        let changed = now.filter { k, it in old[k].map { $0 != it } ?? false }.count
        return (added, removed, changed)
    }
}

extension StudioCatalog {
    /// Remembers that a review gallery was shared from a board, so its feedback lands back on that board.
    public mutating func noteGalleryShared(_ gallery: String, from board: UUID) {
        _ = updateBoard(board) { b in if !b.sharedGalleries.contains(gallery) { b.sharedGalleries.append(gallery) } }
    }

    /// The board a gallery was shared from.
    public func board(forGallery gallery: String) -> UUID? {
        boards.first { $0.sharedGalleries.contains(gallery) }?.id
    }
}
