import Foundation

/// Picks this installation has attributed to one gallery/reviewer since 1.68.
/// Older `client-pick` tags have no attributable reviewer and never enter this ledger.
public struct FeedbackPickRound: Codable, Equatable, Sendable {
    public var gallery: String
    public var reviewer: String
    public var assets: [UUID]
    public init(gallery: String, reviewer: String, assets: [UUID]) {
        self.gallery = gallery.lowercased(); self.reviewer = reviewer
        self.assets = Array(Set(assets)).sorted { $0.uuidString < $1.uuidString }
    }
}

extension StudioCatalog {
    public static func feedbackReviewer(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Client" : trimmed
    }
    public func feedbackRound(gallery: String, reviewer: String) -> FeedbackPickRound? {
        feedbackPickLedger.first { $0.gallery == gallery.lowercased() &&
            $0.reviewer.lowercased() == Self.feedbackReviewer(reviewer).lowercased() }
    }
    /// Only IDs whose tag we added are removable by ledger recomputation.
    public mutating func replaceFeedbackPicks(gallery: String, reviewer: String, with picks: [UUID]) -> Int {
        let who = Self.feedbackReviewer(reviewer), gallery = gallery.lowercased()
        let old = feedbackRound(gallery: gallery, reviewer: who)?.assets ?? []
        let previouslyOwned = ledgerOwnedPickTags
        let fresh = FeedbackPickRound(gallery: gallery, reviewer: who, assets: picks)
        feedbackPickLedger.removeAll { $0.gallery == gallery && $0.reviewer.lowercased() == who.lowercased() }
        feedbackPickLedger.append(fresh) // Empty is an explicit reviewed withdrawal.
        let touched = Set(old).union(fresh.assets)
        for id in touched {
            guard let i = assets.firstIndex(where: { $0.id == id }) else { continue }
            let currentlyTagged = assets[i].tags.contains(ReviewGallery.clientPickTag)
            if currentlyTagged && !previouslyOwned.contains(id) { preservedPickTags.insert(id) }
            let picked = feedbackPickLedger.contains { $0.assets.contains(id) }
            if picked {
                if !currentlyTagged { assets[i].tags.append(ReviewGallery.clientPickTag) }
                if !preservedPickTags.contains(id) { ledgerOwnedPickTags.insert(id) }
            } else if ledgerOwnedPickTags.contains(id) && !preservedPickTags.contains(id) {
                assets[i].tags.removeAll { $0 == ReviewGallery.clientPickTag }
                ledgerOwnedPickTags.remove(id)
            }
        }
        return Set(old).subtracting(fresh.assets).count
    }
}
