import Foundation

/// Ordered preview of a group of feedback files. Later files see earlier files'
/// effects, exactly as the verified batch import does; this is not a policy for
/// reconciling different reviewers' decisions.
public struct FeedbackBatchPreview: Equatable, Sendable {
    public struct Conflict: Equatable, Sendable {
        public var board: UUID
        public var card: UUID
        public var title: String
        public var requests: [Request]
        public var final: CardStatus
        public struct Request: Equatable, Sendable {
            public var reviewer: String
            public var status: CardStatus
        }
    }
    public struct Duplicate: Equatable, Sendable {
        public var gallery: String
        public var title: String
        public var reviewer: String
        /// Indices in the selected file order; the caller supplies display filenames.
        public var indices: [Int]
    }
    public var previews: [FeedbackPreview]
    public var conflicts: [Conflict]
    public var duplicates: [Duplicate]
}

extension StudioCatalog {
    public func previewFeedbackBatch(_ files: [ReviewGallery.Feedback]) -> FeedbackBatchPreview {
        var byKey: [FeedbackRoundKey: [Int]] = [:]
        var keys: [FeedbackRoundKey] = []
        for (i, file) in files.enumerated() {
            let key = FeedbackRoundKey(gallery: file.gallery, reviewer: file.reviewer)
            if byKey[key] == nil { keys.append(key) }
            byKey[key, default: []].append(i)
        }
        let duplicates = keys.compactMap { key -> FeedbackBatchPreview.Duplicate? in
            guard let indices = byKey[key], indices.count > 1 else { return nil }
            return .init(gallery: key.gallery, title: files[indices[0]].title,
                         reviewer: Self.feedbackReviewer(files[indices[0]].reviewer), indices: indices)
        }
        // The commit path rejects the whole batch. Never preview an impossible
        // sequence as if duplicate files could replace each other.
        if !duplicates.isEmpty {
            return .init(previews: files.map { previewFeedback($0) }, conflicts: [], duplicates: duplicates)
        }
        var copy = self
        var previews: [FeedbackPreview] = []
        struct Key: Hashable { var board: UUID; var card: UUID }
        var order: [Key] = [], requests: [Key: [FeedbackBatchPreview.Conflict.Request]] = [:]
        for f in files {
            let preview = copy.previewFeedback(f)
            previews.append(preview)
            if preview.canImport, let board = preview.board {
                for row in preview.rows where row.known {
                    guard let card = row.card, let status = row.to else { continue }
                    let key = Key(board: board, card: card)
                    if requests[key] == nil { order.append(key) }
                    requests[key, default: []].append(.init(reviewer: preview.reviewer, status: status))
                }
            }
            // Use the actual apply path, including its board-card and roster guards.
            if preview.canImport { _ = copy.applyFeedback(f) }
        }
        let conflicts = order.compactMap { key -> FeedbackBatchPreview.Conflict? in
            guard let asked = requests[key], Set(asked.map(\.status)).count > 1,
                  let board = copy.board(key.board), let card = board.items.first(where: { $0.id == key.card }) else { return nil }
            let title = card.assetID.flatMap { id in copy.assets.first(where: { $0.id == id })?.title } ?? "Missing asset"
            return .init(board: key.board, card: key.card, title: title,
                         requests: asked, final: board.status(of: key.card))
        }
        return .init(previews: previews, conflicts: conflicts, duplicates: [])
    }
}
