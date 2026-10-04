import Foundation

/// 1.95: what ASSSETS puts in the system Spotlight index, and the diff that keeps it current. Pure data, so it is
/// unit-tested; the CoreSpotlight calls live in the app target.
public struct SpotlightRecord: Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var keywords: [String]
    /// Shown under the title in Spotlight results.
    public var detail: String
    /// Searchable but not displayed: client note text.
    public var text: String
    public var path: String?
}

public enum SpotlightPlan {
    public static let domain = "co.instinct.asssets.library"

    /// The user's own assets only. The bundled starter library is left out so Spotlight is not filled with files the user did not add.
    public static func records(_ c: StudioCatalog) -> [SpotlightRecord] {
        c.assets.filter { !$0.isStarter }.map { a in
            SpotlightRecord(
                id: a.id, title: a.title,
                keywords: a.tags.filter { !StudioCatalog.isSystemTag($0) && $0 != StudioCatalog.rejectTag },
                detail: "\(a.collection) · \(a.kind.rawValue)",
                text: a.clientNotes.map(\.text).joined(separator: "\n"),
                path: a.importedPath)
        }
    }

    /// What to (re)index and what to delete, given what is already in the index.
    public static func diff(known: [UUID: SpotlightRecord], now: [SpotlightRecord]) -> (index: [SpotlightRecord], delete: [UUID]) {
        let ids = Set(now.map(\.id))
        return (now.filter { known[$0.id] != $0 }, known.keys.filter { !ids.contains($0) }.sorted { $0.uuidString < $1.uuidString })
    }
}
