import Foundation

/// Stable, catalog-order queue of unreviewed source IDs. Selection is not acceptance.
public struct SourceReviewQueue: Equatable, Sendable {
    public let pending: [UUID]
    public let selected: UUID?

    public init(pending: [UUID], selected: UUID?) {
        var seen = Set<UUID>()
        let unique = pending.filter { seen.insert($0).inserted }
        self.pending = unique
        self.selected = selected.flatMap { unique.contains($0) ? $0 : nil } ?? unique.first
    }

    public var position: Int? { selected.flatMap { pending.firstIndex(of: $0) }.map { $0 + 1 } }

    /// After one accepted source, stay at its row if another moves up, otherwise choose the final row.
    public func next(after accepted: UUID) -> UUID? {
        guard let index = pending.firstIndex(of: accepted) else { return selected }
        let remaining = pending.filter { $0 != accepted }
        guard !remaining.isEmpty else { return nil }
        return remaining[min(index, remaining.count - 1)]
    }
}
