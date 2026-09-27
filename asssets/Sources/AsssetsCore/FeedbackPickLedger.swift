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

/// Stable identity for a published gallery and reviewer, not proof of authorship.
public struct FeedbackRoundKey: Hashable, Sendable {
    public let gallery: String
    public let reviewer: String
    public init(gallery: String, reviewer: String) {
        self.gallery = gallery.lowercased()
        self.reviewer = StudioCatalog.feedbackReviewer(reviewer).lowercased()
    }
}

extension StudioCatalog {
    public static func feedbackReviewer(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Client" : trimmed
    }
    /// One identity for a feedback round across the pick ledger, asset notes, and board reviews.
    /// Casing changes in a later file must not create a second person's round.
    public static func sameFeedbackRound(_ firstGallery: String, _ firstReviewer: String,
                                         _ secondGallery: String, _ secondReviewer: String) -> Bool {
        FeedbackRoundKey(gallery: firstGallery, reviewer: firstReviewer) ==
        FeedbackRoundKey(gallery: secondGallery, reviewer: secondReviewer)
    }
    public func feedbackRound(gallery: String, reviewer: String) -> FeedbackPickRound? {
        feedbackPickLedger.first { Self.sameFeedbackRound($0.gallery, $0.reviewer, gallery, reviewer) }
    }
    /// Keep the first accepted display spelling even if a replacement file changes case.
    public func feedbackDisplayReviewer(gallery: String, reviewer: String) -> String {
        let incoming = Self.feedbackReviewer(reviewer)
        if let old = feedbackRound(gallery: gallery, reviewer: incoming) { return old.reviewer }
        if let old = assets.flatMap(\.clientNotes).first(where: {
            Self.sameFeedbackRound($0.gallery, $0.reviewer, gallery, incoming)
        }) { return old.reviewer }
        if let old = boards.flatMap(\.reviews).first(where: {
            Self.sameFeedbackRound($0.gallery, $0.reviewer, gallery, incoming)
        }) { return old.reviewer }
        return incoming
    }
    /// Only IDs whose tag we added are removable by ledger recomputation.
    public mutating func replaceFeedbackPicks(gallery: String, reviewer: String, with picks: [UUID]) -> Int {
        let who = feedbackDisplayReviewer(gallery: gallery, reviewer: reviewer)
        let gallery = gallery.lowercased()
        let old = feedbackRound(gallery: gallery, reviewer: who)?.assets ?? []
        let previouslyOwned = ledgerOwnedPickTags
        let fresh = FeedbackPickRound(gallery: gallery, reviewer: who, assets: picks)
        feedbackPickLedger.removeAll { Self.sameFeedbackRound($0.gallery, $0.reviewer, gallery, who) }
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
