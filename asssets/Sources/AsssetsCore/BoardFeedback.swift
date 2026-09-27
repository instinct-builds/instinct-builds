import Foundation

// MARK: - 1.23: look before importing a client's feedback, and arrange selected cards

/// What importing one feedback file would do, row by row, before anything changes.
public struct FeedbackPreview: Equatable, Sendable {
    public struct Row: Equatable, Sendable {
        public var id: String
        /// Nil when the asset isn't in this library.
        public var asset: UUID?
        public var title: String
        /// Exact published board card, nil if there is no unambiguous match.
        public var card: UUID? = nil
        public var skipped: String? = nil
        public var favorite: Bool
        public var note: String
        /// Trimmed submitted count when the accepted note will be capped on save.
        public var submittedNoteCount: Int? = nil
        /// Current gallery/reviewer pick that this file removes.
        public var withdrawsPick: Bool = false
        /// A withdrawal remains visible in Client Picks due to another tracked reviewer or a preserved tag.
        public var remainsPicked: Bool = false
        /// Prior note for this gallery/reviewer; shown when removed or replaced.
        public var removedNote: String? = nil
        public var replacesNote: Bool = false
        /// Status of the asset's card on the round's board now; nil when there is no board or no card.
        public var from: CardStatus?
        /// What the client asked for with Approve / Request changes.
        public var to: CardStatus?
        public var known: Bool { asset != nil && skipped == nil }
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
    public var rosterIssue: String? = nil
    public var skippedCount: Int { rows.filter { !$0.known }.count }
    public var withdrawals: Int { rows.filter(\.withdrawsPick).count }
    public var noteRemovals: Int { rows.filter { $0.removedNote != nil && !$0.replacesNote }.count }
    public var noteReplacements: Int { rows.filter(\.replacesNote).count }
    public var additions: Int { rows.filter { $0.known && $0.favorite && !$0.withdrawsPick }.count }
    public var hasVerifiedEntry: Bool { rows.contains { $0.known && !$0.withdrawsPick } }
    public var canImport: Bool { rosterIssue == nil && (withdrawals > 0 || noteRemovals > 0 || noteReplacements > 0 || !isEmpty || (replaces && (rows.isEmpty || hasVerifiedEntry))) }

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
        let reviewer = feedbackDisplayReviewer(gallery: f.gallery, reviewer: f.reviewer)
        let roster = roster(for: f.gallery)
        let issue = roster == nil ? "Gallery roster unavailable" : roster?.title != f.title ? "Gallery title differs from published roster" : nil
        let bid = issue == nil && roster?.recovered == false ? roster?.board : nil
        let b = bid.flatMap { board($0) }
        let byID = Dictionary(assets.map { ($0.id.uuidString.uppercased(), $0) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<UUID>()
        let prior = Set(feedbackRound(gallery: f.gallery, reviewer: reviewer)?.assets ?? [])
        var validSeen = Set<UUID>()
        let valid = f.items.compactMap { e -> UUID? in
            guard let id = UUID(uuidString: e.id), roster?.allows(id) == true,
                  byID[e.id.uppercased()] != nil, validSeen.insert(id).inserted else { return nil }
            return id
        }
        let intentional = issue == nil && (f.items.isEmpty || !valid.isEmpty)
        let scope = scopedFeedback(f).feedback
        let nextNotes = Dictionary(uniqueKeysWithValues: scope.items.compactMap { e -> (UUID, String)? in
            guard let id = UUID(uuidString: e.id) else { return nil }
            let text = FeedbackNoteText.saved(e.note)
            return text.isEmpty ? nil : (id, text)
        })
        let priorNotes = Dictionary(uniqueKeysWithValues: assets.compactMap { asset -> (UUID, String)? in
            guard let note = asset.clientNotes.first(where: { Self.sameFeedbackRound($0.gallery, $0.reviewer, f.gallery, reviewer) }) else { return nil }
            return (asset.id, note.text)
        })
        let nextPicks = Set(scope.items.compactMap { e -> UUID? in
            guard e.favorite else { return nil }
            return UUID(uuidString: e.id)
        })
        let rows = f.items.map { e -> FeedbackPreview.Row in
            let id = UUID(uuidString: e.id)
            var reason: String? = issue
            if let id {
                if !seen.insert(id).inserted { reason = "Duplicate asset ID" }
                else if reason == nil && !(roster?.allows(id) ?? false) { reason = "Not in this gallery" }
                else if reason == nil && byID[e.id.uppercased()] == nil { reason = "No longer in this library" }
            } else { reason = "Invalid asset ID" }
            let a = reason == nil ? byID[e.id.uppercased()] : nil
            let card = a.flatMap { asset -> BoardItem? in
                guard let b else { return nil }
                let matches = b.items.filter { $0.kind == .asset && $0.assetID == asset.id }
                guard matches.count == 1, let only = matches.first,
                      roster?.cards.contains(where: { $0.id == only.id && $0.asset == asset.id }) == true else { return nil }
                return only
            }
            var row = FeedbackPreview.Row(id: e.id, asset: a?.id, title: a?.title ?? (reason ?? "Not in this library"),
                                       favorite: e.favorite, note: FeedbackNoteText.saved(e.note),
                                       from: card.map { b!.status(of: $0.id) }, to: card == nil ? nil : e.cardStatus)
            row.skipped = reason
            row.card = card?.id
            let submittedCount = FeedbackNoteText.submittedCount(e.note)
            if reason == nil && submittedCount > FeedbackNoteText.limit { row.submittedNoteCount = submittedCount }
            if reason == nil, let id, intentional, let old = priorNotes[id], old != nextNotes[id] {
                row.removedNote = old
                row.replacesNote = nextNotes[id] != nil
            }
            if reason == nil, let id, intentional, prior.contains(id), !nextPicks.contains(id) {
                row.withdrawsPick = true
                row.remainsPicked = preservedPickTags.contains(id) || feedbackPickLedger.contains {
                    !Self.sameFeedbackRound($0.gallery, $0.reviewer, f.gallery, reviewer) && $0.assets.contains(id)
                }
            }
            return row
        }
        let replaces = feedbackRound(gallery: f.gallery, reviewer: reviewer) != nil ||
            (b?.reviews.contains { Self.sameFeedbackRound($0.gallery, $0.reviewer, f.gallery, reviewer) } ?? false) ||
            assets.contains { asset in asset.clientNotes.contains { Self.sameFeedbackRound($0.gallery, $0.reviewer, f.gallery, reviewer) } }
        var preview = FeedbackPreview(reviewer: reviewer, title: f.title, board: b == nil ? nil : bid, boardName: b?.name, replaces: replaces, rows: rows)
        preview.rosterIssue = issue
        if issue == nil && intentional {
            let vanished = prior.union(Set(priorNotes.keys)).subtracting(Set(valid))
            for id in vanished.sorted(by: { $0.uuidString < $1.uuidString }) {
                var row = FeedbackPreview.Row(id: id.uuidString, asset: id,
                    title: assets.first(where: { $0.id == id })?.title ?? "Removed asset",
                    favorite: false, note: "", from: nil, to: nil)
                row.withdrawsPick = prior.contains(id)
                row.removedNote = priorNotes[id]
                row.remainsPicked = preservedPickTags.contains(id) || feedbackPickLedger.contains {
                    !Self.sameFeedbackRound($0.gallery, $0.reviewer, f.gallery, reviewer) && $0.assets.contains(id)
                }
                preview.rows.append(row)
            }
        }
        return preview
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
