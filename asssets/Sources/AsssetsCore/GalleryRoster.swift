import Foundation

/// Local evidence of what this installation actually published. It is not proof of a reviewer's identity.
public struct GalleryRoster: Codable, Equatable, Sendable {
    public struct Card: Codable, Equatable, Sendable {
        public var id: UUID
        public var asset: UUID
        public init(id: UUID, asset: UUID) { self.id = id; self.asset = asset }
    }
    public var gallery: String
    public var title: String
    public var created: String
    public var assets: [UUID]
    public var board: UUID?
    public var cards: [Card]
    /// A recovered legacy page has no persisted board-card map, even if it names a board image.
    public var recovered: Bool
    public init?(gallery: String, title: String, created: String, assets: [UUID], board: UUID? = nil, cards: [Card] = [], recovered: Bool = false) {
        guard !gallery.isEmpty, !assets.isEmpty, Set(assets).count == assets.count,
              cards.allSatisfy({ assets.contains($0.asset) }), Set(cards.map(\.id)).count == cards.count else { return nil }
        self.gallery = gallery.lowercased(); self.title = title; self.created = created
        self.assets = assets; self.board = board; self.cards = cards; self.recovered = recovered
    }
    enum CodingKeys: String, CodingKey { case gallery, title, created, assets, board, cards, recovered }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gallery = try c.decode(String.self, forKey: .gallery)
        title = try c.decode(String.self, forKey: .title)
        created = try c.decode(String.self, forKey: .created)
        assets = try c.decode([UUID].self, forKey: .assets)
        board = try c.decodeIfPresent(UUID.self, forKey: .board)
        cards = try c.decode([Card].self, forKey: .cards)
        recovered = try c.decodeIfPresent(Bool.self, forKey: .recovered) ?? false
    }
    public func allows(_ id: UUID) -> Bool { assets.contains(id) }
}

extension StudioCatalog {
    /// Duplicate IDs with different rosters are conflicts, never merged.
    @discardableResult public mutating func recordGallery(_ roster: GalleryRoster) -> Bool {
        if galleryRosters.filter({ $0.gallery == roster.gallery }).count > 1 { return false }
        if let current = galleryRosters.first(where: { $0.gallery == roster.gallery }) { return current == roster }
        galleryRosters.append(roster)
        return true
    }
    public func roster(for gallery: String) -> GalleryRoster? {
        let matches = galleryRosters.filter { $0.gallery == gallery.lowercased() }
        return matches.count == 1 ? matches[0] : nil
    }
    public func scopedFeedback(_ f: ReviewGallery.Feedback) -> (feedback: ReviewGallery.Feedback, skipped: [String]) {
        guard let roster = roster(for: f.gallery), roster.title == f.title else {
            return (ReviewGallery.Feedback(gallery: f.gallery, title: f.title, reviewer: f.reviewer, items: []), ["Gallery roster unavailable or title mismatch"])
        }
        var seen = Set<UUID>(), accepted: [ReviewGallery.Feedback.Entry] = [], skipped: [String] = []
        for e in f.items {
            guard let id = UUID(uuidString: e.id) else { skipped.append("Invalid asset ID"); continue }
            guard seen.insert(id).inserted else { skipped.append("Duplicate asset ID"); continue }
            guard roster.allows(id) else { skipped.append("Not in this gallery"); continue }
            guard assets.contains(where: { $0.id == id }) else { skipped.append("No longer in this library"); continue }
            accepted.append(e)
        }
        var filtered = f; filtered.items = accepted
        return (filtered, skipped)
    }
}
