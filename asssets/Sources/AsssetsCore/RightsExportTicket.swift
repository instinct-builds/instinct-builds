import Foundation

/// A one-time decision about exact assets and rights on one calendar day.
/// It is not a license verification or a permanent export exemption.
public struct RightsExportTicket: Equatable, Sendable {
    public enum Decision: Equatable, Sendable { case cleared, anyway, leaveOut }
    public struct Record: Equatable, Sendable {
        public let id: UUID
        public let title: String
        public let rights: UsageRights?
        public let licenseDocs: [UUID]
        public let status: RightsStatus
    }
    public let records: [Record]
    public let day: String
    public let decision: Decision
    public let reviewedIDs: [UUID]
    /// Exact saved board card identity/order when the export comes from a board.
    public let boardItems: [UUID]?

    public init?(catalog: StudioCatalog, ids: [UUID], day: String, decision: Decision, reviewedIDs: [UUID]? = nil, boardItems: [UUID]? = nil) {
        guard !ids.isEmpty, Set(ids).count == ids.count else { return nil }
        let byID = Dictionary(catalog.assets.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var entries: [Record] = []
        for id in ids {
            guard let a = byID[id] else { return nil }
            entries.append(Record(id: id, title: a.title, rights: a.rights,
                                  licenseDocs: a.licenseDocs, status: a.rightsStatus(asOf: day)))
        }
        if decision == .cleared || decision == .leaveOut {
            guard entries.allSatisfy({ !$0.status.isProblem }) else { return nil }
        }
        self.records = entries
        self.day = day
        self.decision = decision
        self.reviewedIDs = reviewedIDs ?? ids
        self.boardItems = boardItems
    }

    public var ids: [UUID] { records.map(\.id) }

    /// `scope` is the live board/selection when that scope is expected to be stable.
    public func stillMatches(_ catalog: StudioCatalog, day: String, scope: [UUID]? = nil, boardItems: [UUID]? = nil) -> Bool {
        guard self.day == day, scope == nil || scope == reviewedIDs,
              self.boardItems == nil || self.boardItems == boardItems,
              let current = RightsExportTicket(catalog: catalog, ids: ids, day: day,
                                                decision: decision, reviewedIDs: reviewedIDs, boardItems: self.boardItems) else { return false }
        return current == self
    }
}
