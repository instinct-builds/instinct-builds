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
    public var previews: [FeedbackPreview]
    public var conflicts: [Conflict]
}

extension StudioCatalog {
    public func previewFeedbackBatch(_ files: [ReviewGallery.Feedback]) -> FeedbackBatchPreview {
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
        return .init(previews: previews, conflicts: conflicts)
    }
}
