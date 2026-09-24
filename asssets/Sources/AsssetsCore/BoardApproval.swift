import Foundation

// MARK: - Card approval, threaded replies and the round summary (1.21)

public enum CardStatus: String, Codable, CaseIterable, Sendable {
    case open, approved, changes
    public var label: String {
        switch self {
        case .open: return "Open"
        case .approved: return "Approved"
        case .changes: return "Changes"
        }
    }
}

/// The studio's answer under a card's client comments.
public struct BoardReply: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var item: UUID
    public var author: String
    public var text: String
    /// ISO-8601 time it was posted.
    public var posted: String
    public init(id: UUID = UUID(), item: UUID, author: String, text: String, posted: String) {
        self.id = id; self.item = item; self.author = author; self.text = text; self.posted = posted
    }
}

extension Moodboard {
    public static let maxReplyLength = 2000

    /// Open unless someone set it. Only asset cards carry a status.
    public func status(of item: UUID) -> CardStatus { statuses[item] ?? .open }

    /// Sets the status on the asset cards among `ids`; returns how many changed.
    @discardableResult
    public mutating func setStatus(_ status: CardStatus, for ids: Set<UUID>) -> Int {
        var n = 0
        for it in items where ids.contains(it.id) && it.kind == .asset && self.status(of: it.id) != status {
            statuses[it.id] = status == .open ? nil : status; n += 1
        }
        return n
    }

    /// Asset cards currently on the board with this status.
    public func cards(with status: CardStatus) -> Set<UUID> {
        Set(items.filter { $0.kind == .asset && self.status(of: $0.id) == status }.map(\.id))
    }

    public var statusCounts: [CardStatus: Int] {
        var out: [CardStatus: Int] = [.open: 0, .approved: 0, .changes: 0]
        for it in items where it.kind == .asset { out[status(of: it.id), default: 0] += 1 }
        return out
    }

    /// Replies under one card, oldest first.
    public func replies(for item: UUID) -> [BoardReply] {
        replies.enumerated().filter { $0.element.item == item }
            .sorted { $0.element.posted == $1.element.posted ? $0.offset < $1.offset : $0.element.posted < $1.element.posted }.map(\.element)
    }

    /// Adds a reply to a card on the board. Empty text or a missing card adds nothing.
    @discardableResult
    public mutating func addReply(to item: UUID, author: String, text: String, posted: String) -> UUID? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, items.contains(where: { $0.id == item }) else { return nil }
        let who = author.trimmingCharacters(in: .whitespacesAndNewlines)
        let r = BoardReply(item: item, author: who.isEmpty ? "Studio" : String(who.prefix(80)), text: String(t.prefix(Self.maxReplyLength)), posted: posted)
        replies.append(r)
        return r.id
    }

    public mutating func editReply(_ id: UUID, text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let i = replies.firstIndex(where: { $0.id == id }) else { return }
        if t.isEmpty { replies.remove(at: i) } else { replies[i].text = String(t.prefix(Self.maxReplyLength)) }
    }

    public mutating func deleteReply(_ id: UUID) { replies.removeAll { $0.id == id } }

    /// Cards that have anything to show in a thread: client picks or comments, replies, or a status.
    public func threadedCards() -> Set<UUID> {
        let onBoard = Set(items.filter { $0.kind == .asset }.map(\.id))
        return Set(pins().keys).union(replies.map(\.item)).union(statuses.keys).intersection(onBoard)
    }
}

/// One page to send back to the client: every asset card in reading order with picks, comments, replies and status.
public struct RoundSummary: Equatable, Sendable {
    public struct Row: Equatable, Sendable {
        public var item: UUID
        public var asset: UUID?
        public var title: String
        public var status: CardStatus
        public var pickedBy: [String]
        public var comments: [BoardPin.Comment]
        public var replies: [BoardReply]
    }
    public var board: String
    public var reviewers: [String]
    public var rows: [Row]
    public var counts: [CardStatus: Int]

    /// "3 approved · 1 changes · 2 open"
    public var tally: String {
        [CardStatus.approved, .changes, .open].map { "\(counts[$0] ?? 0) \($0.label.lowercased())" }.joined(separator: " · ")
    }
}

extension StudioCatalog {
    public func roundSummary(_ boardID: UUID) -> RoundSummary? {
        guard let b = board(boardID) else { return nil }
        let pins = b.pins()
        let titles = Dictionary(assets.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
        let rows = b.readingOrder.filter { $0.kind == .asset }.map { it in
            RoundSummary.Row(item: it.id, asset: it.assetID, title: it.assetID.flatMap { titles[$0] } ?? "Missing asset",
                             status: b.status(of: it.id), pickedBy: pins[it.id]?.pickedBy ?? [], comments: pins[it.id]?.comments ?? [],
                             replies: b.replies(for: it.id))
        }
        return RoundSummary(board: b.name, reviewers: b.reviewers, rows: rows, counts: b.statusCounts)
    }
}
