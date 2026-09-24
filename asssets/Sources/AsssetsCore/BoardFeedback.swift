import Foundation

// MARK: - 1.23: look before importing a client's feedback, and arrange selected cards

/// What importing one feedback file would do, row by row, before anything changes.
public struct FeedbackPreview: Equatable, Sendable {
    public struct Row: Equatable, Sendable {
        public var id: String
        /// Nil when the asset isn't in this library.
        public var asset: UUID?
        public var title: String
        public var favorite: Bool
        public var note: String
        /// Status of the asset's card on the round's board now; nil when there is no board or no card.
        public var from: CardStatus?
        /// What the client asked for with Approve / Request changes.
        public var to: CardStatus?
        public var known: Bool { asset != nil }
        /// True when the import will move this card's status.
        public var changesStatus: Bool { from != nil && to != nil && from != to }
    }
    public var reviewer: String
    public var title: String
    public var board: UUID?
    public var boardName: String?
    /// The same reviewer already sent feedback on this gallery; theirs gets replaced.
    public var replaces: Bool
    public var rows: [Row]

    public var picks: Int { rows.filter { $0.known && $0.favorite }.count }
    public var notes: Int { rows.filter { $0.known && !$0.note.isEmpty }.count }
    public var statusChanges: Int { rows.filter(\.changesStatus).count }
    public var approvals: Int { rows.filter { $0.known && $0.to == .approved }.count }
    public var changeRequests: Int { rows.filter { $0.known && $0.to == .changes }.count }
    public var unknown: Int { rows.filter { !$0.known }.count }
    /// Nothing in the file would land.
    public var isEmpty: Bool { picks + notes + approvals + changeRequests == 0 }
}

extension StudioCatalog {
    /// Reads a feedback file against the library and, when the gallery came from a board, that board. Changes nothing.
    public func previewFeedback(_ f: ReviewGallery.Feedback) -> FeedbackPreview {
        let who = f.reviewer.trimmingCharacters(in: .whitespacesAndNewlines)
        let reviewer = who.isEmpty ? "Client" : who
        let bid = board(forGallery: f.gallery)
        let b = bid.flatMap { board($0) }
        let byID = Dictionary(assets.map { ($0.id.uuidString.uppercased(), $0) }, uniquingKeysWith: { a, _ in a })
        let rows = f.items.map { e -> FeedbackPreview.Row in
            let a = byID[e.id.uppercased()]
            let card = a.flatMap { a in b?.items.first { $0.kind == .asset && $0.assetID == a.id } }
            return FeedbackPreview.Row(id: e.id, asset: a?.id, title: a?.title ?? "Not in this library",
                                       favorite: e.favorite, note: e.note.trimmingCharacters(in: .whitespacesAndNewlines),
                                       from: card.map { b!.status(of: $0.id) }, to: e.cardStatus)
        }
        let replaces = b?.reviews.contains { $0.gallery == f.gallery && $0.reviewer == reviewer } ?? false
        return FeedbackPreview(reviewer: reviewer, title: f.title, board: b == nil ? nil : bid, boardName: b?.name, replaces: replaces, rows: rows)
    }
}

/// Align, distribute and match size for two or more selected cards.
public enum ArrangeOp: String, CaseIterable, Codable, Sendable {
    case left, centerX, right, top, middle, bottom, distributeH, distributeV, matchWidth, matchHeight

    public var label: String {
        switch self {
        case .left: return "Align Left Edges"
        case .centerX: return "Align Centers"
        case .right: return "Align Right Edges"
        case .top: return "Align Top Edges"
        case .middle: return "Align Middles"
        case .bottom: return "Align Bottom Edges"
        case .distributeH: return "Distribute Horizontally"
        case .distributeV: return "Distribute Vertically"
        case .matchWidth: return "Match Widths"
        case .matchHeight: return "Match Heights"
        }
    }

    /// Distributing needs a middle card to move.
    public var minimumCards: Int { self == .distributeH || self == .distributeV ? 3 : 2 }
}

extension Moodboard {
    /// Arranges the selected cards (frames count as cards; what a frame holds does not move with it here).
    /// Aligning uses the selection's own bounds, distributing keeps the two outer cards and evens the gaps,
    /// matching uses the largest card, keeps each card's top-left and each image card's shape. Returns how many cards moved or resized.
    @discardableResult
    public mutating func arrange(_ ids: Set<UUID>, _ op: ArrangeOp) -> Int {
        let idx = items.indices.filter { ids.contains(items[$0].id) }
        guard idx.count >= op.minimumCards else { return 0 }
        let rects = idx.map { items[$0].rect }
        let minX = rects.map(\.x).min()!, maxX = rects.map(\.maxX).max()!
        let minY = rects.map(\.y).min()!, maxY = rects.map(\.maxY).max()!
        var n = 0
        func set(_ i: Int, x: Double? = nil, y: Double? = nil, w: Double? = nil, h: Double? = nil) {
            let old = items[i]
            if let x { items[i].x = x }; if let y { items[i].y = y }
            if let w { items[i].w = max(Self.minSize, w) }; if let h { items[i].h = max(Self.minSize, h) }
            if items[i] != old { n += 1 }
        }
        switch op {
        case .left: for i in idx { set(i, x: minX) }
        case .right: for i in idx { set(i, x: maxX - items[i].w) }
        case .centerX: let c = (minX + maxX) / 2; for i in idx { set(i, x: c - items[i].w / 2) }
        case .top: for i in idx { set(i, y: minY) }
        case .bottom: for i in idx { set(i, y: maxY - items[i].h) }
        case .middle: let c = (minY + maxY) / 2; for i in idx { set(i, y: c - items[i].h / 2) }
        case .distributeH:
            let order = idx.sorted { items[$0].x == items[$1].x ? $0 < $1 : items[$0].x < items[$1].x }
            let gap = (maxX - minX - order.map { items[$0].w }.reduce(0, +)) / Double(order.count - 1)
            var x = items[order[0]].x
            for i in order { set(i, x: x); x += items[i].w + gap }
        case .distributeV:
            let order = idx.sorted { items[$0].y == items[$1].y ? $0 < $1 : items[$0].y < items[$1].y }
            let gap = (maxY - minY - order.map { items[$0].h }.reduce(0, +)) / Double(order.count - 1)
            var y = items[order[0]].y
            for i in order { set(i, y: y); y += items[i].h + gap }
        // Image cards keep their shape (as in resize), so matching one side scales the other.
        case .matchWidth:
            let w = idx.map { items[$0].w }.max()!
            for i in idx { let it = items[i]; set(i, w: w, h: it.kind == .asset && it.w > 0 ? it.h * w / it.w : nil) }
        case .matchHeight:
            let h = idx.map { items[$0].h }.max()!
            for i in idx { let it = items[i]; set(i, w: it.kind == .asset && it.h > 0 ? it.w * h / it.h : nil, h: h) }
        }
        return n
    }
}
